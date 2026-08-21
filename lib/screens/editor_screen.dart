import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:path/path.dart' as p;

import '../services/file_service.dart';

/// A real text editor: it reads the file's actual bytes, edits an in-memory
/// buffer, shows genuine syntax highlighting for the detected language, and
/// writes the exact bytes back to disk on save. Nothing here is a preview
/// or a mock — this is the file.
class EditorScreen extends StatefulWidget {
  final String filePath;
  const EditorScreen({super.key, required this.filePath});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late TextEditingController _controller;
  bool _loading = true;
  bool _dirty = false;
  bool _highlightMode = true;
  String? _error;
  String _originalContent = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    try {
      final content = await FileService.readFile(widget.filePath);
      _originalContent = content;
      _controller.text = content;
      _controller.addListener(() {
        final isDirty = _controller.text != _originalContent;
        if (isDirty != _dirty) setState(() => _dirty = isDirty);
      });
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    try {
      await FileService.writeFile(widget.filePath, _controller.text);
      _originalContent = _controller.text;
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  String get _language {
    switch (p.extension(widget.filePath)) {
      case '.dart':
        return 'dart';
      case '.yaml':
      case '.yml':
        return 'yaml';
      case '.json':
        return 'json';
      case '.md':
        return 'markdown';
      case '.xml':
        return 'xml';
      case '.gradle':
        return 'gradle';
      case '.sh':
        return 'bash';
      default:
        return 'plaintext';
    }
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Discard changes to this file?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscardIfDirty();
        if (!mounted) return;
        if (discard) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(p.basename(widget.filePath) + (_dirty ? ' •' : '')),
          actions: [
            IconButton(
              icon: Icon(_highlightMode ? Icons.text_fields : Icons.color_lens_outlined),
              tooltip: _highlightMode ? 'Plain edit mode' : 'Highlighted view',
              onPressed: () => setState(() => _highlightMode = !_highlightMode),
            ),
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save (Ctrl+S)',
              onPressed: _dirty ? _save : null,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
                : CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
                      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
                    },
                    child: Focus(
                      autofocus: true,
                      child: _highlightMode ? _buildHighlightedEditor() : _buildPlainEditor(),
                    ),
                  ),
      ),
    );
  }

  Widget _buildPlainEditor() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        decoration: const InputDecoration(border: InputBorder.none),
      ),
    );
  }

  /// Uses the `highlight` package's real tokenizer for the detected
  /// language, overlaid on an editable TextField so keystrokes still write
  /// straight into the same buffer that gets saved to disk.
  Widget _buildHighlightedEditor() {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: HighlightView(
                _controller.text.isEmpty ? ' ' : _controller.text,
                language: _language,
                theme: atomOneDarkTheme,
                textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.4),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.4,
                color: Colors.transparent,
              ),
              cursorColor: Colors.white,
              decoration: const InputDecoration(border: InputBorder.none),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ],
    );
  }
}
