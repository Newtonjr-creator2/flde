import 'dart:convert';
import 'dart:io';

import 'toolchain_info.dart';

/// Describes a downloadable toolchain release. This is a data contract,
/// not a claim that a matching download exists — `downloadUrl` is nullable
/// and, in Phase 2, deliberately unset for every entry. See
/// `assets/toolchains/manifest.json`: it ships as an empty list on
/// purpose. We are NOT inventing Flutter/Dart/JDK/Gradle/Android-SDK
/// distribution URLs — those get decided and added once this runtime
/// architecture is confirmed working end-to-end.
class ToolchainManifestEntry {
  final ToolchainKind kind;
  final String version;
  final String architecture; // e.g. "arm64-v8a"
  final String platform; // e.g. "android"
  final String? downloadUrl;
  final String? sha256;
  final int? sizeBytes;
  final String? archiveType; // e.g. "zip", "tar.gz" — explicit, never inferred from a guessed URL
  final List<ToolchainKind> dependencies;
  final String? minimumFldeVersion;
  final RuntimeRequirements? runtimeRequirements;

  const ToolchainManifestEntry({
    required this.kind,
    required this.version,
    required this.architecture,
    required this.platform,
    this.downloadUrl,
    this.sha256,
    this.sizeBytes,
    this.archiveType,
    this.dependencies = const [],
    this.minimumFldeVersion,
    this.runtimeRequirements,
  });

  /// True only when this entry actually has somewhere to download from.
  /// The UI must check this before offering an "Install" action — never
  /// assume a manifest entry is installable just because it exists.
  bool get hasSource => downloadUrl != null && downloadUrl!.isNotEmpty;

  factory ToolchainManifestEntry.fromJson(Map<String, dynamic> json) {
    return ToolchainManifestEntry(
      kind: ToolchainKind.values.firstWhere((k) => k.name == json['kind']),
      version: json['version'] as String,
      architecture: json['architecture'] as String,
      platform: json['platform'] as String,
      downloadUrl: json['downloadUrl'] as String?,
      sha256: json['sha256'] as String?,
      sizeBytes: json['sizeBytes'] as int?,
      archiveType: json['archiveType'] as String?,
      dependencies: (json['dependencies'] as List?)
              ?.map((d) => ToolchainKind.values.firstWhere((k) => k.name == d))
              .toList() ??
          const [],
      minimumFldeVersion: json['minimumFldeVersion'] as String?,
      runtimeRequirements: json['runtimeRequirements'] != null
          ? RuntimeRequirements.fromJson(json['runtimeRequirements'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'version': version,
        'architecture': architecture,
        'platform': platform,
        if (downloadUrl != null) 'downloadUrl': downloadUrl,
        if (sha256 != null) 'sha256': sha256,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (archiveType != null) 'archiveType': archiveType,
        'dependencies': dependencies.map((d) => d.name).toList(),
        if (minimumFldeVersion != null) 'minimumFldeVersion': minimumFldeVersion,
        if (runtimeRequirements != null) 'runtimeRequirements': runtimeRequirements!.toJson(),
      };
}

/// Declares what a manifest entry needs from the runtime in order to
/// actually work — e.g. whether it requires direct-exec-from-private-
/// storage capability (see RuntimeDiagnosticsService). ToolchainManager
/// can use this to reject an install up front on a device where the
/// required capability was already tested and found unavailable, rather
/// than downloading gigabytes only to discover the binary can't run.
class RuntimeRequirements {
  final bool requiresDirectExecFromPrivateStorage;
  final String? minimumAndroidVersion;
  final List<String> supportedAbis;

  const RuntimeRequirements({
    this.requiresDirectExecFromPrivateStorage = true,
    this.minimumAndroidVersion,
    this.supportedAbis = const [],
  });

  factory RuntimeRequirements.fromJson(Map<String, dynamic> json) => RuntimeRequirements(
        requiresDirectExecFromPrivateStorage: json['requiresDirectExecFromPrivateStorage'] as bool? ?? true,
        minimumAndroidVersion: json['minimumAndroidVersion'] as String?,
        supportedAbis: (json['supportedAbis'] as List?)?.cast<String>() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'requiresDirectExecFromPrivateStorage': requiresDirectExecFromPrivateStorage,
        if (minimumAndroidVersion != null) 'minimumAndroidVersion': minimumAndroidVersion,
        'supportedAbis': supportedAbis,
      };
}

/// Loads manifest entries from FLDE's managed storage. Supports layering
/// a user-provided/imported manifest (e.g. dropped in via USB or a future
/// "add toolchain source" screen) over the bundled default, without ever
/// synthesizing a URL that wasn't actually present in a loaded file.
class ToolchainManifestLoader {
  final String manifestFilePath;

  const ToolchainManifestLoader(this.manifestFilePath);

  Future<List<ToolchainManifestEntry>> load() async {
    final file = File(manifestFilePath);
    if (!await file.exists()) {
      return const [];
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ToolchainManifestEntry.fromJson)
          .toList();
    } catch (_) {
      // A corrupt/unreadable manifest must never be treated as "toolchains
      // available" — fail closed to an empty list rather than guessing.
      return const [];
    }
  }

  Future<void> ensureDefaultManifestExists() async {
    final file = File(manifestFilePath);
    if (await file.exists()) return;
    await file.parent.create(recursive: true);
    // Ships empty. No invented URLs. See class doc above.
    await file.writeAsString(jsonEncode(<Map<String, dynamic>>[]));
  }
}
