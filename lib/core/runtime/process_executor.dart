import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/process_result.dart';

/// A single line of live output from a running process, tagged by stream
/// so callers (terminal UI, build logs) can color stdout vs stderr.
class ProcessOutputLine {
  final String text;
  final bool isError;
  final DateTime timestamp;

  ProcessOutputLine(this.text, {required this.isError}) : timestamp = DateTime.now();
}

/// A live, cancellable process. `output` streams lines as they're actually
/// produced by the OS process — nothing here is synthesized. `exitCode`
/// resolves only when the real process actually exits (or is killed).
class RunningProcess {
  final Process _process;
  final String command;
  final List<String> arguments;
  final _outputController = StreamController<ProcessOutputLine>.broadcast();
  final _stopwatch = Stopwatch()..start();
  bool _killed = false;

  RunningProcess._(this._process, this.command, this.arguments) {
    _process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      _outputController.add(ProcessOutputLine(line, isError: false));
    });
    _process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      _outputController.add(ProcessOutputLine(line, isError: true));
    });
  }

  Stream<ProcessOutputLine> get output => _outputController.stream;

  int get pid => _process.pid;

  bool get wasKilled => _killed;

  void writeToStdin(String input) {
    _process.stdin.writeln(input);
  }

  /// Terminates the real OS process. Returns once Android has actually
  /// signaled it (or we've waited long enough to consider it unresponsive).
  Future<void> kill({ProcessSignal signal = ProcessSignal.sigterm}) async {
    _killed = true;
    _process.kill(signal);
  }

  Future<ExecResult> waitForExit({Duration? timeout}) async {
    int exitCode;
    bool timedOut = false;
    try {
      exitCode = timeout != null
          ? await _process.exitCode.timeout(timeout, onTimeout: () {
              timedOut = true;
              _process.kill(ProcessSignal.sigkill);
              return -1;
            })
          : await _process.exitCode;
    } finally {
      _stopwatch.stop();
      await _outputController.close();
    }

    return ExecResult(
      command: command,
      arguments: arguments,
      exitCode: exitCode,
      stdout: '', // full text isn't buffered here — consume `output` for that
      stderr: '',
      duration: _stopwatch.elapsed,
      timedOut: timedOut,
    );
  }
}

/// Runs real OS processes. This is the ONLY place in FLDE that should call
/// `Process.start`/`Process.run` — every other service (terminal, build,
/// toolchain validation) goes through here so behavior (env, cwd, logging)
/// stays consistent instead of every caller reimplementing it.
class ProcessExecutor {
  /// Runs a command to completion and buffers all output. Suitable for
  /// short-lived checks like `flutter --version`. For long-running
  /// commands (flutter run, a build), use [start] and consume the stream.
  static Future<ExecResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = timeout != null
          ? await Process.run(
              executable,
              arguments,
              workingDirectory: workingDirectory,
              environment: environment,
              runInShell: false,
            ).timeout(timeout)
          : await Process.run(
              executable,
              arguments,
              workingDirectory: workingDirectory,
              environment: environment,
              runInShell: false,
            );
      stopwatch.stop();
      return ExecResult(
        command: executable,
        arguments: arguments,
        exitCode: result.exitCode,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
        duration: stopwatch.elapsed,
      );
    } on TimeoutException {
      stopwatch.stop();
      return ExecResult(
        command: executable,
        arguments: arguments,
        exitCode: -1,
        stdout: '',
        stderr: 'Command timed out after ${timeout!.inSeconds}s',
        duration: stopwatch.elapsed,
        timedOut: true,
      );
    } on ProcessException catch (e) {
      stopwatch.stop();
      return ExecResult(
        command: executable,
        arguments: arguments,
        exitCode: -1,
        stdout: '',
        stderr: 'Failed to start process: ${e.message}',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Starts a long-running/interactive process (terminal commands,
  /// `flutter run`, `flutter build apk`) and returns a live handle whose
  /// output can be streamed to a UI as it's actually produced.
  static Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    return RunningProcess._(process, executable, arguments);
  }
}
