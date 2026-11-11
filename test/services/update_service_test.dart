import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:returner/core/app_paths.dart';
import 'package:returner/services/update_service.dart';
import 'package:returner/state/providers.dart';
import 'package:returner/state/updates.dart';

http.Response _release(
  String tag, {
  String? page,
  bool draft = false,
  bool prerelease = false,
}) => http.Response(
  jsonEncode({
    'tag_name': tag,
    'html_url':
        page ?? 'https://github.com/AutoMaTorn/returner/releases/tag/$tag',
    'draft': draft,
    'prerelease': prerelease,
  }),
  200,
);

void main() {
  group('UpdateService', () {
    late List<http.Request> requests;

    UpdateService service(
      http.Response Function() answer, {
      String version = '0.2.2',
    }) {
      requests = [];
      return UpdateService(
        client: MockClient((request) async {
          requests.add(request);
          return answer();
        }),
        currentVersion: version,
      );
    }

    test('a newer release is offered with its page', () async {
      final update = await service(() => _release('v0.3.0')).check();
      expect(update!.version, '0.3.0');
      expect(
        update.pageUrl,
        'https://github.com/AutoMaTorn/returner/releases/tag/v0.3.0',
      );
      final request = requests.single;
      expect(
        request.url.toString(),
        'https://api.github.com/repos/AutoMaTorn/returner/releases/latest',
      );
      // Only the app version: no account or device data.
      expect(request.headers['User-Agent'], 'Returner/0.2.2');
      expect(request.body, isEmpty);
    });

    test('the same or an older release is no update', () async {
      expect(await service(() => _release('v0.2.2')).check(), isNull);
      expect(await service(() => _release('0.2.1')).check(), isNull);
      expect(
        await service(() => _release('v0.10.0'), version: '0.9.9').check(),
        isNotNull,
        reason: 'numbers compare as numbers, not text',
      );
    });

    test('no published release yet is no update', () async {
      expect(await service(() => http.Response('{}', 404)).check(), isNull);
    });

    test('drafts and pre-releases are not offered', () async {
      expect(
        await service(() => _release('v0.3.0', prerelease: true)).check(),
        isNull,
      );
      expect(
        await service(() => _release('v0.3.0', draft: true)).check(),
        isNull,
      );
    });

    test(
      'a page outside the repository is replaced by the latest page',
      () async {
        final update = await service(
          () => _release('v0.3.0', page: 'https://example.com/returner.exe'),
        ).check();
        expect(
          update!.pageUrl,
          'https://github.com/AutoMaTorn/returner/releases/latest',
        );
      },
    );

    test('server errors, garbage and odd tags fail the check', () async {
      for (final answer in [
        () => http.Response('', 500),
        () => http.Response('not json', 200),
        () => http.Response('[]', 200),
        () => _release('nightly'),
      ]) {
        await expectLater(
          service(answer).check(),
          throwsA(isA<UpdateCheckFailed>()),
        );
      }
      final offline = UpdateService(
        client: MockClient((_) => throw const SocketException('offline')),
        currentVersion: '0.2.2',
      );
      await expectLater(offline.check(), throwsA(isA<UpdateCheckFailed>()));
    });

    test('parseVersion', () {
      expect(parseVersion('v1.2.3'), [1, 2, 3]);
      expect(parseVersion(' 0.2.2 '), [0, 2, 2]);
      expect(parseVersion('1.2'), isNull);
      expect(parseVersion('v1.2.3-beta'), isNull);
    });
  });

  group('UpdatesController', () {
    late Directory temp;
    late ProviderContainer container;
    late int calls;

    setUp(() => temp = Directory.systemTemp.createTempSync('returner_upd_'));
    tearDown(() {
      container.dispose();
      temp.deleteSync(recursive: true);
    });

    void build(http.Response Function() answer) {
      calls = 0;
      container = ProviderContainer(
        overrides: [
          appPathsProvider.overrideWithValue(AppPaths(temp.path)),
          updateServiceProvider.overrideWithValue(
            UpdateService(
              client: MockClient((_) async {
                calls++;
                return answer();
              }),
              currentVersion: '0.2.2',
            ),
          ),
        ],
      );
    }

    test('checks once per run on start', () async {
      build(() => _release('v0.3.0'));
      final updates = container.read(updatesProvider.notifier);
      await updates.checkOnStart();
      await updates.checkOnStart();
      expect(calls, 1);
      final state = container.read(updatesProvider);
      expect(state.status, UpdateStatus.available);
      expect(state.update!.version, '0.3.0');
    });

    test('turned off, the start check asks nobody and is remembered', () async {
      build(() => _release('v0.3.0'));
      container.read(checkUpdatesOnStartProvider.notifier).set(false);
      await container.read(updatesProvider.notifier).checkOnStart();
      expect(calls, 0);
      expect(container.read(updatesProvider).status, UpdateStatus.idle);

      // A manual check still works.
      await container.read(updatesProvider.notifier).check();
      expect(calls, 1);

      container.dispose();
      build(() => _release('v0.3.0'));
      expect(container.read(checkUpdatesOnStartProvider), isFalse);
    });

    test('up to date and failure are told apart', () async {
      build(() => _release('v0.2.2'));
      await container.read(updatesProvider.notifier).check();
      expect(container.read(updatesProvider).status, UpdateStatus.upToDate);

      container.dispose();
      build(() => http.Response('', 503));
      await container.read(updatesProvider.notifier).check();
      expect(container.read(updatesProvider).status, UpdateStatus.failed);
    });
  });
}
