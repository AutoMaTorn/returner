import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'log_file.dart';

const _hidden = '***';

final _ansi = RegExp('\x1B\\[[0-?]*[ -/]*[@-~]');

// "Authorization: Token abc", "Cookie: a=b; c=d" — the whole value is secret.
final _headerSecret = RegExp(
  r'\b(authorization|cookie|set-cookie)("?\s*[:=]\s*"?)[^"\r\n]+',
  caseSensitive: false,
);

// password=..., "keychain-passphrase":"...", token: ...
final _keyedSecret = RegExp(
  r'\b(password|passphrase|token|dsid|auth-code|authcode|kbsync)("?\s*[:=]\s*"?)[^"\s,}&]+',
  caseSensitive: false,
);

final _urlQuery = RegExp(r'''(https?://[^\s?"']+)\?[^\s"']+''');

final _email = RegExp(
  r'([A-Z0-9._%+-])[A-Z0-9._%+-]*@([A-Z0-9.-]+\.[A-Z]{2,})',
  caseSensitive: false,
);

// Modern UDIDs are 8-16 hex, older ones are 40 hex characters.
final _udid = RegExp(
  r'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{12}([0-9A-Fa-f]{4})\b|\b[0-9A-Fa-f]{36}([0-9A-Fa-f]{4})\b',
);

final _windowsProfile = RegExp(r'([A-Za-z]:[\\/]Users[\\/])[^\\/\r\n"]+');
final _unixProfile = RegExp(r'(/(?:Users|home)/)[^/\s"]+');

final _longToken = RegExp(r'[A-Za-z0-9+/_=-]{32,}');

final _sixDigits = RegExp(r'\b\d{6}\b');

/// Removes personal data and secrets from text that is about to be logged or
/// shown in a report.
String mask(String input) {
  var value = input.replaceAll(_ansi, '');
  value = value.replaceAllMapped(
    _headerSecret,
    (m) => '${m[1]}${m[2]}$_hidden',
  );
  value = value.replaceAllMapped(_keyedSecret, (m) => '${m[1]}${m[2]}$_hidden');
  value = value.replaceAllMapped(_urlQuery, (m) => '${m[1]}?$_hidden');
  value = value.replaceAllMapped(_email, (m) => '${m[1]}$_hidden@${m[2]}');
  value = value.replaceAllMapped(_udid, (m) => '<udid:…${m[1] ?? m[2]}>');
  value = value.replaceAllMapped(_windowsProfile, (m) => '${m[1]}$_hidden');
  value = value.replaceAllMapped(_unixProfile, (m) => '${m[1]}$_hidden');
  value = value.replaceAll(_longToken, _hidden);
  return value;
}

/// [mask] for output of the login flow, where any six-digit number may be a
/// 2FA code.
String maskAuthOutput(String input) =>
    mask(input).replaceAll(_sixDigits, '******');

/// App logger. Every message goes through [mask] before it reaches the
/// console or the log file.
abstract final class Log {
  static final _logger = Logger('returner');
  static LogFile? _file;
  static var _listening = false;

  /// The file records go to, if any; the source for error reports.
  static LogFile? get file => _file;

  /// Routes records to the debug console and, when [file] is given, to disk.
  static void init({LogFile? file}) {
    _file = file;
    if (_listening) return;
    _listening = true;
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('[${record.level.name}] ${record.message}');
      _file?.write(record.level.name, record.message);
    });
  }

  static void info(String message) => _logger.info(mask(message));

  static void warning(String message) => _logger.warning(mask(message));

  static void error(String message, [Object? error]) =>
      _logger.severe(error == null ? mask(message) : mask('$message: $error'));
}
