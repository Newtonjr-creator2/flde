import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/process_result.dart';
import 'process_executor.dart';

/// Launches Android-compatible ELF files through Android's own dynamic
/// linker. This is the same fundamental execution mechanism used by
/// Termux-style runtimes: the kernel executes the system linker, and the
/// linker loads the target ELF from FLDE's managed filesystem.
///
/// This is intentionally limited to FLDE-managed paths and ELF files.
/// Arbitrary paths are never passed through this launcher.
class SystemLinkerLauncher {
  final Directory managedRoot;

  SystemLinkerLauncher(this.managedRoot);

  static const _linkerCandidates = <String>[
    '/system/bin/linker64',
    '/apex/com.android.runtime/bin/linker64',
  ];

  Future<String?> resolveLinker() async {
    for (final candidate in _linkerCandidates) {
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  Future<bool> canLaunch(File executable) async {
    if (!await executable.exists()) return false;
    if (!_isInsideManagedRoot(executable.path)) return false;
    return _isElf(executable);
  }

  Future<ExecResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final file = File(executable);
    if (!await canLaunch(file)) {
      return ExecResult(
        command: executable,
        arguments: arguments,
        exitCode: -1,
        stdout: '',
        stderr: 'System-linker launch rejected: path is outside FLDE managed '
            'storage or is not an ELF executable.',
        duration: Duration.zero,
      );
    }

    final linker = await resolveLinker();
    if (linker == null) {
      return ExecResult(
        command: executable,
        arguments: arguments,
        exitCode: -1,
        stdout: '',
        stderr: 'Android 64-bit dynamic linker not found on this device.',
        duration: Duration.zero,
      );
    }

    // The target ELF is argv[1]. The system linker becomes the actual
    // executable created by Android's process API.
    return ProcessExecutor.run(
      linker,
      [executable, ...arguments],
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: timeout,
    );
  }

  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final file = File(executable);
    if (!await canLaunch(file)) {
      throw ProcessException(
        executable,
        arguments,
        'System-linker launch rejected: not an FLDE-managed ELF.',
        -1,
      );
    }

    final linker = await resolveLinker();
    if (linker == null) {
      throw ProcessException(linker ?? 'linker64', const [], 'Android linker64 not found.', -1);
    }

    return ProcessExecutor.start(
      linker,
      [executable, ...arguments],
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  bool _isInsideManagedRoot(String path) {
    final root = _canonical(managedRoot.path);
    final candidate = _canonical(path);
    return candidate == root || candidate.startsWith('$root${Platform.pathSeparator}');
  }

  String _canonical(String path) => p.normalize(path).replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');

  Future<bool> _isElf(File file) async {
    try {
      final bytes = await file.openRead(0, 4).fold<List<int>>(
        <int>[],
        (previous, chunk) => previous..addAll(chunk),
      );
      return bytes.length == 4 &&
          bytes[0] == 0x7f &&
          bytes[1] == 0x45 &&
          bytes[2] == 0x4c &&
          bytes[3] == 0x46;
    } catch (_) {
      return false;
    }
  }
}
