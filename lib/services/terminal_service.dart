import 'dart:async';

import '../core/runtime/environment_manager.dart';
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

    // `cd` changes the persistent session cwd because a child shell cannot
    // mutate Dart's parent process cwd. Everything else is executed through
    // a real Android shell so pipes, redirects, quoting, &&, environment
    // expansion, and scripts behave like a terminal instead of a visual
    // command parser. Managed ELF commands are exposed through FLDE shell
    // wrappers that invoke /system/bin/linker64.
    if (trimmed == 'cd' || trimmed.startsWith('cd ')) {
      final target = trimmed.length <= 2 ? '~' : trimmed.substring(3).trim();
      _changeDirectory(target);
      final entry = TerminalHistoryEntry(commandLine: commandLine, output: [], exitCode: 0);
      history.add(entry);
      _outputController.add(entry);
      return;
    }

    final shell = await runtime.resolveShell();
    if (shell == null) {
      final entry = TerminalHistoryEntry(
        commandLine: commandLine,
        output: [ProcessOutputLine('FLDE: no shell available', isError: true)],
        exitCode: -1,
      );
      history.add(entry);
      _outputController.add(entry);
      return;
    }

    final env = await environment.buildEnvironmentForProject(workingDirectory);
    final collected = <ProcessOutputLine>[];
    try {
      final running = await runtime.start(
        shell,
        ['-c', trimmed],
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
        output: [ProcessOutputLine('$shell: failed to start command ($e)', isError: true)],
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
