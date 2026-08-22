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

## 3. Android runtime model and current implementation

**`NativeRuntimeEnvironment` + Android system-linker execution**

Direct `dart:io` execution is still used for Android/system executables such as
`uname` and `sh`. However, FLDE-managed ELF executables are now launched
through Android's own 64-bit dynamic linker:

```
FLDE-managed ELF
      ↓
/system/bin/linker64 <elf> [args...]
      ↓
Android dynamic linker
      ↓
FLDE ELF process
```

This is the important Termux-style mechanism for Android app-data execution:
the Android process API creates the **system linker** process, and the linker
loads the target ELF. FLDE does not rely on `chmod +x` making an app-data ELF
directly executable.

`SystemLinkerLauncher` deliberately accepts only ELF files located under
FLDE's managed storage root. Arbitrary paths are rejected.

The runtime still has no PRoot, VM, or general Linux distribution. That is
intentional: this first implementation isolates the execution restriction
without adding a much larger compatibility layer.

### Runtime proof

`tooling/runtime_probe/runtime_probe.c` is compiled as an ARM64 Android PIE
during CI. The resulting ELF is bundled as a Flutter asset. On first
diagnostics execution FLDE copies it into its managed runtime directory and
invokes it through `SystemLinkerLauncher`.

The probe calls the real `uname()` API itself and prints:

```
FLDE_RUNTIME_PROBE_OK
machine=<kernel-reported architecture>
```

Therefore the successful result proves more than `/system/bin/uname`: code
provided by FLDE was loaded and executed as a native process on the Android
device.

The probe is ARM64-only in this iteration. Non-ARM64 devices are reported as
unsupported rather than pretending compatibility.

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

## 7. Current runtime status

| Capability | Status |
|---|---|
| Android system-binary execution | **VERIFIED** |
| Direct execution of FLDE-private files | **KNOWN TO FAIL on the tested device** |
| Android system-linker ELF execution | **IMPLEMENTED — requires physical-device verification** |
| ARM64 runtime probe build | **IMPLEMENTED in CI** |
| ARM64 runtime probe execution | **PENDING physical-device test after this build** |
| PRoot / VM | NOT IMPLEMENTED |
| Full Linux userspace | NOT IMPLEMENTED |
| Dart SDK execution | NOT YET IMPLEMENTED |
| Flutter execution | NOT YET IMPLEMENTED |
| Java/JDK execution | NOT YET IMPLEMENTED |
| Gradle execution | NOT YET IMPLEMENTED |
| Android SDK execution | NOT YET IMPLEMENTED |

## 8. Toolchain execution implications

Toolchain validation now goes through `RuntimeEnvironment` rather than calling
`ProcessExecutor` directly. When a resolved executable is an ELF inside FLDE
managed storage, `NativeRuntimeEnvironment` can route it through the system
linker automatically.

This is intentionally different from declaring a toolchain installed merely
because an archive was downloaded. A toolchain remains unverified until its
real version command exits successfully.

The next toolchain should be **Android-compatible ARM64 Dart**, not an arbitrary
desktop Linux Dart archive. The package must have compatible ELF/Bionic
dependencies and be tested through the new runtime.

## 9. Userspace roadmap

After the linker proof succeeds, build the smallest useful FLDE userspace:

```
FLDE/
  runtime/
    bin/
    lib/
    etc/
    tmp/
    home/
    usr/
  toolchains/
  projects/
  pub-cache/
  gradle-cache/
```

The runtime environment should then provide a controlled `PATH`, `HOME`,
`TMPDIR`, library paths, and tool-specific variables.

A Termux-style `LD_PRELOAD`/exec compatibility layer is a later step if
child-processes or shell scripts require it. It is not required for the first
ELF proof.

## 10. Toolchain order

1. Android ARM64 runtime probe
2. Android-compatible ARM64 Dart
3. Git
4. JDK
5. Gradle
6. Android SDK command-line tools
7. Flutter

Flutter is deliberately last because its host-tool and process-tree
requirements are substantially larger than Dart's.

## 11. Security requirements

The runtime launcher:

- accepts only ELF files;
- accepts only paths inside FLDE managed storage;
- uses a fixed set of Android linker paths;
- never constructs linker paths from downloaded metadata;
- does not treat `chmod +x` as proof of executability.

The existing toolchain downloader already verifies SHA-256 before extraction.
Archive extraction still needs path-traversal hardening before accepting
untrusted package sources.

## 12. Verified / unverified summary

- **VERIFIED:** Android system binaries execute through Dart `Process`.
- **VERIFIED:** the tested device reports `aarch64` dynamically through
  `uname -m`.
- **VERIFIED:** FLDE app storage is writable.
- **VERIFIED on the tested device:** direct execution of a FLDE-created file
  fails with permission denied.
- **IMPLEMENTED:** Termux-style Android system-linker launcher for
  FLDE-managed ELF files.
- **IMPLEMENTED:** ARM64 native runtime probe and CI build step.
- **PENDING:** physical-device execution of that probe.
- **NOT IMPLEMENTED:** complete Termux-compatible userspace, package
  repository, or all six development toolchains.


## 2026-08 Android runtime/workbench direction

The physical-device runtime probe established that FLDE-owned ARM64 ELF files can be executed from app-managed storage when Android's `/system/bin/linker64` is the process executable and the FLDE ELF is passed as the linker target. Direct `execve` of the same private file remains denied on the tested device.

FLDE therefore uses a Termux-style Android-bionic userspace model without requiring PRoot or a VM:

- managed prefix under FLDE application storage;
- `/system/bin/linker64` for managed ELF launch;
- generated shell launchers in `runtime/bin/` so `/system/bin/sh -c` can resolve managed commands without direct-exec of the private ELF;
- `LD_LIBRARY_PATH` pointing at FLDE-managed libraries;
- rewritten Termux wrapper scripts whose original `/data/data/com.termux/files/usr` prefix would otherwise point at another application's sandbox;
- real shell semantics for the integrated terminal;
- verified, checksummed package manifests rather than arbitrary Linux desktop binaries.

### Flutter host compatibility

The official Flutter SDK documentation describes the SDK and CLI, but the official Linux host SDK is not an Android-bionic host distribution. FLDE must therefore use an Android-bionic ARM64 Flutter build (or build one itself) rather than downloading a normal Linux/glibc archive and hoping it executes. The current manifest references a known ARM64 Termux-compatible Flutter build and a Termux-compatible Android SDK package, both with pinned SHA-256 values. These sources are treated as bootstrap inputs, not as proof of successful FLDE installation; physical-device validation remains authoritative.

The APK intentionally does not bundle the full Flutter + Android SDK + NDK stack. That stack is measured in hundreds of megabytes to multiple gigabytes and includes components with their own licensing/distribution conditions. FLDE downloads the selected packages after installation, verifies them, adapts their Termux prefix to FLDE's managed prefix, and then validates the resulting commands before marking a toolchain installed.

### Editor workbench

The main project screen is a mobile VS-Code-style workbench using Monaco Editor (the editor engine used by VS Code) inside Android WebView. The workbench contains an activity bar, Explorer, tabs, Monaco editor, integrated terminal, run/build actions, and status bar. FLDE branding and mobile layout remain distinct from Microsoft's product UI.
