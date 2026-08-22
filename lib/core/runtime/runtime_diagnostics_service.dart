import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../storage/storage_service.dart';
import 'native_runtime_environment.dart';
import 'process_executor.dart';
import 'system_linker_launcher.dart';
import 'runtime_environment.dart';

enum CheckStatus { verified, unverified, failed, unavailable }

class RuntimeCheck {
  final String label;
  final CheckStatus status;
  final String detail;

  const RuntimeCheck(this.label, this.status, this.detail);
}

class RuntimeDiagnosticsReport {
  final String? androidVersion;
  final String? kernelVersion;
  final String? architecture;
  final String? abi;
  final int? applicationUid;
  final String appPrivateDirectory;
  final String? path;
  final RuntimeAvailability nativeRuntimeAvailability;
  final String? resolvedShell;
  final List<RuntimeCheck> checks;
  final DateTime generatedAt;

  const RuntimeDiagnosticsReport({
    required this.androidVersion,
    required this.kernelVersion,
    required this.architecture,
    required this.abi,
    required this.applicationUid,
    required this.appPrivateDirectory,
    required this.path,
    required this.nativeRuntimeAvailability,
    required this.resolvedShell,
    required this.checks,
    required this.generatedAt,
  });
}

/// Runs the real "first experiment" from Phase 2B spec section 2: what can
/// FLDE actually execute, and specifically — can a file FLDE writes into
/// its own app-private storage be executed directly? Every field/check in
/// the returned report is produced by an actual filesystem/process
/// operation performed at call time. Nothing here is a hardcoded guess,
/// and the two execution checks are deliberately kept separate (direct
/// exec vs. interpreter-invoked) so a failure in one doesn't get
/// misreported as a failure in both.
class RuntimeDiagnosticsService {
  final StorageService storage;
  final NativeRuntimeEnvironment runtime;

  RuntimeDiagnosticsService(this.storage, this.runtime);

  Future<RuntimeDiagnosticsReport> run() async {
    final checks = <RuntimeCheck>[];

    final androidVersion = Platform.operatingSystemVersion;
    final kernelVersion = await _detectKernelVersion();
    final architecture = await _detectArchitecture();
    final abi = Platform.version; // Dart's own ABI/build string — real, not device ABI; see detail below
    final path = Platform.environment['PATH'];

    checks.add(RuntimeCheck(
      'App private directory writable',
      await _checkWritable() ? CheckStatus.verified : CheckStatus.failed,
      storage.root.path,
    ));

    final procCheck = await _checkProcAvailable();
    checks.add(procCheck);

    final nativeAvailability = await runtime.isAvailable();
    checks.add(RuntimeCheck(
      'Native process execution (system binaries)',
      nativeAvailability == RuntimeAvailability.available ? CheckStatus.verified : CheckStatus.failed,
      'Tested via `uname -a`. Result: $nativeAvailability',
    ));

    final shell = await runtime.resolveShell();
    checks.add(RuntimeCheck(
      'Shell resolution',
      shell != null ? CheckStatus.verified : CheckStatus.failed,
      shell ?? 'No shell found at known candidate paths or via `which sh`',
    ));

    // The two critical, previously-untested checks:
    final interpretedCheck = await _checkInterpretedExecution(shell);
    checks.add(interpretedCheck);

    final directExecCheck = await _checkDirectExecutionOfPrivateFile(shell);
    checks.add(directExecCheck);

    // This is the load-bearing proof for the new runtime architecture:
    // execute an ELF supplied by FLDE through Android's own system linker.
    // Unlike the old direct-exec experiment, this deliberately does not
    // chmod/exec the file itself.
    checks.add(await _checkSystemLinkerElfExecution());

    checks.add(await _checkStdoutStderrExitCode());

    return RuntimeDiagnosticsReport(
      androidVersion: androidVersion,
      kernelVersion: kernelVersion,
      architecture: architecture,
      abi: abi,
      applicationUid: null, // requires a platform channel — not implemented in Phase 2B, see ARCHITECTURE.md
      appPrivateDirectory: storage.root.path,
      path: path,
      nativeRuntimeAvailability: nativeAvailability,
      resolvedShell: shell,
      checks: checks,
      generatedAt: DateTime.now(),
    );
  }

