import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/file_service.dart';
import 'ide_workbench_screen.dart';

class ExplorerScreen extends StatefulWidget {
  final String rootPath;
  const ExplorerScreen({super.key, required this.rootPath});

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  late String _currentPath;
  List<FileSystemEntity> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.rootPath;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final entries = await FileService.listDir(_currentPath);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _open(FileSystemEntity entity) {
    if (entity is Directory) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => IdeWorkbenchScreen(rootPath: entity.path)));
    } else if (entity is File) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => IdeWorkbenchScreen(rootPath: widget.rootPath)));
    }
  }

  Future<void> _newFile() async {
    final name = await _promptName('New file', 'main.dart');
    if (name == null) return;
    try {
      await FileService.createFile(_currentPath, name);
      _refresh();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _newFolder() async {
    final name = await _promptName('New folder', 'widgets');
    if (name == null) return;
    try {
      await FileService.createFolder(_currentPath, name);
      _refresh();
    } catch (e) {
      _showError(e);
    }
  }

  Future<String?> _promptName(String title, String hint) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }

  Future<void> _showEntryActions(FileSystemEntity entity) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.drive_file_rename_outline), title: const Text('Rename'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(leading: const Icon(Icons.copy), title: const Text('Duplicate'), onTap: () => Navigator.pop(ctx, 'duplicate')),
          ListTile(leading: const Icon(Icons.delete, color: Colors.redAccent), title: const Text('Delete'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!mounted) return;

    if (action == 'rename') {
      final newName = await _promptName('Rename', p.basename(entity.path));
      if (newName != null && newName.isNotEmpty) {
        try {
          await FileService.rename(entity, newName);
          _refresh();
        } catch (e) {
          _showError(e);
        }
      }
    } else if (action == 'duplicate') {
      try {
        await FileService.duplicate(entity);
        _refresh();
      } catch (e) {
        _showError(e);
      }
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete?'),
          content: Text('Delete "${p.basename(entity.path)}" permanently?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        try {
          await FileService.delete(entity);
          _refresh();
        } catch (e) {
          _showError(e);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(_currentPath)),
        actions: [
          IconButton(icon: const Icon(Icons.note_add_outlined), onPressed: _newFile, tooltip: 'New file'),
          IconButton(icon: const Icon(Icons.create_new_folder_outlined), onPressed: _newFolder, tooltip: 'New folder'),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('Empty folder', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (context, i) {
                    final entity = _entries[i];
                    final isDir = entity is Directory;
                    return ListTile(
                      leading: Icon(
                        isDir ? Icons.folder : _iconFor(entity.path),
                        color: isDir ? Colors.amber : Colors.grey.shade400,
                      ),
                      title: Text(p.basename(entity.path)),
                      onTap: () => _open(entity),
                      onLongPress: () => _showEntryActions(entity),
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert, size: 18),
                        onPressed: () => _showEntryActions(entity),
                      ),
                    );
                  },
                ),
    );
  }

  IconData _iconFor(String path) {
    switch (p.extension(path)) {
      case '.dart':
        return Icons.code;
      case '.yaml':
      case '.yml':
        return Icons.settings_outlined;
      case '.json':
        return Icons.data_object;
      case '.md':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}
