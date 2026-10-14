import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path/path.dart' as p;

import 'errors.dart';
import 'process_runner.dart';

/// Locates the bundled CLIs (`ipatool`, go-ios `ios`).
///
/// Release builds ship them next to the app; during development they live in
/// `tools/bin/<os>-<arch>/` (see `tool/fetch_binaries.dart`).
class Binaries {
  Binaries({
    required this.executablePath,
    required this.currentDirectory,
    required this.platform,
    bool Function(String path)? fileExists,
  }) : _fileExists = fileExists ?? ((path) => File(path).existsSync());

  factory Binaries.forCurrentProcess() => Binaries(
    executablePath: Platform.resolvedExecutable,
    currentDirectory: Directory.current.path,
    platform: currentPlatform(),
  );

  final String executablePath;
  final String currentDirectory;

  /// `<os>-<arch>`, for example `windows-x64` or `macos-arm64`.
  final String platform;

  final bool Function(String path) _fileExists;

  /// Abi names look like `windows_x64`, `macos_arm64`.
  static String currentPlatform() =>
      Abi.current().toString().replaceFirst('_', '-');

  bool get _isWindows => platform.startsWith('windows-');
  bool get _isMacOS => platform.startsWith('macos-');

  String get ipatool => _locate('ipatool');

  /// go-ios.
  String get ios => _locate('ios');

  String _locate(String name) {
    final file = _isWindows ? '$name.exe' : name;
    for (final directory in _candidateDirectories()) {
      final path = p.join(directory, file);
      if (_fileExists(path)) return path;
    }
    throw ComponentMissing(name);
  }

  Iterable<String> _candidateDirectories() sync* {
    final executableDir = p.dirname(executablePath);
    if (_isMacOS) {
      // <App>.app/Contents/MacOS/<exe> → <App>.app/Contents/Resources/bin
      yield p.normalize(p.join(executableDir, '..', 'Resources', 'bin'));
    }
    yield p.join(executableDir, 'bin');

    // Development: walk up from the build output and from the working
    // directory until a checkout with tools/bin is found.
    for (final start in [executableDir, currentDirectory]) {
      var directory = start;
      while (true) {
        yield p.join(directory, 'tools', 'bin', platform);
        final parent = p.dirname(directory);
        if (parent == directory) break;
        directory = parent;
      }
    }
  }

  /// Bundled files can lose their executable bit when copied into an app
  /// bundle. No-op on Windows.
  Future<void> ensureExecutable(ProcessRunner runner) async {
    if (_isWindows) return;
    for (final path in [ipatool, ios]) {
      await runner.run('chmod', ['+x', path]);
    }
  }
}
