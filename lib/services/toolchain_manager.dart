import 'package:path/path.dart' as p;

import '../core/runtime/environment_manager.dart';
import '../core/storage/storage_service.dart';
import '../models/toolchain_info.dart';
import '../models/toolchain_manifest.dart';
import 'toolchain_downloader.dart';
import 'toolchain_validator.dart';

/// Single source of truth for "what toolchains does FLDE know about, and
/// what's their real, verified state right now." Screens should read
/// through this rather than calling ProcessExecutor/EnvironmentManager
/// directly, so there's exactly one place that owns toolchain lifecycle
/// (per Phase 2 spec section 22 — no competing managers).
class ToolchainManager {
  final StorageService storage;
  final EnvironmentManager environment;
  final ToolchainValidator validator;
  final ToolchainDownloader downloader;
  final ToolchainManifestLoader manifestLoader;

  ToolchainManager._({
    required this.storage,
    required this.environment,
    required this.validator,
    required this.downloader,
    required this.manifestLoader,
  });

  static Future<ToolchainManager> create() async {
    final storage = await StorageService.instance();
    final environment = EnvironmentManager(storage);
    final validator = ToolchainValidator(environment);
    final downloader = ToolchainDownloader(storage);
    final manifestLoader = ToolchainManifestLoader(
      p.join(storage.root.path, 'toolchains', 'manifest.json'),
    );
    await manifestLoader.ensureDefaultManifestExists();
    return ToolchainManager._(
      storage: storage,
      environment: environment,
      validator: validator,
      downloader: downloader,
      manifestLoader: manifestLoader,
    );
  }

  /// Real, freshly-checked state of every known toolchain kind — always
  /// re-validates rather than returning a cached guess, since install
  /// state can change outside FLDE (e.g. user installs Flutter in Termux).
  Future<Map<ToolchainKind, ToolchainInfo>> currentState() {
    return validator.validateAll();
  }

  Future<List<ToolchainManifestEntry>> availableManifestEntries() {
    return manifestLoader.load();
  }

  /// Installs a toolchain from a manifest entry. If the entry has no real
  /// download source configured, this fails immediately and honestly
  /// rather than pretending to install anything — see
  /// ToolchainDownloader.installFromManifest and the manifest doc comment.
  Stream<DownloadProgress> install(ToolchainManifestEntry entry) {
    final folderName = _folderNameFor(entry.kind);
    return downloader.installFromManifest(entry, folderName);
  }

  Future<ToolchainInfo> revalidate(ToolchainKind kind, String displayName) {
    return validator.validate(kind, displayName);
  }

  String _folderNameFor(ToolchainKind kind) {
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
}
