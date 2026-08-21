import 'dart:io';
import 'package:path/path.dart' as p;

import '../storage/storage_service.dart';
import '../../models/toolchain_info.dart';

/// Resolves where an executable actually lives before anything runs it —
/// preferring an FLDE-managed install, falling back to whatever's already
/// on the device's system PATH (e.g. a Termux-installed Flutter). Never
/// assumes a binary exists; every resolution here does a real filesystem
/// check.
class EnvironmentManager {
  final StorageService storage;

  EnvironmentManager(this.storage);

  static const Map<ToolchainKind, String> _binSubpath = {
    ToolchainKind.dart: 'bin/dart',
    ToolchainKind.flutter: 'bin/flutter',
    ToolchainKind.java: 'bin/java',
    ToolchainKind.git: 'bin/git',
    ToolchainKind.gradle: 'bin/gradle',
  };

  static const Map<ToolchainKind, String> _systemCommand = {
    ToolchainKind.dart: 'dart',
    ToolchainKind.flutter: 'flutter',
    ToolchainKind.java: 'java',
    ToolchainKind.git: 'git',
    ToolchainKind.gradle: 'gradle',
  };

  /// Looks for a real installed binary under FLDE's own storage first (any
  /// version subdirectory containing the expected bin/ path), then falls
  /// back to resolving the command name against the system PATH via `which`.
  /// Returns null — not a guess — when nothing is actually found.
  Future<ResolvedExecutable?> resolve(ToolchainKind kind) async {
    final managedDir = storage.toolchainDir(_toolchainFolderName(kind));
    if (await managedDir.exists()) {
      final versions = await managedDir.list().where((e) => e is Directory).toList();
      // Prefer the most recently modified version directory if more than one
      // is installed.
      versions.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final versionDir in versions) {
        final relBin = _binSubpath[kind];
        if (relBin == null) continue;
        final candidate = File(p.join(versionDir.path, relBin));
        if (await candidate.exists()) {
          return ResolvedExecutable(
            path: candidate.path,
            origin: ToolchainOrigin.flde,
            installRoot: versionDir.path,
          );
        }
      }
    }

    final systemCommand = _systemCommand[kind];
    if (systemCommand != null) {
      final systemPath = await _which(systemCommand);
      if (systemPath != null) {
        return ResolvedExecutable(path: systemPath, origin: ToolchainOrigin.system, installRoot: null);
      }
    }

    return null;
  }

  Future<String?> _which(String command) async {
    try {
      final whichCmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(whichCmd, [command]);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first.trim();
        return path.isEmpty ? null : path;
      }
    } catch (_) {
      // `which`/`where` itself missing — treat as "not found", not an error
    }
    return null;
  }

  String _toolchainFolderName(ToolchainKind kind) {
    switch (kind) {
      case ToolchainKind.dart:
        return 'dart';
      case ToolchainKind.flutter:
        return 'flutter';
      case ToolchainKind.java:
        return 'java';
      case ToolchainKind.gradle:
        return 'gradle';
      case ToolchainKind.androidSdk:
        return 'android-sdk';
      case ToolchainKind.git:
        return 'git';
    }
  }

  /// Builds a real environment map for spawning processes: system
  /// environment plus a PATH that puts every resolved FLDE-managed
  /// toolchain's bin/ directory first, plus pub-cache/gradle-cache vars
  /// pointed at FLDE's own storage so tools don't fall back to
  /// unpredictable device-default locations.
  ///
  /// Per Phase 2B spec section 8: only ever sets a tool-specific path
  /// (ANDROID_HOME, JAVA_HOME, ...) when that toolchain is actually
  /// resolved — never injects a path for something that doesn't exist.
  Future<Map<String, String>> buildEnvironment() async {
    final env = Map<String, String>.from(Platform.environment);
    final existingPath = env['PATH'] ?? '';
    final fldeBinDirs = <String>[];

    for (final kind in _binSubpath.keys) {
      final resolved = await resolve(kind);
      if (resolved != null && resolved.origin == ToolchainOrigin.flde) {
        fldeBinDirs.add(p.dirname(resolved.path));
      }
    }

    env['PATH'] = [storage.runtimeBinDir.path, ...fldeBinDirs, existingPath]
        .where((s) => s.isNotEmpty)
        .join(':');
    env['HOME'] = storage.runtimeHomeDir.path;
    env['TMPDIR'] = storage.runtimeTmpDir.path;
    env['LANG'] = env['LANG'] ?? 'en_US.UTF-8';
    env['TERM'] = env['TERM'] ?? 'xterm-256color';
    env['FLDE_HOME'] = storage.root.path;
    env['FLDE_RUNTIME'] = storage.runtimeDir.path;
    env['PUB_CACHE'] = storage.pubCacheDir.path;
    env['GRADLE_USER_HOME'] = storage.gradleCacheDir.path;

    final java = await resolve(ToolchainKind.java);
    if (java != null && java.origin == ToolchainOrigin.flde && java.installRoot != null) {
      env['JAVA_HOME'] = java.installRoot!;
    }

    final androidSdkDir = storage.toolchainDir('android-sdk');
    bool androidSdkHasContent = false;
    if (await androidSdkDir.exists()) {
      try {
        androidSdkHasContent = await androidSdkDir.list().isEmpty.then((empty) => !empty);
      } catch (_) {
        androidSdkHasContent = false;
      }
    }
    if (androidSdkHasContent) {
      env['ANDROID_HOME'] = androidSdkDir.path;
      env['ANDROID_SDK_ROOT'] = androidSdkDir.path;
    }

    return env;
  }

  /// Sets FLDE_PROJECT for a specific execution context (a project run,
  /// build, or terminal session cd'd into a project). Kept separate from
  /// [buildEnvironment] because "current project" is a per-session
  /// concept, not a global one.
  Future<Map<String, String>> buildEnvironmentForProject(String projectDirectory) async {
    final env = await buildEnvironment();
    env['FLDE_PROJECT'] = projectDirectory;
    return env;
  }
}

class ResolvedExecutable {
  final String path;
  final ToolchainOrigin origin;
  final String? installRoot;

  const ResolvedExecutable({required this.path, required this.origin, this.installRoot});
}
