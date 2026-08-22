import 'package:flutter/material.dart';

import '../core/runtime/environment_manager.dart';
import '../core/runtime/native_runtime_environment.dart';
import '../core/storage/storage_service.dart';
import '../services/terminal_service.dart';

class TerminalScreen extends StatefulWidget {
  final String? initialDirectory;
  const TerminalScreen({super.key, this.initialDirectory});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  TerminalSession? _session;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Widget> _lines = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final storage = await StorageService.instance();
    final environment = EnvironmentManager(storage);
    final runtime = NativeRuntimeEnvironment();
    final session = TerminalSession(
      environment: environment,
      runtime: runtime,
      workingDirectory: widget.initialDirectory ?? storage.projectsDir.path,
    );
    session.onEntry.listen((entry) {
      if (!mounted) return;
      setState(() {
        _lines.add(_PromptLine(session.workingDirectory, entry.commandLine));
        for (final line in entry.output) {
          _lines.add(_OutputLine(line.text, isError: line.isError));
        }
        if (entry.exitCode != null && entry.exitCode != 0) {
          _lines.add(_OutputLine('(exit code ${entry.exitCode})', isError: true));
        }
      });
      _scrollToBottom();
    });
    if (!mounted) return;
    setState(() => _session = session);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _submit() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _session == null) return;
    _inputController.clear();
    await _session!.execute(text);
    setState(() {}); // refresh cwd shown in app bar / prompt
  }

  @override
  void dispose() {
    _session?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_session?.workingDirectory ?? 'Terminal', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: 'Stop running command',
            onPressed: _session != null && _session!.isRunning ? () => _session!.stopCurrent() : null,
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear',
            onPressed: () => setState(() => _lines.clear()),
          ),
        ],
      ),
      body: _session == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    children: _lines,
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        const Text('\$ ', style: TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)),
                        Expanded(
                          child: TextField(
                            controller: _inputController,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                            decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.send, size: 18), onPressed: _submit),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PromptLine extends StatelessWidget {
  final String cwd;
  final String commandLine;
  const _PromptLine(this.cwd, this.commandLine);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '\$ $commandLine',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.greenAccent),
      ),
    );
  }
}

class _OutputLine extends StatelessWidget {
  final String text;
  final bool isError;
  const _OutputLine(this.text, {required this.isError});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: isError ? Colors.redAccent : Colors.white70,
      ),
    );
  }
}
