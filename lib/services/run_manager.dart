import '../core/runtime/process_executor.dart';

class RunConfiguration {
  final String projectPath;
  final bool flutter;
  final List<String> arguments;

  const RunConfiguration({
    required this.projectPath,
    required this.flutter,
    this.arguments = const [],
  });
}

class RunManager {
  ProcessSession? _session;

  Future<ProcessSession> run(RunConfiguration config) async {
    if (_session != null) {
      throw StateError('A project process is already running.');
    }
    _session = await ProcessExecutor.start(
      config.flutter ? 'flutter' : 'dart',
      config.flutter ? ['run', ...config.arguments] : config.arguments,
      workingDirectory: config.projectPath,
    );
    return _session!;
  }

  Future<void> stop() async {
    await _session?.stop();
    _session = null;
  }
}
