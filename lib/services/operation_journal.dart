import '../core/log.dart';
import 'database.dart';

/// A row of the operation journal.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.type,
    required this.accountId,
    required this.sessionGeneration,
    required this.appKey,
    required this.state,
    this.packageId,
    this.deviceUdid,
    this.errorCode,
  });

  final String id;
  final String type;
  final String accountId;
  final int sessionGeneration;
  final String appKey;
  final String state;
  final String? packageId;
  final String? deviceUdid;
  final String? errorCode;
}

/// One step of an operation, as journaled.
class JournalEvent {
  const JournalEvent({required this.stage, required this.time, this.details});

  final String stage;
  final DateTime time;

  /// Already masked when it was stored.
  final String? details;
}

/// Durable record of what each operation was doing, written before the side
/// effect it describes. After a crash, unfinished operations are reported as
/// interrupted instead of being silently lost or assumed successful.
class OperationJournal {
  OperationJournal(this._database);

  static const interrupted = 'interrupted';

  /// States after which nothing else will happen.
  static const terminalStates = {
    'done',
    'failed',
    'unknown',
    'cancelled',
    interrupted,
  };

  final AppDatabase _database;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  void begin({
    required String id,
    required String type,
    required String accountId,
    required int sessionGeneration,
    required String appKey,
    required String state,
    String? deviceUdid,
  }) {
    final now = _now();
    _database.db.execute(
      'INSERT INTO operations (id, type, account_id, session_generation, '
      'app_key, device_udid, state, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        type,
        accountId,
        sessionGeneration,
        appKey,
        deviceUdid,
        state,
        now,
        now,
      ],
    );
    _event(id, state, null, now);
  }

  /// Records a stage change. [details] is masked before it is stored.
  void advance(
    String id,
    String state, {
    String? details,
    String? errorCode,
    String? packageId,
  }) {
    final now = _now();
    _database.db.execute(
      'UPDATE operations SET state = ?, updated_at = ?, '
      'error_code = COALESCE(?, error_code), '
      'package_id = COALESCE(?, package_id) WHERE id = ?',
      [state, now, errorCode, packageId, id],
    );
    _event(id, state, details, now);
  }

  void _event(String id, String stage, String? details, int now) {
    _database.db.execute(
      'INSERT INTO operation_events (operation_id, sequence, stage, '
      'safe_details, timestamp) VALUES (?, '
      '(SELECT COALESCE(MAX(sequence), 0) + 1 FROM operation_events '
      'WHERE operation_id = ?), ?, ?, ?)',
      [id, id, stage, details == null ? null : mask(details), now],
    );
  }

  /// Marks operations left unfinished by a previous run as interrupted and
  /// returns them, so the caller can clean up and offer a re-check.
  List<JournalEntry> recoverInterrupted() {
    final placeholders = List.filled(terminalStates.length, '?').join(', ');
    final stale = _select(
      'WHERE state NOT IN ($placeholders)',
      terminalStates.toList(),
    );
    for (final entry in stale) {
      advance(entry.id, interrupted, details: 'was ${entry.state}');
    }
    return stale;
  }

  /// The latest operations, newest first, each with its steps.
  List<({JournalEntry entry, List<JournalEvent> events})> recent(int limit) {
    final entries = _select('', const []).reversed.take(limit);
    return [
      for (final entry in entries)
        (
          entry: entry,
          events: [
            for (final row in _database.db.select(
              'SELECT stage, safe_details, timestamp FROM operation_events '
              'WHERE operation_id = ? ORDER BY sequence',
              [entry.id],
            ))
              JournalEvent(
                stage: row['stage'] as String,
                details: row['safe_details'] as String?,
                time: DateTime.fromMillisecondsSinceEpoch(
                  row['timestamp'] as int,
                ),
              ),
          ],
        ),
    ];
  }

  JournalEntry? find(String id) => _select('WHERE id = ?', [id]).firstOrNull;

  /// Stages an operation went through, in order.
  List<String> stages(String id) => [
    for (final row in _database.db.select(
      'SELECT stage FROM operation_events WHERE operation_id = ? '
      'ORDER BY sequence',
      [id],
    ))
      row['stage'] as String,
  ];

  List<JournalEntry> _select(String where, List<Object?> args) => [
    for (final row in _database.db.select(
      'SELECT * FROM operations $where ORDER BY created_at',
      args,
    ))
      JournalEntry(
        id: row['id'] as String,
        type: row['type'] as String,
        accountId: row['account_id'] as String,
        sessionGeneration: row['session_generation'] as int,
        appKey: row['app_key'] as String,
        state: row['state'] as String,
        packageId: row['package_id'] as String?,
        deviceUdid: row['device_udid'] as String?,
        errorCode: row['error_code'] as String?,
      ),
  ];
}
