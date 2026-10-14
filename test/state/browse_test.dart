import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:returner/core/app_paths.dart';
import 'package:returner/core/errors.dart';
import 'package:returner/models/app_ref.dart';
import 'package:returner/models/ipa_info.dart';
import 'package:returner/models/store.dart';
import 'package:returner/services/database.dart';
import 'package:returner/services/ipatool_service.dart';
import 'package:returner/services/package_store.dart';
import 'package:returner/state/auth.dart';
import 'package:returner/state/catalog.dart';
import 'package:returner/state/library.dart';
import 'package:returner/state/providers.dart';
import 'package:returner/state/settings.dart';
import 'package:flutter/material.dart' show ThemeMode;

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

const _signedIn = AuthState(
  AuthStatus.authenticated,
  account: AccountInfo(email: 'user@example.com', name: 'Ivan'),
);

StoreApp _app(int id) => StoreApp(
  appStoreId: '$id',
  bundleId: 'com.example.app$id',
  name: 'App $id',
  version: '1.$id',
  purchaseDate: DateTime.utc(2026, 1, 1).subtract(Duration(days: id)),
);

void main() {
  late Directory temp;
  late AppDatabase database;
  late _MockIpatool ipatool;
  late ProviderContainer container;
  late _FakeAuth auth;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('returner_browse_');
    database = AppDatabase.inMemory();
    ipatool = _MockIpatool();
  });
  tearDown(() {
    container.dispose();
    database.close();
    temp.deleteSync(recursive: true);
  });

  void build({AuthState authState = _signedIn}) {
    auth = _FakeAuth(authState);
    container = ProviderContainer(
      overrides: [
        appPathsProvider.overrideWithValue(AppPaths(temp.path)),
        databaseProvider.overrideWithValue(database),
        ipatoolServiceProvider.overrideWithValue(ipatool),
        authProvider.overrideWith(() => auth),
      ],
    );
  }

  group('search', () {
    test('returns results and ignores an outdated answer', () async {
      build();
      when(() => ipatool.search('slow')).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return [_app(1)];
      });
      when(() => ipatool.search('fast')).thenAnswer((_) async => [_app(2)]);
      final search = container.read(searchProvider.notifier);

      final slow = search.search('slow');
      await search.search(' fast ');
      await slow;

      final state = container.read(searchProvider);
      expect(state.query, 'fast');
      expect(state.results!.single.appStoreId, '2');
    });

    test('an empty query clears the results without a request', () async {
      build();
      await container.read(searchProvider.notifier).search('   ');
      expect(container.read(searchProvider).results, isNull);
      verifyNever(() => ipatool.search(any()));
    });

    test('keeps the error', () async {
      build();
      when(() => ipatool.search(any())).thenThrow(const AppleUnreachable());
      await container.read(searchProvider.notifier).search('x');
      expect(container.read(searchProvider).error, isA<AppleUnreachable>());
    });
  });

  group('catalog', () {
    test('the bundled catalog is valid and has no availability flag', () {
      final json = File('assets/catalog.json').readAsStringSync();
      final products = parseCatalog(json);

      expect(products, isNotEmpty);
      expect(json, isNot(contains('available')));
      final ids = [
        for (final product in products)
          for (final release in product.releases) release.appStoreId,
      ];
      expect(ids, everyElement(matches(r'^\d+$')));
      expect(ids.toSet(), hasLength(ids.length), reason: 'no duplicates');
      for (final product in products) {
        expect(product.title, isNotEmpty);
        expect(product.releases, isNotEmpty);
      }
    });

    test('a product can carry several listings', () {
      final products = parseCatalog(
        '[{"title":"Банк","category":"Банки","releases":['
        '{"appStoreId":"1","bundleId":"a.b","storeName":"Имя"},'
        '{"appStoreId":2,"bundleId":null}]}]',
      );
      final releases = products.single.releases;
      expect(releases.map((r) => r.appStoreId), ['1', '2']);
      expect(releases.first.ref.bundleId, 'a.b');
      expect(releases.first.storeName, 'Имя');
      expect(releases.last.storeName, isNull);
    });
  });

  group('library', () {
    const info = IpaInfo(
      bundleId: 'a.b',
      displayName: 'Имя: с/запретными*символами',
      displayVersion: '1.2',
      sha256: 'x',
      size: 4,
    );

    test('exports a copy and keeps the library file', () async {
      build();
      final staged = File(p.join(temp.path, 'staged.ipa'))
        ..writeAsStringSync('data');
      final package = await container
          .read(packageStoreProvider)
          .add(
            stagedPath: staged.path,
            info: info,
            accountId: 'acc',
            app: const AppRef(appStoreId: '1'),
          );
      container.invalidate(libraryProvider);
      expect(container.read(libraryProvider).single.id, package.id);

      final target = p.join(temp.path, 'Рабочий стол', 'out.ipa');
      Directory(p.dirname(target)).createSync();
      await container.read(libraryProvider.notifier).export(package, target);

      expect(File(target).readAsStringSync(), 'data');
      expect(File(package.path).existsSync(), isTrue);
    });

    test('remove deletes the package and updates the list', () async {
      build();
      final staged = File(p.join(temp.path, 'staged.ipa'))
        ..writeAsStringSync('data');
      final package = await container
          .read(packageStoreProvider)
          .add(
            stagedPath: staged.path,
            info: info,
            accountId: 'acc',
            app: const AppRef(appStoreId: '1'),
          );
      container.invalidate(libraryProvider);
      container.read(libraryProvider);

      await container.read(libraryProvider.notifier).remove(package.id);

      expect(container.read(libraryProvider), isEmpty);
      expect(File(package.path).existsSync(), isFalse);
    });

    test('export file name is safe for Windows', () {
      final name = exportFileName(
        Package(
          id: 'id',
          accountId: 'acc',
          path: 'x',
          info: info,
          finalizedAt: DateTime(2026),
        ),
      );
      expect(name, 'Имя_ с_запретными_символами 1.2.ipa');
    });
  });

  group('theme', () {
    test('night is the default and the choice is remembered', () {
      build();
      expect(container.read(themeModeProvider), ThemeMode.dark);
      container.read(themeModeProvider.notifier).toggle();
      expect(container.read(themeModeProvider), ThemeMode.light);
      container.dispose();

      build();
      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('a broken settings file falls back to night', () {
      File(p.join(temp.path, 'settings.json')).writeAsStringSync('{broken');
      build();
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });
}
