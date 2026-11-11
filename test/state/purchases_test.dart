import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:returner/core/app_paths.dart';
import 'package:returner/core/errors.dart';
import 'package:returner/models/store.dart';
import 'package:returner/services/database.dart';
import 'package:returner/services/ipatool_service.dart';
import 'package:returner/state/auth.dart';
import 'package:returner/state/providers.dart';
import 'package:returner/state/purchases.dart';

class _MockIpatool extends Mock implements IpatoolService {}

class _FakeAuth extends AuthController {
  _FakeAuth(this._initial);

  final AuthState _initial;

  @override
  AuthState build() => _initial;

  void signInAs(String email) => state = AuthState(
    AuthStatus.authenticated,
    account: AccountInfo(email: email, name: ''),
  );
}

AuthState _as(String email) => AuthState(
  AuthStatus.authenticated,
  account: AccountInfo(email: email, name: ''),
);

StoreApp _app(int id, {DateTime? date}) => StoreApp(
  appStoreId: '$id',
  bundleId: 'com.example.app$id',
  name: 'App $id',
  version: '1.$id',
  purchaseDate: date ?? DateTime.utc(2026, 1, 1).subtract(Duration(days: id)),
);

/// Apple's answer for [page], split from [apps] like `list-purchases`.
PurchasePage _page(List<StoreApp> apps, int page, int size, {int? total}) =>
    PurchasePage(
      apps: apps.skip((page - 1) * size).take(size).toList(),
      page: page,
      totalCount: total ?? apps.length,
    );

void main() {
  late Directory temp;
  late AppDatabase database;
  late _MockIpatool ipatool;
  late ProviderContainer container;
  late _FakeAuth auth;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('returner_purchases_');
    database = AppDatabase.inMemory();
    ipatool = _MockIpatool();
  });
  tearDown(() {
    container.dispose();
    database.close();
    temp.deleteSync(recursive: true);
  });

  void build({String email = 'user@example.com'}) {
    auth = _FakeAuth(_as(email));
    container = ProviderContainer(
      overrides: [
        appPathsProvider.overrideWithValue(AppPaths(temp.path)),
        databaseProvider.overrideWithValue(database),
        ipatoolServiceProvider.overrideWithValue(ipatool),
        authProvider.overrideWith(() => auth),
      ],
    );
  }

  void answer(List<StoreApp> apps, {int? total}) {
    when(
      () => ipatool.purchases(
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((call) async {
      final page = call.namedArguments[#page] as int;
      final size = call.namedArguments[#pageSize] as int;
      return _page(apps, page, size, total: total);
    });
  }

  test('nothing is saved before the first fetch', () {
    build();
    expect(container.read(purchasesProvider).history, isNull);
  });

  test('fetches every page, keeps progress and saves newest first', () async {
    build();
    final apps = [for (var i = 1; i <= 250; i++) _app(i)];
    answer(apps);
    final progress = <(int, int)>[];
    container.listen(purchasesProvider, (_, next) {
      if (next.loading && next.total > 0) {
        progress.add((next.loaded, next.total));
      }
    });

    await container.read(purchasesProvider.notifier).refresh();

    verify(() => ipatool.purchases(page: 1, pageSize: 100)).called(1);
    verify(() => ipatool.purchases(page: 2, pageSize: 100)).called(1);
    verify(() => ipatool.purchases(page: 3, pageSize: 100)).called(1);
    verifyNoMoreInteractions(ipatool);
    expect(progress, [(100, 250), (200, 250), (250, 250)]);

    final state = container.read(purchasesProvider);
    expect(state.loading, isFalse);
    expect(state.error, isNull);
    expect(state.history!.apps, hasLength(250));
    // _app(1) has the latest purchase date.
    expect(state.history!.apps.first.appStoreId, '1');
    expect(state.history!.apps.last.appStoreId, '250');

    // A fresh start reads the saved list without asking Apple.
    container.dispose();
    build();
    final saved = container.read(purchasesProvider).history!;
    expect(saved.apps, hasLength(250));
    expect(saved.apps.first.bundleId, 'com.example.app1');
    expect(saved.apps.first.purchaseDate, DateTime.utc(2025, 12, 31));
    verifyNoMoreInteractions(ipatool);
  });

  test(
    'a repeat purchase is one row and a short total ends the loop',
    () async {
      build();
      // Apple reports more than it returns: stop on the short page.
      answer([_app(1), _app(2), _app(1)], total: 5);
      await container.read(purchasesProvider.notifier).refresh();
      expect(
        container
            .read(purchasesProvider)
            .history!
            .apps
            .map((a) => a.appStoreId),
        ['1', '2'],
      );
      verify(() => ipatool.purchases(page: 1, pageSize: 100)).called(1);
      verifyNoMoreInteractions(ipatool);
    },
  );

  test('an empty history is saved as empty, not as never fetched', () async {
    build();
    answer(const []);
    await container.read(purchasesProvider.notifier).refresh();
    final history = container.read(purchasesProvider).history;
    expect(history, isNotNull);
    expect(history!.apps, isEmpty);
  });

  test('a failed refresh keeps the saved list and the error', () async {
    build();
    answer([_app(1), _app(2)]);
    await container.read(purchasesProvider.notifier).refresh();

    // Page 1 succeeds, page 2 fails: nothing of the partial fetch is saved.
    final more = [for (var i = 1; i <= 150; i++) _app(i)];
    when(
      () => ipatool.purchases(
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((call) async {
      if (call.namedArguments[#page] == 2) throw const NetworkInterrupted();
      return _page(more, 1, 100);
    });
    await container.read(purchasesProvider.notifier).refresh();

    final state = container.read(purchasesProvider);
    expect(state.error, isA<NetworkInterrupted>());
    expect(state.loading, isFalse);
    expect(state.history!.apps, hasLength(2));
    container.dispose();
    build();
    expect(container.read(purchasesProvider).history!.apps, hasLength(2));
  });

  test('an expired session signs the account out', () async {
    build();
    when(
      () => ipatool.purchases(
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenThrow(const AuthSessionExpired());
    await container.read(purchasesProvider.notifier).refresh();
    expect(container.read(authProvider).status, AuthStatus.expired);
  });

  test('each account has its own history', () async {
    build(email: 'first@example.com');
    answer([_app(1)]);
    await container.read(purchasesProvider.notifier).refresh();

    auth.signInAs('second@example.com');
    expect(container.read(purchasesProvider).history, isNull);

    auth.signInAs('first@example.com');
    expect(container.read(purchasesProvider).history!.apps, hasLength(1));
  });

  test('a second refresh while one runs does nothing', () async {
    build();
    final gate = Completer<PurchasePage>();
    when(
      () => ipatool.purchases(
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) => gate.future);
    final first = container.read(purchasesProvider.notifier).refresh();
    await container.read(purchasesProvider.notifier).refresh();
    gate.complete(_page([_app(1)], 1, 100));
    await first;
    verify(
      () => ipatool.purchases(
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).called(1);
  });
}
