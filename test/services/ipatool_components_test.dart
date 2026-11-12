import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:returner/core/errors.dart';
import 'package:returner/models/store.dart';
import 'package:returner/services/ipatool_errors.dart';
import 'package:returner/services/ipatool_service.dart';
import 'package:returner/services/secure_store.dart';

import '../support/fake_process_runner.dart';
import '../support/fake_secrets.dart';

// `unit` level: `ipatool prepare` answers in the shape our build prints
// (checked `local` against the built binary on 2026-11-12, byte counts too).
void main() {
  late Directory temp;
  late FakeProcessRunner runner;
  late IpatoolService service;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('returner_components_');
    runner = FakeProcessRunner();
    service = IpatoolService(
      runner: runner,
      executable: () => 'ipatool',
      stateDirectory: p.join(temp.path, 'state'),
      secureStore: SecureStore(FakeSecretsBackend()),
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  String lines(List<Map<String, Object>> values) =>
      values.map(jsonEncode).join('\n');

  Map<String, Object> stage(String name, String state) => {
    'level': 'info',
    'stage': name,
    'state': state,
  };

  group('componentsReady', () {
    test('reads the check without downloading anything', () async {
      runner.on(
        'ipatool',
        ['prepare', '--check'],
        FakeResponse(
          stdout: lines([
            stage('runtime', 'cached'),
            stage('apple-assets', 'missing'),
            {'level': 'info', 'ready': false, 'success': true},
          ]),
        ),
      );
      expect(await service.componentsReady(), isFalse);
      expect(runner.calls.single.arguments.take(2), ['prepare', '--check']);
    });

    test('is true once everything is cached', () async {
      runner.on(
        'ipatool',
        ['prepare', '--check'],
        FakeResponse(
          stdout: lines([
            stage('runtime', 'cached'),
            stage('apple-assets', 'cached'),
            {'level': 'info', 'ready': true, 'success': true},
          ]),
        ),
      );
      expect(await service.componentsReady(), isTrue);
    });
  });

  group('prepareComponents', () {
    test('reports each download and the bytes as they arrive', () async {
      Map<String, Object> at(String name, String state, int bytes) => {
        ...stage(name, state),
        'bytes': bytes,
        'total': 300,
      };
      runner.on(
        'ipatool',
        ['prepare'],
        FakeResponse(
          stdout: lines([
            at('runtime', 'downloading', 0),
            at('runtime', 'progress', 40),
            at('runtime', 'done', 50),
            at('apple-assets', 'downloading', 50),
            at('apple-assets', 'progress', 200),
            at('apple-assets', 'done', 300),
            {'level': 'info', 'ready': true, 'success': true},
          ]),
        ),
      );
      final seen = <ComponentsProgress>[];
      await service.prepareComponents(onProgress: seen.add);
      expect(seen.map((p) => (p.stage, p.bytes, p.total)), [
        (ComponentStage.runtime, 0, 300),
        (ComponentStage.runtime, 40, 300),
        (ComponentStage.appleAssets, 50, 300),
        (ComponentStage.appleAssets, 200, 300),
      ]);
      expect(runner.calls.single.arguments, isNot(contains('--check')));
    });

    test('an older build without byte counts still names the stage', () async {
      runner.on(
        'ipatool',
        ['prepare'],
        FakeResponse(
          stdout: lines([
            stage('runtime', 'downloading'),
            {'level': 'info', 'ready': true, 'success': true},
          ]),
        ),
      );
      final seen = <ComponentsProgress>[];
      await service.prepareComponents(onProgress: seen.add);
      expect(seen.single.stage, ComponentStage.runtime);
      expect(seen.single.total, 0);
    });

    test('a failed connection says which one, masked', () async {
      runner.on(
        'ipatool',
        ['prepare'],
        FakeResponse(
          exitCode: 1,
          stdout: lines([
            stage('runtime', 'downloading'),
            {
              'level': 'error',
              'error':
                  'prepare runtime: download Unicorn 2.1.4: Get '
                  '"https://github.com/unicorn-engine/unicorn/releases/'
                  'download/2.1.4/windows-mingw64-shared.7z?token=secret": '
                  r'dial tcp 140.82.121.4:443: connectex: C:\Users\anna\x '
                  'user@example.com',
              'success': false,
            },
          ]),
        ),
      );
      await expectLater(
        service.prepareComponents(),
        throwsA(
          isA<AppleUnreachable>().having(
            (e) => e.cause,
            'cause',
            allOf(
              contains('download Unicorn 2.1.4'),
              contains('github.com'),
              isNot(contains('secret')),
              isNot(contains('anna')),
              isNot(contains('user@example.com')),
            ),
          ),
        ),
      );
    });
  });

  group('network causes', () {
    test('are kept for the log on both network errors', () {
      final unreachable = mapIpatoolError('get bag: no such host apple.com');
      expect(unreachable, isA<AppleUnreachable>());
      expect(unreachable.logDetails, contains('no such host'));

      final interrupted = mapIpatoolError('read tcp: connection reset by peer');
      expect(interrupted, isA<NetworkInterrupted>());
      expect(interrupted.logDetails, contains('connection reset'));
    });

    test('hide a 2FA code while signing in and stay one short line', () {
      final error = mapIpatoolError(
        'code 123456 sent; dial tcp:\n${'x' * 1000}',
        duringLogin: true,
      );
      final cause = error.logDetails!;
      expect(cause, isNot(contains('123456')));
      expect(cause, isNot(contains('\n')));
      expect(cause.length, lessThanOrEqualTo(networkCauseLimit + 1));
    });

    test('other errors add nothing', () {
      expect(const AuthInvalidCredentials().logDetails, isNull);
    });
  });
}
