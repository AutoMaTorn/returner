import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ref.dart';
import '../models/store.dart';
import '../services/database.dart';
import '../services/ipatool_service.dart';
import 'auth.dart';
import 'providers.dart';

/// Build ids of an app and when Apple was last asked for them.
class VersionList {
  const VersionList({required this.ids, required this.fetchedAt});

  /// Newest first.
  final List<String> ids;
  final DateTime fetchedAt;
}

/// Older builds of an app, for devices whose iOS the latest one no longer
/// supports. Apple identifies builds by an opaque "external version id";
/// the human version behind an id costs one slow request each, so those are
/// fetched on demand and remembered.
class VersionsRepository {
  VersionsRepository(this._ipatool, this._database, this._accountId);

  final IpatoolService _ipatool;
  final AppDatabase _database;
  final String _accountId;

  /// The build list as last fetched, or null if it was never fetched.
  VersionList? saved(AppRef app) {
    final row = _database.db.select(
      'SELECT ids, fetched_at FROM version_lists '
      'WHERE account_id = ? AND app_store_id = ?',
      [_accountId, app.key],
    ).firstOrNull;
    if (row == null) return null;
    final ids = jsonDecode(row['ids'] as String);
    if (ids is! List) return null;
    return VersionList(
      ids: [for (final id in ids) '$id'],
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        row['fetched_at'] as int,
        isUtc: true,
      ),
    );
  }

  /// External version ids, newest first. The saved list is used unless
  /// [refresh] asks Apple again; a fetched list replaces the saved one.
  Future<VersionList> list(
    AppRef app, {
    bool refresh = false,
    DateTime Function() now = DateTime.now,
  }) async {
    if (!refresh) {
      final known = saved(app);
      if (known != null) return known;
    }
    final ids = (await _ipatool.listVersions(app)).reversed.toList();
    final fetchedAt = now().toUtc();
    _database.db.execute(
      'INSERT OR REPLACE INTO version_lists (account_id, app_store_id, ids, '
      'fetched_at) VALUES (?, ?, ?, ?)',
      [_accountId, app.key, jsonEncode(ids), fetchedAt.millisecondsSinceEpoch],
    );
    return VersionList(ids: ids, fetchedAt: fetchedAt);
  }

  /// What is already known about a build, without asking Apple.
  VersionMetadata? cached(AppRef app, String externalVersionId) {
    final row = _database.db.select(
      'SELECT display_version, release_date FROM versions '
      'WHERE account_id = ? AND app_store_id = ? '
      'AND external_version_id = ?',
      [_accountId, app.key, externalVersionId],
    ).firstOrNull;
    final version = row?['display_version'] as String?;
    if (row == null || version == null) return null;
    final date = row['release_date'] as int?;
    return VersionMetadata(
      externalVersionId: externalVersionId,
      displayVersion: version,
      releaseDate: date == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(date, isUtc: true),
    );
  }

  Future<VersionMetadata> metadata(AppRef app, String externalVersionId) async {
    final known = cached(app, externalVersionId);
    if (known != null) return known;
    final metadata = await _ipatool.versionMetadata(app, externalVersionId);
    _database.db.execute(
      'INSERT OR REPLACE INTO versions (account_id, app_store_id, '
      'external_version_id, display_version, release_date) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        _accountId,
        app.key,
        externalVersionId,
        metadata.displayVersion,
        metadata.releaseDate?.millisecondsSinceEpoch,
      ],
    );
    return metadata;
  }
}

final versionsRepositoryProvider = Provider<VersionsRepository>(
  (ref) => VersionsRepository(
    ref.watch(ipatoolServiceProvider),
    ref.watch(databaseProvider),
    ref.watch(authProvider.select((auth) => auth.accountId)) ?? 'unknown',
  ),
);
