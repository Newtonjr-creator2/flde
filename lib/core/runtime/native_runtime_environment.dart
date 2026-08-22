import 'dart:io';

import '../../models/process_result.dart';
import 'process_executor.dart';
import 'runtime_environment.dart';
import 'system_linker_launcher.dart';

/// Executes processes directly through the Android app sandbox's own
/// process-creation APIs (`dart:io` Process, which ultimately goes through
/// Android's `Runtime.exec`/`fork+exec`). This is the smallest viable
/// runtime per spec section 1 — no PRoot, no bundled userspace, no VM.
///
/// What this CAN do (verified by existing Phase 2A/2B diagnostics):
/// execute system binaries already present on the device (`uname`, `sh`,
/// `which`, `chmod`, `git` if installed via Termux, etc.) — these already
/// carry SELinux `execute` permission because they live under system
/// partitions, not app-private storage.
///
/// What is UNVERIFIED and exactly what [RuntimeDiagnosticsService] tests:
/// whether a file FLDE itself writes into its own app-private storage
/// (e.g. a downloaded Dart SDK binary) can be executed directly. Modern
/// Android (SELinux `app_data_file` context, enforced broadly since
/// Android 7+, formalized as W^X since Android 10) is widely documented
/// to deny direct exec of files an app wrote into its own private data
/// directory, regardless of chmod +x — this is not a Dart/Flutter
/// limitation, it's an OS-level policy. This class does not assume that
/// restriction applies to this device; it reports whatever the real test
/// shows.
class NativeRuntimeEnvironment implements RuntimeEnvironment {
  /// When supplied, ELF executables found inside this directory (including
  /// through PATH) are launched via Android's system linker rather than
  /// directly via execve. This is the Termux-style escape hatch for Android
  /// app-data executable restrictions.
  final Directory? managedRoot;
  late final SystemLinkerLauncher? _linker =
      managedRoot == null ? null : SystemLinkerLauncher(managedRoot!);

  NativeRuntimeEnvironment({this.managedRoot});

  @override
  String get name => managedRoot == null
      ? 'NativeRuntimeEnvironment (direct exec, no PRoot/VM)'
      : 'NativeRuntimeEnvironment (Android system-linker ELF runtime)';

  @override
  Future<void> prepare() async {
    // Nothing to provision — this runtime has no managed userspace of its
    // own, it's a thin pass-through to the OS. Directory creation for
    // FLDE's runtime/ layout is StorageService's job (see spec section 4).
  }

  @override
  Future<RuntimeAvailability> isAvailable() async {
    // A real, minimal check: can we execute ANYTHING at all? `echo` is
    // handled by whatever shell resolves, but simplest cross-device probe
    // is invoking `uname` directly (a real system binary on Android/Linux).
    final result = await ProcessExecutor.run('uname', const ['-a'], timeout: const Duration(seconds: 5));
    if (result.succeeded) return RuntimeAvailability.available;
    return RuntimeAvailability.limited;
  }

  @override
  Future<ExecResult> execute(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final managedPath = await _resolveManagedElf(executable, environment);
    if (managedPath != null) {
      return _linker!.run(
        managedPath,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        timeout: timeout,
      );
    }

    return ProcessExecutor.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: timeout,
    );
  }

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final managedPath = await _resolveManagedElf(executable, environment);
    if (managedPath != null) {
      return _linker!.start(
        managedPath,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    }

    return ProcessExecutor.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  Future<String?> _resolveManagedElf(
    String executable,
    Map<String, String>? environment,
  ) async {
    if (_linker == null) return null;

    final candidates = <String>[];
    if (executable.contains('/')) {
      candidates.add(executable);
    } else {
      final path = environment?['PATH'] ?? Platform.environment['PATH'] ?? '';
      for (final directory in path.split(':')) {
        if (directory.isNotEmpty) {
          candidates.add('$directory/$executable');
        }
      }
    }

    for (final candidate in candidates) {
      final file = File(candidate);
      if (await _linker!.canLaunch(file)) return candidate;
    }
    return null;
  }

  static const List<String> _shellCandidates = [
    '/system/bin/sh',
    '/bin/sh',
    '/system/bin/bash',
    '/bin/bash',
  ];

  @override
  Future<String?> resolveShell() async {
    for (final candidate in _shellCandidates) {
      if (await File(candidate).exists()) return candidate;
    }
    // Fall back to whatever `sh` resolves to on PATH, rather than assuming
    // a fixed location.
    try {
      final result = await Process.run('which', const ['sh']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {
      // `which` itself unavailable — genuinely no shell resolvable
    }
    return null;
  }

  @override
  Future<void> destroy() async {
    // No persistent resources to tear down for the native runtime.
  }
}
