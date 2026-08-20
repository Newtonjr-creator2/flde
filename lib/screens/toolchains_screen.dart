import 'package:flutter/material.dart';
import '../core/runtime/architecture_service.dart';
import '../models/toolchain_info.dart';
import '../models/toolchain_manifest.dart';
import '../services/toolchain_manager.dart';

class ToolchainsScreen extends StatefulWidget {
  const ToolchainsScreen({super.key});
  @override
  State<ToolchainsScreen> createState() => _ToolchainsScreenState();
}

class _ToolchainsScreenState extends State<ToolchainsScreen> {
  List<ToolchainInfo> _installed = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ToolchainManager.instance.scanInstalled();
    if (mounted) setState(() => _installed = list);
  }

  Future<void> _installDialog(ToolchainKind kind) async {
    final url = TextEditingController();
    final version = TextEditingController(text: 'unknown');
    final sha = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Install ${kind.name}'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              const Text(
                'Phase 2 requires a real, trusted archive URL and SHA-256. '
                'No download URL is invented by FLDE.',
              ),
              TextField(controller: version, decoration: const InputDecoration(labelText: 'Version')),
              TextField(controller: url, decoration: const InputDecoration(labelText: 'HTTPS ZIP URL')),
              TextField(controller: sha, decoration: const InputDecoration(labelText: 'SHA-256')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Install')),
        ],
      ),
    );
    if (result != true) return;

    setState(() => _busy = true);
    try {
      await ToolchainManager.instance.install(
        ToolchainManifest(
          kind: kind,
          name: kind.name,
          version: version.text.trim(),
          architecture: ArchitectureService.abi,
          platform: 'android',
          downloadUrl: url.text.trim(),
          sha256: sha.text.trim(),
          sizeBytes: 0,
        ),
        onProgress: (progress) {
          if (mounted) setState(() {});
        },
      );
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${kind.name} installed and validated.')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Installation failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = [
      ToolchainKind.dart,
      ToolchainKind.flutter,
      ToolchainKind.java,
      ToolchainKind.gradle,
      ToolchainKind.androidSdk,
      ToolchainKind.git,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Toolchains'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.memory),
              title: Text('Device: ${ArchitectureService.label}'),
              subtitle: Text(ArchitectureService.abi),
            ),
          ),
          const SizedBox(height: 12),
          const Text('INSTALLED', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_installed.isEmpty)
            const Card(child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('No FLDE-managed toolchains installed'),
              subtitle: Text('This is a real status; nothing is assumed.'),
            )),
          ..._installed.map((info) => Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle),
              title: Text(info.name),
              subtitle: Text('${info.version}\n${info.path}'),
              isThreeLine: true,
            ),
          )),
          const SizedBox(height: 20),
          const Text('AVAILABLE / CONFIGURE', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...available.map((kind) => Card(
            child: ListTile(
              leading: const Icon(Icons.download),
              title: Text(kind.name),
              subtitle: const Text('Provide a trusted HTTPS ZIP + SHA-256 to install.'),
              trailing: FilledButton(
                onPressed: _busy ? null : () => _installDialog(kind),
                child: const Text('Install'),
              ),
            ),
          )),
          if (_busy) const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
          const SizedBox(height: 16),
          const Text(
            'Important: many official Flutter/Dart distributions contain Linux executables and are not automatically executable inside Android. '
            'FLDE therefore validates the actual binary after installation instead of marking an archive as usable merely because extraction succeeded.',
          ),
        ],
      ),
    );
  }
}
