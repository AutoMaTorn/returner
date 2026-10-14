import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:returner/app.dart';
import 'package:returner/core/app_paths.dart';
import 'package:returner/core/binaries.dart';
import 'package:returner/core/errors.dart';
import 'package:returner/models/app_ref.dart';
import 'package:returner/models/device.dart';
import 'package:returner/models/ipa_info.dart';
import 'package:returner/models/store.dart';
import 'package:returner/services/driver_service.dart';
import 'package:returner/services/lookup_service.dart';
import 'package:returner/services/package_store.dart';
import 'package:returner/state/auth.dart';
import 'package:returner/state/catalog.dart';
import 'package:returner/state/devices.dart';
import 'package:returner/state/library.dart';
import 'package:returner/state/operations.dart';
import 'package:returner/state/providers.dart';
import 'package:returner/state/settings.dart';
import 'package:returner/state/versions.dart';
import 'package:returner/theme/am_widgets.dart';
import 'package:returner/theme/automatorn_theme.dart';
import 'package:returner/ui/home/install_panel.dart';
import 'package:returner/ui/strings.dart';
import 'package:returner/ui/widgets/app_widgets.dart';

const _account = AccountInfo(email: 'anna@example.com', name: 'Anna');
const _device = Device(
  udid: '00008140-000A1B2C3D4E001C',
  name: 'iPhone (Anna)',
  productType: 'iPhone17,1',
  osVersion: '27.0.1',
);
const _second = Device(
  udid: 'SECOND-UDID',
  name: 'iPhone (Work)',
  productType: 'iPhone15,2',
  osVersion: '18.1',
);
final _package = Package(
  id: 'pkg1',
  accountId: 'acc',
  path: r'C:\library\pkg1.ipa',
  appStoreId: '492224193',
  finalizedAt: DateTime(2026, 10, 14),
  info: const IpaInfo(
    bundleId: 'ru.sberbank.onlineiphone',
    displayName: 'СберБанк',
    displayVersion: '12.15.0',
    minimumOS: '13.0',
    sha256: 'abc123',
    size: 291278339,
  ),
);

/// Scripted sign-in: no processes are started.
class _FakeAuth extends AuthController {
  _FakeAuth({this.saved, this.needsCode = false});

  final AccountInfo? saved;
  final bool needsCode;
  String? lastCode;

  @override
  AuthState build() => const AuthState(AuthStatus.unknown);

  @override
  Future<void> restore() async {
    state = saved == null
        ? const AuthState(AuthStatus.signedOut)
        : AuthState(AuthStatus.authenticated, account: saved);
  }

  @override
  Future<void> login(String email, String password) async {
    state = needsCode
        ? const AuthState(AuthStatus.waitingForCode)
        : password == 'right'
        ? const AuthState(AuthStatus.authenticated, account: _account)
        : const AuthState(
            AuthStatus.signedOut,
            error: AuthInvalidCredentials(),
          );
  }

  @override
  Future<void> submitCode(String code) async {
    lastCode = code;
    state = const AuthState(AuthStatus.authenticated, account: _account);
  }

  @override
  Future<void> logout() async => state = const AuthState(AuthStatus.signedOut);
}

/// Records what the UI asks for and shows a scripted outcome.
class _FakeOperations extends OperationsController {
  final started = <({AppRef app, String? udid, bool allowFreeLicense})>[];
  final installs = <({Package package, String udid})>[];
  final retries = <({String id, bool? allowFreeLicense})>[];
  final cancelled = <String>[];

  /// How the next started operation looks on screen.
  Operation Function(Operation)? outcome;

  @override
  Future<void> recover() async {}

  Operation _show(Operation operation) =>
      (outcome ??
      (o) => o.copyWith(stage: OperationStage.downloading, bytes: 12500000))(
        operation,
      );

  @override
  String start(
    AppRef app, {
    String? title,
    String? deviceUdid,
    bool allowFreeLicense = false,
  }) {
    started.add((
      app: app,
      udid: deviceUdid,
      allowFreeLicense: allowFreeLicense,
    ));
    final id = 'op${started.length}';
    state = [
      ...state,
      _show(
        Operation(
          id: id,
          app: app,
          title: title ?? app.key,
          deviceUdid: deviceUdid,
          allowFreeLicense: allowFreeLicense,
        ),
      ),
    ];
    return id;
  }

