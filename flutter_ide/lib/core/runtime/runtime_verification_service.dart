import '../../models/process_result.dart';
import 'runtime_environment.dart';

class VerificationCommandResult {
  final String command;
  final bool started;
  final String? startError;
  final ExecResult? execResult;

  const VerificationCommandResult({
    required this.command,
    required this.started,
    this.startError,
    this.execResult,
  });

  bool get succeeded => started && execResult != null && execResult!.exitCode == 0;
}

class RuntimeVerificationReport {
  final String? shellUsed;
  final List<VerificationCommandResult> results;
  final DateTime generatedAt;

  const RuntimeVerificationReport({required this.shellUsed, required this.results, required this.generatedAt});
}

/// Phase 2C: proves — with real, undisguised process results captured
/// from inside the actual running APK on the actual Android device — that
/// the full chain (Terminal/verification UI -> ProcessExecutor ->
/// Android's process-creation APIs -> a real resolved shell -> a real
/// command) works end to end. This is deliberately separate from
/// RuntimeDiagnosticsService (which tests exec PERMISSIONS on
/// FLDE-private files) — this class tests actual FUNCTIONAL command
/// execution via already-executable system binaries, which is a
/// different question with a different, already-more-likely-to-succeed
/// answer.
///
/// Every command below is run for real via `<shell> -c "<command>"`.
/// Nothing here hardcodes an expected result — including the
/// known-to-fail command, whose stderr/exit code are whatever the real
/// shell actually produces on this device.
class RuntimeVerificationService {
  final RuntimeEnvironment runtime;

  RuntimeVerificationService(this.runtime);

  static const List<String> _commands = [
    'uname -m',
    'echo hello',
    'pwd',
    'flde_this_command_does_not_exist_12345',
  ];

  Future<RuntimeVerificationReport> run({String? workingDirectory}) async {
    final shell = await runtime.resolveShell();
    final results = <VerificationCommandResult>[];

    for (final command in _commands) {
      if (shell == null) {
        results.add(VerificationCommandResult(
          command: command,
          started: false,
          startError: 'No shell resolved on this device — cannot run any command through a shell.',
        ));
        continue;
      }
      try {
        final execResult = await runtime.execute(
          shell,
          ['-c', command],
          workingDirectory: workingDirectory,
          timeout: const Duration(seconds: 10),
        );
        results.add(VerificationCommandResult(command: command, started: true, execResult: execResult));
      } catch (e) {
        results.add(VerificationCommandResult(command: command, started: false, startError: '$e'));
      }
    }

    return RuntimeVerificationReport(shellUsed: shell, results: results, generatedAt: DateTime.now());
  }
}
