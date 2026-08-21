# FLDE Architecture

## 1. Android runtime model

Android runs on the Linux kernel, but Android **userspace** is not a
conventional Linux distribution — there's no `/bin/bash`-with-coreutils,
no glibc-based dynamic linker guarantees, and critically, SELinux policy
on modern Android (broadly enforced since Android 7+, formalized further
as W^X since Android 10) denies executing files an app wrote into its own
private data directory (`app_data_file` context), independent of `chmod`.
This is documented, common knowledge among Android/Termux-style app
developers — not a bug in this codebase.

## 2. Kernel vs. userspace

- **Kernel**: real, Linux, accessible facts like `/proc/version`,
  `uname -r` — FLDE reads these directly where permitted.
- **Userspace**: Android's own (no standard FHS layout, no system package
  manager, restricted exec). FLDE does not pretend this is a normal Linux
  userland.

## 3. Chosen runtime architecture (Phase 2B)

**`NativeRuntimeEnvironment`**: direct process execution via `dart:io`
`Process`, which itself goes through Android's normal process-creation
path. No PRoot, no bundled userspace, no VM/container.

### Why this first, not PRoot

Per spec section 6, PRoot was not assumed just because Termux uses it.
Direct native execution is strictly simpler, has zero extra licensing
surface, and — critically — is required as a baseline measurement before
any heavier architecture is justified: if direct exec of FLDE-downloaded
binaries turns out to work on a given device, PRoot/userspace-in-a-box is
unnecessary complexity. If it doesn't work (the documented SELinux
restriction above), that tells us exactly what the next architecture must
solve, rather than guessing.

### The experiment (`RuntimeDiagnosticsService`)

Two distinct checks, deliberately kept separate so a failure in one isn't
misreported as the other:

1. **Interpreted execution** — write a script into FLDE's own storage,
   run it via `sh <script>`. This only needs read permission on the file,
   not exec permission, so it's a control test expected to pass broadly.
2. **Direct execution** — write a script, `chmod 755` it, then execute the
   file path directly (relying on the kernel's shebang resolution). This
   is the actual open question for whether a downloaded Dart/Flutter
   binary can run at all without further engineering.

Run **Diagnostics → FLDE Runtime (experimental)** on a real device to see
the actual result — this document does not hardcode an outcome because
only a real device can produce one. If check 2 fails, the documented next
step (NOT implemented yet) is packaging a minimal loader/interpreter as a
`.so` under `android/app/src/main/jniLibs/<abi>/` at APK build time —
Android's PackageManager extracts files under `jniLibs/` with execute
permission specifically because the dynamic linker needs to `dlopen` them.
This only helps for a component fixed at APK-build time, not arbitrary
runtime-downloaded toolchains, so it would only be a partial answer and
needs its own dedicated investigation.

## 4. Supported ABI

Detected dynamically via `uname -m` — never hardcoded. Phase 2B has been
manually verified on `aarch64` (see uploaded diagnostics screenshots);
`armeabi-v7a`/`x86_64` are unverified.

## 5. Storage layout

```
FLDE/
  runtime/{root,bin,lib,etc,tmp,home,usr}/
  toolchains/{dart,flutter,java,gradle,android-sdk}/<version>/
  pub-cache/
  gradle-cache/
  projects/
  downloads/
  temp/
  logs/
```
Resolved at runtime via `path_provider`, never a hardcoded absolute path.

## 6. Process execution model

```
Terminal UI → TerminalService → RuntimeEnvironment → ProcessExecutor → real OS process
```
`RuntimeEnvironment` is an abstract interface specifically so a future
`LinuxUserspaceRuntime` (IF the experiment above shows it's needed) can
be swapped in without changing the terminal, toolchain validator, or
run/build services — they all depend on the interface, not on
`NativeRuntimeEnvironment` directly (`terminal_service.dart` is the
reference example).

Environment variables (`PATH`, `HOME`, `TMPDIR`, `FLDE_HOME`,
`FLDE_RUNTIME`, `JAVA_HOME`, `ANDROID_HOME`, ...) are constructed by
`EnvironmentManager` and only ever set when the underlying
directory/toolchain genuinely exists — see spec section 8's "do not
inject paths for tools that do not exist," which is enforced in code, not
just documentation.

## 7. Current limitations (explicit)

| Item | Status |
|---|---|
| Direct exec of FLDE-private files | **UNVERIFIED** — run Diagnostics on your device for the real answer |
| PRoot / Linux userspace-in-a-box | NOT IMPLEMENTED — deferred pending the experiment above |
| Dart SDK execution | NOT YET ATTEMPTED — no manifest source configured (spec forbids guessing URLs) |
| Flutter/Java/Gradle/Android SDK execution | NOT TESTED |
| Application UID / native library dir | NOT IMPLEMENTED — requires a Kotlin MethodChannel not yet added |
| Dynamic linker behavior (ELF compatibility) | NOT TESTED — requires a real compiled test binary, which needs a build step this phase doesn't include |
| Process groups / child-process trees (e.g. future `flutter run` spawning `dart`+`gradle`+`java`) | Architecture (`ProcessSession`/`RunManager`) exists from Phase 2A; multi-child lifecycle not exercised yet |

## 8. Dart experiment results

Not yet run — blocked on having a real, verified Dart SDK download source
(spec section 27: no guessed URLs). Once a manifest entry with a genuine
`downloadUrl`/`sha256` is added, `ToolchainDownloader` → the direct-exec
check above → `dart --version` is the concrete path to a real result.

## 9. Flutter status

Not tested. Blocked on the same manifest-source gap, and additionally on
whatever the Dart direct-exec experiment reveals (Flutter's toolchain has
a strictly larger exec/process-tree surface than Dart alone).

## 10. Future runtime roadmap

1. Run the direct-exec experiment on real hardware, record the result here.
2. If direct exec works: add a real, verified Dart manifest entry and
   attempt `dart --version` end-to-end.
3. If direct exec fails: investigate the `jniLibs`-extraction technique
   for a minimal loader, OR evaluate a proper userspace approach — with
   the same rigor (real compatibility testing, no assumed success) applied
   here.
4. Only after Dart is genuinely working: repeat for Java, then Gradle,
   then Android SDK, then Flutter — per spec section 20's required
   ordering.

## 11. VERIFIED / UNVERIFIED / NOT IMPLEMENTED summary

- **VERIFIED**: system-binary execution (`uname`, `sh` resolution),
  `/proc` partial availability, stdout/stderr/exit-code plumbing, real
  toolchain absence detection (Dart/Flutter/Java/Git/Gradle correctly
  report "not installed" rather than fabricating a version).
- **UNVERIFIED**: direct exec of FLDE-private files (device-dependent —
  run Diagnostics to find out on yours).
- **NOT IMPLEMENTED**: any actual toolchain install (manifest is
  deliberately empty), Flutter visual preview, PRoot/userspace runtime,
  Android SDK directory validation, application UID/native-lib-dir
  reporting.
