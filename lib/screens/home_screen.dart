import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/file_service.dart';
import '../services/project_service.dart';
import 'explorer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ToolchainStatus? _status;

  @override
  void initState() {
    super.initState();
    _refreshToolchain();
  }

  Future<void> _refreshToolchain() async {
    final status = await ProjectService.detectToolchain();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _createProject() async {
    final nameController = TextEditingController(text: 'my_app');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Project'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Project name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final projectsDir = await FileService.workspaceProjectsDir();
    final status = _status ?? await ProjectService.detectToolchain();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Setting up project...'),
        ]),
      ),
    );

    if (status.flutterAvailable) {
      final log = StringBuffer();
      await for (final line in ProjectService.createFlutterProject(
        parentDir: projectsDir.path,
        projectName: name,
        orgId: 'com.vyomquantum',
      )) {
        log.writeln(line);
      }
      if (!mounted) return;
      Navigator.pop(context); // dismiss progress dialog
      _openProject(p.join(projectsDir.path, name));
    } else {
      // Honest fallback: no Flutter SDK on this device, so we create a
      // real Dart-only skeleton instead of pretending it's a Flutter app.
      await ProjectService.createDartProjectSkeleton(
        parentDir: projectsDir.path,
        projectName: name,
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Flutter SDK not detected — created a Dart-only project instead.'),
      ));
      _openProject(p.join(projectsDir.path, name));
    }
  }

  Future<void> _openExistingProject() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select project folder',
    );
    if (result != null) _openProject(result);
  }

  Future<void> _importZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.single.path == null) return;

    final zipFile = File(result.files.single.path!);
    final projectsDir = await FileService.workspaceProjectsDir();
    final targetName = p.basenameWithoutExtension(zipFile.path);
    final targetDir = Directory(p.join(projectsDir.path, targetName));
    await targetDir.create(recursive: true);

    await FileService.importZip(zipFile, targetDir);
    _openProject(targetDir.path);
  }

  void _openProject(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExplorerScreen(rootPath: path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RealBuzzingIdentifier')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.code, size: 64, color: Color(0xFF4FC3F7)),
                const SizedBox(height: 12),
                const Text('A real IDE, running on Android.', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                _ToolchainBanner(status: _status),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _createProject,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Flutter/Dart Project'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openExistingProject,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open Existing Project'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _importZip,
                  icon: const Icon(Icons.archive),
                  label: const Text('Import Project from ZIP'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolchainBanner extends StatelessWidget {
  final ToolchainStatus? status;
  const _ToolchainBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return const Text('Checking environment...', style: TextStyle(color: Colors.grey));
    }
    final flutterLine = status!.flutterAvailable
        ? 'Flutter: ${status!.flutterVersion}'
        : 'Flutter: not found on this device';
    final dartLine = status!.dartAvailable
        ? 'Dart: ${status!.dartVersion}'
        : 'Dart: not found on this device';
    final gitLine = status!.gitAvailable ? 'Git: available' : 'Git: not found';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(flutterLine, style: const TextStyle(fontSize: 12)),
          Text(dartLine, style: const TextStyle(fontSize: 12)),
          Text(gitLine, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
