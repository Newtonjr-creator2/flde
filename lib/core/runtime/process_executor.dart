import 'dart:async';
import 'dart:io';
import '../../models/process_result.dart';
import 'environment_manager.dart';

class ProcessSession {
  final Stream<ProcessLine> output;
  final Future<int> exitCode;
  final Future<void> Function() stop;

  ProcessSession({
    required this.output,
    required this.exitCode,
    required this.stop,
  });
}

class ProcessExecutor {
  static Future<ProcessResultModel> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration timeout = const Duration(minutes: 10),
    bool allowHostFallback = false,
  }) async {
    final started = DateTime.now();
    final env = environment ?? await EnvironmentManager.buildEnvironment();
    final resolved = await EnvironmentManager.resolve(executable);
    if (resolved == null && !allowHostFallback) {
      throw ProcessException(executable, arguments, 'Executable not found in FLDE environment.', -1);
    }

    final result = await Process.run(
      resolved ?? executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: env,
      runInShell: false,
    ).timeout(timeout);

    return ProcessResultModel(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
      duration: DateTime.now().difference(started),
    );
  }

  static Future<ProcessSession> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final env = environment ?? await EnvironmentManager.buildEnvironment();
    final resolved = await EnvironmentManager.resolve(executable);
    if (resolved == null) {
      throw ProcessException(executable, arguments, 'Executable not found in FLDE environment.', -1);
    }
    final process = await Process.start(
      resolved,
      arguments,
      workingDirectory: workingDirectory,
      environment: env,
      runInShell: false,
    );

    final controller = StreamController<ProcessLine>();
    var completedStreams = 0;
    Future<void> pipe(Stream<List<int>> input, bool error) async {
      try {
        await for (final chunk in input.transform(SystemEncoding().decoder)) {
          controller.add(ProcessLine(chunk, isError: error));
        }
      } finally {
        completedStreams++;
        if (completedStreams == 2 && !controller.isClosed) {
          await controller.close();
        }
      }
    }

    unawaited(pipe(process.stdout, false));
    unawaited(pipe(process.stderr, true));

    return ProcessSession(
      output: controller.stream,
      exitCode: process.exitCode,
      stop: () async {
        process.kill(ProcessSignal.sigterm);
      },
    );
  }
}
