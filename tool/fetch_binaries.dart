// Prepares the bundled CLIs pinned in tools/versions.json in
// tools/bin/<os>-<arch>/:
//   - go-ios is downloaded from GitHub Releases and verified by SHA-256;
//   - ipatool is built from the pinned upstream commit with our patch
//     (credentials on stdin), which needs `git` and `go` on PATH.
//
// Usage:
//   dart run tool/fetch_binaries.dart                 # current OS/arch
//   dart run tool/fetch_binaries.dart --platform=macos-arm64
//   dart run tool/fetch_binaries.dart --force         # redo everything
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';

const _versionsFile = 'tools/versions.json';
const _binRoot = 'tools/bin';
const _buildRoot = 'tools/build';

Future<void> main(List<String> args) async {
  final host = _currentPlatform();
  var platform = host;
  var force = false;
  for (final arg in args) {
    if (arg == '--force') {
      force = true;
    } else if (arg.startsWith('--platform=')) {
      platform = arg.substring('--platform='.length);
    } else {
      stderr.writeln('Unknown argument: $arg');
      exit(64);
    }
  }

  final versionsFile = File(_versionsFile);
  if (!versionsFile.existsSync()) {
    stderr.writeln('$_versionsFile not found. Run from the repository root.');
    exit(66);
  }
  final tools =
      jsonDecode(versionsFile.readAsStringSync()) as Map<String, dynamic>;

  final outDir = Directory('$_binRoot/$platform')..createSync(recursive: true);
  final isWindows = platform.startsWith('windows-');

  for (final entry in tools.entries) {
    final tool = entry.value as Map<String, dynamic>;
    final target = File(
      '${outDir.path}/${tool['binary']}${isWindows ? '.exe' : ''}',
    );
    if (tool['source'] == 'build') {
      await _build(
        name: entry.key,
        tool: tool,
        platform: platform,
        host: host,
        target: target,
        force: force,
      );
      continue;
    }
    final asset =
        (tool['assets'] as Map<String, dynamic>)[platform]
            as Map<String, dynamic>?;
    if (asset == null) {
      stderr.writeln('${entry.key}: no release asset for $platform');
      exit(1);
    }
    await _fetch(
      name: entry.key,
      repo: tool['repo'] as String,
      tag: tool['tag'] as String,
      file: asset['file'] as String,
      sha256Hex: asset['sha256'] as String,
      member: asset['member'] as String,
      target: target,
      force: force,
    );
  }
}

String _currentPlatform() {
  // Abi names look like "windows_x64", "macos_arm64".
  return Abi.current().toString().replaceFirst('_', '-');
}

bool _upToDate(File target, String stampValue, bool force) {
  final stamp = File('${target.path}.stamp');
  return !force &&
      target.existsSync() &&
      stamp.existsSync() &&
      stamp.readAsStringSync().trim() == stampValue;
}

void _writeStamp(File target, String stampValue) {
  File('${target.path}.stamp').writeAsStringSync('$stampValue\n');
}

