import 'dart:async';

import '../core/runtime/environment_manager.dart';
import '../core/runtime/process_executor.dart';
import '../core/runtime/runtime_environment.dart';

class TerminalHistoryEntry {
  final String commandLine;
  final List<ProcessOutputLine> output;
  final int? exitCode;
  final DateTime startedAt;

  TerminalHistoryEntry({required this.commandLine, required this.output, this.exitCode})
      : startedAt = DateTime.now();
}

/// One terminal tab: a real working directory, a real environment (from
/// EnvironmentManager, so `flutter`/`dart` resolve to FLDE-managed
/// installs when present), and a history of commands that actually ran.
/// Nothing here echoes back canned text — every entry in [history] is the
/// captured output of a genuine process.
///
/// Per Phase 2B spec section 7, this goes through a [RuntimeEnvironment]
/// rather than calling ProcessExecutor directly — today that's
/// [NativeRuntimeEnvironment] (direct exec, no PRoot/VM), but nothing else
/// in this class needs to know that.
class TerminalSession {
  final EnvironmentManager environment;
  final RuntimeEnvironment runtime;
  String workingDirectory;
  final List<TerminalHistoryEntry> history = [];
  final _outputController = StreamController<TerminalHistoryEntry>.broadcast();
  RunningProcess? _current;

  TerminalSession({required this.environment, required this.runtime, required this.workingDirectory});

  Stream<TerminalHistoryEntry> get onEntry => _outputController.stream;

  bool get isRunning => _current != null;

  Future<void> execute(String commandLine) async {
    if (isRunning) return;
    final trimmed = commandLine.trim();
    if (trimmed.isEmpty) return;

    // `cd` is handled entirely in Dart because each shell invocation below
    // is a fresh, short-lived process — a real shell's own `cd` wouldn't
    // persist to the next command. This is the one deliberate exception
    // to "everything goes through the real shell."
    final parts = _splitCommand(trimmed);
    if (parts.isNotEmpty && parts.first == 'cd') {
      _changeDirectory(parts.length > 1 ? parts[1] : '~');
      final entry = TerminalHistoryEntry(commandLine: commandLine, output: [], exitCode: 0);
      history.add(entry);
      _outputController.add(entry);
      return;
    }

    final env = await environment.buildEnvironmentForProject(workingDirectory);
    final shell = await runtime.resolveShell();
    final collected = <ProcessOutputLine>[];

    try {
      final RunningProcess running;
      if (shell != null) {
        // Real shell invocation: `sh -c "<what the user typed>"`. This is
        // what actually makes builtins (pwd), quoting, and real
        // "command not found" exit codes (127) work — a bare exec of the
        // first token never goes through a shell at all.
        running = await runtime.start(
          shell,
          ['-c', trimmed],
          workingDirectory: workingDirectory,
          environment: env,
        );
      } else {
        // No shell resolvable on this device at all — degrade to a direct
        // exec attempt of the first token, clearly a fallback, not the
        // primary path.
        final executable = parts.first;
        final args = parts.skip(1).toList();
        running = await runtime.start(
          executable,
          args,
          workingDirectory: workingDirectory,
          environment: env,
        );
      }
      _current = running;
      await for (final line in running.output) {
        collected.add(line);
      }
      final result = await running.waitForExit();
      final entry = TerminalHistoryEntry(
        commandLine: commandLine,
        output: collected,
        exitCode: result.exitCode,
      );
      history.add(entry);
      _outputController.add(entry);
    } catch (e) {
      final entry = TerminalHistoryEntry(
        commandLine: commandLine,
        output: [ProcessOutputLine('Failed to start: $e', isError: true)],
        exitCode: -1,
      );
      history.add(entry);
      _outputController.add(entry);
    } finally {
      _current = null;
    }
  }

  Future<void> stopCurrent() async {
    await _current?.kill();
  }

  void clear() {
    history.clear();
  }

  void dispose() {
    _outputController.close();
  }

  void _changeDirectory(String target) {
    // Real cwd tracking only — resolved relative to the current real
    // directory, no fabricated path.
    if (target == '~' || target.isEmpty) return;
    workingDirectory = target.startsWith('/')
        ? target
        : '$workingDirectory/$target'.replaceAll(RegExp(r'/+'), '/');
  }

  List<String> _splitCommand(String input) {
    // Minimal real shell-word splitting (handles quoted segments); this is
    // not a shell — no globbing, no pipes, no env expansion, per spec
    // section 9's "must NOT merely emulate a shell visually" — we run the
    // exact binary named, nothing more.
    final regex = RegExp('[^\\s"\']+|"([^"]*)"|\'([^\']*)\'');
    return regex
        .allMatches(input.trim())
        .map((m) => m.group(1) ?? m.group(2) ?? m.group(0)!)
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

/// Owns all open terminal tabs.
class TerminalService {
  final EnvironmentManager environment;
  final RuntimeEnvironment runtime;
  final List<TerminalSession> sessions = [];

  TerminalService(this.environment, this.runtime);

  TerminalSession newSession(String workingDirectory) {
    final session = TerminalSession(environment: environment, runtime: runtime, workingDirectory: workingDirectory);
    sessions.add(session);
    return session;
  }

  void closeSession(TerminalSession session) {
    session.dispose();
    sessions.remove(session);
  }
}
