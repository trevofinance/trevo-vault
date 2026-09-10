#!/usr/bin/env bash
set -euo pipefail

# Checks every 64-bit native library in an Android App Bundle. Google Play
# requires each ELF PT_LOAD segment to be aligned to at least 16 KB.

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 path/to/app.aab" >&2
  exit 2
fi

aab=$1
if [[ ! -f "$aab" ]]; then
  echo "AAB not found: $aab" >&2
  exit 2
fi

readelf=${READELF:-}
if [[ -z "$readelf" ]]; then
  sdk_root=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
  if [[ -z "$sdk_root" && -d "$HOME/Library/Android/sdk" ]]; then
    sdk_root="$HOME/Library/Android/sdk"
  fi

  if [[ -n "$sdk_root" && -d "$sdk_root/ndk" ]]; then
    while IFS= read -r candidate; do
      readelf=$candidate
    done < <(find "$sdk_root/ndk" -path '*/toolchains/llvm/prebuilt/*/bin/llvm-readelf' \( -type f -o -type l \) 2>/dev/null | sort)
  fi
fi

if [[ -z "$readelf" || ! -x "$readelf" ]]; then
  echo "llvm-readelf not found. Set ANDROID_SDK_ROOT, ANDROID_HOME, or READELF." >&2
  exit 2
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/trevo-aab-alignment.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
unzip -qq "$aab" 'base/lib/*/*.so' -d "$work_dir"

checked=0
failed=0
for abi in arm64-v8a x86_64; do
  lib_dir="$work_dir/base/lib/$abi"
  [[ -d "$lib_dir" ]] || continue

  while IFS= read -r -d '' library; do
    checked=$((checked + 1))
    while IFS= read -r alignment; do
      if (( alignment < 0x4000 )); then
        echo "ERROR: base/lib/$abi/$(basename "$library") has PT_LOAD alignment $alignment (requires >= 0x4000)" >&2
        failed=$((failed + 1))
      fi
    done < <("$readelf" --program-headers --wide "$library" | awk '$1 == "LOAD" { print $NF }')
  done < <(find "$lib_dir" -type f -name '*.so' -print0)
done

if (( checked == 0 )); then
  echo "No 64-bit native libraries found in $aab" >&2
  exit 1
fi

if (( failed > 0 )); then
  echo "16 KB alignment check failed: $failed misaligned PT_LOAD segment(s)" >&2
  exit 1
fi

echo "16 KB alignment verified for $checked 64-bit native libraries"
