import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/runtime/environment_manager.dart';
import '../core/runtime/process_executor.dart';
import '../models/process_result.dart';

class ToolchainStatus {
  final bool flutterAvailable;
  final String? flutterVersion;
  final bool dartAvailable;
  final String? dartVersion;
  final bool gitAvailable;

  const ToolchainStatus({
    required this.flutterAvailable,
    required this.flutterVersion,
    required this.dartAvailable,
    required this.dartVersion,
    required this.gitAvailable,
  });
}

class ProjectService {
  static Future<ToolchainStatus> detectToolchain() async {
    String? flutterVer;
    String? dartVer;
    var gitOk = false;

    try {
      final r = await ProcessExecutor.run('flutter', ['--version']);
      if (r.succeeded) flutterVer = _firstLine(r.stdout, r.stderr);
    } catch (_) {}

    try {
      final r = await ProcessExecutor.run('dart', ['--version']);
      if (r.succeeded) dartVer = _firstLine(r.stderr, r.stdout);
    } catch (_) {}

    try {
      final r = await ProcessExecutor.run('git', ['--version']);
      gitOk = r.succeeded;
    } catch (_) {}

    return ToolchainStatus(
      flutterAvailable: flutterVer != null,
      flutterVersion: flutterVer,
      dartAvailable: dartVer != null,
      dartVersion: dartVer,
      gitAvailable: gitOk,
    );
  }

  static String? _firstLine(String a, String b) {
    final text = [a, b].where((x) => x.trim().isNotEmpty).join('\n').trim();
    if (text.isEmpty) return null;
    return text.split(RegExp(r'\r?\n')).first.trim();
  }

  static Stream<String> createFlutterProject({
    required String parentDir,
    required String projectName,
    required String orgId,
  }) async* {
    final resolved = await EnvironmentManager.resolve('flutter');
    if (resolved == null) {
      yield 'ERROR: no FLDE-managed flutter executable was found.';
      yield 'Install and validate a compatible Flutter runtime first.';
      return;
    }

    final env = await EnvironmentManager.buildEnvironment();
    final process = await Process.start(
      resolved,
      [
        'create',
        '--org',
        orgId,
        '--project-name',
        projectName,
        p.join(parentDir, projectName),
      ],
      workingDirectory: parentDir,
      environment: env,
      runInShell: false,
    );

    final stdoutFuture = process.stdout
        .transform(SystemEncoding().decoder)
        .transform(const LineSplitter())
        .toList();
    final stderrFuture = process.stderr
        .transform(SystemEncoding().decoder)
        .transform(const LineSplitter())
        .toList();

    final results = await Future.wait([stdoutFuture, stderrFuture]);
    for (final line in results[0] as List<String>) {
      yield line;
    }
    for (final line in results[1] as List<String>) {
      yield 'stderr: $line';
    }

    final code = await process.exitCode;
    yield code == 0
        ? 'Project created successfully.'
        : 'flutter create exited with code $code';
  }

  static Future<void> createDartProjectSkeleton({
    required String parentDir,
    required String projectName,
  }) async {
    final root = Directory(p.join(parentDir, projectName));
    await Directory(p.join(root.path, 'bin')).create(recursive: true);
    await Directory(p.join(root.path, 'lib')).create(recursive: true);
    await Directory(p.join(root.path, 'test')).create(recursive: true);
    await File(p.join(root.path, 'pubspec.yaml')).writeAsString(
      'name: $projectName\n'
      'description: A Dart project created in FLDE.\n'
      'version: 0.0.1\n'
      'environment:\n'
      "  sdk: '>=3.3.0 <4.0.0'\n",
    );
    await File(p.join(root.path, 'bin', '$projectName.dart')).writeAsString(
      "void main(List<String> args) {\n"
      "  print('Hello from $projectName');\n"
      "}\n",
    );
    await File(p.join(root.path, '.gitignore')).writeAsString(
      '.dart_tool/\nbuild/\n.packages\n',
    );
  }

  static Future<ProcessResultModel> buildApk(String projectPath) {
    return ProcessExecutor.run(
      'flutter',
      ['build', 'apk'],
      workingDirectory: projectPath,
      timeout: const Duration(minutes: 30),
    );
  }
}
