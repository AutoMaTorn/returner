import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:returner/core/process_runner.dart';
import 'package:returner/services/driver_service.dart';
import 'package:returner/services/pe_cabinet.dart';

import '../support/fake_process_runner.dart';
import '../support/pe_builder.dart';

const _appleSubject =
    'CN=Apple Inc., O=Apple Inc., L=Cupertino, S=California, C=US';

/// Answers the PowerShell and expand calls of a driver install; `sc` and
/// `reg` go through the usual rules.
class _DriverRunner extends FakeProcessRunner {
  var installExit = 0;
  var expandWrites = true;
  void Function()? onInstall;

  final signed = <String>[];
  final installed = <String>[];

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    final tool = p.windows.basenameWithoutExtension(executable);
    if (tool == 'powershell') {
      calls.add(FakeCall(executable, List.of(arguments), environment, stdin));
      final path = stdin!.trim();
      if (arguments.last == DriverService.signatureScript) {
        signed.add(p.basename(path));
        return ProcessOutput(
          exitCode: 0,
          stdout: signatureFor(path),
          stderr: '',
        );
      }
      if (arguments.last == DriverService.installScript) {
        installed.add(p.basename(path));
        onInstall?.call();
        return ProcessOutput(exitCode: installExit, stdout: '', stderr: '');
      }
      throw StateError('unexpected PowerShell script');
    }
    if (tool == 'expand') {
      calls.add(FakeCall(executable, List.of(arguments), environment, stdin));
      if (expandWrites) {
        await File(p.join(arguments[2], DriverService.packageName))
            .writeAsBytes([1, 2, 3]);
      }
      return const ProcessOutput(exitCode: 0, stdout: '', stderr: '');
    }
    return super.run(
      executable,
      arguments,
      environment: environment,
      stdin: stdin,
      timeout: timeout,
    );
  }

  String Function(String path) signatureFor = (_) =>
      'Valid\r\n$_appleSubject\r\n';
}

