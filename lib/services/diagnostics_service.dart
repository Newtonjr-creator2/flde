import 'dart:io';
import '../core/runtime/architecture_service.dart';
import '../core/runtime/environment_manager.dart';
import '../core/storage/storage_service.dart';
import 'network_service.dart';
import 'toolchain_manager.dart';

class DiagnosticItem {
  final String name;
  final bool ok;
  final String detail;

  const DiagnosticItem(this.name, this.ok, this.detail);
}

class DiagnosticsReport {
  final List<DiagnosticItem> items;
  final DateTime timestamp;

  const DiagnosticsReport(this.items, this.timestamp);

  bool get allReady => items.every((e) => e.ok);
}

class DiagnosticsService {
  static Future<DiagnosticsReport> run() async {
    final items = <DiagnosticItem>[];
    items.add(const DiagnosticItem(
      'FLDE',
      true,
      'Phase 2 runtime foundation loaded',
    ));
    items.add(DiagnosticItem(
      'Android',
      Platform.isAndroid,
      Platform.operatingSystemVersion,
    ));
    items.add(DiagnosticItem(
      'Architecture',
      ArchitectureService.abi != 'unknown',
      ArchitectureService.label,
    ));

    final stats = await StorageService.stats();
    items.add(DiagnosticItem(
      'Managed storage',
      true,
      '${stats.managedText} used at ${stats.rootPath}',
    ));

    final network = await NetworkService.check();
    items.add(DiagnosticItem(
      'Internet',
      network.online,
      network.online ? 'Online' : 'Offline: ${network.detail ?? 'probe failed'}',
    ));

    final installed = await ToolchainManager.instance.scanInstalled();
    for (final kind in [
      'dart',
      'flutter',
      'java',
      'gradle',
      'androidSdk',
      'git',
    ]) {
      final matches = installed.where((e) => e.kind.name == kind);
      items.add(DiagnosticItem(
        kind,
        matches.isNotEmpty,
        matches.isEmpty
            ? 'Not installed or not validated'
            : matches.map((e) => '${e.version} @ ${e.path}').join('\n'),
      ));
    }

    final env = await EnvironmentManager.buildEnvironment();
    items.add(DiagnosticItem(
      'FLDE PATH',
      (env['PATH'] ?? '').contains(stats.rootPath.split(Platform.pathSeparator).first) ||
          (env['PATH'] ?? '').isNotEmpty,
      'Environment prepared for local processes',
    ));

    return DiagnosticsReport(items, DateTime.now());
  }
}
