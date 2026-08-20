class ProcessResultModel {
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;

  const ProcessResultModel({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
  });

  bool get succeeded => exitCode == 0;
}

class ProcessLine {
  final String text;
  final bool isError;

  const ProcessLine(this.text, {this.isError = false});
}
