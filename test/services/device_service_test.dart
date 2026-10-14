import 'package:flutter_test/flutter_test.dart';
import 'package:returner/core/cancel.dart';
import 'package:returner/core/errors.dart';
import 'package:returner/core/process_runner.dart';
import 'package:returner/models/device.dart';
import 'package:returner/services/device_errors.dart';
import 'package:returner/services/device_service.dart';

import '../support/fake_process_runner.dart';
import '../support/fixtures.dart';

const _udid = '00008140-000A1B2C3D4E001C';
const _agentWarning =
    '{"time":"2026-10-14T00:50:50+03:00","level":"WARN","msg":"go-ios agent is not running. You might need to start it with \'ios tunnel start\' for ios17+."}';

// `unit` level: scripted go-ios answers taken from real output.
void main() {
  late FakeProcessRunner runner;
  late DeviceService service;

  setUp(() {
    runner = FakeProcessRunner();
    service = DeviceService(runner: runner, executable: () => 'ios');
  });

  void listReturnsOneDevice() {
    runner
      ..on(
        'ios',
        ['list', '--details'],
        FakeResponse(
          stdout: fixture('ios/list_details.json'),
          stderr: _agentWarning,
        ),
      )
      ..on('ios', [
        'devicename',
      ], FakeResponse(stdout: fixture('ios/devicename.json')));
  }

  group('listDevices', () {
    test('combines the list with the device name', () async {
      listReturnsOneDevice();
      final devices = await service.listDevices();

      expect(devices.single.udid, _udid);
      expect(devices.single.name, 'iPhone (Ivan)');
      expect(devices.single.productType, 'iPhone17,1');
      expect(devices.single.osVersion, '27.0.1');
      expect(runner.calls.last.arguments, [
        'devicename',
        '--udid=$_udid',
      ], reason: 'the device is always addressed explicitly');
    });

    test('asks for the name only once per device', () async {
      listReturnsOneDevice();
      await service.listDevices();
      await service.listDevices();
      expect(
        runner.calls.where((c) => c.arguments.first == 'devicename'),
        hasLength(1),
      );
    });

    test('still lists a device whose name cannot be read', () async {
      runner
        ..on('ios', [
          'list',
          '--details',
        ], FakeResponse(stdout: fixture('ios/list_details.json')))
        ..on(
          'ios',
          ['devicename'],
          const FakeResponse(
            exitCode: 1,
            stderr: '{"level":"ERROR","msg":"failed","err":"device is locked"}',
          ),
        );
      expect((await service.listDevices()).single.name, 'iPhone');
    });

    test('no devices is an empty list', () async {
      runner.on(
        'ios',
        ['list', '--details'],
        const FakeResponse(stdout: '{"deviceList":[]}', stderr: _agentWarning),
      );
      expect(await service.listDevices(), isEmpty);
    });

    test('a missing Apple driver is DriverMissing', () async {
      runner.on(
        'ios',
        ['list', '--details'],
        FakeResponse(
          exitCode: 1,
          stderr: fixture('ios/list_no_driver.stderr.jsonl'),
        ),
      );
      await expectLater(service.listDevices(), throwsA(isA<DriverMissing>()));
    });

    test('a missing binary is ComponentMissing', () async {
      final broken = DeviceService(
        runner: runner,
        executable: () => throw const ComponentMissing('ios'),
      );
      await expectLater(broken.listDevices(), throwsA(isA<ComponentMissing>()));
    });
  });

  test(
    'watchDevices emits on change and reports the driver error once',
    () async {
      var phase = 0;
      final scripted = _PhasedRunner(() => phase, [
        FakeResponse(
          exitCode: 1,
          stderr: fixture('ios/list_no_driver.stderr.jsonl'),
        ),
        const FakeResponse(stdout: '{"deviceList":[]}'),
        FakeResponse(stdout: fixture('ios/list_details.json')),
      ], FakeResponse(stdout: fixture('ios/devicename.json')));
      final watched = DeviceService(runner: scripted, executable: () => 'ios');

      final events = <Object>[];
      final subscription = watched
          .watchDevices(interval: const Duration(milliseconds: 5))
          .listen(events.add, onError: events.add);
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 60));

      await settle();
      expect(events, hasLength(1));
      expect(events.single, isA<DriverMissing>());

      phase = 1;
      await settle();
      expect(events.last, isEmpty);

      phase = 2;
      await settle();
      expect((events.last as List<Device>).single.udid, _udid);
      expect(events, hasLength(3), reason: 'unchanged polls emit nothing');
      await subscription.cancel();
    },
  );

  test('freeBytes reads diskspace', () async {
    runner.on('ios', [
      'diskspace',
    ], FakeResponse(stdout: fixture('ios/diskspace.json')));
    expect(await service.freeBytes(_udid), 41645416448);
  });

  group('installedApp', () {
    setUp(
      () => runner.on('ios', [
        'apps',
        '--list',
      ], FakeResponse(stdout: fixture('ios/apps_list.txt'))),
    );

    test('finds an app and keeps spaces in its name', () async {
      final app = await service.installedApp(_udid, 'com.burgerking.bk');
      expect(app!.name, 'Burger King');
      expect(app.version, '11.11.0');
    });

    test('is null for an app that is not installed', () async {
      expect(await service.installedApp(_udid, 'com.example.none'), isNull);
    });
  });

  group('install', () {
    test('reports stages and completes on "installation successful"', () async {
      runner.on('ios', [
        'install',
      ], FakeResponse(stderr: fixture('ios/install_success.stderr.jsonl')));
      final progress = await service.install(_udid, r'C:\lib\a.ipa').toList();

      expect(progress.first.percent, isNull, reason: 'transfer is silent');
      expect(progress.last.percent, 100);
      expect(progress.last.status, 'InstallComplete');
      expect(progress.map((p) => p.percent).whereType<int>().toList(), [
        5, 15, 20, 30, 40, 50, 60, 70, 80, 90, 100, //
      ]);
      expect(runner.calls.single.arguments, [
        'install',
        r'--path=C:\lib\a.ipa',
        '--udid=$_udid',
      ]);
    });

    test('exit code 0 without the success line is not a success', () async {
      runner.on('ios', ['install'], const FakeResponse(stderr: _agentWarning));
      await expectLater(
        service.install(_udid, 'a.ipa').drain<void>(),
        throwsA(isA<InstallResultUnknown>()),
      );
    });

    test('maps a locked device', () async {
      runner.on(
        'ios',
        ['install'],
        const FakeResponse(
          exitCode: 1,
          stderr: '{"level":"ERROR","msg":"failed installing","err":"PasswordProtected"}',
        ),
      );
      await expectLater(
        service.install(_udid, 'a.ipa').drain<void>(),
        throwsA(isA<DeviceLocked>()),
      );
    });

    test('an unclear failure after processing started is unknown', () async {
      runner.on(
        'ios',
        ['install'],
        const FakeResponse(
          exitCode: 1,
          stderr:
              '{"level":"INFO","msg":"installing","status":"InstallingApplication","percentComplete":60}\n'
              '{"level":"ERROR","msg":"failed installing","err":"EOF"}',
        ),
      );
      await expectLater(
        service.install(_udid, 'a.ipa').drain<void>(),
        throwsA(isA<InstallResultUnknown>()),
      );
    });

    test(
      'cancelling before the device reported anything is Cancelled',
      () async {
        runner.on('ios', ['install'], const FakeResponse(hang: true));
        final cancel = CancelToken();
        final install = service
            .install(_udid, 'a.ipa', cancel: cancel)
            .drain<void>();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        cancel.cancel();
        await expectLater(install, throwsA(isA<Cancelled>()));
      },
    );
  });

  group('mapIosError', () {
    // Hypotheses until real output is captured.
    final cases = <String, Matcher>{
      'dial tcp 127.0.0.1:27015: connectex: Подключение не установлено':
          isA<DriverMissing>(),
      'InvalidHostID': isA<DeviceNotTrusted>(),
      'could not retrieve PairRecord': isA<DeviceNotTrusted>(),
      'kAMDNoSpaceError': isA<InsufficientSpace>(),
      'DeviceOSVersionTooLow': isA<IncompatibleOS>(),
      'Device not found: abc': isA<DeviceNotFound>(),
      'ApplicationVerificationFailed': isA<InstallRejected>(),
      'application-identifier entitlement does not match installed application':
          isA<InstallConflict>(),
      'A coordinated install already exist, Code=46 streaming_zip_conduit':
          isA<InstallConflict>(),
      'something new': isA<Unclassified>(),
    };
    cases.forEach((text, matcher) {
      test(text, () => expect(mapIosError(text), matcher));
    });
  });
}

/// Answers `list` according to the current phase.
class _PhasedRunner extends FakeProcessRunner {
  _PhasedRunner(this._phase, this._lists, this._name);

  final int Function() _phase;
  final List<FakeResponse> _lists;
  final FakeResponse _name;

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    final response = arguments.first == 'list' ? _lists[_phase()] : _name;
    return ProcessOutput(
      exitCode: response.exitCode,
      stdout: response.stdout,
      stderr: response.stderr,
    );
  }
}
