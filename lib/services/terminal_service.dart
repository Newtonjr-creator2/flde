import 'dart:async';
import 'dart:io';
import '../core/runtime/process_executor.dart';
import '../models/process_result.dart';

class TerminalService {
  ProcessSession? _session;
  String? _workingDirectory;

  Stream<ProcessLine> execute(
    String command, {
    String? workingDirectory,
  }) async* {
    final parts = _splitCommand(command);
    if (parts.isEmpty) return;

    if (parts.first == 'cd') {
      final target = parts.length == 1
          ? Directory(Platform.environment['HOME'] ?? '/').path
          : parts[1];
      final base = _workingDirectory ?? Directory.current.path;
      final candidate = Directory(
        target.startsWith('/') ? target : '$base/${target}',
      );
      if (await candidate.exists()) {
        _workingDirectory = candidate.absolute.path;
        yield 'Changed directory to $_workingDirectory';
      } else {
        yield 'cd: no such directory: $target';
      }
      return;
    }

    _session = await ProcessExecutor.start(
      parts.first,
      parts.skip(1).toList(),
      workingDirectory: _workingDirectory,
    );
    final session = _session!;
    await for (final line in session.output) {
      yield line;
    }
    await session.exitCode;
    _session = null;
  }

  Future<void> stop() async {
    await _session?.stop();
  }

  List<String> _splitCommand(String input) {
    final result = <String>[];
    final buffer = StringBuffer();
    var quote = '';
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if ((c == '"' || c == "'")) {
        if (quote.isEmpty) {
          quote = c;
          continue;
        }
        if (quote == c) {
          quote = '';
          continue;
        }
      }
      if (c == ' ' && quote.isEmpty) {
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(c);
      }
    }
    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }
}
