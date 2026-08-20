enum ToolchainKind { dart, flutter, java, gradle, androidSdk, platformTools, buildTools, git }

enum ToolchainInstallStatus { notInstalled, downloading, installed, invalid, error }

class ToolchainInfo {
  final ToolchainKind kind;
  final String name;
  final String version;
  final String architecture;
  final String platform;
  final String path;
  final ToolchainInstallStatus status;
  final String? source;
  final String? sha256;
  final int? sizeBytes;
  final List<ToolchainKind> dependencies;
  final bool enabled;

  const ToolchainInfo({
    required this.kind,
    required this.name,
    required this.version,
    required this.architecture,
    required this.platform,
    required this.path,
    required this.status,
    this.source,
    this.sha256,
    this.sizeBytes,
    this.dependencies = const [],
    this.enabled = true,
  });

  ToolchainInfo copyWith({
    String? version,
    String? architecture,
    String? platform,
    String? path,
    ToolchainInstallStatus? status,
    String? source,
    String? sha256,
    int? sizeBytes,
    List<ToolchainKind>? dependencies,
    bool? enabled,
  }) {
    return ToolchainInfo(
      kind: kind,
      name: name,
      version: version ?? this.version,
      architecture: architecture ?? this.architecture,
      platform: platform ?? this.platform,
      path: path ?? this.path,
      status: status ?? this.status,
      source: source ?? this.source,
      sha256: sha256 ?? this.sha256,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      dependencies: dependencies ?? this.dependencies,
      enabled: enabled ?? this.enabled,
    );
  }
}
