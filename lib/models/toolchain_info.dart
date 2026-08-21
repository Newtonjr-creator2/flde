/// Where a toolchain was found. `system` means it was already on the
/// device's PATH (e.g. installed via Termux) — FLDE didn't install it and
/// can't manage/uninstall it. `flde` means it lives in FLDE's own managed
/// storage and FLDE fully owns its lifecycle.
enum ToolchainOrigin { system, flde, notInstalled }

enum ToolchainInstallState {
  notInstalled,
  downloading,
  verifying,
  extracting,
  installed,
  failed,
}

/// The kinds of tools FLDE knows how to manage. Extendable — this is not
/// a hardcoded assumption that these are the only tools that will ever
/// exist, just the set Phase 2 has validators/manifests for.
enum ToolchainKind { dart, flutter, java, git, gradle, androidSdk }

/// Live, verified state of one toolchain. Every non-null field here was
/// produced by actually running or inspecting real files — see
/// ToolchainValidator. Nothing in this class is a hardcoded guess.
class ToolchainInfo {
  final ToolchainKind kind;
  final String displayName;
  final ToolchainOrigin origin;
  final ToolchainInstallState state;
  final String? version;
  final String? installPath;
  final String? executablePath;
  final int? sizeBytes;
  final String? lastError;
  final DateTime lastChecked;

  const ToolchainInfo({
    required this.kind,
    required this.displayName,
    required this.origin,
    required this.state,
    required this.lastChecked,
    this.version,
    this.installPath,
    this.executablePath,
    this.sizeBytes,
    this.lastError,
  });

  bool get isReady => state == ToolchainInstallState.installed && version != null;

  ToolchainInfo copyWith({
    ToolchainOrigin? origin,
    ToolchainInstallState? state,
    String? version,
    String? installPath,
    String? executablePath,
    int? sizeBytes,
    String? lastError,
    DateTime? lastChecked,
  }) {
    return ToolchainInfo(
      kind: kind,
      displayName: displayName,
      origin: origin ?? this.origin,
      state: state ?? this.state,
      version: version ?? this.version,
      installPath: installPath ?? this.installPath,
      executablePath: executablePath ?? this.executablePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastError: lastError,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }

  factory ToolchainInfo.unknown(ToolchainKind kind, String displayName) {
    return ToolchainInfo(
      kind: kind,
      displayName: displayName,
      origin: ToolchainOrigin.notInstalled,
      state: ToolchainInstallState.notInstalled,
      lastChecked: DateTime.now(),
    );
  }
}
