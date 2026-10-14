import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:returner/core/process_runner.dart';
import 'package:returner/services/driver_service.dart';
import 'package:returner/services/lookup_service.dart';

import '../support/fake_process_runner.dart';

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _telegram = {
  'resultCount': 1,
  'results': [
    {
      'trackId': 686449807,
      'bundleId': 'ph.telegra.Telegraph',
      'trackName': 'Telegram Messenger',
      'artworkUrl100':
          'https://is1-ssl.mzstatic.com/image/thumb/a/100x100bb.jpg',
      'version': '13.0',
      'minimumOsVersion': '15.0',
    },
  ],
};
const _nothing = {'resultCount': 0, 'results': <Object>[]};

void main() {
  group('LookupService', () {
    late Directory temp;
    late List<Uri> requests;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('returner_lookup_');
      requests = [];
    });
    tearDown(() => temp.deleteSync(recursive: true));

    LookupService service(
      http.Response Function(Uri uri) answer, {
      int maxConcurrent = 4,
    }) => LookupService(
      client: MockClient((request) async {
        requests.add(request.url);
        return answer(request.url);
      }),
      iconDirectory: '${temp.path}/Иван Петров/icons',
      maxConcurrent: maxConcurrent,
    );

    test('reads store metadata', () async {
      final result = await service((_) => _json(_telegram)).lookup('686449807');
      expect(result!.name, 'Telegram Messenger');
      expect(result.bundleId, 'ph.telegra.Telegraph');
      expect(result.minimumOS, '15.0');
      expect(requests.single.queryParameters, {
        'id': '686449807',
        'country': 'ru',
      });
    });

    test('tries the next storefront when the first has nothing', () async {
      final result = await service(
        (uri) => _json(
          uri.queryParameters['country'] == 'us' ? _telegram : _nothing,
        ),
      ).lookup('686449807');
      expect(result, isNotNull);
      expect(requests.map((u) => u.queryParameters['country']), ['ru', 'us']);
    });

    test('an app that left the store is null, not an error', () async {
      expect(await service((_) => _json(_nothing)).lookup('492224193'), isNull);
    });

    test('network failures and garbage are null', () async {
      expect(
        await service((_) => throw const SocketException('offline'))
            .lookup('1'),
        isNull,
      );
      expect(
        await service((_) => http.Response('<html>', 200)).lookup('2'),
        isNull,
      );
      expect(await service((_) => http.Response('', 503)).lookup('3'), isNull);
    });

    test('a non-numeric id never reaches the network', () async {
      final lookup = service((_) => _json(_telegram));
      expect(await lookup.lookup('com.example.app'), isNull);
      expect(await lookup.icon('../../evil'), isNull);
      expect(requests, isEmpty);
    });

    test('repeated lookups share one request', () async {
      final lookup = service((_) => _json(_telegram));
      await Future.wait([
        lookup.lookup('686449807'),
        lookup.lookup('686449807'),
      ]);
      await lookup.lookup('686449807');
      expect(requests, hasLength(1));
    });

    test('downloads an icon once and serves it from disk afterwards', () async {
      http.Response answer(Uri uri) => uri.host == 'itunes.apple.com'
          ? _json(_telegram)
          : http.Response.bytes([1, 2, 3], 200);

      final first = await service(answer).icon('686449807');
      expect(first!.readAsBytesSync(), [1, 2, 3]);
      expect(requests, hasLength(2));

      // A new instance (next launch) finds the cached file.
      requests.clear();
      final second = await service(answer).icon('686449807');
      expect(second!.path, first.path);
      expect(requests, isEmpty);
    });

    test(
      'an icon saved from a package is served without any request',
      () async {
        final lookup = service((_) => _json(_nothing));
        expect(lookup.hasIcon('492224193'), isFalse);

        final saved = await lookup.saveIcon('492224193', [5, 6]);
        expect(saved!.readAsBytesSync(), [5, 6]);
        expect(lookup.hasIcon('492224193'), isTrue);
        expect((await lookup.icon('492224193'))!.path, saved.path);
        expect(requests, isEmpty);
        expect(await lookup.saveIcon('../evil', [1]), isNull);
      },
    );

    test('refuses artwork that is not on Apple\'s image CDN', () async {
      final evil = jsonDecode(jsonEncode(_telegram)) as Map<String, dynamic>;
      ((evil['results'] as List).first as Map)['artworkUrl100'] =
          'https://example.com/tracker.png';
      expect(await service((_) => _json(evil)).icon('686449807'), isNull);
      expect(requests.map((u) => u.host), ['itunes.apple.com']);
    });

    test('limits concurrent requests', () async {
      var running = 0;
      var peak = 0;
      final lookup = LookupService(
        client: MockClient((request) async {
          running++;
          peak = running > peak ? running : peak;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          running--;
          return _json(_nothing);
        }),
        iconDirectory: temp.path,
        countries: const ['ru'],
        maxConcurrent: 2,
      );
      await Future.wait([for (var i = 1; i <= 8; i++) lookup.lookup('$i')]);
      expect(peak, 2);
    });
  });

  group('DriverService', () {
    late FakeProcessRunner runner;

    setUp(() => runner = FakeProcessRunner());

    DriverService service({bool isWindows = true, bool Function()? port}) =>
        DriverService(
          runner: runner,
          isWindows: isWindows,
          usbmuxdReachable: () async => port?.call() ?? false,
        );

    test('macOS always has the driver and runs nothing', () async {
      final driver = service(isWindows: false);
      expect(await driver.isInstalled(), isTrue);
      expect(await driver.install(), DriverInstallResult.installed);
      expect(runner.calls, isEmpty);
    });

    test('an open usbmuxd port is enough', () async {
      expect(await service(port: () => true).isInstalled(), isTrue);
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

    test('installs Apple Devices from the Microsoft Store', () async {
      runner.on(
        'winget',
        ['install'],
        const FakeResponse(
          stdout: '  -\n  \\\nFound Apple Devices [9NP83LWLPZ9K]\nSuccessfully installed',
        ),
      );
      final lines = <String>[];

      final result = await service().install(onOutput: lines.add);

      expect(result, DriverInstallResult.installed);
      expect(lines, [
        'Found Apple Devices [9NP83LWLPZ9K]',
        'Successfully installed',
      ]);
      final args = runner.calls.single.arguments;
      expect(args, containsAllInOrder(['install', '--id', '9NP83LWLPZ9K']));
      expect(args, containsAllInOrder(['--source', 'msstore']));
      expect(args, contains('--accept-package-agreements'));
    });

    test(
      'a failing installer with no driver afterwards is a failure',
      () async {
        runner
          ..on('winget', ['install'], const FakeResponse(exitCode: 1))
          ..on('sc', ['query'], const FakeResponse(exitCode: 1060))
          ..on('reg', ['query'], const FakeResponse(exitCode: 1));
        expect(await service().install(), DriverInstallResult.failed);
      },
    );

    test(
      'a non-zero exit with the driver present counts as installed',
      () async {
        // winget also exits non-zero for "already installed".
        runner.on('winget', ['install'], const FakeResponse(exitCode: 1));
        expect(
          await service(port: () => true).install(),
          DriverInstallResult.installed,
        );
      },
    );

    test('a missing winget is a failure, not a crash', () async {
      final driver = DriverService(
        runner: _NoWinget(),
        isWindows: true,
        usbmuxdReachable: () async => false,
      );
      expect(await driver.install(), DriverInstallResult.failed);
    });
  });
}

class _NoWinget extends FakeProcessRunner {
  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? stdin,
  }) => throw ProcessStartFailure(executable, 'not found');
}
