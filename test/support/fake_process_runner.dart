import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:returner/core/process_runner.dart';

/// One recorded invocation.
class FakeCall {
  FakeCall(this.executable, this.arguments, this.environment, this.stdin);

  final String executable;
  final List<String> arguments;
  final Map<String, String>? environment;
  final String? stdin;

  /// Executable name without directory and `.exe`.
  String get tool => p.basenameWithoutExtension(executable);
}

class FakeResponse {
  const FakeResponse({
    this.exitCode = 0,
    this.stdout = '',
    this.stderr = '',
    this.hang = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Never exits on its own; only [RunningProcess.kill] or a timeout ends it.
  final bool hang;
}

/// Scripted [ProcessRunner]: answers by tool name and arguments, records every
/// call including the stdin it was given.
class FakeProcessRunner implements ProcessRunner {
  final calls = <FakeCall>[];
  final _rules = <({bool Function(FakeCall) matches, FakeResponse response})>[];

  /// Answers calls to [tool] whose arguments contain [arguments] in order.
  /// Rules added later win.
  void on(String tool, List<String> arguments, FakeResponse response) {
    _rules.insert(0, (
      matches: (call) =>
          call.tool == tool && _containsInOrder(call.arguments, arguments),
      response: response,
    ));
  }

  static bool _containsInOrder(List<String> haystack, List<String> needles) {
    var index = 0;
    for (final item in haystack) {
      if (index < needles.length && item == needles[index]) index++;
    }
    return index == needles.length;
  }

  FakeResponse _respond(FakeCall call) {
    calls.add(call);
    for (final rule in _rules) {
      if (rule.matches(call)) return rule.response;
    }
    throw StateError(
      'No fake response for ${call.tool} ${call.arguments.join(' ')}',
    );
  }

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? stdin,
  }) async {
    final response = _respond(
      FakeCall(executable, List.of(arguments), environment, stdin),
    );
    return _FakeRunningProcess(response);
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    final response = _respond(
      FakeCall(executable, List.of(arguments), environment, stdin),
    );
    if (response.hang) {
      throw ProcessTimeout(executable, timeout ?? Duration.zero);
    }
    return ProcessOutput(
      exitCode: response.exitCode,
      stdout: response.stdout,
      stderr: response.stderr,
    );
  }
}

class _FakeRunningProcess implements RunningProcess {
  _FakeRunningProcess(this._response) {
    if (!_response.hang) _exit.complete(_response.exitCode);
  }

  final FakeResponse _response;
  final _exit = Completer<int>();

  static Stream<String> _lines(String text) => Stream.fromIterable(
    text.split('\n').map((l) => l.trimRight()).where((l) => l.isNotEmpty),
  );

  @override
  Stream<String> get stdout => _lines(_response.stdout);

  @override
  Stream<String> get stderr => _lines(_response.stderr);

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill() {
    if (_exit.isCompleted) return false;
    _exit.complete(-1);
    return true;
  }
}
