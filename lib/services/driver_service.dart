import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/log.dart';
import '../core/process_runner.dart';
import 'pe_cabinet.dart';

/// Outcome of [DriverService.install]. Every failure names its step so the
/// user is told what to do about it.
enum DriverInstallResult {
  installed,

  /// The user answered "No" to the Windows permission prompt.
  cancelled,

  /// apple.com could not be reached or the download broke off.
  downloadFailed,

  /// The installer or the package in it is not signed by Apple.
  untrusted,

  /// The installer no longer holds the expected package, or the disk is full.
  unpackFailed,

  /// Apple's package finished with an error, or the service never came up.
  installFailed,
}

enum DriverInstallStage { download, verify, unpack, install, start }

class DriverInstallProgress {
  const DriverInstallProgress(this.stage, [this.fraction]);

  final DriverInstallStage stage;

  /// 0…1 while downloading, when the size is known.
  final double? fraction;
}

/// Apple's USB driver on Windows (Apple Mobile Device Service). Without it
/// no iPhone is visible. macOS ships it with the system.
///
/// Installed on request from Apple's own iTunes installer: only the
/// `AppleMobileDeviceSupport64.msi` package inside it (driver and service),
/// not iTunes itself. Nothing is mirrored; every file is checked to be signed
/// by Apple before it runs.
class DriverService {
  DriverService({
    required this._runner,
    required this._client,
    required this._workDirectory,
    bool? isWindows,
    Future<bool> Function()? usbmuxdReachable,
    this._serviceWait = const Duration(seconds: 60),
    this._pollInterval = const Duration(seconds: 1),
    String? systemRoot,
  }) : _isWindows = isWindows ?? Platform.isWindows,
       _usbmuxdReachable = usbmuxdReachable ?? _probePort,
       _system32 = p.windows.join(
         systemRoot ?? Platform.environment['SystemRoot'] ?? r'C:\Windows',
         'System32',
       );

  /// Apple's permanent link; it redirects to the current installer.
  static const installerUri = 'https://www.apple.com/itunes/download/win64';

  /// Manual fallback page.
  static const itunesUri = 'https://www.apple.com/itunes/';

  static const packageName = 'AppleMobileDeviceSupport64.msi';
  static const _serviceName = 'Apple Mobile Device Service';

  /// Windows error codes for "the user declined": UAC prompt, MSI cancel.
  static const _declined = {1223, 1602};

  /// MSI success, success needing a restart, restart started.
  static const _msiSuccess = {0, 3010, 1641};

  final ProcessRunner _runner;
  final http.Client _client;
  final String _workDirectory;
  final bool _isWindows;
  final Future<bool> Function() _usbmuxdReachable;
  final Duration _serviceWait;
  final Duration _pollInterval;
  final String _system32;

  String get _powershell =>
      p.windows.join(_system32, 'WindowsPowerShell', 'v1.0', 'powershell.exe');

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

  /// Downloads Apple's installer, takes the driver package out of it and
  /// installs that package. Runs only when the user asked for it; Windows
  /// asks for administrator permission once.
  Future<DriverInstallResult> install({
    void Function(DriverInstallProgress progress)? onProgress,
  }) async {
    if (!_isWindows) return DriverInstallResult.installed;
    final result = await _install(onProgress ?? (_) {});
    Log.info('Driver install: ${result.name}');
    try {
      await Directory(_workDirectory).delete(recursive: true);
    } on FileSystemException {
      // Leftovers sit in staging, which is cleared on the next start.
    }
    return result;
  }

  Future<DriverInstallResult> _install(
    void Function(DriverInstallProgress) onProgress,
  ) async {
    final work = Directory(_workDirectory);
    final setup = p.join(work.path, 'iTunes64Setup.exe');
    final cabinet = p.join(work.path, 'setup.cab');
    final unpacked = p.join(work.path, 'package');
    final package = p.join(unpacked, packageName);
    try {
      if (await work.exists()) await work.delete(recursive: true);
      await Directory(unpacked).create(recursive: true);

      onProgress(const DriverInstallProgress(DriverInstallStage.download, 0));
      if (!await _download(setup, onProgress)) {
        return DriverInstallResult.downloadFailed;
      }

      onProgress(const DriverInstallProgress(DriverInstallStage.verify));
      if (!await _signedByApple(setup)) return DriverInstallResult.untrusted;

      onProgress(const DriverInstallProgress(DriverInstallStage.unpack));
      final location = await findCabinetInFile(setup);
      if (location == null) {
        Log.warning('Driver install: no cabinet in the installer');
        return DriverInstallResult.unpackFailed;
      }
      await _copyRange(setup, cabinet, location);
      await File(setup).delete();
      final expand = await _runner.run(
        p.windows.join(_system32, 'expand.exe'),
        [cabinet, '-F:$packageName', unpacked],
        timeout: const Duration(minutes: 5),
      );
      // expand exits with 0 even when nothing matched: trust the file.
      if (!await File(package).exists() || await File(package).length() == 0) {
        Log.warning('Driver install: expand ${expand.exitCode}, no package');
        return DriverInstallResult.unpackFailed;
      }
      await File(cabinet).delete();
      if (!await _signedByApple(package)) return DriverInstallResult.untrusted;

      onProgress(const DriverInstallProgress(DriverInstallStage.install));
      final code = await _runPackage(package);
      Log.info('Driver install: msiexec $code');
      if (_declined.contains(code)) return DriverInstallResult.cancelled;
      if (!_msiSuccess.contains(code)) {
        return await isInstalled()
            ? DriverInstallResult.installed
            : DriverInstallResult.installFailed;
      }

      onProgress(const DriverInstallProgress(DriverInstallStage.start));
      return await _waitForService()
          ? DriverInstallResult.installed
          : DriverInstallResult.installFailed;
    } on FileSystemException catch (e) {
      Log.warning('Driver install: file error ${e.osError?.errorCode}');
      return DriverInstallResult.unpackFailed;
    } on ProcessStartFailure catch (e) {
      Log.warning('Driver install: cannot start ${p.basename(e.executable)}');
      return DriverInstallResult.installFailed;
    } on ProcessTimeout catch (e) {
      Log.warning('Driver install: ${p.basename(e.executable)} timed out');
      return DriverInstallResult.installFailed;
    }
  }

