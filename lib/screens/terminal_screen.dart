import 'dart:async';
import 'package:flutter/material.dart';
import '../models/process_result.dart';
import '../services/terminal_service.dart';

class TerminalScreen extends StatefulWidget {
  final String? workingDirectory;
  const TerminalScreen({super.key, this.workingDirectory});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _command = TextEditingController();
  final _scroll = ScrollController();
  final _terminal = TerminalService();
  final _lines = <ProcessLine>[];
  final _history = <String>[];
  bool _running = false;

  Future<void> _execute() async {
    final command = _command.text.trim();
    if (command.isEmpty || _running) return;
    _command.clear();
    _history.add(command);
    setState(() {
      _running = true;
      _lines.add(ProcessLine('\$ $command'));
    });
    try {
      await for (final line in _terminal.execute(
        command,
        workingDirectory: widget.workingDirectory,
      )) {
        if (!mounted) return;
        setState(() => _lines.add(line));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _lines.add(ProcessLine('$e', isError: true)));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _command.dispose();
    _scroll.dispose();
    _terminal.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal'),
        actions: [
          IconButton(onPressed: _running ? _terminal.stop : null, icon: const Icon(Icons.stop)),
          IconButton(onPressed: () => setState(() => _lines.clear()), icon: const Icon(Icons.clear_all)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: const Color(0xFF111111),
              width: double.infinity,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: _lines.length,
                itemBuilder: (_, i) => SelectableText(
                  _lines[i].text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: _lines[i].isError ? Colors.redAccent : Colors.white70,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Text('\$ ', style: TextStyle(fontFamily: 'monospace')),
                  Expanded(
                    child: TextField(
                      controller: _command,
                      enabled: !_running,
                      autofocus: true,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        hintText: 'flutter --version',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _execute(),
                    ),
                  ),
                  IconButton(onPressed: _running ? null : _execute, icon: const Icon(Icons.play_arrow)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
