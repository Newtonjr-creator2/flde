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
  bool _bootstrapping = false;
  final Map<ToolchainKind, DownloadProgress?> _activeInstalls = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _manager = await ToolchainManager.create();
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
      _show(entry.notes ?? 'This toolchain needs a FLDE-specific build before it can be installed.');
      return;
    }
    setState(() => _activeInstalls[entry.kind] = null);
    await for (final progress in _manager!.install(entry)) {
      if (!mounted) return;
      setState(() => _activeInstalls[entry.kind] = progress);
      if (progress.phase == DownloadPhase.done || progress.phase == DownloadPhase.failed) break;
    }
    if (!mounted) return;
    final progress = _activeInstalls.remove(entry.kind);
    if (progress?.phase == DownloadPhase.failed) _show(progress?.message ?? 'Installation failed');
    await _refresh();
  }

  Future<void> _installFlutterStack() async {
    final flutter = _find(ToolchainKind.flutter);
    final sdk = _find(ToolchainKind.androidSdk);
    if (flutter == null || sdk == null) {
      _show('Flutter stack sources are unavailable in this build.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install Flutter build stack?'),
        content: const Text(
          'This downloads a large Android-native development stack. It is not bundled into the APK because the Flutter SDK, Android SDK and build components are hundreds of megabytes. FLDE verifies each archive before installing it.\n\nThe Flutter package is an Android-bionic ARM64 build; the official Linux/glibc Flutter SDK is intentionally not used.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Install')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _bootstrapping = true);
    await _install(flutter);
    if (mounted) await _install(sdk);
    if (mounted) setState(() => _bootstrapping = false);
  }

  ToolchainManifestEntry? _find(ToolchainKind kind) {
    for (final e in _manifestEntries) {
      if (e.kind == kind) return e;
    }
    return null;
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF181818),
      appBar: AppBar(
        backgroundColor: const Color(0xFF252526),
        title: const Text('SDK & Toolchains', style: TextStyle(fontSize: 15)),
        actions: [IconButton(icon: const Icon(Icons.refresh, size: 19), onPressed: _refresh)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFF202020), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF3A3A3A))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('FLDE Android runtime', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    const Text('ARM64 / Android-bionic runtime with system-linker execution. Toolchains are installed into FLDE-managed storage and launched through the same runtime.', style: TextStyle(fontSize: 11, color: Color(0xFF8A8A8A))),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _bootstrapping ? null : _installFlutterStack,
                        icon: _bootstrapping ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_outlined, size: 18),
                        label: Text(_bootstrapping ? 'Installing Flutter stack…' : 'Install Flutter + Android build stack'),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                const Text('Installed', style: TextStyle(fontSize: 12, color: Color(0xFFBDBDBD), letterSpacing: 1.1)),
                const SizedBox(height: 5),
                for (final kind in ToolchainKind.values) _ToolchainTile(info: _state[kind]),
                const SizedBox(height: 18),
                const Text('Sources', style: TextStyle(fontSize: 12, color: Color(0xFFBDBDBD), letterSpacing: 1.1)),
                const SizedBox(height: 5),
                for (final entry in _manifestEntries)
                  _InstallTile(entry: entry, progress: _activeInstalls[entry.kind], onInstall: () => _install(entry)),
              ],
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
      dense: true,
      leading: Icon(ready ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: ready ? const Color(0xFF89D185) : const Color(0xFF777777)),
      title: Text(info!.displayName, style: const TextStyle(fontSize: 13)),
      subtitle: Text(ready ? '${info!.version} • ${info!.origin == ToolchainOrigin.flde ? 'FLDE-managed' : 'system'}' : (info!.lastError ?? 'Not installed'), style: const TextStyle(fontSize: 10, color: Color(0xFF777777))),
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
    final installable = entry.hasSource && entry.installerType == 'termux-deb';
    return Card(
      color: const Color(0xFF202020),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(installable ? Icons.cloud_download_outlined : Icons.build_circle_outlined, size: 19, color: installable ? const Color(0xFF4FC3F7) : const Color(0xFF777777)),
        title: Text('${entry.kind.name} ${entry.version}', style: const TextStyle(fontSize: 12)),
        subtitle: Text(progress != null ? _progressLabel(progress!) : (entry.notes ?? 'Verified source'), style: const TextStyle(fontSize: 10, color: Color(0xFF888888))),
        trailing: progress != null ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : TextButton(onPressed: installable ? onInstall : null, child: Text(installable ? 'Install' : 'Build')),
      ),
    );
  }

  String _progressLabel(DownloadProgress p) {
    switch (p.phase) {
      case DownloadPhase.downloading:
        return p.fraction == null ? 'Downloading…' : 'Downloading ${(p.fraction! * 100).toStringAsFixed(0)}%';
      case DownloadPhase.verifying: return 'Verifying SHA-256…';
      case DownloadPhase.extracting: return 'Installing into FLDE runtime…';
      case DownloadPhase.done: return 'Installed';
      case DownloadPhase.failed: return p.message ?? 'Failed';
      case DownloadPhase.cancelled: return 'Cancelled';
    }
  }
}
