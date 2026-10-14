import 'package:sqlite3/sqlite3.dart';

/// Local SQLite store. Holds no secrets; all external ids are strings.
class AppDatabase {
  AppDatabase._(this.db);

  /// Opens (and migrates) the database at [path].
  factory AppDatabase.open(String path) =>
      AppDatabase._(sqlite3.open(path)).._migrate();

  factory AppDatabase.inMemory() =>
      AppDatabase._(sqlite3.openInMemory()).._migrate();

  final Database db;

  static const _migrations = <String>[
    // 1
    '''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      masked_email TEXT NOT NULL,
      last_auth_at INTEGER NOT NULL
    );
    CREATE TABLE purchases (
      account_id TEXT NOT NULL,
      app_store_id TEXT NOT NULL,
      bundle_id TEXT NOT NULL,
      name TEXT NOT NULL,
      version TEXT,
      purchase_date INTEGER,
      PRIMARY KEY (account_id, app_store_id)
    );
    CREATE TABLE versions (
      account_id TEXT NOT NULL,
      app_store_id TEXT NOT NULL,
      external_version_id TEXT NOT NULL,
      display_version TEXT,
      release_date INTEGER,
      PRIMARY KEY (account_id, app_store_id, external_version_id)
    );
    CREATE TABLE availability_checks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      account_id TEXT NOT NULL,
      app_key TEXT NOT NULL,
      external_version_id TEXT,
      outcome TEXT NOT NULL,
      checked_at INTEGER NOT NULL
    );
    CREATE TABLE packages (
      id TEXT PRIMARY KEY,
      account_id TEXT NOT NULL,
      app_store_id TEXT,
      requested_version_id TEXT,
      bundle_id TEXT NOT NULL,
      display_name TEXT NOT NULL,
      display_version TEXT,
      bundle_version TEXT,
      minimum_os TEXT,
      relative_path TEXT NOT NULL,
      sha256 TEXT NOT NULL,
      size INTEGER NOT NULL,
      finalized_at INTEGER NOT NULL
    );
    CREATE TABLE operations (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      account_id TEXT NOT NULL,
      session_generation INTEGER NOT NULL,
      app_key TEXT NOT NULL,
      package_id TEXT,
      device_udid TEXT,
      state TEXT NOT NULL,
      error_code TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE TABLE operation_events (
      operation_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      stage TEXT NOT NULL,
      safe_details TEXT,
      timestamp INTEGER NOT NULL,
      PRIMARY KEY (operation_id, sequence)
    );
    ''',
  ];

  void _migrate() {
    db.execute('PRAGMA foreign_keys = ON');
    var version = db.select('PRAGMA user_version').first.columnAt(0) as int;
    while (version < _migrations.length) {
      db.execute('BEGIN');
      try {
        db.execute(_migrations[version]);
        version++;
        db.execute('PRAGMA user_version = $version');
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  void close() => db.close();
}
