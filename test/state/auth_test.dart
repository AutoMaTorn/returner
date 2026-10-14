import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:returner/core/cancel.dart';
import 'package:returner/core/errors.dart';
import 'package:returner/models/store.dart';
import 'package:returner/services/ipatool_service.dart';
import 'package:returner/state/auth.dart';
import 'package:returner/state/providers.dart';

class _MockIpatool extends Mock implements IpatoolService {}

const _account = AccountInfo(email: 'User@Example.com', name: 'Ivan');

void main() {
  late _MockIpatool ipatool;
  late ProviderContainer container;

  setUpAll(() => registerFallbackValue(CancelToken()));
  setUp(() {
    ipatool = _MockIpatool();
    container = ProviderContainer(
      overrides: [ipatoolServiceProvider.overrideWithValue(ipatool)],
    );
  });
  tearDown(() => container.dispose());

  AuthController auth() => container.read(authProvider.notifier);
  AuthState state() => container.read(authProvider);

  void loginAnswers(List<Object> results) {
    var index = 0;
    when(
      () => ipatool.login(
        any(),
        any(),
        code: any(named: 'code'),
        cancel: any(named: 'cancel'),
      ),
    ).thenAnswer((_) async {
      final result = results[index++];
      if (result is AppError) throw result;
      return result as AccountInfo;
    });
  }

  group('restore', () {
    test('a saved session signs the user in', () async {
      when(() => ipatool.currentAccount()).thenAnswer((_) async => _account);
      await auth().restore();
      expect(state().status, AuthStatus.authenticated);
      expect(state().account!.email, 'User@Example.com');
    });

    test('no session means signed out, without an error', () async {
      when(() => ipatool.currentAccount()).thenAnswer((_) async => null);
      await auth().restore();
      expect(state().status, AuthStatus.signedOut);
      expect(state().error, isNull);
    });

    test('an unreadable session is reported as locked storage', () async {
      when(() => ipatool.currentAccount()).thenThrow(const StorageLocked());
      await auth().restore();
      expect(state().status, AuthStatus.storageLocked);
    });
  });

  group('login', () {
    test('success', () async {
      loginAnswers([_account]);
      await auth().login(' user@example.com ', 'pw');

      expect(state().status, AuthStatus.authenticated);
      verify(
        () => ipatool.login(
          'user@example.com',
          'pw',
          code: null,
          cancel: any(named: 'cancel'),
        ),
      ).called(1);
    });

    test(
      '2FA: waits for the code, then reuses the pending credentials',
      () async {
        loginAnswers([const AuthNeeds2FA(), _account]);
        await auth().login('user@example.com', 'pw');
        expect(state().status, AuthStatus.waitingForCode);
        expect(state().error, isNull);

        await auth().submitCode(' 123456 ');
        expect(state().status, AuthStatus.authenticated);
        verify(
          () => ipatool.login(
            'user@example.com',
            'pw',
            code: '123456',
            cancel: any(named: 'cancel'),
          ),
        ).called(1);
      },
    );

    test('a wrong code keeps the 2FA step open with an error', () async {
      loginAnswers([const AuthNeeds2FA(), const AuthInvalidCode(), _account]);
      await auth().login('user@example.com', 'pw');
      await auth().submitCode('000000');
      expect(state().status, AuthStatus.waitingForCode);
      expect(state().error, isA<AuthInvalidCode>());

      await auth().submitCode('123456');
      expect(state().status, AuthStatus.authenticated);
    });

    test('a wrong password returns to the form with the reason', () async {
      loginAnswers([const AuthInvalidCredentials()]);
      await auth().login('user@example.com', 'bad');
      expect(state().status, AuthStatus.signedOut);
      expect(state().error, isA<AuthInvalidCredentials>());
    });

    test('pending credentials are dropped after a failure', () async {
      loginAnswers([const AuthNeeds2FA(), const AppleUnreachable()]);
      await auth().login('user@example.com', 'pw');
      await auth().submitCode('123456');
      expect(state().status, AuthStatus.signedOut);

      await auth().submitCode('123456');
      verify(
        () => ipatool.login(
          any(),
          any(),
          code: any(named: 'code'),
          cancel: any(named: 'cancel'),
        ),
      ).called(2);
    });

    test('cancel aborts a running sign-in', () async {
      when(
        () => ipatool.login(
          any(),
          any(),
          code: any(named: 'code'),
          cancel: any(named: 'cancel'),
        ),
      ).thenAnswer((invocation) async {
        await (invocation.namedArguments[#cancel] as CancelToken).whenCancelled;
        throw const Cancelled();
      });

      final login = auth().login('user@example.com', 'pw');
      await Future<void>.delayed(Duration.zero);
      expect(state().status, AuthStatus.signingIn);
      auth().cancel();
      await login;

      expect(state().status, AuthStatus.signedOut);
      expect(state().error, isNull);
    });

    test('cancel leaves the 2FA step and forgets the credentials', () async {
      loginAnswers([const AuthNeeds2FA()]);
      await auth().login('user@example.com', 'pw');
      auth().cancel();
      expect(state().status, AuthStatus.signedOut);

      await auth().submitCode('123456');
      verify(
        () => ipatool.login(
          any(),
          any(),
          code: any(named: 'code'),
          cancel: any(named: 'cancel'),
        ),
      ).called(1);
    });
  });

  test('logout signs out', () async {
    when(() => ipatool.currentAccount()).thenAnswer((_) async => _account);
    when(() => ipatool.logout()).thenAnswer((_) async {});
    await auth().restore();
    await auth().logout();
    expect(state().status, AuthStatus.signedOut);
    expect(state().account, isNull);
  });

  test('accountIdFor is stable, case-insensitive and not the email', () {
    expect(accountIdFor('User@Example.com'), accountIdFor(' user@example.com'));
    expect(accountIdFor('user@example.com'), hasLength(16));
    expect(accountIdFor('user@example.com'), isNot(contains('user')));
    expect(accountIdFor('a@example.com'), isNot(accountIdFor('b@example.com')));
  });
}
