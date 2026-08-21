import 'dart:io';

import '../networking/connectivity_service.dart';
import '../runtime/process_executor.dart';
import '../../models/toolchain_info.dart';
import '../../services/toolchain_manager.dart';

class DiagnosticsReport {
  final String? deviceArchitecture; // e.g. "aarch64" — null if detection failed
  final String androidVersion;
  final ConnectivityState connectivity;
  final Map<ToolchainKind, ToolchainInfo> toolchains;
  final bool offlineDevelopmentReady;
  final List<String> offlineBlockers;
  final DateTime generatedAt;

  const DiagnosticsReport({
    required this.deviceArchitecture,
    required this.androidVersion,
    required this.connectivity,
    required this.toolchains,
    required this.offlineDevelopmentReady,
    required this.offlineBlockers,
    required this.generatedAt,
  });
}

/// Runs the real diagnostic suite described in Phase 2 spec section 19.
/// Every field is produced by an actual check — architecture comes from
/// `uname -m` (a real process), connectivity from a real DNS lookup,
/// toolchain status from ToolchainValidator's real version checks.
class DiagnosticsService {
  final ToolchainManager toolchainManager;

  DiagnosticsService(this.toolchainManager);

  Future<DiagnosticsReport> runFullDiagnostics() async {
    final arch = await _detectArchitecture();
    final connectivity = await ConnectivityService.check();
    final toolchains = await toolchainManager.currentState();

    // "Offline development ready" per spec section 11: true only if the
    // toolchains actually required for basic Dart/Flutter work are
    // genuinely installed right now — never assumed from connectivity.
    final requiredForOffline = [ToolchainKind.dart];
    final blockers = <String>[];
    for (final kind in requiredForOffline) {
      final info = toolchains[kind];
      if (info == null || !info.isReady) {
        blockers.add('${info?.displayName ?? kind.name} is not installed or not verified.');
      }
    }

    return DiagnosticsReport(
      deviceArchitecture: arch,
      androidVersion: Platform.operatingSystemVersion,
      connectivity: connectivity,
      toolchains: toolchains,
      offlineDevelopmentReady: blockers.isEmpty,
      offlineBlockers: blockers,
      generatedAt: DateTime.now(),
    );
  }

  /// Real device architecture via `uname -m`, available on Android's
  /// underlying Linux userspace (toybox/busybox `uname`). Returns null —
  /// not a guess like "assume arm64" — if the command isn't available or
  /// fails; the UI must show that explicitly rather than pretend.
  Future<String?> _detectArchitecture() async {
    final result = await ProcessExecutor.run('uname', ['-m'], timeout: const Duration(seconds: 5));
    if (result.succeeded && result.stdout.trim().isNotEmpty) {
      return result.stdout.trim();
    }
    return null;
  }
}