  @override
  String startInstall(Package package, String deviceUdid) {
    installs.add((package: package, udid: deviceUdid));
    return 'install${installs.length}';
  }

  @override
  String? retry(String id, {bool? allowFreeLicense}) {
    retries.add((id: id, allowFreeLicense: allowFreeLicense));
    return 'retry';
  }

  @override
  void cancel(String id) => cancelled.add(id);
}

class _FakeLibrary extends LibraryController {
  _FakeLibrary(this._packages);

  final List<Package> _packages;
  final removed = <String>[];
  final exported = <String>[];

  @override
  List<Package> build() => _packages;

  @override
  Future<void> remove(String id) async {
    removed.add(id);
    state = const [];
  }

  @override
  Future<void> export(Package package, String destination) async =>
      exported.add(destination);
}

class _FakeSearch extends StoreSearchController {
  final queries = <String>[];

  @override
  Future<void> search(String query) async {
    queries.add(query);
    state = SearchState(
      query: query,
      results: query == 'nothing'
          ? const []
          : const [
              StoreApp(
                appStoreId: '686449807',
                bundleId: 'ph.telegra.Telegraph',
                name: 'Telegram Messenger',
                version: '13.0',
              ),
            ],
    );
  }
}

class _FakeVersions implements VersionsRepository {
  final resolved = <String>[];

  @override
  Future<List<String>> list(AppRef app) async => ['300', '200', '100'];

  @override
  VersionMetadata? cached(AppRef app, String externalVersionId) => null;

  @override
  Future<VersionMetadata> metadata(AppRef app, String id) async {
    resolved.add(id);
    return VersionMetadata(
      externalVersionId: id,
      displayVersion: '11.$id',
      releaseDate: DateTime.utc(2024, 3, 9),
    );
  }
}

class _FakeDriverInstall extends DriverInstallController {
  _FakeDriverInstall(this._result);

  final DriverInstallStatus _result;
  var calls = 0;

  @override
  Future<void> install() async {
    calls++;
    state = DriverInstallState(_result);
  }
}

Finder button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<ButtonStyleButton>(),
);

bool enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(button(label)).onPressed != null;

/// Extra catalog rows, to make the list longer than the window.
var _filler = 0;

const _desktop = Size(1280, 800);
const _phone = Size(390, 844);

