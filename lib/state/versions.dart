import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ref.dart';
import '../models/store.dart';
import '../services/database.dart';
import '../services/ipatool_service.dart';
import 'auth.dart';
import 'providers.dart';

/// Older builds of an app, for devices whose iOS the latest one no longer
/// supports. Apple identifies builds by an opaque "external version id";
/// the human version behind an id costs one slow request each, so those are
/// fetched on demand and remembered.
class VersionsRepository {
  VersionsRepository(this._ipatool, this._database, this._accountId);

  final IpatoolService _ipatool;
  final AppDatabase _database;
  final String _accountId;

  /// External version ids, newest first.
  Future<List<String>> list(AppRef app) async =>
      (await _ipatool.listVersions(app)).reversed.toList();

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