  Future<bool> _download(
    String path,
    void Function(DriverInstallProgress) onProgress,
  ) async {
    IOSink? sink;
    try {
      final response = await _client
          .send(http.Request('GET', Uri.parse(installerUri)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        Log.warning('Driver download: HTTP ${response.statusCode}');
        await response.stream.drain<void>();
        return false;
      }
      final total = response.contentLength;
      sink = File(path).openWrite();
      var received = 0;
      var reported = -1;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          final percent = received * 100 ~/ total;
          if (percent != reported) {
            reported = percent;
            onProgress(
              DriverInstallProgress(
                DriverInstallStage.download,
                received / total,
              ),
            );
          }
        }
      }
      await sink.close();
      sink = null;
      if (total != null && received != total) {
        Log.warning('Driver download: got $received of $total bytes');
        return false;
      }
      return received > 0;
    } on Exception catch (e) {
      Log.warning('Driver download failed: ${e.runtimeType}');
      return false;
    } finally {
      await sink?.close();
    }
  }

  /// Authenticode signature check. The path goes through stdin, never into
  /// the script text. `Status` is an enum name, the same in every language.
  static const signatureScript =
      r'$p = [Console]::In.ReadLine(); '
      r'$s = Get-AuthenticodeSignature -LiteralPath $p; '
      r'[Console]::Out.WriteLine([string]$s.Status); '
      r'[Console]::Out.WriteLine([string]$s.SignerCertificate.Subject)';

  Future<bool> _signedByApple(String path) async {
    final result = await _runner.run(
      _powershell,
      ['-NoProfile', '-NonInteractive', '-Command', signatureScript],
      stdin: '$path\n',
      timeout: const Duration(minutes: 2),
    );
    final lines = result.stdout.trim().split(RegExp(r'\r?\n'));
    final valid = lines.first.trim() == 'Valid';
    final apple =
        lines.length > 1 &&
        RegExp(r'(^|,\s*)O=Apple Inc\.(,|$)').hasMatch(lines[1].trim());
    if (!valid || !apple) {
      Log.warning(
        'Driver install: ${p.basename(path)} signature '
        '${lines.first.trim()}, Apple: $apple',
      );
    }
    return valid && apple;
  }

  /// Installs the package through Windows Installer with a progress bar and
  /// no questions besides the permission prompt. Returns msiexec's exit code,
  /// or 1223 when the permission was refused.
  Future<int> _runPackage(String package) async {
    final result = await _runner.run(
      _powershell,
      ['-NoProfile', '-NonInteractive', '-Command', installScript],
      stdin: '$package\n',
      timeout: const Duration(minutes: 15),
    );
    return result.exitCode;
  }

  /// `Start-Process -Verb RunAs` is what raises the permission prompt;
  /// refusing it throws a Win32Exception with code 1223.
  static final installScript = [
    r'$p = [Console]::In.ReadLine()',
    r"$msi = Join-Path $env:SystemRoot 'System32\msiexec.exe'",
    r'''$a = @('/i', ('"' + $p + '"'), '/passive', '/norestart')''',
    r'try { $x = Start-Process -FilePath $msi -ArgumentList $a -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $x.ExitCode }',
    r'catch { $e = $_.Exception; while ($e) { if ($e -is [ComponentModel.Win32Exception] -and $e.NativeErrorCode -eq 1223) { exit 1223 }; $e = $e.InnerException }; exit 1 }',
  ].join('\n');

  Future<bool> _waitForService() async {
    final deadline = DateTime.now().add(_serviceWait);
    while (true) {
      if (await _usbmuxdReachable()) return true;
      if (!DateTime.now().isBefore(deadline)) break;
      await Future<void>.delayed(_pollInterval);
    }
    // Installed but not listening yet (for example, waits for a restart).
    return isInstalled();
  }

  static Future<void> _copyRange(
    String source,
    String target,
    CabinetLocation location,
  ) async {
    final input = await File(source).open();
    final output = File(target).openWrite();
    try {
      await input.setPosition(location.offset);
      var left = location.length;
      while (left > 0) {
        final chunk = await input.read(left < 1 << 20 ? left : 1 << 20);
        if (chunk.isEmpty) {
          throw const FileSystemException('installer ends early');
        }
        output.add(chunk);
        left -= chunk.length;
      }
    } finally {
      await output.close();
      await input.close();
    }
  }
}
