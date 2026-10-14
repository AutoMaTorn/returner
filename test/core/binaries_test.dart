import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:returner/core/binaries.dart';
import 'package:returner/core/errors.dart';

void main() {
  Binaries binaries({
    required String executable,
    required String cwd,
    required String platform,
    required Set<String> files,
  }) => Binaries(
    executablePath: executable,
    currentDirectory: cwd,
    platform: platform,
    fileExists: files.contains,
  );

  test('release build on Windows uses bin next to the executable', () {
    final dir = p.join('C:', 'Program Files', 'Returner');
    final b = binaries(
      executable: p.join(dir, 'returner.exe'),
      cwd: p.join('C:', 'Windows'),
      platform: 'windows-x64',
      files: {p.join(dir, 'bin', 'ipatool.exe'), p.join(dir, 'bin', 'ios.exe')},
    );
    expect(b.ipatool, p.join(dir, 'bin', 'ipatool.exe'));
    expect(b.ios, p.join(dir, 'bin', 'ios.exe'));
  });

  test('release build on macOS uses Contents/MacOS', () {
    final macos = p.normalize(
      p.join('/Applications', 'Returner.app', 'Contents', 'MacOS'),
    );
    final b = binaries(
      executable: p.join(macos, 'returner'),
      cwd: '/',
      platform: 'macos-arm64',
      files: {p.join(macos, 'ipatool'), p.join(macos, 'ios')},
    );
    expect(b.ipatool, p.join(macos, 'ipatool'));
    expect(b.ios, p.join(macos, 'ios'));
  });

  test('development build finds tools/bin above the build output', () {
    final repo = p.join('C:', 'src', 'app-returner');
    final b = binaries(
      executable: p.join(
        repo,
        'build',
        'windows',
        'x64',
        'runner',
        'Debug',
        'returner.exe',
      ),
      cwd: p.join('C:', 'elsewhere'),
      platform: 'windows-x64',
      files: {p.join(repo, 'tools', 'bin', 'windows-x64', 'ios.exe')},
    );
    expect(b.ios, p.join(repo, 'tools', 'bin', 'windows-x64', 'ios.exe'));
  });

  test('development build finds tools/bin from the working directory', () {
    final repo = p.join('C:', 'src', 'app-returner');
    final b = binaries(
      executable: p.join('C:', 'flutter', 'flutter_tester.exe'),
      cwd: p.join(repo, 'test'),
      platform: 'windows-x64',
      files: {p.join(repo, 'tools', 'bin', 'windows-x64', 'ipatool.exe')},
    );
    expect(
      b.ipatool,
      p.join(repo, 'tools', 'bin', 'windows-x64', 'ipatool.exe'),
    );
  });

  test('a missing binary is reported as ComponentMissing', () {
    final b = binaries(
      executable: p.join('C:', 'app', 'returner.exe'),
      cwd: p.join('C:', 'app'),
      platform: 'windows-x64',
      files: {},
    );
    expect(
      () => b.ipatool,
      throwsA(
        isA<ComponentMissing>().having(
          (e) => e.component,
          'component',
          'ipatool',
        ),
      ),
    );
  });
}
