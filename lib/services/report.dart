import 'dart:io';

import '../core/log.dart';
import '../core/log_file.dart';
import 'operation_journal.dart';

/// Builds the text behind "copy report": what the app is, what the last
/// operations did, and the tail of the log. Everything is masked once more
/// on the way out, so the report can be pasted into a chat as it is.
class ReportBuilder {
  ReportBuilder({
    required this.appVersion,
    required this.platform,
    required this.journal,
    this.log,
    this.toolVersions = '',
  });

  static const _operations = 10;
  static const _logLines = 200;

  final String appVersion;
  final String platform;
  final String toolVersions;
  final OperationJournal journal;
  final LogFile? log;

  String build() {
    final out = StringBuffer()
      ..writeln('Returner $appVersion · $platform')
      ..writeln(Platform.operatingSystemVersion);
    if (toolVersions.isNotEmpty) out.writeln(toolVersions);

    out.writeln('\n--- последние операции');
    final operations = journal.recent(_operations);
    if (operations.isEmpty) out.writeln('нет');
    for (final operation in operations) {
      final entry = operation.entry;
      out.writeln(
        '${entry.id} ${entry.type} app=${entry.appKey} → ${entry.state}'
        '${entry.errorCode == null ? '' : ' (${entry.errorCode})'}',
      );
      for (final event in operation.events) {
        out.writeln(
          '  ${event.time.toIso8601String().substring(11, 19)} ${event.stage}'
          '${event.details == null ? '' : ' — ${event.details}'}',
        );
      }
    }

    out.writeln('\n--- журнал');
    final lines = log?.tail(_logLines) ?? const <String>[];
    out.writeln(lines.isEmpty ? 'пусто' : lines.join('\n'));
    return mask(out.toString());
  }
}
