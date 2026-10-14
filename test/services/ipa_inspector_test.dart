import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:returner/core/errors.dart';
import 'package:returner/models/ipa_info.dart';
import 'package:returner/services/ipa_inspector.dart';
import 'package:returner/services/plist.dart';

import '../support/ipa_builder.dart';

// Produced by Python's plistlib (FMT_BINARY): strings in ASCII and UTF-16,
// integers of several widths, a negative, a real, a date, data, nesting.
const _binaryPlist =
    'YnBsaXN0MDDeAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGR4fIlNCaWdfEBNDRkJ1bmRsZURpc3BsYXlOYW1lXxASQ0ZCdW5kbGVJZGVudGlmaWVyXENGQnVuZGxlTmFtZV8QGkNGQnVuZGxlU2hvcnRWZXJzaW9uU3RyaW5nXxAPQ0ZCdW5kbGVWZXJzaW9uXxASTFNSZXF1aXJlc0lQaG9uZU9TVExvbmdfEBBNaW5pbXVtT1NWZXJzaW9uU05lZ1ZOZXN0ZWRVUmF0aW9eVUlEZXZpY2VGYW1pbHlUV2hlbhMAAAABKgXyAGYEHwRABDgEPAQ1BEBfEA9jb20uZXhhbXBsZS5hcHBXRXhhbXBsZVUxLjIuM1I0NQlfEBR4eHh4eHh4eHh4eHh4eHh4eHh4eFQxNS4wE//////////50hobHB1URGF0YVNLZXlCAQJVVmFsdWUjP/gAAAAAAACiICEQARACM0HIP9MgAAAAAAgAJQApAD8AVABhAH4AkAClAKoAvQDBAMgAzgDdAOIA6wD4AQoBEgEYARsBHAEzATgBQQFGAUsBTwFSAVgBYQFkAWYBaAAAAAAAAAIBAAAAAAAAACMAAAAAAAAAAAAAAAAAAAFx';

