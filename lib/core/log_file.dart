import 'dart:io';

import 'package:path/path.dart' as p;

/// Append-only log on disk with size-based rotation: `returner.log` is the
/// current file, `returner.1.log` the previous one, and so on.
///
/// Callers pass text that is already masked; nothing is filtered here.
class LogFile {
  LogFile(
    this.directory, {
    this.maxBytes = 1024 * 1024,
    this.maxFiles = 5,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const _name = 'returner';

  final String directory;

  /// Size after which the current file is rotated.
  final int maxBytes;

  /// Files kept in total, the current one included.
  final int maxFiles;
  final DateTime Function() _now;

  File _file(int index) =>
      File(p.join(directory, index == 0 ? '$_name.log' : '$_name.$index.log'));

  /// Appends one record. Failures are swallowed: logging must never break
  /// the operation being logged.
  void write(String level, String message) {
    try {
      Directory(directory).createSync(recursive: true);
      final current = _file(0);
      if (current.existsSync() && current.lengthSync() >= maxBytes) _rotate();
      final time = _now().toIso8601String().substring(0, 19);
      current.writeAsStringSync(
        '$time ${level.padRight(7)} ${message.replaceAll('\n', '\n    ')}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException {
      // Disk full, folder locked by another program: go on without the log.
    }
  }

  void _rotate() {
    final oldest = _file(maxFiles - 1);
    if (oldest.existsSync()) oldest.deleteSync();
    for (var index = maxFiles - 2; index >= 0; index--) {
      final file = _file(index);
      if (file.existsSync()) file.renameSync(_file(index + 1).path);
    }
  }

  /// The most recent [lines] lines, oldest first, across rotated files.
  List<String> tail(int lines) {
    final result = <String>[];
    try {
      for (var index = 0; index < maxFiles && result.length < lines; index++) {
        final file = _file(index);
        if (!file.existsSync()) break;
        final content = file.readAsLinesSync();
        final take = lines - result.length;
        result.insertAll(
          0,
          content.length > take
              ? content.sublist(content.length - take)
              : content,
        );
      }
    } on FileSystemException {
      // Return what was read so far.
    }
    return result;
  }
}
