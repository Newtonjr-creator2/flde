import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/runtime/environment_manager.dart';
import '../core/storage/storage_service.dart';
import '../models/toolchain_info.dart';
import 'toolchain_validator.dart';

/// Result of a real capability probe — never guessed, never hardcoded.
/// Kept as the existing public shape so `home_screen.dart` and any other
/// Phase 1 caller keep working unchanged; internally this now delegates
/// to the shared EnvironmentManager/ToolchainValidator (Phase 2) instead
/// of running its own separate `Process.run('flutter', ...)` calls, so
/// there is exactly one place that resolves "where is flutter/dart/git."
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
  static EnvironmentManager? _environment;
  static ToolchainValidator? _validator;

  static Future<EnvironmentManager> _env() async {
    if (_environment != null) return _environment!;
    final storage = await StorageService.instance();
    _environment = EnvironmentManager(storage);
    return _environment!;
  }

  static Future<ToolchainValidator> _val() async {
    if (_validator != null) return _validator!;
    _validator = ToolchainValidator(await _env());
    return _validator!;
  }

  /// Real capability probe — delegates to ToolchainValidator, which
  /// resolves FLDE-managed installs first and falls back to whatever is
  /// on the device's system PATH. Never fabricates a version string.
  static Future<ToolchainStatus> detectToolchain() async {
    final validator = await _val();
    final flutter = await validator.validate(ToolchainKind.flutter, 'Flutter SDK');
    final dart = await validator.validate(ToolchainKind.dart, 'Dart SDK');
    final git = await validator.validate(ToolchainKind.git, 'Git');

    return ToolchainStatus(
      flutterAvailable: flutter.isReady,
      flutterVersion: flutter.version,
      dartAvailable: dart.isReady,
      dartVersion: dart.version,
      gitAvailable: git.isReady,
    );
  }

  /// Creates a Flutter project using the real, resolved Flutter binary
  /// (FLDE-managed install if present, otherwise system PATH). If Flutter
  /// isn't available anywhere, no fake project is created — the caller
  /// gets a clear error instead.
  static Stream<String> createFlutterProject({
    required String parentDir,
    required String projectName,
    required String orgId,
  }) async* {
    final environment = await _env();
    final resolved = await environment.resolve(ToolchainKind.flutter);

    if (resolved == null) {
      yield 'ERROR: Flutter is not installed or verified.';
      yield 'Install it from the Toolchains screen, or run this build step via GitHub Actions, then retry.';
      return;
    }

    final env = await environment.buildEnvironment();
    final process = await Process.start(
      resolved.path,
      ['create', '--org', orgId, '--project-name', projectName, p.join(parentDir, projectName)],
      environment: env,
      runInShell: true,
    );

    await for (final line in process.stdout.transform(utf8.decoder).transform(const LineSplitter())) {
      yield line;
    }
    await for (final line in process.stderr.transform(utf8.decoder).transform(const LineSplitter())) {
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
      'description: A Dart project created in FLDE.\n'
      'version: 0.0.1\n'
      'environment:\n'
      "  sdk: '>=3.0.0 <4.0.0'\n",
    );
    await File(p.join(root.path, 'bin', '$projectName.dart')).writeAsString(
      "void main(List<String> args) {\n  print('Hello from \$projectName');\n}\n",
    );
    await File(p.join(root.path, '.gitignore')).writeAsString(
      '.dart_tool/\nbuild/\n.packages\npubspec.lock\n',
    );
  }
}
