import 'package:flutter/material.dart';

import '../core/diagnostics/diagnostics_service.dart';
import '../core/networking/connectivity_service.dart';
import '../models/toolchain_info.dart';
import '../services/toolchain_manager.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  DiagnosticsReport? _report;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final manager = await ToolchainManager.create();
    final service = DiagnosticsService(manager);
    final report = await service.runFullDiagnostics();
    if (!mounted) return;
    setState(() {
      _report = report;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _readinessBanner(report),
                const SizedBox(height: 16),
                const _Header('Runtime'),
                _kv('Architecture', report.deviceArchitecture ?? 'Unable to detect (uname unavailable)'),
                _kv('Android version', report.androidVersion),
                _kv('Connectivity', _connectivityLabel(report.connectivity)),
                const SizedBox(height: 16),
                const _Header('Toolchains'),
                for (final kind in ToolchainKind.values) _toolchainRow(report.toolchains[kind]),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: _running
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: const Text('Run Full Diagnostics'),
                ),
              ],
            ),
    );
  }

  Widget _readinessBanner(DiagnosticsReport report) {
    final ready = report.offlineDevelopmentReady;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ready ? const Color(0xFF1B3A2A) : const Color(0xFF3A2A1B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ready ? Colors.greenAccent : Colors.orangeAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ready ? 'OFFLINE DEVELOPMENT READY' : 'OFFLINE DEVELOPMENT LIMITED',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: ready ? Colors.greenAccent : Colors.orangeAccent,
            ),
          ),
          if (!ready) ...[
            const SizedBox(height: 8),
            for (final blocker in report.offlineBlockers)
              Text('• $blocker', style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _toolchainRow(ToolchainInfo? info) {
    if (info == null) return const SizedBox.shrink();
    final ready = info.isReady;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(ready ? Icons.check : Icons.close, size: 16, color: ready ? Colors.greenAccent : Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(info.displayName)),
          Text(
            ready ? info.version ?? '' : (info.lastError ?? 'not installed'),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(key, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  String _connectivityLabel(ConnectivityState s) {
    switch (s) {
      case ConnectivityState.online:
        return 'Online';
      case ConnectivityState.offline:
        return 'Offline';
      case ConnectivityState.unknown:
        return 'Unknown';
    }
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.grey, letterSpacing: 1.2)),
    );
  }
}
