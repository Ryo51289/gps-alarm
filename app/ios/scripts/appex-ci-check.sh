#!/usr/bin/env bash
# Checks of the NapStopLiveActivity widget extension inside the built app (docs/specs/T23.6.md §6.2, LC01). macOS only
# (plutil, lipo). Spike B0 version: the checks below, no --self-test yet (B4 adds it with broken fake bundles).
#
# usage: appex-ci-check.sh check <Runner.app> [<NapStop-unsigned.ipa>]
#
# A1 exactly one appex in PlugIns, named NapStopLiveActivity.appex
# A2 Info.plist: NSExtensionPointIdentifier = com.apple.widgetkit-extension, CFBundlePackageType = XPC!
# A3 CFBundleIdentifier = <app bundle id>.LiveActivity (prefix of the app, needed for any signing)
# A4 MinimumOSVersion = 17.0; CFBundleVersion and CFBundleShortVersionString equal to the app's
# A5 executable present, Mach-O with arm64
# A6 no *.entitlements and no embedded.mobileprovision inside the appex (the extension has no capability)
# A7 (with an ipa) the ipa holds Payload/Runner.app/PlugIns/NapStopLiveActivity.appex/
# Report lines "- A<n> ...: ok|FAILED"; exit 1 when one fails. Prints no file content other than these keys.
set -euo pipefail

usage() {
  echo "usage: appex-ci-check.sh check <Runner.app> [<ipa>]" >&2
  exit 2
}

[ "${1:-}" = check ] || usage
app="${2:-}"
ipa="${3:-}"
[ -n "$app" ] && [ -d "$app" ] || usage

name=NapStopLiveActivity
failed=0

# key <plist> <key>: raw value, empty when missing.
key() { plutil -extract "$2" raw -o - "$1" 2>/dev/null || true; }

report() { # report <id> <label> <ok|FAILED> [detail]
  echo "- $1 $2: $3${4:+ ($4)}"
  [ "$3" = ok ] || failed=1
}

app_id="$(key "$app/Info.plist" CFBundleIdentifier)"
app_ver="$(key "$app/Info.plist" CFBundleVersion)"
app_short="$(key "$app/Info.plist" CFBundleShortVersionString)"

plugins=()
if [ -d "$app/PlugIns" ]; then
  while IFS= read -r p; do plugins+=("$(basename "$p")"); done < <(find "$app/PlugIns" -mindepth 1 -maxdepth 1 | LC_ALL=C sort)
fi
appex="$app/PlugIns/$name.appex"
if [ "${#plugins[@]}" -eq 1 ] && [ -d "$appex" ]; then
  report A1 "PlugIns = $name.appex" ok
else
  report A1 "PlugIns = $name.appex" FAILED "found: ${plugins[*]:-none}"
  echo "appex checks: FAILED (no appex)"
  exit 1
fi
plist="$appex/Info.plist"

point="$(key "$plist" NSExtension.NSExtensionPointIdentifier)"
pkg="$(key "$plist" CFBundlePackageType)"
if [ "$point" = com.apple.widgetkit-extension ] && [ "$pkg" = 'XPC!' ]; then
  report A2 "extension point widgetkit, package XPC!" ok
else
  report A2 "extension point widgetkit, package XPC!" FAILED "point=$point package=$pkg"
fi

ext_id="$(key "$plist" CFBundleIdentifier)"
if [ -n "$app_id" ] && [ "$ext_id" = "$app_id.LiveActivity" ]; then
  report A3 "bundle id $ext_id" ok
else
  report A3 "bundle id" FAILED "extension=$ext_id app=$app_id"
fi

min_os="$(key "$plist" MinimumOSVersion)"
ext_ver="$(key "$plist" CFBundleVersion)"
ext_short="$(key "$plist" CFBundleShortVersionString)"
if [ "$min_os" = 17.0 ] && [ -n "$ext_ver" ] && [ "$ext_ver" = "$app_ver" ] && [ "$ext_short" = "$app_short" ]; then
  report A4 "MinimumOSVersion 17.0, version $ext_short ($ext_ver) = app" ok
else
  report A4 "MinimumOSVersion, versions" FAILED "min=$min_os ext=$ext_short ($ext_ver) app=$app_short ($app_ver)"
fi

exe="$(key "$plist" CFBundleExecutable)"
archs=""
[ -n "$exe" ] && [ -f "$appex/$exe" ] && archs="$(lipo -archs "$appex/$exe" 2>/dev/null || true)"
case " $archs " in
  *" arm64 "*) report A5 "executable $exe, archs $archs" ok ;;
  *) report A5 "executable" FAILED "exe=${exe:-none} archs=${archs:-none}" ;;
esac

extra="$(find "$appex" \( -name '*.entitlements' -o -name embedded.mobileprovision \) | sed "s|^$appex/||" | head -n 5)"
if [ -z "$extra" ]; then
  report A6 "no entitlements, no provisioning profile" ok
else
  report A6 "no entitlements, no provisioning profile" FAILED "$(tr '\n' ' ' <<<"$extra")"
fi

if [ -n "$ipa" ]; then
  if [ -f "$ipa" ] && unzip -Z1 "$ipa" | grep -q "^Payload/Runner.app/PlugIns/$name.appex/Info.plist$"; then
    report A7 "ipa holds PlugIns/$name.appex" ok
  else
    report A7 "ipa holds PlugIns/$name.appex" FAILED "$ipa"
  fi
fi

# Informational: App Intents metadata of the extension, appex size.
if [ -d "$appex/Metadata.appintents" ]; then echo "- info: appex has Metadata.appintents"; fi
echo "- info: appex size $(du -sh "$appex" | cut -f1)"

if [ "$failed" -ne 0 ]; then
  echo "appex checks: FAILED"
  exit 1
fi
echo "appex checks: ok"
