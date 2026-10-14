import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Captured result of a finished process.
class ProcessOutput {
  const ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// The executable could not be started (missing, blocked, not executable).
class ProcessStartFailure implements Exception {
  const ProcessStartFailure(this.executable, this.message);

  final String executable;
  final String message;

  @override
  String toString() => 'ProcessStartFailure($executable): $message';
}

/// The process did not finish within the allowed time and was killed.
class ProcessTimeout implements Exception {
  const ProcessTimeout(this.executable, this.timeout);

  final String executable;
  final Duration timeout;

  @override
  String toString() => 'ProcessTimeout($executable) after $timeout';
}

/// A started process with line-based output streams.
abstract class RunningProcess {
  /// Lines of stdout, without line terminators.
  Stream<String> get stdout;

  /// Lines of stderr, without line terminators.
  Stream<String> get stderr;

  Future<int> get exitCode;

  /// Asks the process to terminate. Returns false if it already exited.
  bool kill();
}

/// The only way the app launches external CLIs, so tests can replace it.
///
/// Arguments are always passed as a list and never through a shell. [stdin]
/// is written once and closed; it is the channel for secrets and must never
/// be logged by implementations.
abstract class ProcessRunner {
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  });

  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? stdin,
  });
}

class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner();

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? stdin,
  }) async {
    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        environment: environment,
      );
    } on ProcessException catch (e) {
      throw ProcessStartFailure(executable, e.message);
    }

    // A child that exits early closes its end of the pipe; that is not an
    // error for us, so write failures are ignored.
    unawaited(_feedStdin(process, stdin));
    return _SystemRunningProcess(process);
  }

  static Future<void> _feedStdin(Process process, String? stdin) async {
    try {
      if (stdin != null) process.stdin.write(stdin);
      await process.stdin.close();
    } catch (_) {}
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    final process = await start(
      executable,
      arguments,
      environment: environment,
      stdin: stdin,
    );
    final stdoutText = process.stdout.join('\n');
    final stderrText = process.stderr.join('\n');

    int exitCode;
    if (timeout == null) {
      exitCode = await process.exitCode;
    } else {
      try {
        exitCode = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        process.kill();
        await process.exitCode;
        throw ProcessTimeout(executable, timeout);
      }
    }
    return ProcessOutput(
      exitCode: exitCode,
      stdout: await stdoutText,
      stderr: await stderrText,
    );
  }
}

class _SystemRunningProcess implements RunningProcess {
  _SystemRunningProcess(this._process)
    : stdout = _lines(_process.stdout),
      stderr = _lines(_process.stderr);

  final Process _process;

  @override
  final Stream<String> stdout;

  @override
  final Stream<String> stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill() => _process.kill();

  static Stream<String> _lines(Stream<List<int>> bytes) => bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());
}
