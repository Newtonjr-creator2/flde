import 'toolchain_info.dart';

class ToolchainManifest {
  final ToolchainKind kind;
  final String name;
  final String version;
  final String architecture;
  final String platform;
  final String downloadUrl;
  final String sha256;
  final int sizeBytes;
  final List<ToolchainKind> dependencies;

  const ToolchainManifest({
    required this.kind,
    required this.name,
    required this.version,
    required this.architecture,
    required this.platform,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
    this.dependencies = const [],
  });

  factory ToolchainManifest.fromJson(Map<String, dynamic> json) {
    final deps = (json['dependencies'] as List<dynamic>? ?? const [])
        .map((e) => ToolchainKind.values.byName(e.toString()))
        .toList();
    return ToolchainManifest(
      kind: ToolchainKind.values.byName(json['kind'].toString()),
      name: json['name'].toString(),
      version: json['version'].toString(),
      architecture: json['architecture'].toString(),
      platform: json['platform'].toString(),
      downloadUrl: json['downloadUrl'].toString(),
      sha256: json['sha256'].toString(),
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
      dependencies: deps,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'name': name,
        'version': version,
        'architecture': architecture,
        'platform': platform,
        'downloadUrl': downloadUrl,
        'sha256': sha256,
        'size': sizeBytes,
        'dependencies': dependencies.map((e) => e.name).toList(),
      };
}