Future<void> _build({
  required String name,
  required Map<String, dynamic> tool,
  required String platform,
  required String host,
  required File target,
  required bool force,
}) async {
  final repo = tool['repo'] as String;
  final tag = tool['tag'] as String;
  final commit = tool['commit'] as String;
  final version = tool['version'] as String;
  final patch = File(tool['patch'] as String);
  final ldflagsVar = tool['versionVariable'] as String;

  final parts = platform.split('-');
  final goos = const {'windows': 'windows', 'macos': 'darwin'}[parts[0]];
  final goarch = const {'x64': 'amd64', 'arm64': 'arm64'}[parts[1]];
  if (goos == null || goarch == null) {
    stderr.writeln('$name: unsupported platform $platform');
    exit(1);
  }
  // The macOS keychain backend needs cgo, so it cannot be cross-compiled.
  final needsCgo = goos == 'darwin';
  if (needsCgo && !host.startsWith('macos-')) {
    stderr.writeln('$name: $platform must be built on macOS (cgo keychain).');
    exit(1);
  }

  final patchHash = sha256.convert(patch.readAsBytesSync()).toString();
  final stampValue = '$commit+$patchHash+$version';
  if (_upToDate(target, stampValue, force)) {
    stdout.writeln('$name $version: up to date (${target.path})');
    return;
  }

  final src = Directory('$_buildRoot/$name');
  if (src.existsSync()) src.deleteSync(recursive: true);
  src.parent.createSync(recursive: true);

  stdout.writeln('$name $version: cloning $repo@$tag');
  await _run('git', [
    // Keep upstream line endings so the patch applies on Windows too.
    '-c', 'core.autocrlf=false',
    '-c', 'advice.detachedHead=false',
    'clone', '--quiet', '--depth', '1', '--branch', tag,
    'https://github.com/$repo.git', src.path,
  ]);
  final head = (await _run('git', ['rev-parse', 'HEAD'], cwd: src.path)).trim();
  if (head != commit) {
    stderr.writeln('$name: tag $tag is at $head, expected $commit');
    exit(1);
  }

  stdout.writeln('$name $version: applying ${patch.path}');
  await _run('git', ['apply', patch.absolute.path], cwd: src.path);

  stdout.writeln('$name $version: building for $goos/$goarch');
  await _run(
    'go',
    [
      'build',
      '-trimpath',
      '-ldflags',
      '-X $ldflagsVar=$version',
      '-o',
      target.absolute.path,
      '.',
    ],
    cwd: src.path,
    env: {'GOOS': goos, 'GOARCH': goarch, 'CGO_ENABLED': needsCgo ? '1' : '0'},
  );
  _writeStamp(target, stampValue);
  stdout.writeln('$name $version: built ${target.path}');
}

Future<void> _fetch({
  required String name,
  required String repo,
  required String tag,
  required String file,
  required String sha256Hex,
  required String member,
  required File target,
  required bool force,
}) async {
  // The stamp records which archive the binary was extracted from.
  if (_upToDate(target, sha256Hex, force)) {
    stdout.writeln('$name $tag: up to date (${target.path})');
    return;
  }

  final tmp = Directory.systemTemp.createTempSync('returner_fetch_');
  try {
    final archive = File('${tmp.path}/$file');
    final url = Uri.parse(
      'https://github.com/$repo/releases/download/$tag/$file',
    );
    stdout.writeln('$name $tag: downloading $url');
    await _download(url, archive);

    final actual = (await sha256.bind(archive.openRead()).first).toString();
    if (actual != sha256Hex) {
      stderr.writeln(
        '$name: SHA-256 mismatch for $file\n'
        '  expected $sha256Hex\n'
        '  actual   $actual',
      );
      exit(1);
    }

    final extractDir = Directory('${tmp.path}/x')..createSync();
    await _extract(archive, member, extractDir);
    final extracted = File('${extractDir.path}/$member');
    if (!extracted.existsSync()) {
      stderr.writeln('$name: $member not found in $file');
      exit(1);
    }

    extracted.copySync(target.path);
    if (!Platform.isWindows) {
      await _run('chmod', ['+x', target.path]);
    }
    _writeStamp(target, sha256Hex);
    stdout.writeln('$name $tag: installed ${target.path}');
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

Future<void> _download(Uri url, File out) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      stderr.writeln('GET $url failed: HTTP ${response.statusCode}');
      exit(1);
    }
    await response.pipe(out.openWrite());
  } finally {
    client.close();
  }
}

Future<void> _extract(File archive, String member, Directory into) async {
  // bsdtar (Windows 10+, macOS) reads both tar.gz and zip.
  await _run('tar', ['-xf', archive.path, '-C', into.path, member]);
}

Future<String> _run(
  String exe,
  List<String> args, {
  String? cwd,
  Map<String, String>? env,
}) async {
  final ProcessResult result;
  try {
    result = await Process.run(
      exe,
      args,
      workingDirectory: cwd,
      environment: env,
    );
  } on ProcessException catch (e) {
    stderr.writeln(
      'Cannot run $exe: ${e.message}. Is it installed and on PATH?',
    );
    exit(1);
  }
  if (result.exitCode != 0) {
    stderr.writeln(
      '$exe ${args.join(' ')} failed (${result.exitCode}):\n${result.stderr}',
    );
    exit(1);
  }
  return result.stdout as String;
}
