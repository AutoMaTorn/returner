import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:returner/core/process_runner.dart';

import '../support/fake_process_runner.dart';

// A command that runs for several seconds without reading stdin.
final _slow = Platform.isWindows
    ? (exe: 'ping', args: ['-n', '10', '127.0.0.1'])
    : (exe: 'sleep', args: ['10']);

// Echoes stdin back line by line.
final _echo = Platform.isWindows
    ? (exe: 'findstr', args: ['^'])
    : (exe: 'cat', args: <String>[]);

void main() {
  // `local` level: starts real system utilities.
  group('SystemProcessRunner', () {
    const runner = SystemProcessRunner();

    test('passes stdin and captures stdout', () async {
      final result = await runner.run(_echo.exe, _echo.args, stdin: 'b\na\n');
      expect(result.exitCode, 0);
      expect(result.stdout.split('\n').map((l) => l.trim()).toList(), [
        'b',
        'a',
      ]);
    });

    test('kills the process and throws on timeout', () async {
      final watch = Stopwatch()..start();
      await expectLater(
        runner.run(
          _slow.exe,
          _slow.args,
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<ProcessTimeout>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('kill ends a started process', () async {
      final process = await runner.start(_slow.exe, _slow.args);
      expect(process.kill(), isTrue);
      await process.exitCode.timeout(const Duration(seconds: 5));
    });

    test('reports a missing executable', () async {
      await expectLater(
        runner.run('returner-no-such-tool', []),
        throwsA(isA<ProcessStartFailure>()),
      );
    });
  });

  group('FakeProcessRunner', () {
    test('answers by tool and arguments and records stdin', () async {
      final runner = FakeProcessRunner()
        ..on('ipatool', [
          'auth',
          'info',
        ], const FakeResponse(stdout: '{"success":true}'));

      final result = await runner.run(r'C:\app\bin\ipatool.exe', [
        'auth',
        'info',
        '--format',
        'json',
      ], stdin: '{"keychain-passphrase":"k"}\n');

      expect(result.stdout, '{"success":true}');
      expect(runner.calls.single.stdin, contains('keychain-passphrase'));
      expect(runner.calls.single.arguments, isNot(contains('k')));
    });

    test('fails loudly on an unexpected call', () {
      expect(() => FakeProcessRunner().run('ios', ['list']), throwsStateError);
    });

    test('a hanging process ends only when killed', () async {
      final runner = FakeProcessRunner()
        ..on('ios', ['install'], const FakeResponse(hang: true));
      final process = await runner.start('ios', ['install', '--path=x']);
      expect(process.kill(), isTrue);
      expect(await process.exitCode, -1);
    });
  });
}
