import 'package:flutter/material.dart';
import '../services/diagnostics_service.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  DiagnosticsReport? _report;
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final report = await DiagnosticsService.run();
      if (mounted) setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FLDE Diagnostics'),
        actions: [IconButton(onPressed: _running ? null : _run, icon: const Icon(Icons.refresh))],
      ),
      body: _report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(
                      _report!.allReady ? Icons.check_circle : Icons.warning_amber,
                    ),
                    title: Text(
                      _report!.allReady
                          ? 'ALL CHECKS READY'
                          : 'DEVELOPMENT ENVIRONMENT LIMITED',
                    ),
                    subtitle: Text(_report!.timestamp.toLocal().toString()),
                  ),
                ),
                const SizedBox(height: 12),
                ..._report!.items.map((item) => Card(
                  child: ListTile(
                    leading: Icon(
                      item.ok ? Icons.check_circle_outline : Icons.error_outline,
                      color: item.ok ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                    title: Text(item.name),
                    subtitle: Text(item.detail),
                  ),
                )),
              ],
            ),
    );
  }
}
