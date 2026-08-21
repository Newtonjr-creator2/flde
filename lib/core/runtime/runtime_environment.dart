import '../../models/process_result.dart';
import 'process_executor.dart';

enum RuntimeAvailability { available, limited, unavailable, unknown }

/// A single line of live output from a runtime-executed process.
typedef RuntimeOutputLine = ProcessOutputLine;

/// Abstraction the rest of FLDE (terminal, toolchain validation, project
/// execution) should depend on instead of calling `dart:io` Process
/// directly. Phase 2B ships exactly one implementation —
/// [NativeRuntimeEnvironment], which executes binaries directly via the
/// Android app sandbox's own process-creation APIs (no PRoot, no VM, no
/// bundled userspace). A `LinuxUserspaceRuntime` implementing this same
/// interface is the documented future path IF the native experiment shows
/// direct execution is insufficient (see ARCHITECTURE.md) — it does not
/// exist yet and nothing in FLDE should assume it does.
abstract class RuntimeEnvironment {
  /// Human-readable name of this runtime strategy, for diagnostics/logs.
  String get name;

  /// Prepares the runtime for use (creates directories, etc). Must be
  /// idempotent and must not claim success without actually verifying
  /// the runtime is usable — see [isAvailable].
  Future<void> prepare();

  /// Real availability check — actually attempts something, never a
  /// hardcoded true/false.
  Future<RuntimeAvailability> isAvailable();

  /// Runs a command to completion through this runtime.
  Future<ExecResult> execute(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  });

  /// Starts a long-running/interactive process through this runtime.
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });

  /// Resolves the real path to a usable shell within this runtime, or
  /// null if none is available. Never hardcodes "/bin/sh" — that path
  /// may not exist in the expected location, or at all, depending on the
  /// device.
  Future<String?> resolveShell();

  Future<void> destroy();
}
