import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:returner/core/app_paths.dart';
import 'package:returner/core/log_file.dart';
import 'package:returner/models/app_ref.dart';
import 'package:returner/models/store.dart';
import 'package:returner/services/database.dart';
import 'package:returner/services/ipatool_service.dart';
import 'package:returner/services/lookup_service.dart';
import 'package:returner/services/operation_journal.dart';
import 'package:returner/services/report.dart';
import 'package:returner/state/providers.dart';
import 'package:returner/state/settings.dart';
import 'package:returner/state/versions.dart';

class _MockIpatool extends Mock implements IpatoolService {}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('returner_log_'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('LogFile', () {
    LogFile log({int maxBytes = 200, int maxFiles = 3}) => LogFile(
      p.join(temp.path, 'Иван Петров', 'logs'),
      maxBytes: maxBytes,
      maxFiles: maxFiles,
      now: () => DateTime(2026, 10, 14, 12, 30, 5),
    );

    test('appends timestamped records and creates the folder', () {
      log()
        ..write('INFO', 'started')
        ..write('WARNING', 'operation ab12 failed: LICENSE_REQUIRED');
      expect(log().tail(10), [
        '2026-10-14T12:30:05 INFO    started',
        '2026-10-14T12:30:05 WARNING operation ab12 failed: LICENSE_REQUIRED',
      ]);
    });

    test('keeps a multi-line message as one indented record', () {
      log().write('SEVERE', 'first\nsecond');
      expect(log().tail(10), [
        '2026-10-14T12:30:05 SEVERE  first',
        '    second',
      ]);
    });

    test('rotates by size and keeps a bounded number of files', () {
      final file = log();
      for (var i = 0; i < 60; i++) {
        file.write('INFO', 'line number $i with some padding');
      }
      final names = Directory(file.directory)
          .listSync()
          .map((f) => p.basename(f.path))
          .toSet();
      expect(names, {'returner.log', 'returner.1.log', 'returner.2.log'});
      for (final entity in Directory(file.directory).listSync()) {
        expect((entity as File).lengthSync(), lessThan(300));
      }
    });

    test('tail reads across rotated files, oldest first', () {
      final file = log();
      for (var i = 0; i < 12; i++) {
        file.write('INFO', 'line $i');
      }
      final tail = file.tail(8);
      expect(tail, hasLength(8));
      expect(tail.last, endsWith('line 11'));
      expect(tail.first, endsWith('line 4'));
    });

    test('a log folder that cannot be written does not throw', () {
      final blocker = File(p.join(temp.path, 'blocked'))
        ..writeAsStringSync('x');
      final file = LogFile(p.join(blocker.path, 'logs'));
      expect(() => file.write('INFO', 'x'), returnsNormally);
      expect(file.tail(5), isEmpty);
    });
  });

  group('ReportBuilder', () {
    late AppDatabase database;
    late OperationJournal journal;

    setUp(() {
      database = AppDatabase.inMemory();
      journal = OperationJournal(database);
    });
    tearDown(() => database.close());

    test('lists recent operations with their steps and the log tail', () {
      journal.begin(
        id: 'op1',
        type: 'downloadAndInstall',
        accountId: 'acc',
        sessionGeneration: 1,
        appKey: '492224193',
        deviceUdid: '00008140-000A1B2C3D4E001C',
        state: 'queued',
      );
      journal
        ..advance('op1', 'downloading')
        ..advance('op1', 'failed', errorCode: 'DEVICE_LOCKED');
      final log = LogFile(p.join(temp.path, 'logs'))
        ..write('WARNING', 'operation op1 failed: DEVICE_LOCKED');

      final report = ReportBuilder(
        appVersion: '0.1.0',
        platform: 'windows-x64',
        toolVersions: 'ipatool 2.7.0-returner.1 · go-ios 1.3.2',
        journal: journal,
        log: log,
      ).build();

      expect(report, startsWith('Returner 0.1.0 · windows-x64'));
      expect(report, contains('ipatool 2.7.0-returner.1'));
      expect(
        report,
        contains(
          'op1 downloadAndInstall app=492224193 → failed (DEVICE_LOCKED)',
        ),
      );
      expect(report, contains(' queued'));
      expect(report, contains(' downloading'));
      expect(report, contains('operation op1 failed: DEVICE_LOCKED'));
    });

    test('carries no personal data even if some reached the log', () {
      journal.begin(
        id: 'op1',
        type: 'download',
        accountId: 'acc',
        sessionGeneration: 1,
        appKey: '1',
        state: 'queued',
      );
      journal.advance(
        'op1',
        'failed',
        errorCode: 'UNCLASSIFIED',
        details: 'refused for anna.petrova@icloud.com',
      );
      // A line written around the logger, unmasked.
      final log = LogFile(p.join(temp.path, 'logs'))
        ..write(
          'INFO',
          r'user anna.petrova@icloud.com device 00008140-000A1B2C3D4E001C '
              r'path C:\Users\Анна\AppData password=hunter2',
        );

      final report = ReportBuilder(
        appVersion: '0.1.0',
        platform: 'windows-x64',
        journal: journal,
        log: log,
      ).build();

      for (final secret in [
        'anna.petrova',
        '00008140-000A1B2C3D4E001C',
        'Анна',
        'hunter2',
      ]) {
        expect(report, isNot(contains(secret)), reason: secret);
      }
      expect(report, contains('a***@icloud.com'));
    });

    test('says so when there is nothing yet', () {
      final report = ReportBuilder(
        appVersion: '0.1.0',
        platform: 'windows-x64',
        journal: journal,
      ).build();
      expect(report, contains('--- последние операции\nнет'));
      expect(report, contains('--- журнал\nпусто'));
    });

    test('recent returns the newest operations first, limited', () {
      for (var i = 0; i < 4; i++) {
        journal.begin(
          id: 'op$i',
          type: 'download',
          accountId: 'acc',
          sessionGeneration: 1,
          appKey: '$i',
          state: 'queued',
        );
      }
      expect(journal.recent(2).map((o) => o.entry.id), ['op3', 'op2']);
      expect(journal.recent(2).first.events.single.stage, 'queued');
    });
  });

  group('settings and lookup country', () {
    late List<Uri> requests;
    late LookupService lookup;

    ProviderContainer container() => ProviderContainer(
      overrides: [
        appPathsProvider.overrideWithValue(AppPaths(temp.path)),
        lookupServiceProvider.overrideWithValue(lookup),
      ],
    );

    setUp(() {
      requests = [];
      lookup = LookupService(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response('{"resultCount":0,"results":[]}', 200);
        }),
        iconDirectory: p.join(temp.path, 'icons'),
      );
    });

    test('Russia first by default', () async {
      final c = container();
      addTearDown(c.dispose);
      expect(c.read(lookupCountryProvider), 'ru');
      await lookup.lookup('1');
      expect(requests.first.queryParameters['country'], 'ru');
    });

    test('the chosen storefront is asked first and remembered', () async {
      final c = container();
      c.read(lookupCountryProvider.notifier).set('kz');
      await lookup.lookup('1');
      expect(requests.map((u) => u.queryParameters['country']).toList(), [
        'kz',
        'ru',
        'us',
      ]);
      c.dispose();

      final again = container();
      addTearDown(again.dispose);
      expect(again.read(lookupCountryProvider), 'kz');
    });

    test(
      'changing the storefront asks again instead of reusing answers',
      () async {
        await lookup.lookup('1');
        final before = requests.length;
        lookup.preferCountry('us');
        await lookup.lookup('1');
        expect(requests.length, greaterThan(before));
        expect(requests[before].queryParameters['country'], 'us');
      },
    );

    test('unknown codes are ignored', () {
      final c = container();
      addTearDown(c.dispose);
      c.read(lookupCountryProvider.notifier).set('xx');
      expect(c.read(lookupCountryProvider), 'ru');
      lookup.preferCountry('../etc');
      expect(lookup.countries.first, 'ru');
    });

    test('theme and storefront share the settings file without clobbering', () {
      final c = container();
      addTearDown(c.dispose);
      c.read(themeModeProvider.notifier).toggle();
      c.read(lookupCountryProvider.notifier).set('by');
      expect(c.read(settingsFileProvider).read(), {
        'theme': 'light',
        'lookupCountry': 'by',
      });
    });
  });

  group('VersionsRepository', () {
    late AppDatabase database;
    late _MockIpatool ipatool;
    const app = AppRef(appStoreId: '686449807');

    setUpAll(() => registerFallbackValue(app));
    setUp(() {
      database = AppDatabase.inMemory();
      ipatool = _MockIpatool();
    });
    tearDown(() => database.close());

    VersionsRepository repository([String account = 'acc']) =>
        VersionsRepository(ipatool, database, account);

    test('lists builds newest first', () async {
      when(() => ipatool.listVersions(any()))
          .thenAnswer((_) async => ['100', '200', '300']);
      expect(await repository().list(app), ['300', '200', '100']);
    });

    test('asks Apple for a build once and remembers the answer', () async {
      when(() => ipatool.versionMetadata(any(), any())).thenAnswer(
        (_) async => VersionMetadata(
          externalVersionId: '300',
          displayVersion: '13.0',
          releaseDate: DateTime.utc(2026, 10, 7),
        ),
      );
      expect(repository().cached(app, '300'), isNull);

      final first = await repository().metadata(app, '300');
      final second = await repository().metadata(app, '300');

      expect(first.displayVersion, '13.0');
      expect(second.releaseDate, DateTime.utc(2026, 10, 7));
      expect(repository().cached(app, '300')!.displayVersion, '13.0');
      verify(() => ipatool.versionMetadata(app, '300')).called(1);
    });

    test('the cache is per account', () async {
      when(() => ipatool.versionMetadata(any(), any())).thenAnswer(
        (_) async => const VersionMetadata(
          externalVersionId: '300',
          displayVersion: '13.0',
        ),
      );
      await repository('acc-a').metadata(app, '300');
      expect(repository('acc-b').cached(app, '300'), isNull);
    });
  });
}