void main() {
  late Directory temp;
  late _FakeAuth auth;
  late _FakeOperations operations;
  late _FakeLibrary library;
  late _FakeSearch search;
  late _FakeDriverInstall driver;
  late _FakeVersions versions;
  late List<String> opened;
  late List<String> clipboard;

  setUp(() {
    _filler = 0;
    temp = Directory.systemTemp.createTempSync('returner_ui_');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = _desktop,
    AccountInfo? saved,
    bool needsCode = false,
    List<Device> devices = const [_device],
    List<Package>? packages,
    bool driverMissing = false,
    DriverInstallStatus driverResult = DriverInstallStatus.idle,
    bool binariesPresent = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The text spinner runs forever; with animations off it stands still.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    auth = _FakeAuth(saved: saved, needsCode: needsCode);
    operations = _FakeOperations();
    library = _FakeLibrary(packages ?? [_package]);
    search = _FakeSearch();
    driver = _FakeDriverInstall(driverResult);
    versions = _FakeVersions();
    opened = [];
    clipboard = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPathsProvider.overrideWithValue(AppPaths(temp.path)),
          authProvider.overrideWith(() => auth),
          operationsProvider.overrideWith(() => operations),
          libraryProvider.overrideWith(() => library),
          searchProvider.overrideWith(() => search),
          driverInstallProvider.overrideWith(() => driver),
          versionsRepositoryProvider.overrideWithValue(versions),
          reportProvider.overrideWithValue(() => 'REPORT 0.1.0'),
          devicesProvider.overrideWith(
            (ref) => driverMissing
                ? Stream.error(const DriverMissing())
                : Stream.value(devices),
          ),
          catalogProvider.overrideWith(
            (ref) async => [
              const CatalogProduct(
                title: 'СберБанк Онлайн',
                category: 'Банки',
                releases: [
                  CatalogRelease(
                    appStoreId: '492224193',
                    bundleId: 'ru.sberbank.onlineiphone',
                  ),
                ],
              ),
              const CatalogProduct(
                title: 'Rutube',
                category: 'Кино и ТВ',
                releases: [
                  CatalogRelease(appStoreId: '111', storeName: 'SlicingDices'),
                  CatalogRelease(appStoreId: '222', storeName: 'Starship'),
                ],
              ),
              for (var i = 0; i < _filler; i++)
                CatalogProduct(
                  title: 'Приложение $i',
                  category: '',
                  releases: [CatalogRelease(appStoreId: '${9000 + i}')],
                ),
            ],
          ),
          lookupServiceProvider.overrideWithValue(
            LookupService(
              client: MockClient((_) async => http.Response('', 404)),
              iconDirectory: temp.path,
            ),
          ),
          urlOpenerProvider.overrideWithValue((url) async => opened.add(url)),
          saveLocationProvider.overrideWithValue(
            (name) async => '${temp.path}/$name',
          ),
          binariesProvider.overrideWithValue(
            Binaries(
              executablePath: r'C:\app\returner.exe',
              currentDirectory: r'C:\app',
              platform: 'windows-x64',
              fileExists: (_) => binariesPresent,
            ),
          ),
        ],
        child: const ReturnerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openHome(
    WidgetTester tester, {
    Size size = _desktop,
    List<Device> devices = const [_device],
    List<Package>? packages,
    bool driverMissing = false,
    DriverInstallStatus driverResult = DriverInstallStatus.idle,
  }) async {
    await pumpApp(
      tester,
      size: size,
      saved: _account,
      devices: devices,
      packages: packages,
      driverMissing: driverMissing,
      driverResult: driverResult,
    );
    await tap(tester, button(S.setupContinue));
  }

  Future<void> openSection(WidgetTester tester, String label) =>
      tap(tester, find.text(label).first);

  group('sign-in', () {
    testWidgets('first run: setup → login → home → settings → logout', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text(S.setupLead), findsOneWidget);

      await tap(tester, button(S.setupContinue));
      expect(find.text(S.loginTitle), findsOneWidget);

      // An empty form says what is missing.
      await tap(tester, button(S.loginSubmit));
      expect(find.text(S.loginFillBoth), findsOneWidget);

      // Wrong password: the reason and the fix are shown, the field is cleared.
      await tester.enterText(find.byType(TextField).at(0), 'anna@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'wrong');
      await tap(tester, button(S.loginSubmit));
      expect(find.text(S.loginFailed), findsOneWidget);
      expect(
        find.text(S.errorText(const AuthInvalidCredentials())),
        findsOneWidget,
      );
      expect(find.text('wrong'), findsNothing);

      await tester.enterText(find.byType(TextField).at(1), 'right');
      await tap(tester, button(S.loginSubmit));

      // Home: masked account and the device in the side navigation.
      expect(find.text('a***@example.com'), findsOneWidget);
      expect(find.text('anna@example.com'), findsNothing);
      expect(find.text('iPhone (Anna)'), findsOneWidget);
      expect(find.text('iOS 27.0.1'), findsOneWidget);

      await openSection(tester, S.sectionSettings);
      expect(find.text(S.settingsLogoutNote), findsOneWidget);
      await tap(tester, button(S.settingsLogout));
      expect(find.text(S.loginTitle), findsOneWidget);
    });

    testWidgets('a saved session skips the login screen', (tester) async {
      await openHome(tester);
      expect(find.text(S.catalogLabel), findsOneWidget);
    });

    testWidgets('2FA step accepts only a six-digit code', (tester) async {
      await pumpApp(tester, needsCode: true);
      await tap(tester, button(S.setupContinue));
      await tester.enterText(find.byType(TextField).at(0), 'anna@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'right');
      await tap(tester, button(S.loginSubmit));
      expect(find.text(S.loginCodeTitle), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123');
      await tap(tester, button(S.loginCodeSubmit));
      expect(auth.lastCode, isNull);

      await tester.enterText(find.byType(TextField), '123456');
      await tap(tester, button(S.loginCodeSubmit));
      expect(auth.lastCode, '123456');
      expect(find.text(S.catalogLabel), findsOneWidget);
    });

    testWidgets('a missing bundled tool is reported on the setup screen', (
      tester,
    ) async {
      await pumpApp(tester, binariesPresent: false);
      expect(find.text(S.setupFailed), findsOneWidget);
      expect(find.textContaining('ipatool'), findsOneWidget);
      expect(button(S.setupContinue), findsNothing);
      expect(button(S.retry), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('has four sections and no purchases or tasks screens', (
      tester,
    ) async {
      await openHome(tester);
      for (final label in [
        S.sectionCatalog,
        S.sectionSearch,
        S.sectionFiles,
        S.sectionSettings,
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      for (final gone in ['покупки', 'Покупки', 'задачи', 'Задачи']) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
      // The files counter sits next to its section.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('phone width uses a bottom bar and stacks the panels', (
      tester,
    ) async {
      await openHome(tester, size: _phone);
      expect(find.byType(NavigationBar), findsOneWidget);

      for (final label in ['поиск', 'файлы', 'настройки', 'каталог']) {
        await tap(tester, find.text(label));
        expect(tester.takeException(), isNull, reason: label);
      }
      await tap(tester, find.text('СберБанк Онлайн'));
      expect(button(S.actionInstall), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('catalog', () {
    for (final size in [_desktop, _phone]) {
      testWidgets(
        'the install button stays reachable far down the list at $size',
        (tester) async {
          _filler = 80;
          await openHome(tester, size: size);
          final last = find.text('Приложение 79');
          await tester.scrollUntilVisible(
            last,
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(last);
          await tester.pumpAndSettle();

          // No scrolling back: the button is on screen and takes the tap.
          final install = button(S.actionInstall);
          final box = tester.getRect(install);
          expect(box.top, greaterThanOrEqualTo(0));
          expect(box.bottom, lessThanOrEqualTo(size.height));
          await tester.tap(install);
          await tester.pumpAndSettle();
          expect(operations.started.single.app.appStoreId, '9079');
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'filters by name, store name or ID and says when nothing fits',
      (tester) async {
        await openHome(tester);
        await tester.enterText(find.byType(TextField), 'starship');
        await tester.pumpAndSettle();
        expect(find.text('Rutube'), findsOneWidget);
        expect(find.text('СберБанк Онлайн'), findsNothing);
        expect(find.text('1 из 3'), findsOneWidget);

        await tester.enterText(find.byType(TextField), '4922');
        await tester.pumpAndSettle();
        expect(find.text('СберБанк Онлайн'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'нет такого');
        await tester.pumpAndSettle();
        expect(find.text(S.catalogEmpty('нет такого')), findsOneWidget);
        await tap(tester, button(S.catalogOpenSearch));
        expect(find.text(S.searchLabel), findsOneWidget);
      },
    );

    testWidgets('each listing is its own row with its own ID', (tester) async {
      await openHome(tester);
      expect(find.text('Rutube'), findsNWidgets(2));
      expect(find.text('SlicingDices · кино и тв · id 111'), findsOneWidget);
      expect(find.text('Starship · кино и тв · id 222'), findsOneWidget);
      // Nothing is selected yet: the panel says what to do.
      expect(find.text(S.panelEmpty), findsOneWidget);
      expect(button(S.actionInstall), findsNothing);
    });

    testWidgets(
      'install is the one primary action and is pinned to the device',
      (tester) async {
        await openHome(tester);
        await tap(tester, find.text('СберБанк Онлайн'));

        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.text('ru.sberbank.onlineiphone'), findsOneWidget);
        await tap(tester, button(S.actionInstall));

        final started = operations.started.single;
        expect(started.app.appStoreId, '492224193');
        expect(started.udid, _device.udid);
        expect(started.allowFreeLicense, isFalse);

        // Progress is shown in place, with real bytes and a way to stop.
        expect(find.text('скачиваем — 12.5 МБ'), findsOneWidget);
        expect(find.text('идёт'), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
        await tap(tester, find.text('[${S.cancel}]'));
        expect(operations.cancelled, ['op1']);
      },
    );

    testWidgets('install progress is a text scale with a percentage', (
      tester,
    ) async {
      await openHome(tester);
      operations.outcome = (o) => o.copyWith(
        stage: OperationStage.installing,
        installPercent: () => 50,
      );
      await tap(tester, find.text('СберБанк Онлайн'));
      await tap(tester, button(S.actionInstall));
      expect(find.byType(AmAsciiProgress), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'устанавливаем\s+50%')),
        findsOneWidget,
      );
    });

    testWidgets('a confirmed install is said in words with a mark', (
      tester,
    ) async {
      await openHome(tester);
      operations.outcome = (o) => o.copyWith(
        stage: OperationStage.done,
        outcome: InstallOutcome.confirmed,
        package: _package,
        title: 'СберБанк',
      );
      await tap(tester, find.text('СберБанк Онлайн'));
      await tap(tester, button(S.actionInstall));

      expect(find.text(S.doneInstalled), findsOneWidget);
      expect(
        find.text('«СберБанк» 12.15.0 на iPhone — версия подтверждена.'),
        findsOneWidget,
      );
      expect(find.text('✓ установлено'), findsOneWidget);
    });

    testWidgets('a missing license is explained and needs explicit consent', (
      tester,
    ) async {
      await openHome(tester);
      operations.outcome = (o) => o.copyWith(
        stage: OperationStage.failed,
        error: const LicenseRequired(),
      );
      await tap(tester, find.text('СберБанк Онлайн'));
      // No consent checkbox anywhere before the question arises.
      expect(find.byType(Checkbox), findsNothing);
      await tap(tester, button(S.actionDownload));

      expect(operations.started.single.allowFreeLicense, isFalse);
      expect(find.text(S.noLicense), findsOneWidget);
      expect(find.text(S.noLicenseBody), findsOneWidget);

      await tap(tester, button(S.actionGetLicense));
      expect(operations.retries.single, (id: 'op1', allowFreeLicense: true));
    });

    testWidgets('another failure offers a plain retry', (tester) async {
      await openHome(tester);
      operations.outcome = (o) =>
          o.copyWith(stage: OperationStage.failed, error: const DeviceLocked());
      await tap(tester, find.text('СберБанк Онлайн'));
      await tap(tester, button(S.actionInstall));

      expect(find.text(S.errorText(const DeviceLocked())), findsOneWidget);
      expect(find.text('! ошибка'), findsOneWidget);
      await tap(tester, button(S.retry));
      expect(operations.retries.single, (id: 'op1', allowFreeLicense: null));
    });

    testWidgets('an unknown result warns before any retry', (tester) async {
      await openHome(tester);
      operations.outcome = (o) => o.copyWith(
        stage: OperationStage.unknown,
        error: const InstallResultUnknown(),
      );
      await tap(tester, find.text('СберБанк Онлайн'));
      await tap(tester, button(S.actionInstall));
      expect(find.text(S.resultUnknown), findsOneWidget);
      expect(find.text(S.resultUnknownBody), findsOneWidget);
    });

    testWidgets('a task for another app stays in sight', (tester) async {
      await openHome(tester);
      await tap(tester, find.text('СберБанк Онлайн'));
      await tap(tester, button(S.actionDownload));
      expect(find.text(S.activityLabel), findsNothing);

      await tap(tester, find.text('SlicingDices · кино и тв · id 111'));
      expect(find.text(S.activityLabel), findsOneWidget);
      expect(
        find.text('СберБанк Онлайн — скачиваем — 12.5 МБ'),
        findsOneWidget,
      );
      await tap(tester, find.text('[${S.activityShow}]'));
      expect(find.text(S.activityLabel), findsNothing);
      expect(find.text('ru.sberbank.onlineiphone'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets(
      'an App Store ID or link is offered at once, without a search',
      (tester) async {
        await openHome(tester);
        await openSection(tester, S.sectionSearch);
        await tester.enterText(
          find.byType(TextField),
          'https://apps.apple.com/ru/app/x/id492224193',
        );
        await tester.pumpAndSettle();

        expect(find.text('App Store ID 492224193'), findsOneWidget);
        expect(enabled(tester, S.searchSubmit), isFalse);
        await tap(tester, find.text('App Store ID 492224193'));
        await tap(tester, button(S.actionInstall));
        expect(operations.started.single.app.appStoreId, '492224193');
        expect(search.queries, isEmpty);
      },
    );

    testWidgets('a name is searched in the store', (tester) async {
      await openHome(tester);
      await openSection(tester, S.sectionSearch);
      await tester.enterText(find.byType(TextField), 'telegram');
      await tester.pumpAndSettle();
      await tap(tester, button(S.searchSubmit));

      expect(search.queries, ['telegram']);
      await tap(tester, find.text('Telegram Messenger'));
      expect(find.text('ph.telegra.Telegraph'), findsOneWidget);
    });

    testWidgets('nothing found says what to try instead', (tester) async {
      await openHome(tester);
      await openSection(tester, S.sectionSearch);
      await tester.enterText(find.byType(TextField), 'nothing');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text(S.searchEmpty('nothing')), findsOneWidget);
    });
  });

  group('files', () {
    Future<void> openPackage(WidgetTester tester) async {
      await openHome(tester);
      await openSection(tester, S.sectionFiles);
      expect(find.text('12.15.0 · 291.3 МБ'), findsOneWidget);
      expect(find.text('14.10.2026'), findsOneWidget);
      await tap(tester, find.text('СберБанк'));
    }

    testWidgets('shows the package details and installs it', (tester) async {
      await openPackage(tester);
      expect(find.text('abc123'), findsOneWidget);
      expect(find.text('13.0'), findsOneWidget);
      await tap(tester, button(S.actionInstall));
      expect(operations.installs.single.package.id, 'pkg1');
      expect(operations.installs.single.udid, _device.udid);
    });

    testWidgets('saves a copy and confirms with a toast', (tester) async {
      await openPackage(tester);
      await tap(tester, button(S.actionExport));
      expect(library.exported.single, endsWith('СберБанк 12.15.0.ipa'));
      expect(find.text(S.exported), findsOneWidget);
    });

    testWidgets('removal asks first and says what will happen', (tester) async {
      await openPackage(tester);
      await tap(tester, button(S.actionRemove));
      expect(find.text(S.removeTitle), findsOneWidget);
      expect(find.text(S.removeBody), findsOneWidget);

      await tap(tester, find.text('[${S.cancel}]'));
      expect(library.removed, isEmpty);

      await tap(tester, button(S.actionRemove));
      await tap(tester, button(S.actionRemove).last);
      expect(library.removed, ['pkg1']);
      expect(find.text(S.filesEmpty), findsOneWidget);
    });

    testWidgets('an empty library says how to fill it', (tester) async {
      await openHome(tester, packages: const []);
      await openSection(tester, S.sectionFiles);
      expect(find.text(S.filesEmpty), findsOneWidget);
      await tap(tester, button(S.filesOpenCatalog));
      expect(find.text(S.catalogLabel), findsOneWidget);
    });
  });

  group('versions', () {
    testWidgets(
      'an older build can be pinned and is then what gets installed',
      (tester) async {
        await openHome(tester);
        await tap(tester, find.text('СберБанк Онлайн'));
        await tap(tester, button(S.actionPickVersion));

        expect(find.text(S.versionsTitle), findsOneWidget);
        expect(find.text('сборка 300 · последняя'), findsOneWidget);
        expect(find.text('сборка 100'), findsOneWidget);

        // The human version is fetched only on request, one build at a time.
        expect(versions.resolved, isEmpty);
        await tap(tester, find.text('[${S.versionsResolve}]').at(1));
        expect(versions.resolved, ['200']);
        expect(find.text('11.200 · 09.03.2024'), findsOneWidget);

        await tap(tester, find.text('сборка 200'));
        expect(find.text(S.versionsTitle), findsNothing);
        expect(find.text('11.200 · сборка 200'), findsOneWidget);

        await tap(tester, button(S.actionInstall));
        final started = operations.started.single;
        expect(started.app.appStoreId, '492224193');
        expect(started.app.externalVersionId, '200');
        expect(started.udid, _device.udid);
      },
    );

    testWidgets('going back to the latest version clears the pin', (
      tester,
    ) async {
      await openHome(tester);
      await tap(tester, find.text('СберБанк Онлайн'));
      await tap(tester, button(S.actionPickVersion));
      await tap(tester, find.text('сборка 100'));
      expect(find.text('сборка 100'), findsOneWidget);

      await tap(tester, button(S.actionPickVersion));
      await tap(tester, button(S.versionsLatest));
      expect(find.textContaining('сборка 100'), findsNothing);
      await tap(tester, button(S.actionDownload));
      expect(operations.started.single.app.externalVersionId, isNull);
    });

    testWidgets('an iOS that is too old leads straight to the picker', (
      tester,
    ) async {
      await openHome(tester);
      operations.outcome = (o) => o.copyWith(
        stage: OperationStage.failed,
        error: const IncompatibleOS(),
      );
      await tap(tester, find.text('СберБанк Онлайн'));
      await tap(tester, button(S.actionInstall));
      expect(find.text(S.errorText(const IncompatibleOS())), findsOneWidget);

      await tap(tester, button(S.actionOlderVersion));
      await tap(tester, find.text('сборка 100'));

      // The install starts again with the chosen build, on the same device.
      expect(operations.started, hasLength(2));
      expect(operations.started.last.app.externalVersionId, '100');
      expect(operations.started.last.udid, _device.udid);
    });
  });

  group('report and settings', () {
    testWidgets('a failure can be reported in one click', (tester) async {
      await openHome(tester);
      operations.outcome = (o) => o.copyWith(
        stage: OperationStage.failed,
        error: const Unclassified('x'),
      );
      await tap(tester, find.text('СберБанк Онлайн'));
      await tap(tester, button(S.actionInstall));

      await tap(tester, find.text('[${S.copyReport}]'));
      expect(clipboard, ['REPORT 0.1.0']);
      expect(find.text(S.reportCopied), findsOneWidget);
    });

    testWidgets('settings: report, log folder, storefront, licenses', (
      tester,
    ) async {
      await openHome(tester);
      await openSection(tester, S.sectionSettings);

      await tap(tester, button(S.copyReportButton));
      expect(clipboard, ['REPORT 0.1.0']);

      await tap(tester, button(S.openLogFolder));
      expect(opened.single, startsWith('file:///'));
      expect(opened.single, endsWith('/logs'));

      await tap(tester, find.text('KZ'));
      expect(
        File('${temp.path}/settings.json').readAsStringSync(),
        contains('"lookupCountry":"kz"'),
      );

      // Let the "report copied" toast go away: it floats over the bottom.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tap(tester, button(S.aboutLicenses));
      // The license texts are read from bundled files: real I/O.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(find.text(S.aboutPatched), findsOneWidget);
      expect(find.textContaining('Majd Alfhaily'), findsOneWidget);
      expect(find.textContaining('danielpaulus'), findsOneWidget);
      await tap(tester, find.text('[${S.aboutClose}]'));

      await tap(tester, find.text('[ipatool]'));
      expect(opened.last, 'https://github.com/majd/ipatool');
    });
  });

  group('devices', () {
    testWidgets('without a device install is off and says why', (tester) async {
      await openHome(tester, devices: const []);
      expect(find.text(S.deviceNone), findsOneWidget);
      await tap(tester, find.text('СберБанк Онлайн'));

      expect(enabled(tester, S.actionInstall), isFalse);
      expect(find.text(S.needDevice), findsOneWidget);
      await tap(tester, button(S.actionDownload));
      expect(operations.started.single.udid, isNull);
    });

    testWidgets('with two devices none is picked silently', (tester) async {
      await openHome(tester, devices: const [_device, _second]);
      expect(find.text(S.severalTitle), findsOneWidget);
      await tap(tester, find.text('СберБанк Онлайн'));
      expect(enabled(tester, S.actionInstall), isFalse);

      await tap(tester, button('iPhone (Work)'));
      expect(find.text(S.severalTitle), findsNothing);
      await tap(tester, button(S.actionInstall));
      expect(operations.started.single.udid, _second.udid);
    });

    testWidgets('a missing driver is installed only on request', (
      tester,
    ) async {
      await openHome(tester, driverMissing: true);
      expect(find.text(S.driverTitle), findsOneWidget);
      expect(find.text(S.deviceDriverMissing), findsOneWidget);
      expect(driver.calls, 0);

      await tap(tester, button(S.driverInstall));
      expect(driver.calls, 1);
    });

    testWidgets('manual links appear when the automatic install fails', (
      tester,
    ) async {
      await openHome(
        tester,
        driverMissing: true,
        driverResult: DriverInstallStatus.failed,
      );
      expect(button(S.driverOpenStore), findsNothing);
      await tap(tester, button(S.driverInstall));
      expect(find.text(S.driverFailedTitle), findsOneWidget);

      await tap(tester, button(S.driverOpenStore));
      await tap(tester, button(S.driverItunes));
      expect(opened, [DriverService.storeUri, DriverService.itunesUri]);
    });
  });

  group('design system', () {
    Color background(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(Scaffold).first))
            .scaffoldBackgroundColor;

    testWidgets('night by default; the choice is remembered', (tester) async {
      await openHome(tester);
      expect(background(tester), AmColors.dark.page);

      await openSection(tester, S.sectionSettings);
      await tap(tester, find.text(S.themePaper));
      expect(background(tester), AmColors.light.page);
      expect(
        File('${temp.path}/settings.json').readAsStringSync(),
        contains('light'),
      );
    });

    testWidgets('every section renders in both themes at both widths', (
      tester,
    ) async {
      for (final size in [_desktop, _phone]) {
        await openHome(tester, size: size);
        final phone = size == _phone;
        for (final theme in [S.themePaper, S.themeNight]) {
          await tap(tester, find.text(phone ? 'настройки' : S.sectionSettings));
          await tap(tester, find.text(theme));
          for (final label in [
            S.sectionCatalog,
            S.sectionSearch,
            S.sectionFiles,
            S.sectionSettings,
          ]) {
            await tap(
              tester,
              find.text(phone ? label.toLowerCase() : label).first,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$size $theme $label',
            );
          }
        }
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('one typeface at weight 400 everywhere', (tester) async {
      await openHome(tester);
      await tap(tester, find.text('СберБанк Онлайн'));
      final styles = [
        for (final text in tester.widgetList<RichText>(find.byType(RichText)))
          text.text.style,
      ];
      expect(styles, isNotEmpty);
      for (final style in styles) {
        expect(style?.fontFamily, Automatorn.fontFamily);
        expect(style?.fontWeight, FontWeight.w400);
      }
    });

    testWidgets('controls keep the system height on desktop', (tester) async {
      await openHome(tester);
      await tap(tester, find.text('СберБанк Онлайн'));
      expect(
        tester.getSize(button(S.actionInstall)).height,
        AmSize.controlHeight,
      );
      expect(
        tester.getSize(button(S.actionDownload)).height,
        AmSize.controlHeight,
      );
    });

    testWidgets('no elevation, cards or app bars', (tester) async {
      await openHome(tester);
      await tap(tester, find.text('СберБанк Онлайн'));
      for (final type in [Card, AppBar, FloatingActionButton, ElevatedButton]) {
        expect(find.byType(type), findsNothing, reason: '$type');
      }
      for (final material in tester.widgetList<Material>(
        find.byType(Material),
      )) {
        expect(material.elevation, 0);
      }
    });

    testWidgets('buttons work from the keyboard', (tester) async {
      await pumpApp(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text(S.loginTitle), findsOneWidget);
    });
  });
}
