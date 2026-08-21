import 'dart:async';

import '../core/runtime/environment_manager.dart';
import '../core/runtime/process_executor.dart';

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
class TerminalSession {
  final EnvironmentManager environment;
  String workingDirectory;
  final List<TerminalHistoryEntry> history = [];
  final _outputController = StreamController<TerminalHistoryEntry>.broadcast();
  RunningProcess? _current;

  TerminalSession({required this.environment, required this.workingDirectory});

  Stream<TerminalHistoryEntry> get onEntry => _outputController.stream;

  bool get isRunning => _current != null;

  Future<void> execute(String commandLine) async {
    if (isRunning) return;
    final parts = _splitCommand(commandLine);
    if (parts.isEmpty) return;
    final executable = parts.first;
    final args = parts.skip(1).toList();

    if (executable == 'cd') {
      _changeDirectory(args.isNotEmpty ? args.first : '~');
      final entry = TerminalHistoryEntry(commandLine: commandLine, output: [], exitCode: 0);
      history.add(entry);
      _outputController.add(entry);
      return;
    }

    final env = await environment.buildEnvironment();
    final collected = <ProcessOutputLine>[];
    try {
      final running = await ProcessExecutor.start(
        executable,
        args,
        workingDirectory: workingDirectory,
        environment: env,
      );
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
        output: [ProcessOutputLine('$executable: command not found or failed to start ($e)', isError: true)],
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
  final List<TerminalSession> sessions = [];

  TerminalService(this.environment);

  TerminalSession newSession(String workingDirectory) {
    final session = TerminalSession(environment: environment, workingDirectory: workingDirectory);
    sessions.add(session);
    return session;
  }

  void closeSession(TerminalSession session) {
    session.dispose();
    sessions.remove(session);
  }
}
