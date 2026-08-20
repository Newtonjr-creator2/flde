# RealBuzzingIdentifier — Phase 1

Mobile-first Flutter/Dart IDE for Android. This is the **first real,
working slice** toward the full spec in `SPEC.md` — not a mockup.

## What's real right now

| Capability | Status |
|---|---|
| Create Flutter project (`flutter create`) | Real — runs the actual binary; falls back to a labeled Dart-only skeleton if Flutter isn't installed on-device |
| Open existing project (SAF folder picker) | Real |
| Import project from ZIP | Real — actual archive extraction via `archive` package |
| File explorer (list/create/rename/delete/duplicate) | Real — `dart:io` |
| Code editor (open/edit/save) | Real — reads/writes actual file bytes |
| Syntax highlighting (Dart/YAML/JSON/Markdown/XML/Gradle/Bash) | Real — `highlight` package tokenizer |
| Recursive project search | Real |
| Toolchain detection (Flutter/Dart/Git present?) | Real — probes actual binaries, never fabricates a version |
| Cloud APK build | Real — GitHub Actions workflow at `.github/workflows/build.yml` |

## Not built yet (do not assume these work)

Terminal, package manager UI, Git/GitHub client, hot reload, Flutter visual
preview, widget inspector, debugger, local APK build, multi-tab/split
editing, command palette, themes engine, AI assistant. See `SPEC.md` for
the full target and `ROADMAP.md` for phase order.

## Setup (you have no laptop — do this from Termux + GitHub Actions)

```bash
# In Termux, once, to generate android/ (needs a working flutter on the runner
# or in Termux itself — the project has no android/ios folders committed yet):
flutter create --org com.vyomquantum --project-name real_buzzing_identifier .
flutter pub get
```

If you don't have Flutter installed in Termux, skip local `flutter create`
entirely — the GitHub Actions workflow does it for you on first push (see
`build.yml`), and uploads a debug APK as a build artifact you can download
from the Actions tab.

## Run locally (if you ever have a machine with Flutter)

```bash
flutter pub get
flutter run
```
