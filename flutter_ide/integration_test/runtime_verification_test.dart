// GENUINE ON-DEVICE TEST — NOT run by the GitHub Actions CI workflow.
//
// Everything in `test/` (runtime_test.dart, toolchain_manifest_test.dart,
// widget_test.dart) runs via `flutter test` on the Ubuntu CI runner. Those
// prove the Dart *logic* is correct, but `uname`/`sh` on that Ubuntu box
// are Ubuntu's own binaries — they say nothing about whether the same
// code path works inside the actual Android APK sandbox.
//
// This file uses `integration_test`, which compiles into the real APK and
// runs ON a connected Android device/emulator via `adb`. There is no
// GitHub Actions step for this — running an Android emulator in CI is a
// real, heavier undertaking (e.g. reactivecircus/android-emulator-runner)
// deliberately not added here per the instruction to build only the
// minimum required for this phase. To run this for real:
//
//   flutter test integration_test/runtime_verification_test.dart -d <device-id>
//
// (requires the phone connected via adb, or `adb connect` over wifi —
// not always available from a Termux-only, no-laptop setup; the in-app
// "Runtime Verification" screen is the practical equivalent for that
// workflow and requires no adb at all).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:real_buzzing_identifier/core/runtime/native_runtime_environment.dart';
import 'package:real_buzzing_identifier/core/runtime/runtime_verification_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Real command execution inside the actual Android APK sandbox', (tester) async {
    final service = RuntimeVerificationService(NativeRuntimeEnvironment());
    final report = await service.run();

    // A shell must actually resolve on this device — if this fails, no
    // command below could possibly have run through a real shell.
    expect(report.shellUsed, isNotNull, reason: 'No shell resolved on this Android device');

    final byCommand = {for (final r in report.results) r.command: r};

    final uname = byCommand['uname -m']!;
    expect(uname.started, isTrue);
    expect(uname.execResult!.exitCode, 0);
    expect(uname.execResult!.stdout.trim(), isNotEmpty);
    // Print (not hardcode) the real result for the person running this.
    // ignore: avoid_print
    print('REAL uname -m output on this device: "${uname.execResult!.stdout.trim()}"');

    final echo = byCommand['echo hello']!;
    expect(echo.started, isTrue);
    expect(echo.execResult!.exitCode, 0);
    expect(echo.execResult!.stdout.trim(), 'hello');

    final pwd = byCommand['pwd']!;
    expect(pwd.started, isTrue);
    // Whatever the real cwd is — just confirm the shell actually answered.
    expect(pwd.execResult!.stdout.trim(), isNotEmpty);

    final missing = byCommand['flde_this_command_does_not_exist_12345']!;
    expect(missing.started, isTrue, reason: 'the SHELL must start even though the target command does not exist');
    expect(missing.execResult!.exitCode, isNot(0), reason: 'a nonexistent command must produce a real nonzero exit code');
  });
}
