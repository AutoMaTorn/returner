import 'package:flutter_test/flutter_test.dart';
import 'package:returner/core/log.dart';

void main() {
  group('mask', () {
    test('keeps the first letter and domain of an email', () {
      expect(
        mask('logged in as anna.petrova@icloud.com ok'),
        'logged in as a***@icloud.com ok',
      );
    });

    test('hides keyed secrets in JSON and key=value form', () {
      expect(
        mask('{"keychain-passphrase":"abc","password":"p@ss w0rd"}'),
        isNot(anyOf(contains('abc'), contains('p@ss'))),
      );
      expect(mask('token=abcdef dsid: 12345'), 'token=*** dsid: ***');
    });

    test('does not treat prose about passwords as a secret', () {
      const text = 'password is required when not running in interactive mode';
      expect(mask(text), text);
    });

    test('hides whole authorization and cookie values', () {
      expect(mask('Authorization: Token abc def'), 'Authorization: ***');
      expect(mask('cookie: a=1; b=2'), 'cookie: ***');
    });

    test('hides URL query strings but keeps the path', () {
      expect(
        mask('GET https://example.apple.com/a/b.ipa?accessKey=123&x=y done'),
        'GET https://example.apple.com/a/b.ipa?*** done',
      );
    });

    test('shortens modern and legacy UDIDs to the last four characters', () {
      expect(
        mask('device 00008140-000A1B2C3D4E001C attached'),
        'device <udid:…001C> attached',
      );
      expect(
        mask('udid=0123456789abcdef0123456789abcdef01234567'),
        'udid=<udid:…4567>',
      );
    });

    test('hides the user name in profile paths', () {
      expect(
        mask(r'C:\Users\Иван Петров\AppData\Roaming\returner\x.ipa'),
        r'C:\Users\***\AppData\Roaming\returner\x.ipa',
      );
      expect(
        mask('/Users/ivan/Library/Caches/x'),
        '/Users/***/Library/Caches/x',
      );
      expect(mask('/home/ivan/.local/x'), '/home/***/.local/x');
    });

    test('hides long opaque tokens', () {
      expect(
        mask('kbsync AAAAbbbbCCCCddddEEEEffffGGGGhhhh1234 end'),
        'kbsync *** end',
      );
    });

    test('strips ANSI escape sequences', () {
      expect(mask('\x1B[31mfailed\x1B[0m'), 'failed');
    });

    test('leaves ordinary tool output readable', () {
      const line =
          '{"level":"info","output":"cache/com.cdek.cdekapp.ipa","purchased":false,"success":true}';
      expect(mask(line), line);
    });
  });

  group('maskAuthOutput', () {
    test('hides six-digit codes', () {
      expect(maskAuthOutput('code 123456 rejected'), 'code ****** rejected');
    });

    test('keeps other numbers', () {
      expect(
        maskAuthOutput('failureType 5020, 12 attempts'),
        'failureType 5020, 12 attempts',
      );
    });
  });
}
