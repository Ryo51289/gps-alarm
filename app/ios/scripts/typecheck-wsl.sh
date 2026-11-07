#!/usr/bin/env bash
# Swift typecheck of NapStopCore + Runner against the Darwin SDK of xtool, inside WSL (docs/specs/T01.2.md §8;
# PLAN-ios §6.3, layer L2). From Git Bash:
#   MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -e bash /mnt/d/work/gps-alarm/app/ios/scripts/typecheck-wsl.sh [--self-test]
#
# For arm64-apple-ios16.0 and arm64-apple-ios16.0-simulator: `swiftc -emit-module` for the NapStopCore targets in
# dependency order (Trip, TripRuntime, NapStopIOS; a target whose directory does not exist yet is "skipped"), then
# `swiftc -typecheck` of every Swift file under app/ios/Runner, without and with -D NAPSTOP_DIAG. --self-test adds a
# broken file to a copy of Runner and must see the compiler fail. (Until T23.2 a stub of the Google map SDK was emitted
# too; the app no longer links any Google Maps SDK, ADR-002.)
#
# Limits: this does not replace the CI build (L3). It does not read project.pbxproj, does not link, does not extract
# App Intents metadata, does not check RunnerTests (needs XCTest), and Swift settings of Package.swift other than
# swiftLanguageMode(.v5) are not applied. The xtool SDK (27.1) may differ from the Xcode SDK of the CI runner
# (T17 RK-T17-6).
#
# Environment (defaults in brackets):
#   NAPSTOP_SWIFT_BIN            [$HOME/opt/swift-6.4.1/usr/bin], must be Swift 6.4.1
#   NAPSTOP_IPHONEOS_SDK         iPhoneOS*.sdk     [newest under $HOME/.xtool, $HOME/.swiftpm/swift-sdks]
#   NAPSTOP_IPHONESIM_SDK        iPhoneSimulator*.sdk [same]
#   NAPSTOP_FLUTTER_XCFRAMEWORK  [/mnt/d/src/flutter/bin/cache/artifacts/engine/ios/Flutter.xcframework]
#                                (Windows: `flutter precache --ios`)
#   NAPSTOP_SCRATCH              [$HOME/.cache/napstop/typecheck]
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 2
}

self_test=false
case "${1:-}" in
  '') ;;
  --self-test) self_test=true ;;
  -h | --help)
    sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d'
    exit 0
    ;;
  *) die "usage: typecheck-wsl.sh [--self-test]" ;;
esac

ios_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_dir="$ios_dir/Core"
runner_dir="$ios_dir/Runner"

swift_bin="${NAPSTOP_SWIFT_BIN:-$HOME/opt/swift-6.4.1/usr/bin}"
swiftc="$swift_bin/swiftc"
[ -x "$swiftc" ] || die "no swiftc in $swift_bin (set NAPSTOP_SWIFT_BIN)"
version="$("$swiftc" --version 2>&1)"
grep -qF 'Swift version 6.4.1' <<<"$version" || die "Swift 6.4.1 required, found: $(head -n 1 <<<"$version")"
head -n 1 <<<"$version"

# Newest SDK named <prefix><version>.sdk (or <prefix>.sdk when no versioned one exists).
find_sdk() {
  local prefix="$1" roots=() r found
  for r in "$HOME/.xtool" "$HOME/.swiftpm/swift-sdks"; do [ -d "$r" ] && roots+=("$r"); done
  [ "${#roots[@]}" -gt 0 ] || return 0
  found="$(find "${roots[@]}" -maxdepth 8 -name "${prefix}[0-9]*.sdk" 2>/dev/null | sort -V | tail -n 1)"
  [ -n "$found" ] || found="$(find "${roots[@]}" -maxdepth 8 -name "${prefix}.sdk" 2>/dev/null | sort | tail -n 1)"
  printf '%s' "$found"
}

