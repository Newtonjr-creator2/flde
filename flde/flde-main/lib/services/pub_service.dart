import '../core/runtime/environment_manager.dart';
import '../core/runtime/process_executor.dart';
import '../models/process_result.dart';
import '../models/toolchain_info.dart';

/// Foundation for pub/package management (Phase 2 spec section 12). Real
/// operations (`pub get`, `pub add`) run the actual Flutter/Dart binary
/// against FLDE's environment. Package SEARCH against pub.dev is
/// deliberately NOT implemented here — faking search results was
/// explicitly disallowed, and a real implementation needs a defined API
/// contract that's out of scope for the runtime-foundation phase. Calling
/// [searchPackages] throws UnimplementedError on purpose so callers can't
/// mistake a stub for a working feature.
class PubService {
  final EnvironmentManager environment;

  PubService(this.environment);

  Future<ExecResult> pubGet(String projectDirectory) => _runPubCommand(projectDirectory, ['pub', 'get']);

  Future<ExecResult> pubAdd(String projectDirectory, String package) =>
      _runPubCommand(projectDirectory, ['pub', 'add', package]);

  Future<ExecResult> pubUpgrade(String projectDirectory) =>
      _runPubCommand(projectDirectory, ['pub', 'upgrade']);

  Future<ExecResult> pubRemove(String projectDirectory, String package) =>
      _runPubCommand(projectDirectory, ['pub', 'remove', package]);

  Future<List<PubPackageEntry>> searchPackages(String query) {
    throw UnimplementedError(
      'Package search against pub.dev is not implemented in Phase 2. '
      'This is intentional — see PubService doc comment.',
    );
  }

  Future<ExecResult> _runPubCommand(String projectDirectory, List<String> args) async {
    final resolved = await environment.resolve(ToolchainKind.flutter);
    if (resolved == null) {
      final dartResolved = await environment.resolve(ToolchainKind.dart);
      if (dartResolved == null) {
        return ExecResult(
          command: 'flutter',
          arguments: args,
          exitCode: -1,
          stdout: '',
          stderr: 'Neither Flutter nor Dart is installed/verified — cannot run "$args".',
          duration: Duration.zero,
        );
      }
      final env = await environment.buildEnvironment();
      return ProcessExecutor.run(dartResolved.path, args, workingDirectory: projectDirectory, environment: env);
    }
    final env = await environment.buildEnvironment();
    return ProcessExecutor.run(resolved.path, args, workingDirectory: projectDirectory, environment: env);
  }
}

/// Placeholder shape for a future real pub.dev search result — not
/// currently produced anywhere.
class PubPackageEntry {
  final String name;
  final String latestVersion;
  final String description;

  const PubPackageEntry({required this.name, required this.latestVersion, required this.description});
}
