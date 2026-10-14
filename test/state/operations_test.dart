import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:returner/core/app_paths.dart';
import 'package:returner/core/cancel.dart';
import 'package:returner/core/errors.dart';
import 'package:returner/models/app_ref.dart';
import 'package:returner/models/device.dart';
import 'package:returner/models/ipa_info.dart';
import 'package:returner/models/store.dart';
import 'package:returner/services/database.dart';
import 'package:returner/services/device_service.dart';
import 'package:returner/services/download_service.dart';
import 'package:returner/services/ipa_inspector.dart';
import 'package:returner/services/ipatool_service.dart';
import 'package:returner/services/lookup_service.dart';
import 'package:returner/services/operation_journal.dart';
import 'package:returner/state/auth.dart';
import 'package:returner/state/operations.dart';
import 'package:returner/state/providers.dart';
import 'package:returner/state/settings.dart';

class _MockIpatool extends Mock implements IpatoolService {}

class _MockDownloads extends Mock implements DownloadService {}

class _MockInspector extends Mock implements IpaInspector {}

class _MockDevices extends Mock implements DeviceService {}

class _FakeAuth extends AuthController {
  _FakeAuth(this._initial);

  final AuthState _initial;

  @override
  AuthState build() => _initial;
}

const _app = AppRef(appStoreId: '492224193');
const _udid = '00008140-000A1B2C3D4E001C';
const _device = Device(
  udid: _udid,
  name: 'iPhone (Ivan)',
  productType: 'iPhone17,1',
  osVersion: '27.0.1',
);
const _info = IpaInfo(
  bundleId: 'ru.sberbank.onlineiphone',
  displayName: 'СберБанк',
  displayVersion: '12.15.0',
  minimumOS: '13.0',
  sha256: 'abc',
  size: 4,
);
const _signedIn = AuthState(
  AuthStatus.authenticated,
  account: AccountInfo(email: 'user@example.com', name: 'Ivan'),
);

