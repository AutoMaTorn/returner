import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:returner/core/errors.dart';
import 'package:returner/models/app_ref.dart';
import 'package:returner/models/ipa_info.dart';
import 'package:returner/services/database.dart';
import 'package:returner/services/operation_journal.dart';
import 'package:returner/services/package_store.dart';
import 'package:returner/services/secure_store.dart';

import '../support/fake_secrets.dart';

const _info = IpaInfo(
  bundleId: 'ru.sberbank.onlineiphone',
  displayName: 'СберБанк',
  displayVersion: '12.15.0',
  bundleVersion: '245',
  minimumOS: '13.0',
  sha256: 'abc123',
  size: 4,
);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('returner_store_'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('AppDatabase', () {
    test('migrates a new file and reopens it without changes', () {
      final path = p.join(temp.path, 'returner.db');
      AppDatabase.open(path).close();
      final reopened = AppDatabase.open(path);
      final tables = reopened.db
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name']);
      expect(
        tables,
        containsAll(['accounts', 'packages', 'operations', 'operation_events']),
      );
      expect(reopened.db.select('PRAGMA user_version').first.columnAt(0), 1);
      reopened.close();
    });
  });

  group('OperationJournal', () {
    late AppDatabase database;
    late OperationJournal journal;

    setUp(() {
      database = AppDatabase.inMemory();
      journal = OperationJournal(database);
    });
    tearDown(() => database.close());

    void begin(String id) => journal.begin(
      id: id,
      type: 'downloadAndInstall',
      accountId: 'acc',
      sessionGeneration: 3,
      appKey: '492224193',
      deviceUdid: 'udid-1',
      state: 'queued',
    );

    test('records stages in order', () {
      begin('op1');
      journal
        ..advance('op1', 'downloading')
        ..advance('op1', 'validating', packageId: 'pkg1')
        ..advance('op1', 'done');

      expect(journal.stages('op1'), [
        'queued',
        'downloading',
        'validating',
        'done',
      ]);
      final entry = journal.find('op1')!;
      expect(entry.state, 'done');
      expect(entry.packageId, 'pkg1');
      expect(entry.deviceUdid, 'udid-1');
      expect(entry.sessionGeneration, 3);
    });

    test('keeps the error code and masks details', () {
      begin('op1');
      journal.advance(
        'op1',
        'failed',
        errorCode: const LicenseRequired().code,
        details: 'refused for user@example.com',
      );
      expect(journal.find('op1')!.errorCode, 'LICENSE_REQUIRED');
      final details = database.db
          .select(
            "SELECT safe_details FROM operation_events WHERE stage = 'failed'",
          )
          .single['safe_details'];
      expect(details, isNot(contains('user@example.com')));
    });

    test('unfinished operations become interrupted after a restart', () {
      begin('running');
      journal.advance('running', 'installing');
      begin('finished');
      journal.advance('finished', 'done');
      begin('refused');
      journal.advance('refused', 'failed', errorCode: 'X');

      final recovered = journal.recoverInterrupted();

      expect(recovered.map((e) => e.id), ['running']);
      expect(journal.find('running')!.state, OperationJournal.interrupted);
      expect(journal.stages('running').last, OperationJournal.interrupted);
      expect(journal.find('finished')!.state, 'done');
      expect(journal.find('refused')!.state, 'failed');
      expect(journal.recoverInterrupted(), isEmpty, reason: 'idempotent');
    });
  });

  group('PackageStore', () {
    late AppDatabase database;
    late PackageStore store;
    late String library;

    setUp(() {
      database = AppDatabase.inMemory();
      library = p.join(temp.path, 'Иван Петров', 'library');
      store = PackageStore(database, library);
    });
    tearDown(() => database.close());

    String staged([String name = 'download.ipa']) {
      final file = File(p.join(temp.path, 'staging', name))
        ..createSync(recursive: true)
        ..writeAsStringSync('data');
      return file.path;
    }

    test('moves the staged file into the library and indexes it', () async {
      final source = staged();
      final package = await store.add(
        stagedPath: source,
        info: _info,
        accountId: 'acc',
        app: const AppRef(appStoreId: '492224193', externalVersionId: '99'),
      );

      expect(File(source).existsSync(), isFalse);
      expect(File(package.path).readAsStringSync(), 'data');
      expect(p.isWithin(library, package.path), isTrue);
      expect(p.basename(package.path), '${package.id}.ipa');

      final listed = store.list().single;
      expect(listed.id, package.id);
      expect(listed.accountId, 'acc');
      expect(listed.appStoreId, '492224193');
      expect(listed.requestedVersionId, '99');
      expect(listed.info.displayName, 'СберБанк');
      expect(listed.info.minimumOS, '13.0');
      expect(listed.info.sha256, 'abc123');
    });

    test('the same app from two accounts stays two packages', () async {
      const app = AppRef(appStoreId: '1');
      final a = await store.add(
        stagedPath: staged('a.ipa'),
        info: _info,
        accountId: 'acc-a',
        app: app,
      );
      final b = await store.add(
        stagedPath: staged('b.ipa'),
        info: _info,
        accountId: 'acc-b',
        app: app,
      );
      expect(a.id, isNot(b.id));
      expect(store.list().map((p) => p.accountId).toSet(), {'acc-a', 'acc-b'});
    });

    test('drops rows whose file has disappeared', () async {
      final package = await store.add(
        stagedPath: staged(),
        info: _info,
        accountId: 'acc',
        app: const AppRef(appStoreId: '1'),
      );
      File(package.path).deleteSync();
      expect(store.list(), isEmpty);
    });

    test('remove deletes the file and the row', () async {
      final package = await store.add(
        stagedPath: staged(),
        info: _info,
        accountId: 'acc',
        app: const AppRef(appStoreId: '1'),
      );
      await store.remove(package.id);
      expect(File(package.path).existsSync(), isFalse);
      expect(store.find(package.id), isNull);
    });

    test('finds and adopts files that lost their index row', () async {
      Directory(library).createSync(recursive: true);
      final orphan = File(p.join(library, 'deadbeef.ipa'))
        ..writeAsStringSync('data');
      File(p.join(library, 'notes.txt')).writeAsStringSync('ignored');

      expect(store.unindexedFiles(), [orphan.path]);
      final adopted = store.adopt(orphan.path, _info);

      expect(adopted.id, 'deadbeef');
      expect(adopted.accountId, PackageStore.unknownAccount);
      expect(store.unindexedFiles(), isEmpty);
      expect(store.list().single.info.bundleId, 'ru.sberbank.onlineiphone');
    });
  });

  group('SecureStore', () {
    test('creates a 32-byte passphrase once and reuses it', () async {
      final backend = FakeSecretsBackend();
      final first = await SecureStore(backend).keychainPassphrase();
      final second = await SecureStore(backend).keychainPassphrase();

      expect(first, second);
      expect(first.length, 44, reason: 'base64 of 32 bytes');
      expect(backend.values, hasLength(1));
    });

    test('refuses to work without a credential store', () async {
      await expectLater(
        SecureStore(FakeSecretsBackend(failing: true)).keychainPassphrase(),
        throwsA(isA<StorageLocked>()),
      );
    });

    test('does not hand out a passphrase that was not saved', () async {
      await expectLater(
        SecureStore(FakeSecretsBackend(dropWrites: true)).keychainPassphrase(),
        throwsA(isA<StorageLocked>()),
      );
    });
  });

  group('AppRef.parse', () {
    test('numeric App Store ID', () {
      expect(AppRef.parse(' 492224193 ')!.appStoreId, '492224193');
    });

    test('App Store links, ignoring the slug and query', () {
      for (final url in [
        'https://apps.apple.com/ru/app/id492224193',
        'https://apps.apple.com/ru/app/сбербанк-онлайн/id492224193?l=en',
        'https://apps.apple.com/app/id492224193/',
        'http://itunes.apple.com/us/app/some-name/id492224193#x',
      ]) {
        expect(AppRef.parse(url)?.appStoreId, '492224193', reason: url);
      }
    });

    test('bundle id', () {
      final ref = AppRef.parse('ru.sberbank.onlineiphone')!;
      expect(ref.bundleId, 'ru.sberbank.onlineiphone');
      expect(ref.appStoreId, isNull);
    });

    test('rejects other hosts and junk', () {
      for (final input in [
        '',
        'сбербанк',
        'https://example.com/app/id492224193',
        'https://apps.apple.com/ru/developer/id123name',
        'file:///C:/x/id1',
        '--purchase',
      ]) {
        expect(AppRef.parse(input), isNull, reason: input);
      }
    });

    test('key prefers the App Store ID', () {
      expect(const AppRef(appStoreId: '1', bundleId: 'a.b').key, '1');
      expect(const AppRef(bundleId: 'a.b').key, 'a.b');
    });
  });
}
