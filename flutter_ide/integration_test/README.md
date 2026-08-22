# On-device integration tests (Phase 2C)

Tests here run **inside the real Android APK** on a connected device or
emulator — unlike everything in `/test`, which runs on whatever machine
executes `flutter test` (Ubuntu, in CI).

## Why these aren't in the GitHub Actions workflow

`ubuntu-latest` has no Android device or emulator attached, so `adb`
cannot reach anything. Adding one (e.g. via
`reactivecircus/android-emulator-runner`) is a real, separate undertaking
— slower CI, more moving parts — deliberately left out per "build the
minimum required for this phase."

## How to actually run this

From a machine with the Android SDK/adb and a connected device:

```bash
flutter test integration_test/runtime_verification_test.dart -d <device-id>
```

If you're doing everything from Termux with no laptop, this specific
command likely isn't practical for you (no local adb toolchain). The
in-app **Runtime Verification** screen (Diagnostics is separate — look
for the ▶ icon on the home screen) exercises the exact same
`RuntimeVerificationService` and requires nothing but installing and
opening the APK — that's the realistic verification path for your setup.
