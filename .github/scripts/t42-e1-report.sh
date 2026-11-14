#!/usr/bin/env bash
# T42.1 step A, experiment E1 (temporary, CI branches ci/ios-*-t42ads-* only, never merged; docs/specs/T42.1.md §1).
# Measures a built Runner.app (base or with google_mobile_ads) for the E1-a…g table: sizes, link type, AdSupport/ATT
# signals per binary, privacy manifests, SwiftPM pins, Firebase IDFA frameworks, strings.
#
# usage: t42-e1-report.sh <Runner.app> <ipa> <ios dir> > e1.md      (macOS runner: otool, nm, strings, plutil, jq)
# Never fails: every probe prints its own error line. No user data in the app bundle, nothing secret is printed
# (GoogleService-Info.plist is never read).
set -uo pipefail

app="${1:?Runner.app}"
ipa="${2:?ipa}"
iosdir="${3:?ios dir}"
SIG_LIB='AdSupport|AppTrackingTransparency|GoogleMobileAds|UserMessagingPlatform'
SIG_SYM='ASIdentifierManager|ATTrackingManager'

count() { # <pattern> : count of matching lines on stdin, 0 when none (grep -c exits 1 on 0)
  grep -c -E -i -- "$1" || true
}

# Every Mach-O binary: Runner plus each framework / dylib in Frameworks.
binaries=("$app/Runner")
if [ -d "$app/Frameworks" ]; then
  for fw in "$app"/Frameworks/*.framework; do
    [ -d "$fw" ] || continue
    b="$fw/$(basename "$fw" .framework)"
    [ -f "$b" ] && binaries+=("$b")
  done
  for d in "$app"/Frameworks/*.dylib; do
    [ -f "$d" ] && binaries+=("$d")
  done
fi

echo "## E1 report (T42.1)"
echo
echo "### Sizes (E1-f)"
echo
if [ -f "$ipa" ]; then echo "- ipa bytes: $(stat -f%z "$ipa")"; else echo "- ipa: missing"; fi
echo "- Runner.app KiB (du -sk): $(du -sk "$app" | cut -f1)"
echo "- Runner binary bytes: $(stat -f%z "$app/Runner" 2>/dev/null || echo missing)"
echo
echo '```'
for e in "$app"/Frameworks/* "$app"/*.bundle; do
  [ -e "$e" ] || continue
  printf '%8s KiB  %s\n' "$(du -sk "$e" | cut -f1)" "${e#"$app"/}"
done
echo '```'
echo
echo "### Link type and AdSupport/ATT signals per binary (E1-a, E1-c)"
echo
echo "| binary | type | otool -L ($SIG_LIB) | nm -u ($SIG_SYM) | strings ($SIG_SYM) |"
echo "|---|---|---|---|---|"
for b in "${binaries[@]}"; do
  rb="${b#"$app"/}"
  type="$(otool -hv "$b" 2>/dev/null | awk '/MH_MAGIC/ { print $5; exit }')"
  libs="$(otool -L "$b" 2>/dev/null | grep -E -o -- "[^ /]*($SIG_LIB)[^ ]*" | sort -u | paste -sd ' ' -)"
  syms="$(nm -u "$b" 2>/dev/null | grep -E -o -- "[^ ]*($SIG_SYM)[^ ]*" | sort -u | paste -sd ' ' -)"
  str="$(strings -a "$b" 2>/dev/null | count "$SIG_SYM")"
  echo "| $rb | ${type:-?} | ${libs:-none} | ${syms:-none} | $str |"
done
echo
echo "- Runner, GMA linked in statically? \`nm -m Runner | grep -c -i GADMobileAds\` = $(nm -m "$app/Runner" 2>/dev/null | count GADMobileAds);" \
  "\`strings -a Runner | grep -c GADMobileAds\` = $(strings -a "$app/Runner" 2>/dev/null | count GADMobileAds)"
echo "- Runner load commands, AdSupport / ATT (weak or not):"
echo
echo '```'
otool -l "$app/Runner" 2>/dev/null | awk '/cmd LC_LOAD_(WEAK_)?DYLIB/ { c = $2 } /name / && c { print c, $2; c = "" }' |
  grep -E -- "AdSupport|AppTrackingTransparency" || echo "none"
echo '```'
echo
echo "### Strings in Runner (for C5 of T42.3, E1-d)"
echo
for s in coarseLocationCollectionEnabled setCoarseLocationCollectionEnabled: publisherPrivacyPersonalizationState \
  GADApplicationIdentifier GoogleAppMeasurementIdentitySupport GoogleAdsOnDeviceConversion; do
  echo "- \`$s\`: $(strings -a "$app/Runner" 2>/dev/null | grep -c -F -- "$s" || true)"
done
echo
echo "### Privacy manifests in the bundle (E1-b)"
echo
manifest_summary() { # <file>
  plutil -convert json -o - "$1" 2>/dev/null | jq -c '{
      tracking: .NSPrivacyTracking,
      domains: .NSPrivacyTrackingDomains,
      collected: [.NSPrivacyCollectedDataTypes[]? | "\((.NSPrivacyCollectedDataType // "?") | sub("NSPrivacyCollectedDataType"; ""))(linked=\(.NSPrivacyCollectedDataTypeLinked),tracking=\(.NSPrivacyCollectedDataTypeTracking))"],
      api: [.NSPrivacyAccessedAPITypes[]? | "\((.NSPrivacyAccessedAPIType // "?") | sub("NSPrivacyAccessedAPICategory"; "")):\((.NSPrivacyAccessedAPITypeReasons // []) | join(","))"]
    }' 2>/dev/null || echo "unreadable"
}
found=0
while IFS= read -r f; do
  found=$((found + 1))
  echo "- \`${f#"$app"/}\`: $(manifest_summary "$f")"
done < <(find "$app" -name PrivacyInfo.xcprivacy | sort)
[ "$found" -gt 0 ] || echo "- none"
echo
echo "Manifests of the GMA/UMP SwiftPM artifacts (not necessarily embedded; a static xcframework's manifest may not be copied):"
echo
dd="$HOME/Library/Developer/Xcode/DerivedData"
found=0
while IFS= read -r f; do
  found=$((found + 1))
  echo "- \`${f#"$dd"/}\`: $(manifest_summary "$f")"
done < <(find "$dd" "$iosdir" "$iosdir/../build" -path '*ios-arm64/*' -name PrivacyInfo.xcprivacy 2>/dev/null |
  grep -E 'GoogleMobileAds|UserMessagingPlatform' | sort -u | head -n 6)
[ "$found" -gt 0 ] || echo "- none found"
echo
echo "### SwiftPM pins (E1-d, E1-g)"
echo
found=0
while IFS= read -r f; do
  found=$((found + 1))
  echo "- \`${f#"$HOME"/}\`:"
  jq -r '.pins[]? | select(.identity | test("google-mobile-ads|user-messaging-platform|googleappmeasurement|firebase-ios-sdk"))
      | "  - \(.identity) \(.state.version // .state.branch // "?") (\(.state.revision[0:12] // "?"))"' "$f" 2>/dev/null ||
    echo "  - unreadable"
done < <(find "$iosdir" "$dd" -name Package.resolved -not -path '*/checkouts/*' 2>/dev/null | sort -u | head -n 4)
[ "$found" -gt 0 ] || echo "- no Package.resolved found"
echo
echo "### Firebase IDFA frameworks (E1-g)"
echo
echo "- embedded GoogleAppMeasurementIdentitySupport / GoogleAdsOnDeviceConversion / FirebaseAnalytics(IDFA):" \
  "$(find "$app" -maxdepth 3 \( -iname '*IdentitySupport*' -o -iname '*OnDeviceConversion*' \) 2>/dev/null |
    sed "s|^$app/||" | paste -sd ' ' - | sed 's/^$/none/')"
echo "- SwiftPM checkouts/artifacts with IdentitySupport or OnDeviceConversion:" \
  "$(find "$dd" -maxdepth 6 -type d \( -iname '*IdentitySupport*' -o -iname '*OnDeviceConversion*' \) 2>/dev/null |
    sed "s|^$dd/||" | head -n 6 | paste -sd ' ' - | sed 's/^$/none/')"
echo
echo "SwiftPM checkouts actually used (DerivedData workspace-state.json):"
echo
found=0
while IFS= read -r f; do
  found=$((found + 1))
  jq -r '.object.dependencies[]? | select(.packageRef.identity | test("google-mobile-ads|user-messaging-platform|googleappmeasurement"))
      | "- \(.packageRef.identity) \(.state.checkoutState.version // .state.checkoutState.branch // .state.name // "?")"' "$f" 2>/dev/null ||
    echo "- unreadable: ${f#"$HOME"/}"
done < <(find "$dd" -maxdepth 4 -path '*/SourcePackages/workspace-state.json' 2>/dev/null | head -n 2)
[ "$found" -gt 0 ] || echo "- no workspace-state.json found"
