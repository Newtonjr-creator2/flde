import 'dart:convert';
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
  /// it never fabricates a version string.
  static Future<ToolchainStatus> detectToolchain() async {
    String? flutterVer;
    String? dartVer;
    bool gitOk = false;

    try {
      final r = await Process.run(
        'flutter',
        ['--version'],
      ).timeout(const Duration(seconds: 8));

      if (r.exitCode == 0) {
        final stdoutText = r.stdout.toString().trim();

        if (stdoutText.isNotEmpty) {
          flutterVer = stdoutText.split('\n').first.trim();
        }
      }
    } catch (_) {
      flutterVer = null;
    }

    try {
      final r = await Process.run(
        'dart',
        ['--version'],
      ).timeout(const Duration(seconds: 8));

      if (r.exitCode == 0) {
        final stderrText = r.stderr.toString().trim();
        final stdoutText = r.stdout.toString().trim();

        dartVer = stderrText.isNotEmpty ? stderrText : stdoutText;
      }
    } catch (_) {
      dartVer = null;
    }

    try {
      final r = await Process.run(
        'git',
        ['--version'],
      ).timeout(const Duration(seconds: 5));

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

  /// Creates a Flutter project using the real Flutter binary.
  ///
  /// If Flutter is not installed on the device, no fake project is created.
  /// The caller receives a clear error message instead.
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
      [
        'create',
        '--org',
        orgId,
        '--project-name',
        projectName,
        p.join(parentDir, projectName),
      ],
      runInShell: true,
    );

    // Read stdout line-by-line as it is produced.
    await for (final line in process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      yield line;
    }

    // Read stderr line-by-line as it is produced.
    await for (final line in process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      yield 'stderr: $line';
    }

    final code = await process.exitCode;

    if (code == 0) {
      yield 'Project created successfully.';
    } else {
      yield 'flutter create exited with code $code';
    }
  }

  /// Creates a plain Dart-only project skeleton by hand when only the Dart
  /// SDK (not full Flutter) is available.
  ///
  /// This creates real files on disk and clearly identifies the result as
  /// a Dart project rather than pretending it is a Flutter project.
  static Future<void> createDartProjectSkeleton({
    required String parentDir,
    required String projectName,
  }) async {
    final root = Directory(
      p.join(parentDir, projectName),
    );

    await Directory(
      p.join(root.path, 'bin'),
    ).create(recursive: true);

    await Directory(
      p.join(root.path, 'lib'),
    ).create(recursive: true);

    await Directory(
      p.join(root.path, 'test'),
    ).create(recursive: true);

    await File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsString(
      'name: $projectName\n'
      'description: A Dart project created in RealBuzzingIdentifier.\n'
      'version: 0.0.1\n'
      'environment:\n'
      "  sdk: '>=3.0.0 <4.0.0'\n",
    );

    await File(
      p.join(root.path, 'bin', '$projectName.dart'),
    ).writeAsString(
      "void main(List<String> args) {\n"
      "  print('Hello from $projectName');\n"
      "}\n",
    );

    await File(
      p.join(root.path, '.gitignore'),
    ).writeAsString(
      '.dart_tool/\n'
      'build/\n'
      '.packages\n'
      'pubspec.lock\n',
    );
  }
}
