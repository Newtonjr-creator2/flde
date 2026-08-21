import 'package:flutter/material.dart';

import '../models/toolchain_info.dart';
import '../models/toolchain_manifest.dart';
import '../services/toolchain_downloader.dart';
import '../services/toolchain_manager.dart';

class ToolchainsScreen extends StatefulWidget {
  const ToolchainsScreen({super.key});

  @override
  State<ToolchainsScreen> createState() => _ToolchainsScreenState();
}

class _ToolchainsScreenState extends State<ToolchainsScreen> {
  ToolchainManager? _manager;
  Map<ToolchainKind, ToolchainInfo> _state = {};
  List<ToolchainManifestEntry> _manifestEntries = [];
  bool _loading = true;
  final Map<ToolchainKind, DownloadProgress?> _activeInstalls = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final manager = await ToolchainManager.create();
    _manager = manager;
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_manager == null) return;
    setState(() => _loading = true);
    final state = await _manager!.currentState();
    final entries = await _manager!.availableManifestEntries();
    if (!mounted) return;
    setState(() {
      _state = state;
      _manifestEntries = entries;
      _loading = false;
    });
  }

  Future<void> _install(ToolchainManifestEntry entry) async {
    if (!entry.hasSource) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No download source configured for this toolchain yet.')),
      );
      return;
    }
    setState(() => _activeInstalls[entry.kind] = null);
    await for (final progress in _manager!.install(entry)) {
      if (!mounted) return;
      setState(() => _activeInstalls[entry.kind] = progress);
      if (progress.phase == DownloadPhase.done || progress.phase == DownloadPhase.failed) {
        break;
      }
    }
    setState(() => _activeInstalls.remove(entry.kind));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Toolchains'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const _SectionHeader('Detected'),
                for (final kind in ToolchainKind.values) _ToolchainTile(info: _state[kind]),
                const SizedBox(height: 24),
                const _SectionHeader('Available to Install'),
                if (_manifestEntries.isEmpty) const _NoSourcesConfiguredCard(),
                for (final entry in _manifestEntries)
                  _InstallTile(
                    entry: entry,
                    progress: _activeInstalls[entry.kind],
                    onInstall: () => _install(entry),
                  ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey, letterSpacing: 1.2)),
    );
  }
}

class _NoSourcesConfiguredCard extends StatelessWidget {
  const _NoSourcesConfiguredCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2D2D2D),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No toolchain download sources are configured yet. FLDE only installs '
          'toolchains from verified, checksummed manifest entries — those sources '
          'will be added in a future update rather than guessed at now.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ),
    );
  }
}

class _ToolchainTile extends StatelessWidget {
  final ToolchainInfo? info;
  const _ToolchainTile({required this.info});

  @override
  Widget build(BuildContext context) {
    if (info == null) return const SizedBox.shrink();
    final ready = info!.isReady;
    return ListTile(
      leading: Icon(
        ready ? Icons.check_circle : Icons.radio_button_unchecked,
        color: ready ? Colors.greenAccent : Colors.grey,
      ),
      title: Text(info!.displayName),
      subtitle: Text(
        ready
            ? '${info!.version}  •  ${info!.origin == ToolchainOrigin.flde ? "FLDE-managed" : "system"}'
            : (info!.lastError ?? 'Not installed'),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _InstallTile extends StatelessWidget {
  final ToolchainManifestEntry entry;
  final DownloadProgress? progress;
  final VoidCallback onInstall;

  const _InstallTile({required this.entry, required this.progress, required this.onInstall});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.cloud_download_outlined),
      title: Text('${entry.kind.name} ${entry.version}'),
      subtitle: progress != null
          ? Text(_progressLabel(progress!), style: const TextStyle(fontSize: 12))
          : Text(entry.hasSource ? 'Ready to install' : 'No source configured', style: const TextStyle(fontSize: 12)),
      trailing: progress != null
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : FilledButton(onPressed: entry.hasSource ? onInstall : null, child: const Text('Install')),
    );
  }

  String _progressLabel(DownloadProgress p) {
    switch (p.phase) {
      case DownloadPhase.downloading:
        final pct = p.fraction != null ? '${(p.fraction! * 100).toStringAsFixed(0)}%' : '${p.received} bytes';
        return 'Downloading... $pct';
      case DownloadPhase.verifying:
        return 'Verifying checksum...';
      case DownloadPhase.extracting:
        return 'Extracting...';
      case DownloadPhase.done:
        return 'Installed';
      case DownloadPhase.failed:
        return p.message ?? 'Failed';
      case DownloadPhase.cancelled:
        return 'Cancelled';
    }
  }
}
