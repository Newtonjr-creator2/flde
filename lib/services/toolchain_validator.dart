import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/process_result.dart';
import '../models/toolchain_info.dart';
import '../core/runtime/process_executor.dart';

class ToolchainValidationResult {
  final ToolchainKind kind;
  final bool valid;
  final String? version;
  final String message;
  final ProcessResultModel? process;

  const ToolchainValidationResult({
    required this.kind,
    required this.valid,
    required this.version,
    required this.message,
    this.process,
  });
}

class ToolchainValidator {
  static Future<ToolchainValidationResult> validate(ToolchainInfo info) async {
    switch (info.kind) {
      case ToolchainKind.dart:
        return _runVersion(info, 'dart', ['--version']);
      case ToolchainKind.flutter:
        return _runVersion(info, 'flutter', ['--version']);
      case ToolchainKind.git:
        return _runVersion(info, 'git', ['--version']);
      case ToolchainKind.java:
        return _runVersion(info, 'java', ['-version']);
      case ToolchainKind.gradle:
        return _runVersion(info, 'gradle', ['--version']);
      case ToolchainKind.androidSdk:
        return _checkDirectory(info, [
          p.join(info.path, 'platform-tools'),
        ]);
      case ToolchainKind.platformTools:
        return _checkDirectory(info, [
          p.join(info.path, 'adb'),
        ]);
      case ToolchainKind.buildTools:
        return _checkDirectory(info, [info.path]);
    }
  }

  static Future<ToolchainValidationResult> _runVersion(
    ToolchainInfo info,
    String executable,
    List<String> args,
  ) async {
    try {
      final result = await ProcessExecutor.run(executable, args);
      final combined = [
        result.stdout.trim(),
        result.stderr.trim(),
      ].where((e) => e.isNotEmpty).join('\n');
      return ToolchainValidationResult(
        kind: info.kind,
        valid: result.succeeded,
        version: result.succeeded ? combined.split('\n').first : null,
        message: result.succeeded
            ? 'Validated by executing $executable.'
            : 'Execution failed with exit code ${result.exitCode}: ${combined.isEmpty ? 'no output' : combined}',
        process: result,
      );
    } catch (e) {
      return ToolchainValidationResult(
        kind: info.kind,
        valid: false,
        version: null,
        message: 'Could not execute $executable: $e',
      );
    }
  }

  static Future<ToolchainValidationResult> _checkDirectory(
    ToolchainInfo info,
    List<String> requiredPaths,
  ) async {
    for (final path in requiredPaths) {
      if (!await FileSystemEntity.isDirectory(path) &&
          !await FileSystemEntity.isFile(path)) {
        return ToolchainValidationResult(
          kind: info.kind,
          valid: false,
          version: null,
          message: 'Required path is missing: $path',
        );
      }
    }
    return ToolchainValidationResult(
      kind: info.kind,
      valid: true,
      version: info.version,
      message: 'Required files/directories exist.',
    );
  }
}
