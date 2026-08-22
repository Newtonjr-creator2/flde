import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/file_service.dart';
import '../services/project_service.dart';
import 'diagnostics_screen.dart';
import 'ide_workbench_screen.dart';
import 'toolchains_screen.dart';

/// VS-Code-style welcome/workspace entry point for FLDE.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ToolchainStatus? _status;
  bool _creatingProject = false;

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
    // Prevents a real crash: a fast double-tap previously pushed two
    // overlapping dialogs sharing one Navigator, and the pops could
    // resolve out of order — disposing the first dialog's
    // TextEditingController while its TextField was still mounted
    // underneath the second dialog ("used after being disposed").
    if (_creatingProject) return;
    setState(() => _creatingProject = true);
    try {
      await _runCreateProjectFlow();
    } finally {
      if (mounted) setState(() => _creatingProject = false);
    }
  }

  Future<void> _runCreateProjectFlow() async {
    final controller = TextEditingController(text: 'my_app');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Flutter project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Project name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    final projectsDir = await FileService.workspaceProjectsDir();
    final status = _status ?? await ProjectService.detectToolchain();
    if (!status.flutterAvailable) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Flutter SDK required'),
          content: const Text(
            'FLDE is ready to create a real Flutter workspace, but the Android-compatible Flutter build stack is not installed yet. Open Toolchains and install the Flutter build stack first.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolchainsScreen()));
              },
              child: const Text('Open Toolchains'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Creating project...')]),
      ),
    );
    await for (final _ in ProjectService.createFlutterProject(
      parentDir: projectsDir.path,
      projectName: name,
      orgId: 'com.flde',
    )) {}
    if (!mounted) return;
    Navigator.pop(context);
    _openProject(p.join(projectsDir.path, name));
  }

  Future<void> _openExistingProject() async {
    final result = await FilePicker.getDirectoryPath(dialogTitle: 'Open project folder');
    if (result != null) _openProject(result);
  }

  Future<void> _importZip() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    if (result.isEmpty || result.single.path == null) return;
    final projectsDir = await FileService.workspaceProjectsDir();
    final zipFile = File(result.single.path!);
    final target = Directory(p.join(projectsDir.path, p.basenameWithoutExtension(zipFile.path)));
    await target.create(recursive: true);
    await FileService.importZip(zipFile, target);
    _openProject(target.path);
  }

  void _openProject(String path) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => IdeWorkbenchScreen(rootPath: path)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF181818),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 46,
              color: const Color(0xFF252526),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.code, color: Color(0xFF4FC3F7), size: 19),
                  const SizedBox(width: 8),
                  const Text('FLDE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.extension_outlined, size: 20), tooltip: 'Toolchains', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolchainsScreen()))),
                  IconButton(icon: const Icon(Icons.health_and_safety_outlined, size: 20), tooltip: 'Diagnostics', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiagnosticsScreen()))),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Container(
                      width: 48,
                      color: const Color(0xFF181818),
                      child: const Column(children: [
                        SizedBox(height: 10),
                        Icon(Icons.folder_open, color: Color(0xFFCCCCCC)),
                        SizedBox(height: 18),
                        Icon(Icons.search, color: Color(0xFF777777)),
                        SizedBox(height: 18),
                        Icon(Icons.source_outlined, color: Color(0xFF777777)),
                        Spacer(),
                        Icon(Icons.settings_outlined, color: Color(0xFF777777)),
                        SizedBox(height: 14),
                      ]),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(horizontal: constraints.maxWidth < 500 ? 22 : 60, vertical: 40),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('FLDE', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Color(0xFFE6E6E6))),
                                const SizedBox(height: 4),
                                const Text('Flutter development environment for Android', style: TextStyle(color: Color(0xFF858585), fontSize: 13)),
                                const SizedBox(height: 34),
                                const Text('Start', style: TextStyle(color: Color(0xFFE6E6E6), fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 12),
                                _WelcomeAction(Icons.add, 'Create Flutter project', 'Create a real Flutter workspace', _createProject),
                                _WelcomeAction(Icons.folder_open, 'Open folder', 'Open an existing Flutter/Dart project', _openExistingProject),
                                _WelcomeAction(Icons.archive_outlined, 'Import ZIP', 'Import a project archive into FLDE workspace', _importZip),
                                const SizedBox(height: 30),
                                const Text('Installed SDKs', style: TextStyle(color: Color(0xFFE6E6E6), fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 12),
                                _SdkLine('Flutter', _status?.flutterAvailable == true ? (_status!.flutterVersion ?? 'installed') : 'Not installed'),
                                _SdkLine('Dart', _status?.dartAvailable == true ? (_status!.dartVersion ?? 'installed') : 'Not installed'),
                                _SdkLine('Git', _status?.gitAvailable == true ? 'Installed' : 'Not installed'),
                                const SizedBox(height: 20),
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolchainsScreen())),
                                  icon: const Icon(Icons.download_outlined, size: 18),
                                  label: const Text('Manage SDKs and build tools'),
                                ),
                                const SizedBox(height: 34),
                                const Text('Recent', style: TextStyle(color: Color(0xFFE6E6E6), fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                const Text('Your projects will appear here as FLDE learns the workspace history.', style: TextStyle(color: Color(0xFF777777), fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(height: 22, color: const Color(0xFF007ACC), padding: const EdgeInsets.symmetric(horizontal: 8), child: const Row(children: [Icon(Icons.code, size: 12), SizedBox(width: 6), Text('FLDE', style: TextStyle(fontSize: 10)), Spacer(), Text('Android • ARM64', style: TextStyle(fontSize: 10))])),
          ],
        ),
      ),
    );
  }
}

class _WelcomeAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _WelcomeAction(this.icon, this.title, this.subtitle, this.onTap);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF4FC3F7)),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF777777))),
      onTap: onTap,
    );
  }
}

class _SdkLine extends StatelessWidget {
  final String name;
  final String status;
  const _SdkLine(this.name, this.status);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [Text(name, style: const TextStyle(fontSize: 12)), const Spacer(), Text(status, style: TextStyle(fontSize: 11, color: status == 'Not installed' ? const Color(0xFF858585) : const Color(0xFF89D185)))]),
      );
}