device_sdk="${NAPSTOP_IPHONEOS_SDK:-$(find_sdk iPhoneOS)}"
sim_sdk="${NAPSTOP_IPHONESIM_SDK:-$(find_sdk iPhoneSimulator)}"
[ -n "$device_sdk" ] && [ -d "$device_sdk" ] || die "no iPhoneOS SDK found (set NAPSTOP_IPHONEOS_SDK; xtool setup installs one)"
[ -n "$sim_sdk" ] && [ -d "$sim_sdk" ] || die "no iPhoneSimulator SDK found (set NAPSTOP_IPHONESIM_SDK)"
echo "iPhoneOS SDK:        $device_sdk"
echo "iPhoneSimulator SDK: $sim_sdk"

# The Apple Swift resources (SwiftShims, Darwin overlays) sit next to the SDKs in the xtool bundle:
# <bundle>/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/<sdk> -> <bundle>/Developer/Toolchains/...
resource_dir="${NAPSTOP_SWIFT_RESOURCE_DIR:-$(cd "$device_sdk/../../../../.." && pwd)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift}"
[ -d "$resource_dir/iphoneos" ] || die "no Apple Swift resource dir (with iphoneos/) at $resource_dir (set NAPSTOP_SWIFT_RESOURCE_DIR)"
echo "Swift resources:     $resource_dir"
# Same extra options as the toolset.json of the xtool Swift SDK.
common_flags=(-resource-dir "$resource_dir" -Xfrontend -enable-cross-import-overlays)

xcframework="${NAPSTOP_FLUTTER_XCFRAMEWORK:-/mnt/d/src/flutter/bin/cache/artifacts/engine/ios/Flutter.xcframework}"
[ -d "$xcframework" ] || die "no Flutter.xcframework at $xcframework (run 'flutter precache --ios', or set NAPSTOP_FLUTTER_XCFRAMEWORK)"
device_slice="$xcframework/ios-arm64"
sim_slice="$(find "$xcframework" -mindepth 1 -maxdepth 1 -type d -name 'ios-*simulator*' | sort | head -n 1)"
[ -d "$device_slice/Flutter.framework" ] || die "no ios-arm64 slice in $xcframework"
[ -n "$sim_slice" ] && [ -d "$sim_slice/Flutter.framework" ] || die "no simulator slice in $xcframework"
echo "Flutter.xcframework: $xcframework"

[ -f "$runner_dir/GeneratedPluginRegistrant.h" ] ||
  die "no Runner/GeneratedPluginRegistrant.h (gitignored, written by 'flutter pub get' in app/)"

scratch="${NAPSTOP_SCRATCH:-$HOME/.cache/napstop/typecheck}"
mkdir -p "$scratch"

# Package.swift flattened to one target declaration per line, for the language mode lookup.
package_swift="$core_dir/Package.swift"
[ -f "$package_swift" ] || die "no $package_swift"
package_flat="$(tr '\n' ' ' <"$package_swift" |
  sed -E 's/\.(target|testTarget|executableTarget|binaryTarget|systemLibrary|macro|plugin)\(/\n&/g')"

# 5 when the target (or the whole package) declares Swift language mode 5, else 6 (tools version 6.0 default).
language_mode() {
  local decl
  decl="$(grep -E "^\.(target|executableTarget)\( *name: *\"$1\"" <<<"$package_flat" || true)"
  if [ -z "$decl" ]; then
    echo "warning: target $1 not found in Package.swift; assuming Swift 6 mode" >&2
    echo 6
  elif grep -qE 'swiftLanguageMode\( *\.v5 *\)' <<<"$decl"; then
    echo 5
  elif grep -qE 'swiftLanguageModes: *\[ *\.v5' <<<"$package_flat"; then
    echo 5
  else
    echo 6
  fi
}

failures=0
results=()

# run <label> <log> <cmd...>: runs, records "<label>: OK (<n> warnings)" or FAILED, never exits.
run() {
  local label="$1" log="$2" rc warnings
  shift 2
  set +e
  "$@" >"$log" 2>&1
  rc=$?
  set -e
  warnings="$(grep -c ': warning:' "$log" || true)"
  if [ "$rc" -eq 0 ]; then
    results+=("$label: OK ($warnings warnings)")
  else
    results+=("$label: FAILED (exit $rc, $(grep -c ': error:' "$log" || true) errors, $warnings warnings; log $log)")
    failures=$((failures + 1))
    sed -n '1,60p' "$log" >&2
  fi
  return "$rc"
}

