#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/assets/runtime"
mkdir -p "$OUT"

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-}}"
if [[ -z "$NDK" || ! -d "$NDK" ]]; then
  if [[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME/ndk" ]]; then
    NDK="$(find "$ANDROID_HOME/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
  fi
fi

if [[ -z "$NDK" || ! -d "$NDK" ]]; then
  echo "Android NDK not found. Set ANDROID_NDK_HOME or install an NDK." >&2
  exit 1
fi

HOST_TAG=""
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) HOST_TAG="linux-x86_64" ;;
  Darwin-arm64|Darwin-aarch64) HOST_TAG="darwin-arm64" ;;
  Darwin-x86_64) HOST_TAG="darwin-x86_64" ;;
  *) echo "Unsupported NDK host: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

CLANG="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/aarch64-linux-android24-clang"
if [[ ! -x "$CLANG" ]]; then
  echo "ARM64 Android clang not found: $CLANG" >&2
  exit 1
fi

"$CLANG" \
  -O2 \
  -fPIE -pie \
  "$ROOT/tooling/runtime_probe/runtime_probe.c" \
  -o "$OUT/runtime_probe_arm64-v8a"

chmod 755 "$OUT/runtime_probe_arm64-v8a"
file "$OUT/runtime_probe_arm64-v8a" || true
echo "Built $OUT/runtime_probe_arm64-v8a"