  Future<String?> _detectKernelVersion() async {
    // Prefer /proc/version if readable (most direct source).
    final procVersion = File('/proc/version');
    if (await procVersion.exists()) {
      try {
        final content = await procVersion.readAsString();
        if (content.trim().isNotEmpty) return content.trim();
      } catch (_) {
        // permission denied or unreadable — fall through to uname -r
      }
    }
    final result = await ProcessExecutor.run('uname', const ['-r'], timeout: const Duration(seconds: 5));
    if (result.succeeded && result.stdout.trim().isNotEmpty) return result.stdout.trim();
    return null;
  }

  Future<String?> _detectArchitecture() async {
    final result = await ProcessExecutor.run('uname', const ['-m'], timeout: const Duration(seconds: 5));
    if (result.succeeded && result.stdout.trim().isNotEmpty) return result.stdout.trim();
    return null;
  }

  Future<bool> _checkWritable() async {
    try {
      final probe = File(p.join(storage.runtimeTmpDir.path, '.write_probe'));
      await probe.writeAsString('ok');
      final readBack = await probe.readAsString();
      await probe.delete();
      return readBack == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<RuntimeCheck> _checkProcAvailable() async {
    final targets = ['/proc/version', '/proc/cpuinfo', '/proc/self/status'];
    final available = <String>[];
    for (final t in targets) {
      if (await File(t).exists()) available.add(t);
    }
    if (available.length == targets.length) {
      return RuntimeCheck('/proc availability', CheckStatus.verified, 'All of $targets readable');
    } else if (available.isNotEmpty) {
      return RuntimeCheck(
        '/proc availability',
        CheckStatus.unverified,
        'Partially available: $available (missing: ${targets.where((t) => !available.contains(t)).toList()})',
      );
    }
    return const RuntimeCheck('/proc availability', CheckStatus.failed, 'None of the probed /proc paths were readable');
  }

  /// Control test: can we get a shell to READ and INTERPRET a script FLDE
  /// wrote into its own private storage? This does not require exec
  /// permission on the script file itself, only read permission — it
  /// should succeed even on devices that block direct execution.
  Future<RuntimeCheck> _checkInterpretedExecution(String? shell) async {
    if (shell == null) {
      return const RuntimeCheck(
        'Interpreted execution (shell reads private script)',
        CheckStatus.unavailable,
        'No shell resolved — cannot test',
      );
    }
    final script = File(p.join(storage.runtimeTmpDir.path, 'flde_interp_test.sh'));
    try {
      await script.writeAsString('echo FLDE_INTERPRETED_EXEC_OK\n');
      final result = await ProcessExecutor.run(shell, [script.path], timeout: const Duration(seconds: 5));
      await script.delete();
      final ok = result.succeeded && result.stdout.contains('FLDE_INTERPRETED_EXEC_OK');
      return RuntimeCheck(
        'Interpreted execution (shell reads private script)',
        ok ? CheckStatus.verified : CheckStatus.failed,
        ok ? 'Confirmed: `$shell <script>` runs a file FLDE wrote to its own storage' : 'exit ${result.exitCode}: ${result.stderr}',
      );
    } catch (e) {
      return RuntimeCheck('Interpreted execution (shell reads private script)', CheckStatus.failed, '$e');
    }
  }

  /// THE critical, previously-unverified test from spec section 2/11: can
  /// FLDE directly execute (not interpret) a file it wrote into its own
  /// app-private storage, after chmod +x? This is what determines whether
  /// a downloaded toolchain binary (e.g. Dart) can run at all without
  /// further runtime engineering (see ARCHITECTURE.md for what happens if
  /// this fails — it is a well-documented Android SELinux/W^X restriction
  /// on many devices, not a bug in this code).
  Future<RuntimeCheck> _checkDirectExecutionOfPrivateFile(String? shell) async {
    if (shell == null) {
      return const RuntimeCheck(
        'Direct execution of private file (chmod +x, then exec directly)',
        CheckStatus.unavailable,
        'No shell resolved — cannot construct a test script',
      );
    }
    final script = File(p.join(storage.runtimeTmpDir.path, 'flde_direct_exec_test.sh'));
    try {
      await script.writeAsString('#!$shell\necho FLDE_DIRECT_EXEC_OK\n');
      final chmodResult = await Process.run('chmod', ['755', script.path]);
      if (chmodResult.exitCode != 0) {
        await script.delete();
        return RuntimeCheck(
          'Direct execution of private file (chmod +x, then exec directly)',
          CheckStatus.failed,
          'chmod itself failed: ${chmodResult.stderr}',
        );
      }

      final result = await ProcessExecutor.run(script.path, const [], timeout: const Duration(seconds: 5));
      await script.delete();

      final ok = result.succeeded && result.stdout.contains('FLDE_DIRECT_EXEC_OK');
      return RuntimeCheck(
        'Direct execution of private file (chmod +x, then exec directly)',
        ok ? CheckStatus.verified : CheckStatus.failed,
        ok
            ? 'Confirmed: this device allows direct exec of files FLDE writes to its own storage.'
            : 'DENIED (exit ${result.exitCode}). This matches Android\'s documented SELinux app_data_file '
                'exec restriction on many devices — see ARCHITECTURE.md for the implication and next steps.\n'
                'stderr: ${result.stderr}',
      );
    } catch (e) {
      return RuntimeCheck(
        'Direct execution of private file (chmod +x, then exec directly)',
        CheckStatus.failed,
        'Process failed to even start: $e (this itself is evidence of an exec restriction, not a code bug)',
      );
    }
  }

  Future<RuntimeCheck> _checkSystemLinkerElfExecution() async {
    final launcher = SystemLinkerLauncher(storage.root);
    final linker = await launcher.resolveLinker();
    if (linker == null) {
      return const RuntimeCheck(
        'FLDE ELF via Android system linker',
        CheckStatus.unavailable,
        'No 64-bit Android dynamic linker was found.',
      );
    }

    final architecture = await _detectArchitecture();
    if (architecture != 'aarch64') {
      return RuntimeCheck(
        'FLDE ELF via Android system linker',
        CheckStatus.unavailable,
        'The bundled proof currently targets ARM64 (aarch64); detected ${architecture ?? 'unknown'}.',
      );
    }

    final probe = File(p.join(storage.runtimeBinDir.path, 'flde_runtime_probe'));
    try {
      final data = await rootBundle.load('assets/runtime/runtime_probe_arm64-v8a');
      await probe.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);

      if (!await launcher.canLaunch(probe)) {
        return const RuntimeCheck(
          'FLDE ELF via Android system linker',
          CheckStatus.failed,
          'The bundled runtime probe was not recognized as an ELF inside FLDE storage.',
        );
      }

      final result = await launcher.run(
        probe.path,
        const [],
        environment: Platform.environment,
        timeout: const Duration(seconds: 10),
      );

      final output = result.stdout.trim();
      final ok = result.succeeded && output.contains('FLDE_RUNTIME_PROBE_OK');
      return RuntimeCheck(
        'FLDE ELF via Android system linker',
        ok ? CheckStatus.verified : CheckStatus.failed,
        ok
            ? 'SUCCESS through $linker. FLDE-provided ELF executed; output: ${output.replaceAll('\n', ' | ')}'
            : 'Linker launch failed: exit=${result.exitCode}, stdout=${result.stdout.trim()}, stderr=${result.stderr.trim()}',
      );
    } on FlutterError catch (e) {
      return RuntimeCheck(
        'FLDE ELF via Android system linker',
        CheckStatus.unavailable,
        'Runtime probe asset is not bundled in this build. Run tooling/build_runtime_probe.sh before building: $e',
      );
    } catch (e) {
      return RuntimeCheck(
        'FLDE ELF via Android system linker',
        CheckStatus.failed,
        'Probe setup/launch failed: $e',
      );
    } finally {
      try {
        if (await probe.exists()) await probe.delete();
      } catch (_) {}
    }
  }

  Future<RuntimeCheck> _checkStdoutStderrExitCode() async {
    final result = await ProcessExecutor.run('uname', const ['-a'], timeout: const Duration(seconds: 5));
    final ok = result.succeeded && result.stdout.isNotEmpty;
    return RuntimeCheck(
      'stdout / exit code plumbing',
      ok ? CheckStatus.verified : CheckStatus.failed,
      'exit=${result.exitCode}, stdout length=${result.stdout.length}',
    );
  }
}
