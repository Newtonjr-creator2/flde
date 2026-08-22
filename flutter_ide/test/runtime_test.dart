import 'package:flutter_test/flutter_test.dart';
import 'package:real_buzzing_identifier/core/runtime/native_runtime_environment.dart';
import 'package:real_buzzing_identifier/core/runtime/process_executor.dart';
import 'package:real_buzzing_identifier/core/runtime/runtime_environment.dart';

/// These are genuine integration tests — they spawn real OS processes on
/// whatever machine runs `flutter test` (the CI runner or a real device).
/// `uname` and `sh` exist on both Linux CI runners and Android, so this
/// exercises the actual code path without needing a mock.
void main() {
  group('ProcessExecutor (real processes)', () {
    test('running uname -m returns real, non-empty output', () async {
      final result = await ProcessExecutor.run('uname', ['-m']);
      expect(result.succeeded, isTrue);
      expect(result.stdout.trim(), isNotEmpty);
    });

    test('a nonexistent binary fails cleanly rather than throwing unhandled', () async {
      final result = await ProcessExecutor.run('flde_definitely_not_a_real_binary', []);
      expect(result.succeeded, isFalse);
    });
  });

  group('NativeRuntimeEnvironment (real runtime)', () {
    final runtime = NativeRuntimeEnvironment();

    test('isAvailable reflects a genuine capability probe', () async {
      final availability = await runtime.isAvailable();
      expect(availability, isNot(RuntimeAvailability.unknown));
    });

    test('resolveShell finds a real shell on the test runner', () async {
      final shell = await runtime.resolveShell();
      expect(shell, isNotNull);
    });

    test('execute runs a real command through the runtime abstraction', () async {
      final result = await runtime.execute('uname', ['-a']);
      expect(result.succeeded, isTrue);
      expect(result.stdout, isNotEmpty);
    });
  });
}
