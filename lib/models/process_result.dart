/// Result of a real process execution. Every field here is populated from
/// an actual `dart:io` Process run — never fabricated or guessed.
class ExecResult {
  final String command;
  final List<String> arguments;
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;
  final bool timedOut;

  const ExecResult({
    required this.command,
    required this.arguments,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
    this.timedOut = false,
  });

  bool get succeeded => exitCode == 0 && !timedOut;

  String get commandLine => '$command ${arguments.join(' ')}'.trim();

  @override
  String toString() =>
      '\$ $commandLine\n(exit $exitCode, ${duration.inMilliseconds}ms)\n$stdout${stderr.isNotEmpty ? '\nstderr: $stderr' : ''}';
}
