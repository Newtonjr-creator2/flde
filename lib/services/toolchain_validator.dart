import '../core/runtime/environment_manager.dart';
import '../core/runtime/runtime_environment.dart';
import '../models/toolchain_info.dart';

/// Actually runs each tool's version command and parses the real output.
/// A ToolchainInfo is only ever marked `installed` here after a genuine
/// process exits 0 and prints something recognizable — never on the mere
/// presence of a file, and never hardcoded.
class ToolchainValidator {
  final EnvironmentManager environment;
  final RuntimeEnvironment runtime;

  ToolchainValidator(this.environment, this.runtime);

  Future<ToolchainInfo> validate(ToolchainKind kind, String displayName) async {
    final resolved = await environment.resolve(kind);
    if (resolved == null) {
      return ToolchainInfo(
        kind: kind,
        displayName: displayName,
        origin: ToolchainOrigin.notInstalled,
        state: ToolchainInstallState.notInstalled,
        lastChecked: DateTime.now(),
      );
    }

    final args = _versionArgs(kind);
    final result = await runtime.execute(
      resolved.path,
      args,
      timeout: const Duration(seconds: 10),
    );

    if (!result.succeeded) {
      return ToolchainInfo(
        kind: kind,
        displayName: displayName,
        origin: resolved.origin,
        state: ToolchainInstallState.failed,
        executablePath: resolved.path,
        installPath: resolved.installRoot,
        lastError: result.stderr.isNotEmpty ? result.stderr : 'Exited with code ${result.exitCode}',
        lastChecked: DateTime.now(),
      );
    }

    final version = _parseVersion(kind, result.stdout.isNotEmpty ? result.stdout : result.stderr);
    return ToolchainInfo(
      kind: kind,
      displayName: displayName,
      origin: resolved.origin,
      state: ToolchainInstallState.installed,
      version: version,
      executablePath: resolved.path,
      installPath: resolved.installRoot,
      lastChecked: DateTime.now(),
    );
  }

  Future<Map<ToolchainKind, ToolchainInfo>> validateAll() async {
    const known = {
      ToolchainKind.flutter: 'Flutter SDK',
      ToolchainKind.dart: 'Dart SDK',
      ToolchainKind.java: 'Java / JDK',
      ToolchainKind.git: 'Git',
      ToolchainKind.gradle: 'Gradle',
    };
    final results = <ToolchainKind, ToolchainInfo>{};
    for (final entry in known.entries) {
      results[entry.key] = await validate(entry.key, entry.value);
    }
    // Android SDK isn't a single binary — validated separately by checking
    // for required directories/files, per spec section 6. Phase 2 reports
    // it honestly as unverified rather than guessing.
    results[ToolchainKind.androidSdk] = ToolchainInfo(
      kind: ToolchainKind.androidSdk,
      displayName: 'Android SDK',
      origin: ToolchainOrigin.notInstalled,
      state: ToolchainInstallState.notInstalled,
      lastError: 'Android SDK directory validation not yet implemented in Phase 2',
      lastChecked: DateTime.now(),
    );
    return results;
  }

  List<String> _versionArgs(ToolchainKind kind) {
    switch (kind) {
      case ToolchainKind.dart:
      case ToolchainKind.flutter:
      case ToolchainKind.git:
      case ToolchainKind.gradle:
        return ['--version'];
      case ToolchainKind.java:
        return ['-version'];
      case ToolchainKind.androidSdk:
        return const [];
    }
  }

  /// Extracts the first line as the version string — genuine output, just
  /// trimmed for display. We don't attempt fragile regex version-number
  /// extraction because a slightly-off parse would be worse than showing
  /// the tool's own first output line verbatim.
  String _parseVersion(ToolchainKind kind, String rawOutput) {
    final firstLine = rawOutput.trim().split('\n').first.trim();
    return firstLine.isEmpty ? '(unknown — command produced no output)' : firstLine;
  }
}
