import 'package:flutter/material.dart';
import '../services/run_manager.dart';
import '../core/runtime/process_executor.dart';

class ProjectRunScreen extends StatefulWidget {
  final String projectPath;
  final bool flutter;
  const ProjectRunScreen({
    super.key,
    required this.projectPath,
    this.flutter = true,
  });

  @override
  State<ProjectRunScreen> createState() => _ProjectRunScreenState();
}

class _ProjectRunScreenState extends State<ProjectRunScreen> {
  final _manager = RunManager();
  final _lines = <String>[];
  ProcessSession? _session;
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _lines.clear();
    });
    try {
      _session = await _manager.run(RunConfiguration(
        projectPath: widget.projectPath,
        flutter: widget.flutter,
      ));
      await for (final line in _session!.output) {
        if (mounted) setState(() => _lines.add(
          '${line.isError ? '[stderr] ' : ''}${line.text}',
        ));
      }
      final code = await _session!.exitCode;
      if (mounted) setState(() => _lines.add('Process exited with code $code.'));
    } catch (e) {
      if (mounted) setState(() => _lines.add('Run failed: $e'));
    } finally {
      if (mounted) setState(() {
        _running = false;
        _session = null;
      });
    }
  }

  @override
  void dispose() {
    _manager.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Run / Output'),
        actions: [
          IconButton(onPressed: _running ? _manager.stop : null, icon: const Icon(Icons.stop)),
          IconButton(onPressed: _running ? null : _run, icon: const Icon(Icons.play_arrow)),
        ],
      ),
      body: Container(
        color: const Color(0xFF111111),
        width: double.infinity,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _lines.length,
          itemBuilder: (_, i) => SelectableText(
            _lines[i],
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    );
  }
}