# Emits the NapStopCore modules into <out>.
emit_modules() {
  local triple="$1" sdk="$2" out="$3" target mode files
  for target in Trip TripRuntime NapStopIOS; do
    if [ ! -d "$core_dir/Sources/$target" ]; then
      results+=("$triple $target: skipped (no Sources/$target)")
      continue
    fi
    mode="$(language_mode "$target")"
    mapfile -t files < <(find "$core_dir/Sources/$target" -name '*.swift' | sort)
    [ "${#files[@]}" -gt 0 ] || { results+=("$triple $target: skipped (no Swift files)"); continue; }
    run "$triple $target (Swift $mode)" "$out/$target.log" \
      "$swiftc" "${common_flags[@]}" -emit-module -parse-as-library -module-name "$target" -swift-version "$mode" \
      -target "$triple" -sdk "$sdk" -I "$out" -emit-module-path "$out/$target.swiftmodule" "${files[@]}" || true
  done
}

# typecheck_runner <triple> <sdk> <slice> <out> <runner dir> <on|off> <label>
typecheck_runner() {
  local triple="$1" sdk="$2" slice="$3" out="$4" dir="$5" diag="$6" label="$7" files defines=()
  mapfile -t files < <(find "$dir" -name '*.swift' | sort)
  [ "$diag" = on ] && defines=(-D NAPSTOP_DIAG)
  run "$label" "$out/Runner-diag-$diag.log" \
    "$swiftc" "${common_flags[@]}" -typecheck -swift-version 5 -module-name Runner -target "$triple" -sdk "$sdk" \
    -I "$out" -F "$slice" -import-objc-header "$dir/Runner-Bridging-Header.h" \
    "${defines[@]+"${defines[@]}"}" "${files[@]}"
}

if [ "$self_test" = true ]; then
  triple=arm64-apple-ios16.0
  out="$scratch/self-test"
  rm -rf "$out"
  mkdir -p "$out/Runner"
  emit_modules "$triple" "$device_sdk" "$out"
  cp -R "$runner_dir/." "$out/Runner/"
  echo 'let napstopSelfTest: Int = "x"' >"$out/Runner/Broken.swift"
  if typecheck_runner "$triple" "$device_sdk" "$device_slice" "$out" "$out/Runner" off "self-test" 2>/dev/null; then
    echo "self-test FAILED: the broken file typechecked" >&2
    exit 1
  fi
  if ! grep -q 'Broken.swift:[0-9]*:[0-9]*: error:' "$out/Runner-diag-off.log"; then
    echo "self-test FAILED: the compiler failed, but not on Broken.swift:" >&2
    sed -n '1,40p' "$out/Runner-diag-off.log" >&2
    exit 1
  fi
  echo "self-test OK (Broken.swift rejected: $(grep -m 1 'Broken.swift' "$out/Runner-diag-off.log"))"
  exit 0
fi

for triple in arm64-apple-ios16.0 arm64-apple-ios16.0-simulator; do
  case "$triple" in
    *-simulator) sdk="$sim_sdk" slice="$sim_slice" ;;
    *) sdk="$device_sdk" slice="$device_slice" ;;
  esac
  out="$scratch/$triple"
  rm -rf "$out"
  mkdir -p "$out"
  emit_modules "$triple" "$sdk" "$out"
  for diag in off on; do
    typecheck_runner "$triple" "$sdk" "$slice" "$out" "$runner_dir" "$diag" "$triple Runner diag=$diag" || true
  done
done

echo
echo "Summary:"
for r in "${results[@]}"; do echo "  $r"; done
if [ "$failures" -gt 0 ]; then
  echo "typecheck: $failures FAILED"
  exit 1
fi
echo "typecheck: all OK"
