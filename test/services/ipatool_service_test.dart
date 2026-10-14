import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:returner/core/cancel.dart';
import 'package:returner/core/errors.dart';
import 'package:returner/core/process_runner.dart';
import 'package:returner/models/app_ref.dart';
import 'package:returner/services/ipatool_service.dart';
import 'package:returner/services/secure_store.dart';

import '../support/fake_process_runner.dart';
import '../support/fake_secrets.dart';
import '../support/fixtures.dart';

// `unit` level: scripted ipatool answers taken from real output.
void main() {
  late Directory temp;
  late FakeProcessRunner runner;
  late IpatoolService service;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('returner_ipatool_');
    runner = FakeProcessRunner();
    service = IpatoolService(
      runner: runner,
      executable: () => 'ipatool',
      stateDirectory: p.join(temp.path, 'state'),
      secureStore: SecureStore(FakeSecretsBackend()),
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  FakeResponse ok(String name) =>
      FakeResponse(stdout: fixture('ipatool/$name'));
  FakeResponse failed(String name) =>
      FakeResponse(exitCode: 1, stdout: fixture('ipatool/$name'));
  FakeResponse error(String message) => FakeResponse(
    exitCode: 1,
    stdout: jsonEncode({'level': 'error', 'error': message, 'success': false}),
  );

  group('every call', () {
    test('passes secrets on stdin only and isolates the session', () async {
      runner.on('ipatool', ['auth', 'info'], ok('auth_info.json'));
      await service.currentAccount();

      final call = runner.calls.single;
      final stdin = jsonDecode(call.stdin!) as Map<String, dynamic>;
      final passphrase = stdin['keychain-passphrase'] as String;
      expect(passphrase, isNotEmpty);
      expect(call.arguments, containsAll(['--format', 'json']));
      expect(call.arguments, contains('--non-interactive'));
      expect(call.arguments, contains('--credentials-stdin'));
      expect(call.arguments, isNot(contains('--keychain-passphrase')));
      expect(call.arguments.join(' '), isNot(contains(passphrase)));
      expect(call.environment, {
        'IPATOOL_STATE_DIR': p.join(temp.path, 'state'),
      });
    });

    test('a missing binary is ComponentMissing', () async {
      final broken = IpatoolService(
        runner: runner,
        executable: () => throw const ComponentMissing('ipatool'),
        stateDirectory: temp.path,
        secureStore: SecureStore(FakeSecretsBackend()),
      );
      await expectLater(
        broken.currentAccount(),
        throwsA(isA<ComponentMissing>()),
      );
    });

    test('an unusable credential store is StorageLocked', () async {
      final locked = IpatoolService(
        runner: runner,
        executable: () => 'ipatool',
        stateDirectory: temp.path,
        secureStore: SecureStore(FakeSecretsBackend(failing: true)),
      );
      await expectLater(locked.currentAccount(), throwsA(isA<StorageLocked>()));
      expect(runner.calls, isEmpty);
    });
  });

  group('currentAccount', () {
    test('returns the saved account', () async {
      runner.on('ipatool', ['auth', 'info'], ok('auth_info.json'));
      final account = await service.currentAccount();
      expect(account!.email, 'user@example.com');
      expect(account.name, 'Ivan Ivanov');
    });

    test('is null when nobody is signed in', () async {
      runner.on('ipatool', ['auth', 'info'], failed('not_logged_in.json'));
      expect(await service.currentAccount(), isNull);
    });

    test('reports a session encrypted with another passphrase', () async {
      runner.on('ipatool', [
        'auth',
        'info',
      ], failed('keychain_wrong_passphrase.json'));
      await expectLater(
        service.currentAccount(),
        throwsA(isA<StorageLocked>()),
      );
    });
  });

  group('login', () {
    const loginOk = FakeResponse(
      stdout:
          '{"level":"info","message":"preparing authentication; the first login may take a few minutes"}\n'
          '{"level":"info","name":"Ivan Ivanov","email":"user@example.com","success":true}',
    );

    test('sends the password on stdin, never in arguments', () async {
      runner
        ..on('ipatool', ['auth', 'login'], loginOk)
        ..on('ipatool', ['auth', 'info'], ok('auth_info.json'));
      final before = service.generation;

      final account = await service.login('user@example.com', 's3cret pass');

      expect(account.email, 'user@example.com');
      final call = runner.calls.first;
      expect(
        call.arguments,
        containsAllInOrder(['--email', 'user@example.com']),
      );
      expect(call.arguments.join(' '), isNot(contains('s3cret')));
      expect((jsonDecode(call.stdin!) as Map)['password'], 's3cret pass');
      expect(
        (jsonDecode(call.stdin!) as Map).containsKey('auth-code'),
        isFalse,
      );
      expect(service.generation, greaterThan(before));
    });

    test('asks for a 2FA code when ipatool only prints the hint', () async {
      // Hypothesis from upstream source: exit code 0, no success line.
      runner.on(
        'ipatool',
        ['auth', 'login'],
        const FakeResponse(
          stdout: '{"level":"info","message":"2FA code is required; run the command again and supply a code using the `--auth-code` flag"}',
        ),
      );
      await expectLater(
        service.login('user@example.com', 'pw'),
        throwsA(isA<AuthNeeds2FA>()),
      );
    });

    test('passes the 2FA code on stdin', () async {
      runner
        ..on('ipatool', ['auth', 'login'], loginOk)
        ..on('ipatool', ['auth', 'info'], ok('auth_info.json'));
      await service.login('user@example.com', 'pw', code: '123456');
      final stdin = jsonDecode(runner.calls.first.stdin!) as Map;
      expect(stdin['auth-code'], '123456');
      expect(runner.calls.first.arguments.join(' '), isNot(contains('123456')));
    });

    test('maps a rejected password', () async {
      runner.on('ipatool', [
        'auth',
        'login',
      ], error('something went wrong metadata={"failureType":"5020"}'));
      await expectLater(
        service.login('user@example.com', 'bad'),
        throwsA(isA<AuthInvalidCredentials>()),
      );
    });

    test('does not trust a login that left no readable session', () async {
      runner
        ..on('ipatool', ['auth', 'login'], loginOk)
        ..on('ipatool', ['auth', 'info'], failed('not_logged_in.json'));
      await expectLater(
        service.login('user@example.com', 'pw'),
        throwsA(isA<StorageLocked>()),
      );
    });

    test('sets an unreadable session aside and retries once', () async {
      final state = Directory(p.join(temp.path, 'state'))..createSync();
      File(p.join(state.path, 'account')).writeAsStringSync('old');
      var attempts = 0;
      final sequenced = _SequencedRunner(runner, (call) {
        if (call.arguments.contains('login')) attempts++;
        return call.arguments.contains('login') && attempts == 1
            ? failed('keychain_wrong_passphrase.json')
            : null;
      });
      runner
        ..on('ipatool', ['auth', 'login'], loginOk)
        ..on('ipatool', ['auth', 'info'], ok('auth_info.json'));
      service = IpatoolService(
        runner: sequenced,
        executable: () => 'ipatool',
        stateDirectory: state.path,
        secureStore: SecureStore(FakeSecretsBackend()),
      );

      await service.login('user@example.com', 'pw');

      expect(attempts, 2);
      expect(File(p.join(state.path, 'account')).existsSync(), isFalse);
      final backups = temp.listSync().whereType<Directory>().where(
        (d) => p.basename(d.path).startsWith('state.unreadable-'),
      );
      expect(
        File(p.join(backups.single.path, 'account')).readAsStringSync(),
        'old',
      );
    });

    test('can be cancelled while waiting for Apple', () async {
      runner.on('ipatool', ['auth', 'login'], const FakeResponse(hang: true));
      final cancel = CancelToken();
      final login = service.login('user@example.com', 'pw', cancel: cancel);
      await Future<void>.delayed(Duration.zero);
      cancel.cancel();
      await expectLater(login, throwsA(isA<Cancelled>()));
    });
  });

  test('logout bumps the generation even when already signed out', () async {
    runner.on('ipatool', ['auth', 'revoke'], failed('not_logged_in.json'));
    final before = service.generation;
    await service.logout();
    expect(service.generation, greaterThan(before));
  });

  test('purchases parses a page of the history', () async {
    runner.on('ipatool', ['list-purchases'], ok('list_purchases.json'));
    final page = await service.purchases(page: 1, pageSize: 2);

    expect(page.totalCount, 714);
    expect(page.page, 1);
    expect(page.apps, hasLength(2));
    expect(page.apps.first.appStoreId, '686449807');
    expect(page.apps.first.bundleId, 'ph.telegra.Telegraph');
    expect(page.apps.first.purchaseDate, DateTime.utc(2026, 2, 24, 12, 28, 24));
    expect(
      runner.calls.single.arguments,
      containsAllInOrder(['--max-results', '2', '--page', '1']),
    );
  });

  group('search', () {
    test('parses results', () async {
      runner.on('ipatool', ['search'], ok('search.json'));
      final apps = await service.search('telegram', limit: 3);
      expect(apps.map((a) => a.name), contains('Telegram Messenger'));
      expect(apps.first.platforms, contains('iphone'));
    });

    test('an empty result is not an error', () async {
      runner.on('ipatool', ['search'], ok('search_empty.json'));
      expect(await service.search('zzz'), isEmpty);
    });

    test('a term that looks like a flag stays an argument', () async {
      runner.on('ipatool', ['search'], ok('search_empty.json'));
      await service.search('--purchase');
      final args = runner.calls.single.arguments;
      expect(args.indexOf('--'), lessThan(args.indexOf('--purchase')));
    });
  });

  group('versions', () {
    test('prefers the numeric App Store ID', () async {
      runner.on('ipatool', ['list-versions'], ok('list_versions.json'));
      final ids = await service.listVersions(
        const AppRef(appStoreId: '686449807', bundleId: 'ph.telegra.Telegraph'),
      );
      expect(ids.first, '16060826');
      expect(ids.last, '892661437');
      final args = runner.calls.single.arguments;
      expect(args, containsAllInOrder(['--app-id', '686449807']));
      expect(args, isNot(contains('--bundle-identifier')));
    });

    test('falls back to the bundle id', () async {
      runner.on('ipatool', ['list-versions'], ok('list_versions.json'));
      await service.listVersions(
        const AppRef(bundleId: 'ph.telegra.Telegraph'),
      );
      expect(
        runner.calls.single.arguments,
        containsAllInOrder(['--bundle-identifier', 'ph.telegra.Telegraph']),
      );
    });

    test('an unknown app is AssetUnavailable', () async {
      runner.on('ipatool', ['list-versions'], failed('app_not_found.json'));
      await expectLater(
        service.listVersions(const AppRef(bundleId: 'com.example.none')),
        throwsA(isA<AssetUnavailable>()),
      );
    });

    test('reads version metadata', () async {
      runner.on('ipatool', [
        'get-version-metadata',
      ], ok('version_metadata.json'));
      final meta = await service.versionMetadata(
        const AppRef(appStoreId: '686449807'),
        '892661437',
      );
      expect(meta.displayVersion, '13.0');
      expect(meta.releaseDate, DateTime.utc(2026, 10, 7, 0, 32, 16));
    });

    test('a foreign version id is VersionUnavailable', () async {
      runner.on('ipatool', [
        'get-version-metadata',
      ], failed('version_metadata_bad_version.json'));
      await expectLater(
        service.versionMetadata(const AppRef(appStoreId: '686449807'), '1'),
        throwsA(isA<VersionUnavailable>()),
      );
    });
  });

  group('download', () {
    test('builds the command and reads the result', () async {
      runner.on('ipatool', ['download'], ok('download_success.json'));
      final result = await service.download(
        const AppRef(appStoreId: '492224193', externalVersionId: '555'),
        r'C:\staging\download.ipa',
      );
      expect(result.licenseAcquired, isFalse);
      final args = runner.calls.single.arguments;
      expect(args, containsAllInOrder(['--app-id', '492224193']));
      expect(
        args,
        containsAllInOrder(['--output', r'C:\staging\download.ipa']),
      );
      expect(args, containsAllInOrder(['--external-version-id', '555']));
      expect(args, isNot(contains('--purchase')));
    });

    test('adds --purchase only when allowed', () async {
      runner.on('ipatool', ['download'], ok('download_success.json'));
      await service.download(
        const AppRef(appStoreId: '1'),
        'out.ipa',
        allowPurchase: true,
      );
      expect(runner.calls.single.arguments, contains('--purchase'));
    });

    test('maps a missing license', () async {
      runner.on('ipatool', ['download'], error('license is required'));
      await expectLater(
        service.download(const AppRef(appStoreId: '1'), 'out.ipa'),
        throwsA(isA<LicenseRequired>()),
      );
    });

    test('keeps Apple\'s reason for a refusal', () async {
      runner.on(
        'ipatool',
        ['download'],
        const FakeResponse(
          exitCode: 1,
          stdout: '{"level":"error","error":"received error","metadata":{"CustomerMessage":"This item is no longer available."},"success":false}',
        ),
      );
      await expectLater(
        service.download(const AppRef(appStoreId: '1'), 'out.ipa'),
        throwsA(
          isA<AssetUnavailable>().having(
            (e) => e.appleMessage,
            'appleMessage',
            'This item is no longer available.',
          ),
        ),
      );
    });

    test('an expired session is AuthSessionExpired', () async {
      runner.on('ipatool', ['download'], error('password token is expired'));
      await expectLater(
        service.download(const AppRef(appStoreId: '1'), 'out.ipa'),
        throwsA(isA<AuthSessionExpired>()),
      );
    });

    test('a crash without a JSON error is Unclassified and masked', () async {
      runner.on(
        'ipatool',
        ['download'],
        const FakeResponse(
          exitCode: 2,
          stderr: 'panic: runtime error for user@example.com',
        ),
      );
      await expectLater(
        service.download(const AppRef(appStoreId: '1'), 'out.ipa'),
        throwsA(
          isA<Unclassified>().having(
            (e) => e.safeDetails,
            'safeDetails',
            allOf(contains('panic'), isNot(contains('user@example.com'))),
          ),
        ),
      );
    });
  });
}

/// Lets a test answer selected calls itself and delegate the rest.
class _SequencedRunner extends FakeProcessRunner {
  _SequencedRunner(this._inner, this._override);

  final FakeProcessRunner _inner;
  final FakeResponse? Function(FakeCall) _override;

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? stdin,
  }) {
    final call = FakeCall(executable, arguments, environment, stdin);
    final response = _override(call);
    if (response == null) {
      return _inner.start(
        executable,
        arguments,
        environment: environment,
        stdin: stdin,
      );
    }
    on(call.tool, arguments, response);
    return super.start(
      executable,
      arguments,
      environment: environment,
      stdin: stdin,
    );
  }
}