void main() {
  group('parsePlist', () {
    test('reads a binary plist', () {
      final plist = parsePlist(base64.decode(_binaryPlist)) as Map;
      expect(plist['CFBundleIdentifier'], 'com.example.app');
      expect(plist['CFBundleDisplayName'], 'Пример');
      expect(plist['CFBundleShortVersionString'], '1.2.3');
      expect(plist['MinimumOSVersion'], '15.0');
      expect(plist['UIDeviceFamily'], [1, 2]);
      expect(plist['LSRequiresIPhoneOS'], true);
      expect(plist['Big'], 5000000000);
      expect(plist['Neg'], -7);
      expect(plist['Ratio'], 1.5);
      expect(plist['Long'], 'x' * 20);
      expect(plist['When'], DateTime.utc(2026, 10, 14, 12));
      expect((plist['Nested'] as Map)['Key'], 'Value');
      expect((plist['Nested'] as Map)['Data'], [1, 2]);
    });

    test('reads an XML plist', () {
      final plist =
          parsePlist(utf8.encode(infoPlistXml(displayName: 'Тест'))) as Map;
      expect(plist['CFBundleDisplayName'], 'Тест');
      expect(plist['UIDeviceFamily'], [1, 2]);
      expect(plist['LSRequiresIPhoneOS'], true);
    });

    test('rejects garbage instead of crashing', () {
      expect(
        () => parsePlist(utf8.encode('<html>Access Denied</html>')),
        throwsFormatException,
      );
      expect(
        () => parsePlist(Uint8List.fromList(utf8.encode('bplist00') + [1, 2])),
        throwsFormatException,
      );
      final truncated = base64.decode(_binaryPlist).sublist(0, 200);
      expect(() => parsePlist(truncated), throwsA(anything));
    });
  });

  group('IpaInspector', () {
    late Directory temp;
    const inspector = IpaInspector();

    setUp(() => temp = Directory.systemTemp.createTempSync('returner_ipa_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('reads the app Info.plist, not the extension one', () async {
      final path = writeIpa(temp);
      final info = await inspector.inspect(path);

      expect(info.bundleId, 'com.example.app');
      expect(info.displayName, 'Example');
      expect(info.displayVersion, '1.2.3');
      expect(info.bundleVersion, '45');
      expect(info.minimumOS, '15.0');
      expect(info.size, File(path).lengthSync());
      expect(
        info.sha256,
        sha256.convert(File(path).readAsBytesSync()).toString(),
      );
    });

    test('reads a binary Info.plist', () async {
      final info = await inspector.inspect(
        writeIpa(temp, infoPlist: base64.decode(_binaryPlist)),
      );
      expect(info.displayName, 'Пример');
      expect(info.minimumOS, '15.0');
    });

    test('falls back to CFBundleName when there is no display name', () async {
      final info = await inspector.inspect(
        writeIpa(
          temp,
          infoPlist: utf8.encode(
            infoPlistXml(displayName: null, minimumOS: null),
          ),
        ),
      );
      expect(info.displayName, 'ExampleBundle');
      expect(info.minimumOS, isNull);
    });

    test('works under a path with Cyrillic and spaces', () async {
      final dir = Directory('${temp.path}/Иван Петров')..createSync();
      expect((await inspector.inspect(writeIpa(dir))).bundleId, isNotEmpty);
    });

    Future<void> expectInvalid(String path) =>
        expectLater(inspector.inspect(path), throwsA(isA<PackageInvalid>()));

    test('rejects an HTML error page saved as .ipa', () async {
      final file = File('${temp.path}/page.ipa')
        ..writeAsStringSync('<html><body>Access Denied</body></html>');
      await expectInvalid(file.path);
    });

    test('rejects a truncated archive', () async {
      final bytes = File(writeIpa(temp)).readAsBytesSync();
      final file = File('${temp.path}/cut.ipa')
        ..writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      await expectInvalid(file.path);
    });

    test('rejects an archive with a corrupted entry', () async {
      final bytes = File(writeIpa(temp)).readAsBytesSync();
      // Flip bytes inside the first entry's data, past its local header.
      for (var i = 80; i < 120; i++) {
        bytes[i] ^= 0xFF;
      }
      final file = File('${temp.path}/bad.ipa')..writeAsBytesSync(bytes);
      await expectInvalid(file.path);
    });

    test('rejects a ZIP without an app Info.plist', () async {
      final file = File('${temp.path}/other.ipa')
        ..writeAsBytesSync(buildZip({'readme.txt': utf8.encode('hello')}));
      await expectInvalid(file.path);
    });

    test('rejects entries that escape the archive root', () async {
      await expectInvalid(
        writeIpa(temp, extra: {'Payload/../../evil.txt': utf8.encode('x')}),
      );
    });

    test('reads the store artwork from the package root', () async {
      final path = writeIpa(
        temp,
        extra: {
          'iTunesArtwork': [1, 2, 3, 4],
        },
      );
      expect(await inspector.artwork(path), [1, 2, 3, 4]);
    });

    test(
      'no artwork, or an unreadable file, is null rather than an error',
      () async {
        expect(await inspector.artwork(writeIpa(temp)), isNull);
        expect(await inspector.artwork('${temp.path}/nope.ipa'), isNull);
        final junk = File('${temp.path}/junk.ipa')..writeAsStringSync('<html>');
        expect(await inspector.artwork(junk.path), isNull);
      },
    );

    test('rejects a missing file', () async {
      await expectInvalid('${temp.path}/nope.ipa');
    });
  });

  group('compareVersions', () {
    test('compares numeric segments, not strings', () {
      expect(compareVersions('17.10', '17.9'), greaterThan(0));
      expect(compareVersions('9.3.5', '13.0'), lessThan(0));
      expect(compareVersions('27.0.1', '27.0'), greaterThan(0));
      expect(compareVersions('15', '15.0.0'), 0);
    });
  });
}
