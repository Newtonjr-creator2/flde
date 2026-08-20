import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/runtime/architecture_service.dart';
import '../core/storage/storage_service.dart';
import '../services/network_service.dart';
import '../services/project_service.dart';
import '../services/usb_storage_service.dart';
import 'diagnostics_screen.dart';
import 'explorer_screen.dart';
import 'terminal_screen.dart';
import 'toolchains_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ToolchainStatus? _status;
  NetworkStatus? _network;
  StorageStats? _storage;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final values = await Future.wait([
      ProjectService.detectToolchain(),
      NetworkService.check(),
      StorageService.stats(),
    ]);
    if (!mounted) return;
    setState(() {
      _status = values[0] as ToolchainStatus;
      _network = values[1] as NetworkStatus;
      _storage = values[2] as StorageStats;
    });
  }

  Future<void> _createProject() async {
    final controller = TextEditingController(text: 'my_app');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Flutter project'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Project name',
            helperText: 'Requires a validated FLDE Flutter runtime.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final projectsDir = await StorageService.initialize().then((e) => e.projects);
    final status = _status ?? await ProjectService.detectToolchain();

    if (!status.flutterAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flutter runtime is not validated. Install it from Toolchains first.')),
      );
      return;
    }

    final log = <String>[];
    await for (final line in ProjectService.createFlutterProject(
      parentDir: projectsDir.path,
      projectName: name,
      orgId: 'com.flde',
    )) {
      log.add(line);
    }
    final path = p.join(projectsDir.path, name);
    if (!mounted) return;
    _openProject(path);
  }

  Future<void> _createDartProject() async {
    final controller = TextEditingController(text: 'my_dart_app');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Dart project'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Project name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final projectsDir = (await StorageService.initialize()).projects;
    await ProjectService.createDartProjectSkeleton(
      parentDir: projectsDir.path,
      projectName: name,
    );
    if (mounted) _openProject(p.join(projectsDir.path, name));
  }

  Future<void> _openExistingProject() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select project folder',
    );
    if (result != null && mounted) _openProject(result);
  }

  Future<void> _importZip() async {
    final path = await UsbStorageService().pickProjectZip();
    if (path == null) return;
    final target = await UsbStorageService().importZip(path);
    if (mounted) _openProject(target.path);
  }

  Future<void> _importFromUsb() async {
    final path = await UsbStorageService().pickDirectory();
    if (path == null) return;
    try {
      final target = await UsbStorageService().importDirectory(path);
      if (mounted) _openProject(target.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('USB import failed: $e')));
    }
  }

  void _openProject(String path) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ExplorerScreen(rootPath: path)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.terminal, size: 20),
          SizedBox(width: 8),
          Text('FLDE'),
        ]),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'toolchains') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolchainsScreen()));
              } else if (value == 'diagnostics') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DiagnosticsScreen()));
              } else if (value == 'terminal') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TerminalScreen()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'toolchains', child: Text('Toolchains')),
              PopupMenuItem(value: 'terminal', child: Text('Terminal')),
              PopupMenuItem(value: 'diagnostics', child: Text('Diagnostics')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ideHeader(),
            const SizedBox(height: 16),
            _environmentCard(),
            const SizedBox(height: 16),
            _primaryActions(),
            const SizedBox(height: 16),
            _storageCard(),
            const SizedBox(height: 16),
            _runtimeNotice(),
          ],
        ),
      ),
    );
  }

  Widget _ideHeader() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF263238),
            ),
            child: const Icon(Icons.code, size: 30, color: Color(0xFF4FC3F7)),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FLDE', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text('Flutter Lightweight Development Environment'),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _environmentCard() {
    final s = _status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DEVELOPMENT ENVIRONMENT', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _statusLine('Flutter', s?.flutterAvailable == true, s?.flutterVersion),
            _statusLine('Dart', s?.dartAvailable == true, s?.dartVersion),
            _statusLine('Git', s?.gitAvailable == true, s?.gitAvailable == true ? 'validated' : null),
            _statusLine('Network', _network?.online == true, _network?.online == true ? 'online' : 'offline'),
            _statusLine('Architecture', true, ArchitectureService.label),
          ],
        ),
      ),
    );
  }

  Widget _statusLine(String name, bool ok, String? detail) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? Colors.greenAccent : Colors.grey),
    title: Text(name),
    subtitle: Text(detail ?? 'Not available'),
  );

  Widget _primaryActions() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: _status?.flutterAvailable == true ? _createProject : null,
        icon: const Icon(Icons.flutter_dash),
        label: const Text('Create Flutter Project'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _createDartProject,
        icon: const Icon(Icons.data_object),
        label: const Text('Create Dart Project'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _openExistingProject,
        icon: const Icon(Icons.folder_open),
        label: const Text('Open Existing Project'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _importZip,
        icon: const Icon(Icons.archive),
        label: const Text('Import ZIP'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _importFromUsb,
        icon: const Icon(Icons.usb),
        label: const Text('Import from USB / External Storage'),
      ),
    ],
  );

  Widget _storageCard() => Card(
    child: ListTile(
      leading: const Icon(Icons.storage),
      title: const Text('FLDE managed storage'),
      subtitle: Text(
        _storage == null
            ? 'Calculating...'
            : '${_storage!.managedText} used\n${_storage!.rootPath}',
      ),
    ),
  );

  Widget _runtimeNotice() => const Card(
    child: Padding(
      padding: EdgeInsets.all(14),
      child: Text(
        'Phase 2 deliberately does not claim that a downloaded desktop/Linux Flutter SDK is Android-compatible. '
        'Toolchains are verified by actual execution. A future Android-compatible runtime/container may be required for full local Flutter builds.',
      ),
    ),
  );
}
