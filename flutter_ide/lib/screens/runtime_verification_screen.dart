import 'package:flutter/material.dart';

import '../core/runtime/native_runtime_environment.dart';
import '../core/runtime/runtime_verification_service.dart';
import '../core/storage/storage_service.dart';

class RuntimeVerificationScreen extends StatefulWidget {
  const RuntimeVerificationScreen({super.key});

  @override
  State<RuntimeVerificationScreen> createState() => _RuntimeVerificationScreenState();
}

class _RuntimeVerificationScreenState extends State<RuntimeVerificationScreen> {
  RuntimeVerificationReport? _report;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final storage = await StorageService.instance();
    final service = RuntimeVerificationService(NativeRuntimeEnvironment());
    final report = await service.run(workingDirectory: storage.projectsDir.path);
    if (!mounted) return;
    setState(() {
      _report = report;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Runtime Verification')),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'This runs 4 real commands, right now, on THIS device, through '
                    '${report.shellUsed ?? "no shell (none resolved)"}. Every stdout/stderr/exit '
                    'code below is genuine — nothing is precomputed or simulated.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 16),
                for (final result in report.results) _CommandCard(result: result),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: _running
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: const Text('Run Again'),
                ),
              ],
            ),
    );
  }
}

class _CommandCard extends StatelessWidget {
  final VerificationCommandResult result;
  const _CommandCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final exec = result.execResult;
    final ok = result.succeeded;
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: ok ? const Color(0xFF69F0AE) : const Color(0xFFFFAB40)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ok ? Icons.check_circle : Icons.error_outline, size: 16, color: ok ? Colors.greenAccent : Colors.orangeAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('\$ ${result.command}', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!result.started) ...[
              Text('Process failed to start: ${result.startError}', style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
            ] else ...[
              _line('exit code', '${exec!.exitCode}'),
              if (exec.stdout.isNotEmpty) _line('stdout', exec.stdout.trim()),
              if (exec.stderr.isNotEmpty) _line('stderr', exec.stderr.trim(), color: Colors.orangeAccent),
              if (exec.stdout.isEmpty && exec.stderr.isEmpty) _line('output', '(empty)'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value, {Color color = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(color: Colors.grey)),
            TextSpan(text: value, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}
