import 'dart:io';
import 'package:path/path.dart' as p;

/// Result of a real capability probe — never guessed, never hardcoded.
class ToolchainStatus {
  final bool flutterAvailable;
  final String? flutterVersion;
  final bool dartAvailable;
  final String? dartVersion;
  final bool gitAvailable;

  ToolchainStatus({
    required this.flutterAvailable,
    required this.flutterVersion,
    required this.dartAvailable,
    required this.dartVersion,
    required this.gitAvailable,
  });
}

class ProjectService {
  /// Actually invokes the binaries on PATH. If `flutter`/`dart`/`git` are
  /// not installed on this device, this correctly reports them missing —
  /// it never fabricates a version string (spec section 90 — no mock).
  static Future<ToolchainStatus> detectToolchain() async {
    String? flutterVer;
    String? dartVer;
    bool gitOk = false;

    try {
      final r = await Process.run('flutter', ['--version']).timeout(const Duration(seconds: 8));
      if (r.exitCode == 0) flutterVer = (r.stdout as String).split('\n').first.trim();
    } catch (_) {
      flutterVer = null;
    }

    try {
      final r = await Process.run('dart', ['--version']).timeout(const Duration(seconds: 8));
      if (r.exitCode == 0) dartVer = (r.stderr as String).trim().isNotEmpty
          ? (r.stderr as String).trim()
          : (r.stdout as String).trim();
    } catch (_) {
      dartVer = null;
    }

    try {
      final r = await Process.run('git', ['--version']).timeout(const Duration(seconds: 5));
      gitOk = r.exitCode == 0;
    } catch (_) {
      gitOk = false;
    }

    return ToolchainStatus(
      flutterAvailable: flutterVer != null,
      flutterVersion: flutterVer,
      dartAvailable: dartVer != null,
      dartVersion: dartVer,
      gitAvailable: gitOk,
    );
  }

  /// Creates a project. If the real `flutter` binary is on PATH, this runs
  /// the genuine `flutter create` command and streams its output. If it
  /// isn't, we do NOT fake a Flutter project — we tell the caller so the UI
  /// can show "Flutter not available on this device" (spec section 61).
  static Stream<String> createFlutterProject({
    required String parentDir,
    required String projectName,
    required String orgId,
  }) async* {
    final status = await detectToolchain();
    if (!status.flutterAvailable) {
      yield 'ERROR: flutter binary not found on PATH.';
      yield 'Install the Flutter SDK (Toolchains screen) or run this build step via GitHub Actions, then retry.';
      return;
    }

    final process = await Process.start(
      'flutter',
      ['create', '--org', orgId, '--project-name', projectName, p.join(parentDir, projectName)],
      runInShell: true,
    );
    await for (final line in process.stdout.transform(const _LineSplitter())) {
      yield line;
    }
    await for (final line in process.stderr.transform(const _LineSplitter())) {
      yield 'stderr: $line';
    }
    final code = await process.exitCode;
    yield code == 0 ? 'Project created successfully.' : 'flutter create exited with code $code';
  }

  /// Creates a plain Dart-only project skeleton by hand when only the Dart
  /// SDK (not full Flutter) is available — real files written to disk,
  /// clearly a Dart project, never mislabeled as Flutter.
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
      'description: A Dart project created in RealBuzzingIdentifier.\n'
      'version: 0.0.1\n'
      'environment:\n'
      "  sdk: '>=3.0.0 <4.0.0'\n",
    );
    await File(p.join(root.path, 'bin', '$projectName.dart')).writeAsString(
      "void main(List<String> args) {\n  print('Hello from $projectName');\n}\n",
    );
    await File(p.join(root.path, '.gitignore')).writeAsString(
      '.dart_tool/\nbuild/\n.packages\npubspec.lock\n',
    );
  }
}

/// Minimal line-splitting transformer so we can stream process output
/// line-by-line into the UI/terminal panel as it's actually produced.
class _LineSplitter extends StreamTransformerBase<List<int>, String> {
  const _LineSplitter();

  @override
  Stream<String> bind(Stream<List<int>> stream) {
    return stream
        .transform(SystemEncoding().decoder)
        .transform(const LineSplitter());
  }
}
