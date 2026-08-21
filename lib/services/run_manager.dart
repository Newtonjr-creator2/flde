import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../core/runtime/environment_manager.dart';
import '../core/runtime/process_executor.dart';
import '../models/toolchain_info.dart';

enum RunState { idle, starting, running, stopped, failed }

class RunConfiguration {
  final String projectDirectory;
  final String target; // e.g. "chrome", a device id — UI decides what's offered
  final String mode; // debug | profile | release

  const RunConfiguration({required this.projectDirectory, required this.target, this.mode = 'debug'});
}

/// A live `flutter run` (or similar) process session. Hot reload/restart
/// send real signals to the real process's stdin — `flutter run` listens
/// for 'r'/'R' on stdin exactly like it does in a normal terminal. This
/// class does not simulate reload; it forwards the real keystroke.
class ProcessSession {
  final RunningProcess process;
  RunState state = RunState.running;
  final List<ProcessOutputLine> log = [];
  final _controller = StreamController<ProcessOutputLine>.broadcast();

  ProcessSession(this.process) {
    process.output.listen((line) {
      log.add(line);
      _controller.add(line);
    });
  }

  Stream<ProcessOutputLine> get onOutput => _controller.stream;

  void hotReload() {
    if (state == RunState.running) process.writeToStdin('r');
  }

  void hotRestart() {
    if (state == RunState.running) process.writeToStdin('R');
  }

  Future<void> stop() async {
    state = RunState.stopped;
    await process.kill();
  }
}

/// Foundation for launching/stopping a project run, per Phase 2 spec
/// section 14. IMPORTANT / UNVERIFIED: whether `flutter run` can actually
/// attach to a usable target from inside FLDE's own Android app sandbox
/// (no attached device, no desktop target) has not been experimentally
/// confirmed. This class provides real process orchestration; it does not
/// claim the run will succeed on every target — a failed real process is
/// reported as failed, never hidden.
class RunManager {
  final EnvironmentManager environment;

  RunManager(this.environment);

  Future<ProcessSession?> start(RunConfiguration config, {void Function(String)? onError}) async {
    final resolved = await environment.resolve(ToolchainKind.flutter);
    if (resolved == null) {
      onError?.call('Flutter is not installed/verified — cannot run this project.');
      return null;
    }
    final env = await environment.buildEnvironment();
    try {
      final process = await ProcessExecutor.start(
        resolved.path,
        ['run', '-d', config.target, '--${config.mode}'],
        workingDirectory: config.projectDirectory,
        environment: env,
      );
      return ProcessSession(process);
    } catch (e) {
      onError?.call('Failed to start flutter run: $e');
      return null;
    }
  }
}

class ApkBuildResult {
  final bool succeeded;
  final String? apkPath;
  final String stdout;
  final String stderr;
  final int exitCode;

  const ApkBuildResult({
    required this.succeeded,
    this.apkPath,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });
}

/// Foundation for `flutter build apk`, per Phase 2 spec section 15. Success
/// is reported only when the actual output file exists on disk afterward
/// — never inferred purely from exit code 0, since that alone doesn't
/// guarantee the artifact FLDE would point the user to is really there.
class ApkBuildService {
  final EnvironmentManager environment;

  ApkBuildService(this.environment);

  Future<ApkBuildResult> buildDebugApk(String projectDirectory) async {
    final resolved = await environment.resolve(ToolchainKind.flutter);
    if (resolved == null) {
      return const ApkBuildResult(
        succeeded: false,
        stdout: '',
        stderr: 'Flutter is not installed/verified — cannot build an APK.',
        exitCode: -1,
      );
    }
    final env = await environment.buildEnvironment();
    final result = await ProcessExecutor.run(
      resolved.path,
      ['build', 'apk', '--debug'],
      workingDirectory: projectDirectory,
      environment: env,
      timeout: const Duration(minutes: 20),
    );

    final expectedApk = File(p.join(projectDirectory, 'build', 'app', 'outputs', 'flutter-apk', 'app-debug.apk'));
    final apkExists = await expectedApk.exists();

    return ApkBuildResult(
      succeeded: result.succeeded && apkExists,
      apkPath: apkExists ? expectedApk.path : null,
      stdout: result.stdout,
      stderr: apkExists || result.succeeded
          ? result.stderr
          : '${result.stderr}\n(build reported success but expected output file was not found at ${expectedApk.path})',
      exitCode: result.exitCode,
    );
  }
}