void main() {
  late Directory temp;
  late AppPaths paths;
  late AppDatabase database;
  late _MockIpatool ipatool;
  late _MockDownloads downloads;
  late _MockInspector inspector;
  late _MockDevices devices;
  late ProviderContainer container;
  late int generation;

  setUpAll(() {
    registerFallbackValue(_app);
    registerFallbackValue(CancelToken());
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('returner_ops_');
    paths = AppPaths(temp.path);
    database = AppDatabase.inMemory();
    ipatool = _MockIpatool();
    downloads = _MockDownloads();
    inspector = _MockInspector();
    devices = _MockDevices();
    generation = 1;
    when(() => ipatool.generation).thenAnswer((_) => generation);
    when(() => inspector.inspect(any())).thenAnswer((_) async => _info);
    when(() => inspector.artwork(any())).thenAnswer((_) async => null);
    when(() => devices.listDevices()).thenAnswer((_) async => [_device]);
    when(() => devices.freeBytes(any())).thenAnswer((_) async => 1 << 30);
    when(() => devices.install(any(), any(), cancel: any(named: 'cancel')))
        .thenAnswer(
          (_) => Stream.fromIterable(const [
            InstallProgress(null, null),
            InstallProgress(60, 'InstallingApplication'),
            InstallProgress(100, 'InstallComplete'),
          ]),
        );
    when(() => devices.installedApp(any(), any())).thenAnswer(
      (_) async => const InstalledApp(
        bundleId: 'ru.sberbank.onlineiphone',
        name: 'СберБанк',
        version: '12.15.0',
      ),
    );
  });

  tearDown(() {
    container.dispose();
    database.close();
    temp.deleteSync(recursive: true);
  });

  void build({AuthState auth = _signedIn}) {
    container = ProviderContainer(
      overrides: [
        appPathsProvider.overrideWithValue(paths),
        databaseProvider.overrideWithValue(database),
        ipatoolServiceProvider.overrideWithValue(ipatool),
        downloadServiceProvider.overrideWithValue(downloads),
        ipaInspectorProvider.overrideWithValue(inspector),
        deviceServiceProvider.overrideWithValue(devices),
        lookupServiceProvider.overrideWithValue(
          LookupService(
            client: MockClient((_) async => http.Response('', 404)),
            iconDirectory: p.join(temp.path, 'icons'),
          ),
        ),
        authProvider.overrideWith(() => _FakeAuth(auth)),
      ],
    );
  }

  /// Scripts consecutive `DownloadService.download` calls. Each writes a file
  /// into the staging directory unless it throws.
  void downloadsAnswer(List<Object> results) {
    var index = 0;
    when(
      () => downloads.download(
        any(),
        any(),
        allowPurchase: any(named: 'allowPurchase'),
        cancel: any(named: 'cancel'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((invocation) async {
      final result =
          results[index < results.length ? index : results.length - 1];
      index++;
      if (result is AppError) throw result;
      final staging = invocation.positionalArguments[1] as String;
      final file = File(p.join(staging, DownloadService.fileName))
        ..createSync(recursive: true)
        ..writeAsStringSync('data');
      (invocation.namedArguments[#onProgress] as void Function(int)?)?.call(4);
      return DownloadResult(
        path: file.path,
        licenseAcquired: invocation.namedArguments[#allowPurchase] == true,
      );
    });
  }

  OperationsController controller() =>
      container.read(operationsProvider.notifier);
  Operation only() => container.read(operationsProvider).single;
  OperationJournal journal() => container.read(operationJournalProvider);

  Future<Operation> run({
    String? udid = _udid,
    bool allowFreeLicense = false,
  }) async {
    controller().start(
      _app,
      deviceUdid: udid,
      allowFreeLicense: allowFreeLicense,
    );
    await controller().idle;
    return only();
  }

  test('downloads, validates, installs and confirms on the device', () async {
    build();
    downloadsAnswer(['ok']);
    final stages = <OperationStage>[];
    container.listen(operationsProvider, (_, next) {
      if (stages.isEmpty || stages.last != next.single.stage) {
        stages.add(next.single.stage);
      }
    });

    final operation = await run();

    expect(operation.stage, OperationStage.done);
    expect(operation.outcome, InstallOutcome.confirmed);
    expect(operation.title, 'СберБанк');
    expect(operation.bytes, 4);
    expect(operation.error, isNull);
    expect(stages, [
      OperationStage.queued,
      OperationStage.checkingLicense,
      OperationStage.downloading,
      OperationStage.validating,
      OperationStage.installing,
      OperationStage.verifying,
      OperationStage.done,
    ]);
    expect(journal().stages(operation.id).last, 'done');
    expect(journal().find(operation.id)!.packageId, operation.package!.id);
    expect(journal().find(operation.id)!.deviceUdid, _udid);

    // The package is in the library, staging is gone.
    expect(File(operation.package!.path).existsSync(), isTrue);
    expect(Directory(paths.stagingFor(operation.id)).existsSync(), isFalse);
    verify(
      () => devices.install(
        _udid,
        operation.package!.path,
        cancel: any(named: 'cancel'),
      ),
    ).called(1);
  });

  test('download-only stops after the package is in the library', () async {
    build();
    downloadsAnswer(['ok']);
    final operation = await run(udid: null);

    expect(operation.stage, OperationStage.done);
    expect(operation.outcome, isNull);
    expect(operation.package, isNotNull);
    verifyNever(
      () => devices.install(any(), any(), cancel: any(named: 'cancel')),
    );
  });

  group('license', () {
    test('a missing license is reported, not worked around', () async {
      build();
      downloadsAnswer([const LicenseRequired()]);
      final operation = await run();

      expect(operation.stage, OperationStage.failed);
      expect(operation.error, isA<LicenseRequired>());
      expect(journal().find(operation.id)!.errorCode, 'LICENSE_REQUIRED');
      verify(
        () => downloads.download(
          any(),
          any(),
          allowPurchase: false,
          cancel: any(named: 'cancel'),
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);
      verifyNever(
        () => downloads.download(
          any(),
          any(),
          allowPurchase: true,
          cancel: any(named: 'cancel'),
          onProgress: any(named: 'onProgress'),
        ),
      );
    });

    test(
      'with consent the free license is acquired and the download retried',
      () async {
        build();
        downloadsAnswer([const LicenseRequired(), 'ok']);
        final operation = await run(allowFreeLicense: true);

        expect(operation.stage, OperationStage.done);
        expect(operation.licenseAcquired, isTrue);
        expect(journal().stages(operation.id), contains('acquiringLicense'));
      },
    );

    test('a refusal after the attempt is LicenseRefused', () async {
      build();
      downloadsAnswer([const LicenseRequired()]);
      final operation = await run(allowFreeLicense: true);

      expect(operation.stage, OperationStage.failed);
      expect(operation.error, isA<LicenseRefused>());
    });
  });

  test(
    'Apple refusing the asset fails with its reason and no package',
    () async {
      build();
      downloadsAnswer([const AssetUnavailable('No longer available.')]);
      final operation = await run();

      expect(operation.stage, OperationStage.failed);
      expect(
        (operation.error as AssetUnavailable).appleMessage,
        'No longer available.',
      );
      expect(operation.package, isNull);
      expect(container.read(packageStoreProvider).list(), isEmpty);
    },
  );

  test('an invalid file never reaches the library', () async {
    build();
    downloadsAnswer(['ok']);
    when(() => inspector.inspect(any())).thenThrow(const PackageInvalid());
    final operation = await run();

    expect(operation.stage, OperationStage.failed);
    expect(operation.error, isA<PackageInvalid>());
    expect(container.read(packageStoreProvider).list(), isEmpty);
    expect(Directory(paths.stagingFor(operation.id)).existsSync(), isFalse);
  });

  test(
    'an expired session fails the operation and flags the account',
    () async {
      build();
      downloadsAnswer([const AuthSessionExpired()]);
      final operation = await run();

      expect(operation.error, isA<AuthSessionExpired>());
      expect(container.read(authProvider).status, AuthStatus.expired);
    },
  );

  test('not signed in: nothing is downloaded', () async {
    build(auth: const AuthState(AuthStatus.signedOut));
    downloadsAnswer(['ok']);
    final operation = await run();

    expect(operation.stage, OperationStage.failed);
    expect(operation.error, isA<AuthSessionExpired>());
    verifyNever(
      () => downloads.download(
        any(),
        any(),
        allowPurchase: any(named: 'allowPurchase'),
        cancel: any(named: 'cancel'),
        onProgress: any(named: 'onProgress'),
      ),
    );
  });

  test('an account change mid-download discards the package', () async {
    build();
    downloadsAnswer(['ok']);
    when(() => inspector.inspect(any())).thenAnswer((_) async {
      generation++;
      return _info;
    });
    final operation = await run();

    expect(operation.stage, OperationStage.cancelled);
    expect(container.read(packageStoreProvider).list(), isEmpty);
    verifyNever(
      () => devices.install(any(), any(), cancel: any(named: 'cancel')),
    );
  });

  group('install', () {
    setUp(() {
      build();
      downloadsAnswer(['ok']);
    });

    void installThrows(AppError error) =>
        when(() => devices.install(any(), any(), cancel: any(named: 'cancel')))
            .thenAnswer((_) => Stream.error(error));

    test(
      'never switches to another device when the chosen one is gone',
      () async {
        when(() => devices.listDevices()).thenAnswer(
          (_) async => [
            const Device(
              udid: 'OTHER-UDID',
              name: 'Other iPhone',
              productType: 'iPhone15,2',
              osVersion: '18.0',
            ),
          ],
        );
        final operation = await run();

        expect(operation.stage, OperationStage.failed);
        expect(operation.error, isA<DeviceNotFound>());
        expect(operation.package, isNotNull, reason: 'the download is kept');
        expect(File(operation.package!.path).existsSync(), isTrue);
        verifyNever(
          () => devices.install(any(), any(), cancel: any(named: 'cancel')),
        );
      },
    );

    test(
      'refuses an app that needs a newer iOS, comparing numerically',
      () async {
        when(() => inspector.inspect(any())).thenAnswer(
          (_) async => const IpaInfo(
            bundleId: 'a.b',
            displayName: 'A',
            minimumOS: '27.10',
            sha256: 'x',
            size: 4,
          ),
        );
        final operation = await run();

        expect(operation.error, isA<IncompatibleOS>());
        verifyNever(
          () => devices.install(any(), any(), cancel: any(named: 'cancel')),
        );
      },
    );

    test(
      'refuses when the device has less free space than the package',
      () async {
        when(() => devices.freeBytes(any())).thenAnswer((_) async => 3);
        final operation = await run();
        expect(operation.error, isA<InsufficientSpace>());
      },
    );

    test('unknown free space does not block the install', () async {
      when(() => devices.freeBytes(any())).thenThrow(const Unclassified('x'));
      expect((await run()).stage, OperationStage.done);
    });

    test('an install error keeps the package', () async {
      installThrows(const DeviceLocked());
      final operation = await run();

      expect(operation.stage, OperationStage.failed);
      expect(operation.error, isA<DeviceLocked>());
      expect(container.read(packageStoreProvider).list(), hasLength(1));
    });

    test(
      'an older version already on the device is not proof of an upgrade',
      () async {
        when(() => devices.installedApp(any(), any())).thenAnswer(
          (_) async => const InstalledApp(
            bundleId: 'ru.sberbank.onlineiphone',
            name: 'СберБанк',
            version: '11.0.0',
          ),
        );
        final operation = await run();

        expect(operation.stage, OperationStage.done);
        expect(operation.outcome, InstallOutcome.versionUnknown);
      },
    );

    test(
      'installer success that the app list cannot confirm is "unverified"',
      () async {
        when(() => devices.installedApp(any(), any()))
            .thenAnswer((_) async => null);
        final operation = await run();

        expect(operation.stage, OperationStage.done);
        expect(operation.outcome, InstallOutcome.unverified);
      },
    );

    test(
      'an unknown installer result is settled by asking the device: found',
      () async {
        installThrows(const InstallResultUnknown());
        final operation = await run();

        expect(operation.stage, OperationStage.done);
        expect(operation.outcome, InstallOutcome.confirmed);
        verify(
          () => devices.install(any(), any(), cancel: any(named: 'cancel')),
        ).called(1);
      },
    );

    test('an unknown installer result stays unknown when the device cannot confirm', () async {
      installThrows(const InstallResultUnknown());
      when(() => devices.installedApp(any(), any()))
          .thenThrow(const DeviceNotFound());
      final operation = await run();

      expect(operation.stage, OperationStage.unknown);
      expect(operation.error, isA<InstallResultUnknown>());
      expect(journal().find(operation.id)!.state, 'unknown');
      verify(() => devices.install(any(), any(), cancel: any(named: 'cancel')))
          .called(1);
    });
  });

  test('cancel stops a running download and leaves no files', () async {
    build();
    final started = Completer<void>();
    when(
      () => downloads.download(
        any(),
        any(),
        allowPurchase: any(named: 'allowPurchase'),
        cancel: any(named: 'cancel'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((invocation) async {
      started.complete();
      await (invocation.namedArguments[#cancel] as CancelToken).whenCancelled;
      throw const Cancelled();
    });

    final id = controller().start(_app, deviceUdid: _udid);
    await started.future;
    controller().cancel(id);
    await controller().idle;

    expect(only().stage, OperationStage.cancelled);
    expect(only().error, isNull);
    expect(Directory(paths.stagingFor(id)).existsSync(), isFalse);
    expect(container.read(packageStoreProvider).list(), isEmpty);
  });

  test('operations run one at a time, in order', () async {
    build();
    var running = 0;
    var maxRunning = 0;
    final order = <String>[];
    when(
      () => downloads.download(
        any(),
        any(),
        allowPurchase: any(named: 'allowPurchase'),
        cancel: any(named: 'cancel'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((invocation) async {
      running++;
      maxRunning = running > maxRunning ? running : maxRunning;
      final app = invocation.positionalArguments[0] as AppRef;
      order.add(app.key);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final file = File(
        p.join(invocation.positionalArguments[1] as String, 'download.ipa'),
      )..createSync(recursive: true);
      running--;
      return DownloadResult(path: file.path, licenseAcquired: false);
    });

    controller()
      ..start(const AppRef(appStoreId: '1'))
      ..start(const AppRef(appStoreId: '2'))
      ..start(const AppRef(appStoreId: '3'));
    await controller().idle;

    expect(maxRunning, 1);
    expect(order, ['1', '2', '3']);
    expect(
      container.read(operationsProvider).map((o) => o.stage),
      everyElement(OperationStage.done),
    );
  });

  test(
    'recover marks stale operations, clears their staging, adopts orphans',
    () async {
      build();
      journal().begin(
        id: 'stale',
        type: 'downloadAndInstall',
        accountId: 'acc',
        sessionGeneration: 1,
        appKey: '1',
        state: 'downloading',
      );
      File(p.join(paths.stagingFor('stale'), 'download.ipa.tmp'))
        ..createSync(recursive: true)
        ..writeAsStringSync('partial');
      File(p.join(paths.library, 'orphan01.ipa'))
        ..createSync(recursive: true)
        ..writeAsStringSync('data');
      File(p.join(paths.library, 'broken02.ipa')).writeAsStringSync('junk');
      when(() => inspector.inspect(any())).thenAnswer((invocation) async {
        final path = invocation.positionalArguments.single as String;
        if (path.contains('broken')) throw const PackageInvalid();
        return _info;
      });

      await controller().recover();

      expect(journal().find('stale')!.state, OperationJournal.interrupted);
      expect(Directory(paths.stagingFor('stale')).existsSync(), isFalse);
      final packages = container.read(packageStoreProvider).list();
      expect(packages.single.id, 'orphan01');
      expect(File(p.join(paths.library, 'broken02.ipa')).existsSync(), isFalse);
    },
  );

  group('library install and retry', () {
    test(
      'installs a library package without downloading or a session',
      () async {
        build();
        downloadsAnswer(['ok']);
        final package = (await run(udid: null)).package!;
        clearInteractions(downloads);
        container.dispose();
        build(auth: const AuthState(AuthStatus.signedOut));

        final id = controller().startInstall(package, _udid);
        await controller().idle;

        final operation = container.read(operationsProvider).single;
        expect(operation.stage, OperationStage.done);
        expect(operation.outcome, InstallOutcome.confirmed);
        expect(operation.title, 'СберБанк');
        expect(journal().find(id)!.state, 'done');
        verifyNever(
          () => downloads.download(
            any(),
            any(),
            allowPurchase: any(named: 'allowPurchase'),
            cancel: any(named: 'cancel'),
            onProgress: any(named: 'onProgress'),
          ),
        );
        verify(
          () => devices.install(
            _udid,
            package.path,
            cancel: any(named: 'cancel'),
          ),
        ).called(1);
      },
    );

    test(
      'retry after a failed install reuses the downloaded package',
      () async {
        build();
        downloadsAnswer(['ok']);
        when(() => devices.install(any(), any(), cancel: any(named: 'cancel')))
            .thenAnswer((_) => Stream.error(const DeviceLocked()));
        final failed = await run();
        expect(failed.stage, OperationStage.failed);

        when(() => devices.install(any(), any(), cancel: any(named: 'cancel')))
            .thenAnswer((_) => const Stream.empty());
        final retried = controller().retry(failed.id);
        await controller().idle;

        final operations = container.read(operationsProvider);
        expect(operations, hasLength(2));
        expect(operations.last.id, retried);
        expect(operations.last.stage, OperationStage.done);
        expect(operations.last.package!.id, failed.package!.id);
        verify(
          () => downloads.download(
            any(),
            any(),
            allowPurchase: any(named: 'allowPurchase'),
            cancel: any(named: 'cancel'),
            onProgress: any(named: 'onProgress'),
          ),
        ).called(1);
      },
    );

    test('retry after a failed download starts the download again', () async {
      build();
      downloadsAnswer([const NetworkInterrupted(), 'ok']);
      final failed = await run(allowFreeLicense: true);
      expect(failed.error, isA<NetworkInterrupted>());

      controller().retry(failed.id);
      await controller().idle;

      final retried = container.read(operationsProvider).last;
      expect(retried.stage, OperationStage.done);
      expect(retried.allowFreeLicense, isTrue);
      expect(retried.deviceUdid, _udid);
    });

    test('a running operation cannot be retried', () async {
      build();
      final started = Completer<void>();
      when(
        () => downloads.download(
          any(),
          any(),
          allowPurchase: any(named: 'allowPurchase'),
          cancel: any(named: 'cancel'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) async {
        started.complete();
        await (invocation.namedArguments[#cancel] as CancelToken).whenCancelled;
        throw const Cancelled();
      });
      final id = controller().start(_app);
      await started.future;

      expect(controller().retry(id), isNull);
      expect(container.read(operationsProvider), hasLength(1));
      controller().cancel(id);
      await controller().idle;
    });
  });

  group('icons', () {
    test(
      'the artwork inside a downloaded package becomes the app icon',
      () async {
        build();
        downloadsAnswer(['ok']);
        when(() => inspector.artwork(any()))
            .thenAnswer((_) async => Uint8List.fromList([9, 8, 7]));

        final operation = await run(udid: null);

        final icon = await container
            .read(lookupServiceProvider)
            .icon(operation.app.appStoreId!);
        expect(icon!.readAsBytesSync(), [9, 8, 7]);
        verify(() => inspector.artwork(operation.package!.path)).called(1);
      },
    );

    test('recover backfills icons for packages downloaded earlier', () async {
      build();
      downloadsAnswer(['ok']);
      final package = (await run(udid: null)).package!;
      expect(
        await container.read(lookupServiceProvider).icon(package.appStoreId!),
        isNull,
      );
      container.dispose();

      build();
      when(() => inspector.artwork(any()))
          .thenAnswer((_) async => Uint8List.fromList([1, 2]));
      await controller().recover();

      final icon = await container
          .read(lookupServiceProvider)
          .icon(package.appStoreId!);
      expect(icon!.readAsBytesSync(), [1, 2]);
    });
  });
}
