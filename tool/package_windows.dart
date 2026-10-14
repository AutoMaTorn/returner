// Builds the Windows release and packages it:
//   build/dist/returner-<version>-windows-x64.zip          portable folder
//   build/dist/returner-setup-<version>-windows-x64.exe    installer (needs Inno Setup)
//
// Usage (from the repository root, on Windows x64):
//   dart run tool/fetch_binaries.dart
//   dart run tool/package_windows.dart
//   dart run tool/package_windows.dart --skip-build    # reuse the last build
import 'dart:io';

const _platform = 'windows-x64';
const _release = 'build/windows/x64/runner/Release';
const _stage = 'build/dist/stage';
const _dist = 'build/dist';
const _tools = ['ipatool.exe', 'ios.exe'];

// The Visual C++ runtime the Flutter engine links against. Most machines
// have it; shipping it next to the executable covers the ones that do not.
const _vcRuntime = ['msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'];

Future<void> main(List<String> args) async {
  if (!Platform.isWindows) _fail('This script packages the Windows build.');
  final skipBuild = args.contains('--skip-build');
  final version = _version();

  for (final tool in _tools) {
    if (!File('tools/bin/$_platform/$tool').existsSync()) {
      _fail(
        'tools/bin/$_platform/$tool is missing. '
        'Run: dart run tool/fetch_binaries.dart',
      );
    }
  }

  if (!skipBuild) {
    stdout.writeln('Building the release…');
    await _run('flutter', ['build', 'windows', '--release'], shell: true);
  }
  if (!File('$_release/returner.exe').existsSync()) {
    _fail('$_release/returner.exe not found. Build without --skip-build.');
  }

  stdout.writeln('Staging $_stage');
  final stage = Directory(_stage);
  if (stage.existsSync()) stage.deleteSync(recursive: true);
  _copyDirectory(Directory(_release), stage);
  Directory('$_stage/bin').createSync();
  for (final tool in _tools) {
    File('tools/bin/$_platform/$tool').copySync('$_stage/bin/$tool');
  }
  final system32 = '${Platform.environment['SystemRoot']}\\System32';
  for (final dll in _vcRuntime) {
    final source = File('$system32\\$dll');
    if (source.existsSync()) {
      source.copySync('$_stage/$dll');
    } else {
      stdout.writeln('  note: $dll not found in System32, not bundled');
    }
  }

  final zip = File('$_dist/returner-$version-$_platform.zip');
  if (zip.existsSync()) zip.deleteSync();
  // bsdtar ships with Windows 10+ and writes zip with -a.
  await _run('tar', ['-a', '-c', '-f', zip.absolute.path, '-C', _stage, '.']);
  stdout.writeln('Portable build: ${zip.path} (${_megabytes(zip)})');

  final iscc = _findInnoSetup();
  if (iscc == null) {
    stdout.writeln(
      'Inno Setup not found: the installer was not built.\n'
      'Install it (winget install JRSoftware.InnoSetup) and run again '
      'with --skip-build.',
    );
    return;
  }
  await _run(iscc, [
    '/Qp',
    '/DAppVersion=$version',
    '/DStageDir=${stage.absolute.path}',
    '/DOutputDir=${Directory(_dist).absolute.path}',
    'installer\\windows.iss',
  ]);
  final installer = File('$_dist/returner-setup-$version-$_platform.exe');
  stdout.writeln('Installer: ${installer.path} (${_megabytes(installer)})');
}

/// "0.1.0+1" in pubspec.yaml → "0.1.0".
String _version() {
  final match = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync());
  if (match == null) _fail('No version in pubspec.yaml.');
  return match[1]!;
}

String? _findInnoSetup() {
  final env = Platform.environment;
  final candidates = [
    '${env['LOCALAPPDATA']}\\Programs\\Inno Setup 6\\ISCC.exe',
    '${env['ProgramFiles(x86)']}\\Inno Setup 6\\ISCC.exe',
    '${env['ProgramFiles']}\\Inno Setup 6\\ISCC.exe',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

void _copyDirectory(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync()) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entity is Directory) {
      _copyDirectory(entity, Directory('${to.path}/$name'));
    } else if (entity is File) {
      entity.copySync('${to.path}/$name');
    }
  }
}

String _megabytes(File file) =>
    '${(file.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB';

Future<void> _run(
  String executable,
  List<String> arguments, {
  bool shell = false,
}) async {
  // `flutter` is a .bat on Windows and needs the shell; its arguments here
  // are fixed strings, never user input.
  final process = await Process.start(
    executable,
    arguments,
    runInShell: shell,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) _fail('$executable exited with code $code.');
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
