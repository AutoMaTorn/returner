import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/log.dart';
import '../models/store.dart';
import '../services/database.dart';
import '../services/ipatool_service.dart';
import 'auth.dart';
import 'providers.dart';

/// The purchase history of one account as last fetched in full.
class PurchaseHistory {
  const PurchaseHistory({required this.apps, required this.syncedAt});

  /// Newest purchase first.
  final List<StoreApp> apps;
  final DateTime syncedAt;
}

/// Purchase history kept in SQLite per account, so the section opens at once
/// and a failed refresh never wipes what was there.
class PurchasesRepository {
  PurchasesRepository(this._ipatool, this._database, this._accountId);

  /// Apple's largest page for `list-purchases`.
  static const pageSize = 100;

  /// Guards against a server that keeps answering with full pages.
  static const maxPages = 200;

  final IpatoolService _ipatool;
  final AppDatabase _database;
  final String _accountId;

  /// The saved history, or null if it was never fetched for this account.
  PurchaseHistory? cached() {
    final sync = _database.db.select(
      'SELECT synced_at FROM purchase_sync WHERE account_id = ?',
      [_accountId],
    ).firstOrNull;
    if (sync == null) return null;
    final rows = _database.db.select(
      'SELECT app_store_id, bundle_id, name, version, purchase_date '
      'FROM purchases WHERE account_id = ? '
      'ORDER BY purchase_date IS NULL, purchase_date DESC, name',
      [_accountId],
    );
    return PurchaseHistory(
      syncedAt: DateTime.fromMillisecondsSinceEpoch(
        sync['synced_at'] as int,
        isUtc: true,
      ),
      apps: [
        for (final row in rows)
          StoreApp(
            appStoreId: row['app_store_id'] as String,
            bundleId: row['bundle_id'] as String,
            name: row['name'] as String,
            version: row['version'] as String?,
            purchaseDate: switch (row['purchase_date']) {
              final int ms => DateTime.fromMillisecondsSinceEpoch(
                ms,
                isUtc: true,
              ),
              _ => null,
            },
          ),
      ],
    );
  }

  /// Fetches every page, then replaces the saved history in one transaction.
  /// [onProgress] gets the number of apps received and Apple's total.
  Future<PurchaseHistory> refresh({
    void Function(int loaded, int total)? onProgress,
    DateTime Function() now = DateTime.now,
  }) async {
    final apps = <String, StoreApp>{};
    var total = 0;
    for (var page = 1; page <= maxPages; page++) {
      final result = await _ipatool.purchases(page: page, pageSize: pageSize);
      total = result.totalCount;
      for (final app in result.apps) {
        // A repeat purchase must not become a second row.
        apps.putIfAbsent(app.appStoreId, () => app);
      }
      onProgress?.call(apps.length, total);
      if (result.apps.length < pageSize || apps.length >= total) break;
    }
    if (apps.length != total) {
      Log.info('Purchase history: $total reported, ${apps.length} received');
    }
    final syncedAt = now().toUtc();
    _save(apps.values, total, syncedAt);
    return cached() ??
        PurchaseHistory(apps: apps.values.toList(), syncedAt: syncedAt);
  }

  void _save(Iterable<StoreApp> apps, int total, DateTime syncedAt) {
    final db = _database.db;
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM purchases WHERE account_id = ?', [_accountId]);
      final insert = db.prepare(
        'INSERT INTO purchases (account_id, app_store_id, bundle_id, name, '
        'version, purchase_date) VALUES (?, ?, ?, ?, ?, ?)',
      );
      try {
        for (final app in apps) {
          insert.execute([
            _accountId,
            app.appStoreId,
            app.bundleId,
            app.name,
            app.version,
            app.purchaseDate?.millisecondsSinceEpoch,
          ]);
        }
      } finally {
        insert.close();
      }
      db.execute(
        'INSERT OR REPLACE INTO purchase_sync (account_id, synced_at, '
        'total_count) VALUES (?, ?, ?)',
        [_accountId, syncedAt.millisecondsSinceEpoch, total],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}

final purchasesRepositoryProvider = Provider<PurchasesRepository>(
  (ref) => PurchasesRepository(
    ref.watch(ipatoolServiceProvider),
    ref.watch(databaseProvider),
    ref.watch(authProvider.select((auth) => auth.accountId)) ?? 'unknown',
  ),
);

class PurchasesState {
  const PurchasesState({
    this.history,
    this.loading = false,
    this.loaded = 0,
    this.total = 0,
    this.error,
  });

  /// Null until the history was fetched once for this account.
  final PurchaseHistory? history;
  final bool loading;

  /// Progress of the running refresh.
  final int loaded;
  final int total;

  /// Why the last refresh failed; the saved history stays usable.
  final AppError? error;
}

final purchasesProvider = NotifierProvider<PurchasesController, PurchasesState>(
  PurchasesController.new,
);

class PurchasesController extends Notifier<PurchasesState> {
  var _request = 0;

  @override
  PurchasesState build() {
    // A new repository means another account: drop any running refresh.
    final repository = ref.watch(purchasesRepositoryProvider);
    _request++;
    return PurchasesState(history: repository.cached());
  }

  /// Fetches the history unless a fetch is already running.
  Future<void> refresh() async {
    if (state.loading) return;
    final request = ++_request;
    final repository = ref.read(purchasesRepositoryProvider);
    state = PurchasesState(history: state.history, loading: true);
    try {
      final history = await repository.refresh(
        onProgress: (loaded, total) {
          if (request != _request) return;
          state = PurchasesState(
            history: state.history,
            loading: true,
            loaded: loaded,
            total: total,
          );
        },
      );
      if (request != _request) return;
      state = PurchasesState(history: history);
    } on AppError catch (error) {
      if (request != _request) return;
      if (error is AuthSessionExpired) {
        ref.read(authProvider.notifier).markExpired();
      }
      state = PurchasesState(history: state.history, error: error);
    }
  }
}
