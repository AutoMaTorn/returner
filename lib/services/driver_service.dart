import 'dart:async';
import 'dart:io';

import '../core/process_runner.dart';

enum DriverInstallResult {
  installed,

  /// winget is missing or the install failed; offer the manual links.
  failed,
}

/// Apple's USB driver on Windows (Apple Mobile Device Service). Without it
/// no iPhone is visible. macOS ships it with the system.
class DriverService {
  DriverService({
    required this._runner,
    bool? isWindows,
    Future<bool> Function()? usbmuxdReachable,
  }) : _isWindows = isWindows ?? Platform.isWindows,
       _usbmuxdReachable = usbmuxdReachable ?? _probePort;

  /// "Apple Devices" in the Microsoft Store, published by Apple Inc.
  static const storeProductId = '9NP83LWLPZ9K';
  static const storeUri = 'ms-windows-store://pdp/?ProductId=$storeProductId';
  static const itunesUri = 'https://www.apple.com/itunes/';
  static const _serviceName = 'Apple Mobile Device Service';

  final ProcessRunner _runner;
  final bool _isWindows;
  final Future<bool> Function() _usbmuxdReachable;

  static Future<bool> _probePort() async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        27015,
        timeout: const Duration(milliseconds: 1200),
      );
      socket.destroy();
      return true;
    } on Exception {
      return false;
    }
  }

  /// Whether the driver is present.
  ///
  /// The open port comes first: the Store version of "Apple Devices" does not
  /// register a service under the classic name. Exit codes of `sc` and `reg`
  /// do not depend on the Windows display language.
  Future<bool> isInstalled() async {
    if (!_isWindows) return true;
    if (await _usbmuxdReachable()) return true;
    if (await _succeeds('sc', ['query', _serviceName])) return true;
    return _succeeds('reg', [
      'query',
      'HKLM\\SYSTEM\\CurrentControlSet\\Services\\$_serviceName',
    ]);
  }

  Future<bool> _succeeds(String executable, List<String> arguments) async {
    try {
      final result = await _runner.run(
        executable,
        arguments,
        timeout: const Duration(seconds: 20),
      );
      return result.exitCode == 0;
    } on Exception {
      return false;
    }
  }

  /// Installs "Apple Devices" from the Microsoft Store with winget. Runs only
  /// when the user asked for it. [onOutput] receives winget's progress lines.
  Future<DriverInstallResult> install({
    void Function(String line)? onOutput,
  }) async {
    if (!_isWindows) return DriverInstallResult.installed;
    final RunningProcess process;
    try {
      process = await _runner.start('winget', [
        'install',
        '--id',
        storeProductId,
        '--source',
        'msstore',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity',
      ]);
    } on ProcessStartFailure {
      return DriverInstallResult.failed;
    }
    unawaited(process.stderr.drain<void>());
    await for (final line in process.stdout) {
      final text = line.trim();
      // winget redraws a spinner and a progress bar; keep real sentences.
      if (text.length > 3 && RegExp(r'[A-Za-zА-Яа-я]{3}').hasMatch(text)) {
        onOutput?.call(text);
      }
    }
    final exitCode = await process.exitCode;
    // Trust the driver, not the exit code: winget also fails with "already
    // installed", and can succeed before the service is up.
    if (exitCode == 0 || await isInstalled()) {
      return DriverInstallResult.installed;
    }
    return DriverInstallResult.failed;
  }
}