void main() {
  late Directory temp;
  late _DriverRunner runner;
  late bool portOpen;
  late Uint8List installer;
  late List<DriverInstallProgress> progress;
  late String work;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('returner_driver_');
    runner = _DriverRunner();
    portOpen = false;
    installer = fakeInstaller(fakeCabinet(4096));
    progress = [];
    work = p.join(temp.path, 'driver');
    runner.onInstall = () => portOpen = true;
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  http.Client apple({int status = 200, int? declaredLength}) =>
      MockClient.streaming((request, _) async {
        expect(request.url.toString(), DriverService.installerUri);
        final body = status == 200 ? installer : Uint8List(0);
        return http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < body.length; i += 1000)
              body.sublist(i, i + 1000 > body.length ? body.length : i + 1000),
          ]),
          status,
          contentLength: declaredLength ?? body.length,
        );
      });

  DriverService service({http.Client? client, bool isWindows = true}) =>
      DriverService(
        runner: runner,
        client: client ?? apple(),
        workDirectory: work,
        isWindows: isWindows,
        usbmuxdReachable: () async => portOpen,
        serviceWait: Duration.zero,
        pollInterval: Duration.zero,
        systemRoot: r'C:\Windows',
      );

  Future<DriverInstallResult> install([DriverService? driver]) =>
      (driver ?? service()).install(onProgress: progress.add);

  group('detection', () {
    test('macOS always has the driver and runs nothing', () async {
      final driver = service(isWindows: false);
      expect(await driver.isInstalled(), isTrue);
      expect(await driver.install(), DriverInstallResult.installed);
      expect(runner.calls, isEmpty);
    });

    test('an open usbmuxd port is enough', () async {
      portOpen = true;
      expect(await service().isInstalled(), isTrue);
      expect(runner.calls, isEmpty);
    });

    test('falls back to the service, then the registry', () async {
      runner
        ..on('sc', ['query'], const FakeResponse(exitCode: 1060))
        ..on('reg', ['query'], const FakeResponse());
      expect(await service().isInstalled(), isTrue);
      expect(runner.calls.map((c) => c.tool), ['sc', 'reg']);
      expect(runner.calls.first.arguments, [
        'query',
        'Apple Mobile Device Service',
      ]);
    });

    test('reports a missing driver', () async {
      runner
        ..on('sc', ['query'], const FakeResponse(exitCode: 1060))
        ..on('reg', ['query'], const FakeResponse(exitCode: 1));
      expect(await service().isInstalled(), isFalse);
    });
  });

  group('install from the iTunes installer', () {
    void noDriver() => runner
      ..on('sc', ['query'], const FakeResponse(exitCode: 1060))
      ..on('reg', ['query'], const FakeResponse(exitCode: 1));

    test('installs only the driver package, every step in order', () async {
      expect(await install(), DriverInstallResult.installed);

      expect(runner.signed, ['iTunes64Setup.exe', DriverService.packageName]);
      expect(runner.installed, [DriverService.packageName]);
      final expand = runner.calls.singleWhere((c) => c.tool == 'expand');
      expect(expand.executable, r'C:\Windows\System32\expand.exe');
      expect(expand.arguments, [
        p.join(work, 'setup.cab'),
        '-F:${DriverService.packageName}',
        p.join(work, 'package'),
      ]);
      expect(
        progress.map((e) => e.stage).toSet().toList(),
        DriverInstallStage.values,
      );
      expect(progress.where((e) => e.fraction != null).last.fraction, 1.0);
      expect(await Directory(work).exists(), isFalse);
    });

    test('paths go through stdin, never into the script', () async {
      await install();
      final shells = runner.calls.where((c) => c.tool == 'powershell');
      expect(shells, hasLength(3));
      for (final call in shells) {
        expect(
          call.executable,
          r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
        );
        expect(call.arguments.take(3), [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
        ]);
        expect(call.arguments.join(' '), isNot(contains(temp.path)));
        expect(call.stdin, startsWith(work));
      }
    });

    test('a failed download stops before anything runs', () async {
      expect(
        await install(service(client: apple(status: 503))),
        DriverInstallResult.downloadFailed,
      );
      expect(runner.calls, isEmpty);
    });

    test('a download that breaks off is a failure', () async {
      expect(
        await install(
          service(client: apple(declaredLength: installer.length + 10)),
        ),
        DriverInstallResult.downloadFailed,
      );
      expect(runner.calls, isEmpty);
    });

    test('no network is a failure, not a crash', () async {
      final offline = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      expect(
        await install(service(client: offline)),
        DriverInstallResult.downloadFailed,
      );
    });

    test('an unsigned installer is never unpacked', () async {
      runner.signatureFor = (_) => 'NotSigned\r\n\r\n';
      expect(await install(), DriverInstallResult.untrusted);
      expect(runner.calls.map((c) => c.tool), ['powershell']);
    });

    test('a valid signature by someone else is not trusted', () async {
      runner.signatureFor = (path) => p.basename(path).endsWith('.msi')
          ? 'Valid\r\nCN=Someone, O=Not Apple Inc., C=US\r\n'
          : 'Valid\r\n$_appleSubject\r\n';
      expect(await install(), DriverInstallResult.untrusted);
      expect(runner.installed, isEmpty);
    });

    test('an installer without the cabinet resource', () async {
      installer = fakeInstaller(fakeCabinet(4096), resourceName: 'OTHER');
      expect(await install(), DriverInstallResult.unpackFailed);
      expect(runner.calls.map((c) => c.tool), ['powershell']);
    });

    test('a resource that is not a cabinet', () async {
      installer = fakeInstaller(fakeCabinet(4096, header: false));
      expect(await install(), DriverInstallResult.unpackFailed);
    });

    test('expand finding nothing is a failure despite exit code 0', () async {
      runner.expandWrites = false;
      expect(await install(), DriverInstallResult.unpackFailed);
      expect(runner.installed, isEmpty);
    });

    for (final code in [1223, 1602]) {
      test('a refused permission prompt ($code) is a cancel', () async {
        runner.installExit = code;
        runner.onInstall = null;
        expect(await install(), DriverInstallResult.cancelled);
      });
    }

    test('an installer error with no driver afterwards', () async {
      noDriver();
      runner
        ..installExit = 1603
        ..onInstall = null;
      expect(await install(), DriverInstallResult.installFailed);
    });

    test('an installer error with the driver present counts', () async {
      runner.installExit = 1603;
      expect(await install(), DriverInstallResult.installed);
    });

    test('a restart request is still a success', () async {
      runner.installExit = 3010;
      expect(await install(), DriverInstallResult.installed);
    });

    test('installed but the service never answers', () async {
      noDriver();
      runner.onInstall = null;
      expect(await install(), DriverInstallResult.installFailed);
      expect(await Directory(work).exists(), isFalse);
    });

    test('a registered service counts when the port is still closed', () async {
      runner
        ..on('sc', ['query'], const FakeResponse())
        ..onInstall = null;
      expect(await install(), DriverInstallResult.installed);
    });
  });

  group('findCabinet', () {
    Future<CabinetLocation?> find(Uint8List bytes) => findCabinet(
      (offset, length) async => Uint8List.sublistView(
        bytes,
        offset.clamp(0, bytes.length),
        (offset + length).clamp(0, bytes.length),
      ),
    );

    test('finds the named resource', () async {
      final bytes = fakeInstaller(fakeCabinet(300));
      final location = await find(bytes);
      expect(location, const CabinetLocation(0x200 + 0x80, 300));
      expect(
        bytes.sublist(location!.offset, location.offset + 4),
        'MSCF'.codeUnits,
      );
    });

    test('not a PE file', () async {
      expect(await find(Uint8List.fromList('hello'.codeUnits)), isNull);
      expect(await find(Uint8List(4096)), isNull);
    });

    test('a truncated file', () async {
      final bytes = fakeInstaller(fakeCabinet(300));
      expect(await find(bytes.sublist(0, 0x220)), isNull);
    });
  });

  test('PowerShell parses both scripts (local)', () async {
    for (final script in [
      DriverService.signatureScript,
      DriverService.installScript,
    ]) {
      final file = File(p.join(temp.path, 'script.ps1'));
      await file.writeAsString(script);
      final shell = await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$e = $null; $path = [Console]::In.ReadLine(); '
            r'[void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$e); '
            r'if ($e) { $e | ForEach-Object { $_.Message }; exit 1 }',
      ]);
      shell.stdin.writeln(file.path);
      await shell.stdin.close();
      final output = await shell.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      await shell.stderr.drain<void>();
      expect(await shell.exitCode, 0, reason: output);
    }
  }, skip: Platform.isWindows ? false : 'PowerShell is Windows-only');
}
