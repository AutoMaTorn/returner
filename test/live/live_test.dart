// `live` level: real ipatool session, real Apple servers, real iPhone.
//
// Skipped unless configured through the environment:
//   RETURNER_LIVE_STATE_DIR   ipatool session directory to use
//   RETURNER_LIVE_PASSPHRASE  passphrase of that session
//   RETURNER_LIVE_APP_ID      numeric App Store ID to download
//   RETURNER_LIVE_INSTALL=1   also install it on the connected iPhone
//   RETURNER_LIVE_IPA         existing .ipa to inspect (optional)
//
// Run: flutter test test/live/live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:returner/core/binaries.dart';
import 'package:returner/core/log.dart';
import 'package:returner/core/process_runner.dart';
import 'package:returner/models/app_ref.dart';
import 'package:returner/services/device_service.dart';
import 'package:returner/services/download_service.dart';
import 'package:returner/services/ipa_inspector.dart';
import 'package:returner/services/ipatool_service.dart';
import 'package:returner/services/secure_store.dart';

class _FixedSecrets implements SecretsBackend {
  _FixedSecrets(this._passphrase);

  final String _passphrase;

  @override
  Future<String?> read(String key) async => _passphrase;

  @override
  Future<void> write(String key, String value) async {}
}

void main() {
  final env = Platform.environment;
  final stateDir = env['RETURNER_LIVE_STATE_DIR'];
  final passphrase = env['RETURNER_LIVE_PASSPHRASE'];
  final appId = env['RETURNER_LIVE_APP_ID'];
  final install = env['RETURNER_LIVE_INSTALL'] == '1';
  final existingIpa = env['RETURNER_LIVE_IPA'];
  final configured = stateDir != null && passphrase != null;
  final skip = configured ? null : 'live environment is not configured';

  final binaries = Binaries.forCurrentProcess();
  const runner = SystemProcessRunner();
  const inspector = IpaInspector();
  late IpatoolService ipatool;
  late DeviceService devices;

  setUpAll(() {
    if (!configured) return;
    ipatool = IpatoolService(
      runner: runner,
      executable: () => binaries.ipatool,
      stateDirectory: stateDir,
      secureStore: SecureStore(_FixedSecrets(passphrase)),
    );
    devices = DeviceService(runner: runner, executable: () => binaries.ios);
  });

  test('inspects an existing package', () async {
    final watch = Stopwatch()..start();
    final info = await inspector.inspect(existingIpa!);
    // ignore: avoid_print
    print(
      'inspected ${info.size} bytes in ${watch.elapsedMilliseconds} ms: '
      '${info.bundleId} "${info.displayName}" ${info.displayVersion} '
      '(${info.bundleVersion}), min iOS ${info.minimumOS}',
    );
    expect(info.bundleId, isNotEmpty);
    expect(info.sha256, hasLength(64));
  }, skip: existingIpa == null ? 'RETURNER_LIVE_IPA is not set' : null);

  test(
    'reads the account and the purchase history',
    () async {
      final account = await ipatool.currentAccount();
      expect(account, isNotNull);
      // ignore: avoid_print
      print('account: ${mask(account!.email)}');

      final page = await ipatool.purchases(pageSize: 5);
      // ignore: avoid_print
      print('purchases: ${page.apps.length} of ${page.totalCount}');
      expect(page.totalCount, greaterThan(0));
      expect(page.apps, isNotEmpty);
      expect(page.apps.first.appStoreId, matches(r'^\d+$'));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('lists connected devices', () async {
    final list = await devices.listDevices();
    for (final device in list) {
      // ignore: avoid_print
      print(
        'device: ${device.productType}, iOS ${device.osVersion}, '
        'free ${await devices.freeBytes(device.udid)} bytes',
      );
    }
  }, skip: skip);

  test(
    'downloads by numeric ID, validates and optionally installs',
    () async {
      final staging = Directory.systemTemp.createTempSync('returner_live_');
      addTearDown(() => staging.deleteSync(recursive: true));
      final app = AppRef(appStoreId: appId);

      final progress = <int>[];
      final watch = Stopwatch()..start();
      final result = await DownloadService(ipatool)
          .download(app, staging.path, onProgress: progress.add);
      // ignore: avoid_print
      print(
        'downloaded ${File(result.path).lengthSync()} bytes in '
        '${watch.elapsed.inSeconds} s, ${progress.length} progress events, '
        'license acquired: ${result.licenseAcquired}',
      );
      expect(progress, isNotEmpty);
      expect(progress.last, File(result.path).lengthSync());

      watch.reset();
      final info = await inspector.inspect(result.path);
      // ignore: avoid_print
      print(
        'validated in ${watch.elapsedMilliseconds} ms: ${info.bundleId} '
        '"${info.displayName}" ${info.displayVersion}, min iOS ${info.minimumOS}',
      );

      if (!install) return;
      final device = (await devices.listDevices()).single;
      watch.reset();
      final stages = await devices.install(device.udid, result.path).toList();
      // ignore: avoid_print
      print(
        'installed in ${watch.elapsed.inSeconds} s, ${stages.length} events, '
        'last: ${stages.last.status} ${stages.last.percent}%',
      );
      final installed = await devices.installedApp(device.udid, info.bundleId);
      // ignore: avoid_print
      print('on device: ${installed?.bundleId} ${installed?.version}');
      expect(installed, isNotNull);
      expect(installed!.version, info.displayVersion);
    },
    skip: skip ?? (appId == null ? 'RETURNER_LIVE_APP_ID is not set' : null),
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
