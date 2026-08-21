# FLDE — Phase 2

Mobile-first Flutter/Dart IDE for Android. Phase 2 adds a real local
development runtime foundation on top of Phase 1's explorer/editor.

## What's real right now

| Capability | Status |
|---|---|
| File explorer, editor, ZIP import (Phase 1) | Real |
| Toolchain detection (Flutter/Dart/Java/Git/Gradle) | Real — resolves FLDE-managed installs first, falls back to system PATH, never fabricates a version |
| Toolchain Manager / Downloader / Validator | Real architecture — download → sha256 verify → extract → validate → mark installed. **Ships with an empty manifest — no SDK download URLs are hardcoded yet.** Install buttons stay disabled until real, versioned sources are added. |
| Integrated terminal | Real — every command runs as an actual OS process via `ProcessExecutor`, streamed live. Not a shell (no globbing/pipes) — runs the exact binary named. |
| Storage manager | Real — computes actual on-disk usage of FLDE's managed directories (`toolchains/`, `pub-cache/`, `gradle-cache/`, `projects/`, `downloads/`, `temp/`). Device-level free space is explicitly marked **not yet implemented** (needs a platform channel we haven't added) rather than guessed. |
| Connectivity check | Real — actual DNS lookup, not a "connected to WiFi" flag |
| Diagnostics screen | Real — architecture via `uname -m`, live toolchain validation, honest OFFLINE READY / LIMITED banner |
| USB/external storage project import | Real — Storage Access Framework via `file_picker`, reuses the existing file service |
| Pub foundation (`pub get`/`add`/`upgrade`/`remove`) | Real, runs actual Flutter/Dart. Package **search** is deliberately `UnimplementedError` — not faked. |
| Run foundation (`flutter run`, hot reload/restart) | Real process orchestration. **UNVERIFIED**: whether `flutter run` can attach to a usable target from inside FLDE's own Android sandbox hasn't been tested yet. |
| APK build foundation (`flutter build apk`) | Real — success is only reported if the output `.apk` file actually exists on disk afterward, not just from exit code 0 |

## Not built yet

Flutter visual preview, widget inspector, full GitHub integration, package
search UI, debugger, command palette, themes engine. See `SPEC.md` (Phase 1)
and the Phase 2 brief for the complete target.

## Storage layout

```
FLDE/
  toolchains/{dart,flutter,java,gradle,android-sdk}/<version>/
  pub-cache/
  gradle-cache/
  projects/
  downloads/
  temp/
```
Resolved at runtime via `path_provider` — never a hardcoded absolute path.

## Toolchain sources

`ToolchainManifestLoader` reads `FLDE/toolchains/manifest.json`, which is
created empty on first launch. **No Flutter/Dart/JDK/Gradle/Android SDK
distribution URLs are hardcoded in this codebase.** Deciding official,
versioned, checksummed sources (GitHub Releases, a CDN, etc.) is explicit
future work — see `ToolchainManifestEntry` for the exact contract a real
entry needs (`downloadUrl`, `sha256`, `sizeBytes`, `dependencies`).

## Offline mode

`DiagnosticsService` reports `OFFLINE DEVELOPMENT READY` only when the
toolchains actually required (currently: Dart) are genuinely installed and
validated right now — never inferred from having been online recently.

## Terminal

Runs real processes with FLDE's own constructed `PATH`/`PUB_CACHE`/
`GRADLE_USER_HOME` environment (see `EnvironmentManager`), so once real
toolchains are installed, commands resolve to FLDE-managed binaries before
falling back to anything on the device's system PATH.

## Limitations (explicit, per Phase 2 rules)

- No toolchain can currently be installed — the manifest is empty on
  purpose. Detection of *already-installed* system tools (e.g. via Termux)
  still works.
- Device-level free storage isn't reported (only per-category usage of
  FLDE's own managed folders).
- `flutter run`/hot reload against a real target from inside the app
  sandbox is unverified.
- Package search is not implemented (throws `UnimplementedError`).
- Android SDK "installed" validation is a placeholder — it currently always
  reports not-installed with an explicit "not yet implemented" message
  rather than checking real directories.

## Setup (Termux + GitHub Actions, no laptop)

The GitHub Actions workflow (`.github/workflows/build.yml`) runs
`flutter create` to generate `android/`/`ios/`/etc. on first run, then
`flutter analyze` (now fatal — no more `|| true` hiding real errors),
then builds and uploads a debug APK artifact.
