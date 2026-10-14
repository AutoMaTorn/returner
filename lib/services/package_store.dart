import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../models/app_ref.dart';
import '../models/ipa_info.dart';
import 'database.dart';

/// A verified `.ipa` in the local library.
class Package {
  const Package({
    required this.id,
    required this.accountId,
    required this.path,
    required this.info,
    required this.finalizedAt,
    this.appStoreId,
    this.requestedVersionId,
  });

  /// Opaque id; the UI never handles file system paths directly.
  final String id;

  /// The account that downloaded it. Packages carry that account's license
  /// and are never merged across accounts.
  final String accountId;
  final String path;
  final IpaInfo info;
  final DateTime finalizedAt;
  final String? appStoreId;
  final String? requestedVersionId;
}

/// Library of downloaded packages: files in one directory, index in SQLite.
class PackageStore {
  PackageStore(this._database, this.libraryDirectory, {Random? random})
    : _random = random ?? Random.secure();

  final AppDatabase _database;
  final String libraryDirectory;
  final Random _random;

  String _newId() => [
    for (var i = 0; i < 16; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  /// Moves an already verified file from staging into the library and indexes
  /// it. The file only appears under its final name once it is complete.
  Future<Package> add({
    required String stagedPath,
    required IpaInfo info,
    required String accountId,
    required AppRef app,
  }) async {
    await Directory(libraryDirectory).create(recursive: true);
    final id = _newId();
    final target = p.join(libraryDirectory, '$id.ipa');
    try {
      await File(stagedPath).rename(target);
    } on FileSystemException {
      // Staging and library on different volumes: copy, then swap in.
      final partial = '$target.partial';
      await File(stagedPath).copy(partial);
      await File(partial).rename(target);
      await File(stagedPath).delete();
    }
    return _index(id, target, info, accountId, app);
  }

  /// Indexes a file that is already in the library but has no row (see
  /// [unindexedFiles]). The owning account is no longer known.
  Package adopt(String path, IpaInfo info) => _index(
    p.basenameWithoutExtension(path),
    path,
    info,
    unknownAccount,
    AppRef(bundleId: info.bundleId),
  );

  static const unknownAccount = 'unknown';

  Package _index(
    String id,
    String target,
    IpaInfo info,
    String accountId,
    AppRef app,
  ) {
    final relativePath = p.basename(target);
    final finalizedAt = DateTime.now();
    _database.db.execute(
      'INSERT INTO packages (id, account_id, app_store_id, '
      'requested_version_id, bundle_id, display_name, display_version, '
      'bundle_version, minimum_os, relative_path, sha256, size, finalized_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        accountId,
        app.appStoreId,
        app.externalVersionId,
        info.bundleId,
        info.displayName,
        info.displayVersion,
        info.bundleVersion,
        info.minimumOS,
        relativePath,
        info.sha256,
        info.size,
        finalizedAt.millisecondsSinceEpoch,
      ],
    );
    return Package(
      id: id,
      accountId: accountId,
      path: target,
      info: info,
      finalizedAt: finalizedAt,
      appStoreId: app.appStoreId,
      requestedVersionId: app.externalVersionId,
    );
  }

  /// Packages newest first. Rows whose file has disappeared are dropped.
  List<Package> list() {
    final packages = <Package>[];
    for (final row in _database.db.select(
      'SELECT * FROM packages ORDER BY finalized_at DESC',
    )) {
      final path = p.join(libraryDirectory, row['relative_path'] as String);
      if (!File(path).existsSync()) {
        _database.db.execute('DELETE FROM packages WHERE id = ?', [row['id']]);
        continue;
      }
      packages.add(
        Package(
          id: row['id'] as String,
          accountId: row['account_id'] as String,
          path: path,
          appStoreId: row['app_store_id'] as String?,
          requestedVersionId: row['requested_version_id'] as String?,
          finalizedAt: DateTime.fromMillisecondsSinceEpoch(
            row['finalized_at'] as int,
          ),
          info: IpaInfo(
            bundleId: row['bundle_id'] as String,
            displayName: row['display_name'] as String,
            displayVersion: row['display_version'] as String?,
            bundleVersion: row['bundle_version'] as String?,
            minimumOS: row['minimum_os'] as String?,
            sha256: row['sha256'] as String,
            size: row['size'] as int,
          ),
        ),
      );
    }
    return packages;
  }

  Package? find(String id) => list().where((p) => p.id == id).firstOrNull;

  Future<void> remove(String id) async {
    final package = find(id);
    if (package == null) return;
    await File(package.path).delete();
    _database.db.execute('DELETE FROM packages WHERE id = ?', [id]);
  }

  /// Library files that have no index row (for example after a crash between
  /// the move and the insert). The caller re-inspects and re-adds them.
  List<String> unindexedFiles() {
    final directory = Directory(libraryDirectory);
    if (!directory.existsSync()) return const [];
    final known = {
      for (final row in _database.db.select(
        'SELECT relative_path FROM packages',
      ))
        row['relative_path'] as String,
    };
    return [
      for (final file in directory.listSync().whereType<File>())
        if (file.path.endsWith('.ipa') &&
            !known.contains(p.basename(file.path)))
          file.path,
    ];
  }
}
