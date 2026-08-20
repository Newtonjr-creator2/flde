# FLDE — Phase 2

FLDE (Flutter Lightweight Development Environment) is an Android-first mobile IDE foundation.

Phase 2 adds real runtime infrastructure instead of pretending that an SDK exists:

- FLDE-managed storage
- toolchain manifest model
- HTTPS archive download
- SHA-256 verification
- ZIP extraction
- actual toolchain validation
- process execution with FLDE environment variables
- integrated terminal
- diagnostics
- offline/online probe
- project run/build foundation
- pub command foundation
- USB/SAF project import foundation

## Critical runtime reality

The APK does **not** embed the complete Flutter/Android development stack.

More importantly, a normal official Flutter SDK archive commonly contains binaries built for a desktop Linux host. Android cannot automatically execute those binaries merely because they were downloaded into the APK's private storage.

Therefore Phase 2 deliberately validates the executable after installation. Extraction success is not treated as runtime success.

The architecture leaves room for a later Android-compatible Linux userspace/runtime layer if experiments show that direct execution is insufficient.

## Managed storage

The app creates an application-private FLDE directory containing:

```text
FLDE/
  toolchains/
  downloads/
  temp/
  projects/
  pub-cache/
  gradle-cache/
```

The exact absolute path is discovered at runtime with `path_provider`.

## Toolchain installation

The Toolchains screen accepts a real HTTPS ZIP archive and its SHA-256 checksum.

Installation:

```text
download
  -> temporary .part file
  -> SHA-256 verification
  -> ZIP extraction
  -> installation marker
  -> executable/filesystem validation
  -> installed status
```

No download URL or version is fabricated.

The current UI intentionally asks for the source URL because Phase 2 does not invent unofficial mirrors.

## Terminal

The terminal executes real processes through `Process.start`.

It prepares:

- PATH
- FLDE_HOME
- PUB_CACHE
- GRADLE_USER_HOME
- FLDE_TOOLCHAINS

Terminal output is not simulated.

## USB / external storage

USB OTG is treated as a project/file transport.

FLDE uses Android's file picker / Storage Access Framework entry point where available. The user can select a project directory or ZIP and import it into FLDE-managed project storage.

FLDE does not automatically execute SDK binaries directly from a USB drive.

## Current limitations

Not yet complete:

- Android-compatible Flutter runtime
- local Flutter engine/VM integration
- graphical Flutter preview
- widget inspector
- debugger
- hot reload transport
- GitHub OAuth/client
- full pub.dev package browser
- full shell emulator
- Gradle/Android SDK installation recipes
- desktop-class multi-cursor editor

These are intentionally not represented as complete.

## Build

The repository intentionally does not commit generated Android/iOS platform folders. The GitHub Actions workflow generates Android scaffolding and builds a debug APK.

Local build requires Flutter.

```bash
flutter pub get
flutter analyze
flutter build apk --debug
```
