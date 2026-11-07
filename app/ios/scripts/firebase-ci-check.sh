#!/usr/bin/env bash
# Firebase checks of the iOS device build (docs/specs/T29.2.md §4, §6, FD01/FD02), for the ios-device job of
# .github/workflows/ios-compile.yml. The checks and the self-test also run on Linux/WSL (jq needed; without plutil only
# XML plists can be read, and the self-test brings its own fake otool/dwarfdump).
#
#   firebase-ci-check.sh check <Runner.app>
#       C1 GoogleService-Info.plist is in the bundle, BUNDLE_ID = $NAPSTOP_EXPECT_BUNDLE_ID [app.napstop], GOOGLE_APP_ID
#          is an iOS app id;
#       C2 the 7 collection keys of §5 are false in the built Info.plist, no NSUserTrackingUsageDescription;
#       C3 `otool -L` of Runner and of every binary in Runner.app/Frameworks links neither AdSupport nor
#          AppTrackingTransparency;
#       C4 every PrivacyInfo.xcprivacy in the bundle has NSPrivacyTracking != true and no NSPrivacyTrackingDomains.
#       Summary lines ("- ...") on stdout, "::error::" lines on stderr; exit 1 when any check fails.
#   firebase-ci-check.sh upload-dsyms <build_dir> <GoogleService-Info.plist>
#       Collects the *.dSYM of <build_dir>/ios/Release-iphoneos (+ the Flutter engine dSYM if the cache has one), prints
#       name/UUID/arch of each (dwarfdump -u), copies them to $NAPSTOP_DSYM_OUT when set, then runs Crashlytics
#       upload-symbols -gsp <plist> -p ios <dSYM> for each. The tool comes from the SwiftPM checkout of firebase-ios-sdk
#       (DerivedData or <build_dir>), else a shallow clone of the version in Package.resolved [13.1.1]. Its output goes
#       to $NAPSTOP_DSYM_LOG [$RUNNER_TEMP/dsym-upload.log], never to stdout (it may print the app id). Exit 1 when no
#       dSYM was found or an upload failed.
#   firebase-ci-check.sh --self-test
#       Builds fake bundles: a good one must pass `check`, each broken one (manifest with tracking, missing or true
#       Info.plist key, missing plist, wrong bundle id, AdSupport linked, ...) must fail; then upload-dsyms with a fake
#       tool: none found → exit 1, found → ok.
#
# Never prints the API key or the contents of GoogleService-Info.plist.
#
# Environment: NAPSTOP_OTOOL [otool], NAPSTOP_DWARFDUMP [dwarfdump], NAPSTOP_UPLOAD_SYMBOLS (skip the search),
#   NAPSTOP_DERIVED_DATA [$HOME/Library/Developer/Xcode/DerivedData], FLUTTER_ROOT (engine dSYM).
set -euo pipefail

die() {
  echo "::error::$*" >&2
  exit 2
}

# The 7 keys of T29.2 §5, all <false/>.
COLLECTION_KEYS=(
  FirebaseCrashlyticsCollectionEnabled
  FIREBASE_ANALYTICS_COLLECTION_ENABLED
  GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED
  GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS
  GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE
  GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA
  FirebaseAutomaticScreenReportingEnabled
)

# XML plist → JSON (dict, array, key, string, true/false, integer, real, date, data). POSIX awk; only used where
# plutil is missing (Linux self-test). Binary plists need plutil.
plist_xml_to_json() {
  tr -d '\r' <"$1" | awk '
    function jesc(t) {
      gsub(/&lt;/, "<", t); gsub(/&gt;/, ">", t); gsub(/&quot;/, "\"", t); gsub(/&apos;/, "\047", t)
      gsub(/&amp;/, "\\&", t)
      gsub(/\\/, "\\\\", t); gsub(/"/, "\\\"", t); gsub(/\t/, "\\t", t); gsub(/\n/, "\\n", t)
      return t
    }
    function sep() {
      if (depth > 0 && kind[depth] == "a") { if (count[depth] > 0) out = out ","; count[depth]++ }
    }
    function text_until(endtag,   i, t) {
      i = index(s, endtag)
      if (i == 0) { bad = 1; return "" }
      t = substr(s, 1, i - 1); s = substr(s, i + length(endtag)); return t
    }
    { all = all $0 "\n" }
    END {
      s = all; out = ""; depth = 0; bad = 0
      while (!bad && match(s, /<[^>]*>/)) {
        tag = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        if (tag ~ /^<[?!]/ || tag ~ /^<\/?plist/) continue
        if (tag == "<dict>") { sep(); out = out "{"; kind[++depth] = "d"; count[depth] = 0 }
        else if (tag == "</dict>") { out = out "}"; depth-- }
        else if (tag == "<dict/>") { sep(); out = out "{}" }
        else if (tag == "<array>") { sep(); out = out "["; kind[++depth] = "a"; count[depth] = 0 }
        else if (tag == "</array>") { out = out "]"; depth-- }
        else if (tag == "<array/>") { sep(); out = out "[]" }
        else if (tag == "<key>") {
          k = text_until("</key>"); if (count[depth] > 0) out = out ","; count[depth]++
          out = out "\"" jesc(k) "\":"
        }
        else if (tag == "<string>" || tag == "<date>" || tag == "<data>") {
          c = "</" substr(tag, 2); sep(); out = out "\"" jesc(text_until(c)) "\""
        }
        else if (tag == "<string/>") { sep(); out = out "\"\"" }
        else if (tag == "<true/>" || tag == "<true>") { sep(); out = out "true" }
        else if (tag == "<false/>" || tag == "<false>") { sep(); out = out "false" }
        else if (tag == "</true>" || tag == "</false>") continue
        else if (tag == "<integer>" || tag == "<real>") {
          c = "</" substr(tag, 2); v = text_until(c); gsub(/[ \t\n]/, "", v); sep(); out = out v
        }
        else { bad = 1 }
      }
      if (bad || depth != 0 || out == "") exit 1
      print out
    }'
}

# JSON of any plist on stdout; non-zero when it cannot be read.
plist_json() {
  local f="$1"
  [ -f "$f" ] || return 1
  if command -v plutil >/dev/null 2>&1; then
    plutil -convert json -o - "$f" 2>/dev/null
  else
    plist_xml_to_json "$f"
  fi
}

# Path of $1 relative to $2 (for the summary).
rel() {
  case "$1" in
    "$2"/*) printf '%s\n' "${1#"$2"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

cmd_check() {
  local app="${1:-}"
  [ -n "$app" ] || die "usage: firebase-ci-check.sh check <Runner.app>"
  [ -d "$app" ] || die "$app is not a directory"
  command -v jq >/dev/null 2>&1 || die "jq is required"
  local otool="${NAPSTOP_OTOOL:-otool}"
  local want_bundle="${NAPSTOP_EXPECT_BUNDLE_ID:-app.napstop}"
  local failed=0 json v

  # C1 — values are compared, never printed (the API key is in the same file).
  local gsp="$app/GoogleService-Info.plist"
  if ! json="$(plist_json "$gsp")"; then
    echo "::error::C1 GoogleService-Info.plist missing or unreadable in the bundle" >&2
    echo "- C1 GoogleService-Info.plist: FAILED (missing)"
    failed=1
  else
    local c1=ok
    v="$(jq -r '.BUNDLE_ID // ""' <<<"$json")"
    if [ "$v" != "$want_bundle" ]; then
      echo "::error::C1 BUNDLE_ID of GoogleService-Info.plist is not $want_bundle" >&2
      c1=FAILED
    fi
    if ! jq -e '(.GOOGLE_APP_ID // "") | test("^1:[0-9]+:ios:[0-9a-f]+$")' <<<"$json" >/dev/null; then
      echo "::error::C1 GOOGLE_APP_ID is not an iOS app id" >&2
      c1=FAILED
    fi
    if ! jq -e '(.API_KEY // "") | length > 0' <<<"$json" >/dev/null; then
      echo "::error::C1 API_KEY is empty" >&2
      c1=FAILED
    fi
    [ "$c1" = ok ] || failed=1
    echo "- C1 GoogleService-Info.plist in bundle: $c1 (BUNDLE_ID expected $want_bundle)"
  fi

  # C2
  local c2=ok k
  if ! json="$(plist_json "$app/Info.plist")"; then
    echo "::error::C2 Info.plist missing or unreadable" >&2
    c2=FAILED
  else
    for k in "${COLLECTION_KEYS[@]}"; do
      if ! jq -e --arg k "$k" 'has($k) and .[$k] == false' <<<"$json" >/dev/null; then
        echo "::error::C2 Info.plist: $k must be false" >&2
        c2=FAILED
      fi
    done
    for k in NSUserTrackingUsageDescription FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED; do
      if jq -e --arg k "$k" 'has($k)' <<<"$json" >/dev/null; then
        echo "::error::C2 Info.plist must not have $k" >&2
        c2=FAILED
      fi
    done
  fi
  [ "$c2" = ok ] || failed=1
  echo "- C2 Info.plist collection keys (${#COLLECTION_KEYS[@]} false): $c2"

  # C3
  local c3=ok n=0 bin libs fw
  local bins=("$app/Runner")
  if [ -d "$app/Frameworks" ]; then
    for fw in "$app"/Frameworks/*.framework; do
      [ -d "$fw" ] || continue
      bin="$fw/$(basename "$fw" .framework)"
      [ -f "$bin" ] && bins+=("$bin")
    done
    for bin in "$app"/Frameworks/*.dylib; do
      [ -f "$bin" ] && bins+=("$bin")
    done
  fi
  for bin in "${bins[@]}"; do
    if [ ! -f "$bin" ]; then
      echo "::error::C3 $(rel "$bin" "$app") not found" >&2
      c3=FAILED
      continue
    fi
    if ! libs="$("$otool" -L "$bin" 2>&1)"; then
      echo "::error::C3 otool -L failed on $(rel "$bin" "$app")" >&2
      c3=FAILED
      continue
    fi
    n=$((n + 1))
    if grep -Eq 'AdSupport\.framework|AppTrackingTransparency\.framework' <<<"$libs"; then
      echo "::error::C3 $(rel "$bin" "$app") links AdSupport or AppTrackingTransparency (IDFA/ATT, T29.2 D6)" >&2
      c3=FAILED
    fi
  done
  [ "$c3" = ok ] || failed=1
  echo "- C3 no AdSupport / AppTrackingTransparency ($n binaries): $c3"

  # C4
  local c4=ok m=0 names=() f
  if [ ! -f "$app/PrivacyInfo.xcprivacy" ]; then
    echo "::error::C4 the app privacy manifest is missing" >&2
    c4=FAILED
  fi
  while IFS= read -r f; do
    m=$((m + 1))
    names+=("$(rel "$f" "$app")")
    if ! json="$(plist_json "$f")"; then
      echo "::error::C4 $(rel "$f" "$app") unreadable" >&2
      c4=FAILED
      continue
    fi
    if ! jq -e '(.NSPrivacyTracking // false) != true and ((.NSPrivacyTrackingDomains // []) | length == 0)' \
      <<<"$json" >/dev/null; then
      echo "::error::C4 $(rel "$f" "$app") declares tracking (needs ATT, T29.2 D6)" >&2
      c4=FAILED
    fi
  done < <(find "$app" -name PrivacyInfo.xcprivacy -type f | LC_ALL=C sort)
  [ "$c4" = ok ] || failed=1
  echo "- C4 privacy manifests ($m, no tracking): $c4"
  for f in "${names[@]}"; do echo "  - $f"; done

  return "$failed"
}

# Version of firebase-ios-sdk pinned by a Package.resolved under the given roots, else 13.1.1.
sdk_version() {
  local f v
  while IFS= read -r f; do
    v="$(jq -r '[.pins[]? | select(.identity == "firebase-ios-sdk") | .state.version // empty][0] // empty' "$f" \
      2>/dev/null || true)"
    if [ -n "$v" ]; then
      printf '%s\n' "$v"
      return 0
    fi
  done < <(find "$@" -name Package.resolved -type f 2>/dev/null)
  echo 13.1.1
}

cmd_upload_dsyms() {
  local build="${1:-}" gsp="${2:-}"
  [ -n "$build" ] && [ -n "$gsp" ] || die "usage: firebase-ci-check.sh upload-dsyms <build_dir> <GoogleService-Info.plist>"
  [ -f "$gsp" ] || die "$gsp not found"
  local dwarfdump="${NAPSTOP_DWARFDUMP:-dwarfdump}"
  local derived="${NAPSTOP_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"
  local tmp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
  local log="${NAPSTOP_DSYM_LOG:-$tmp/dsym-upload.log}"
  local dsyms=() d seen=" "

  # Shallowest first; one dSYM per bundle name (the build products repeat some under sub-folders).
  if [ -d "$build/ios/Release-iphoneos" ]; then
    while IFS= read -r d; do
      case "$seen" in *" $(basename "$d") "*) continue ;; esac
      seen="$seen$(basename "$d") "
      dsyms+=("$d")
    done < <(find "$build/ios/Release-iphoneos" -name '*.dSYM' -type d -prune |
      awk '{ n = gsub(/\//, "/"); printf "%04d %s\n", n, $0 }' | LC_ALL=C sort | cut -d' ' -f2-)
  fi
  # The engine dSYM of the device slice (not ios-arm64_x86_64-simulator), unless the build already has one.
  local engine=none root="${FLUTTER_ROOT:-}"
  if [ -z "$root" ] && command -v flutter >/dev/null 2>&1; then
    root="$(cd "$(dirname "$(command -v flutter)")/.." && pwd)"
  fi
  case "$seen" in
    *" Flutter.framework.dSYM "*) engine="Flutter.framework.dSYM (from the build)" ;;
    *)
      if [ -n "$root" ] && [ -d "$root/bin/cache/artifacts/engine/ios-release" ]; then
        while IFS= read -r d; do
          dsyms+=("$d")
          engine="$(basename "$d") (from the engine cache)"
        done < <(find "$root/bin/cache/artifacts/engine/ios-release" -path '*/ios-arm64/*' -name '*.dSYM' -type d \
          -prune | head -n 1)
      fi
      ;;
  esac
  if [ "${#dsyms[@]}" -eq 0 ]; then
    echo "- dSYM: none found"
    echo "::error::no dSYM under $build/ios/Release-iphoneos" >&2
    return 1
  fi
  echo "- dSYM: ${#dsyms[@]} found (Flutter engine: $engine)"
  local line uuid arch
  for d in "${dsyms[@]}"; do
    while IFS= read -r line; do
      # "UUID: <uuid> (<arch>) <path>"
      uuid="$(awk '{print $2}' <<<"$line")"
      arch="$(awk '{print $3}' <<<"$line" | tr -d '()')"
      [ -n "$uuid" ] && echo "  - $(basename "$d") $uuid $arch"
    done < <("$dwarfdump" -u "$d" 2>/dev/null | grep '^UUID:' || true)
  done
  if [ -n "${NAPSTOP_DSYM_OUT:-}" ]; then
    mkdir -p "$NAPSTOP_DSYM_OUT"
    for d in "${dsyms[@]}"; do cp -R "$d" "$NAPSTOP_DSYM_OUT/"; done
  fi

  local tool="${NAPSTOP_UPLOAD_SYMBOLS:-}" where
  if [ -z "$tool" ]; then
    local roots=()
    [ -d "$derived" ] && roots+=("$derived")
    roots+=("$build")
    tool="$(find "${roots[@]}" -path '*/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols' \
      -type f 2>/dev/null | head -n 1 || true)"
    where="SwiftPM checkout"
    if [ -z "$tool" ]; then
      local ver clone="$tmp/firebase-ios-sdk"
      ver="$(sdk_version "${roots[@]}" "$(dirname "$gsp")/..")"
      rm -rf "$clone"
      if git clone -q --depth 1 --branch "$ver" https://github.com/firebase/firebase-ios-sdk "$clone" >>"$log" 2>&1; then
        tool="$clone/Crashlytics/upload-symbols"
        where="clone of firebase-ios-sdk $ver"
      fi
    fi
  else
    where="NAPSTOP_UPLOAD_SYMBOLS"
  fi
  if [ -z "$tool" ] || [ ! -f "$tool" ]; then
    echo "- dSYM upload: failed (upload-symbols not found), ${#dsyms[@]} file(s)"
    return 1
  fi
  [ -x "$tool" ] || chmod +x "$tool"
  local rc=0 r
  for d in "${dsyms[@]}"; do
    r=0
    "$tool" -gsp "$gsp" -p ios "$d" >>"$log" 2>&1 || r=$?
    [ "$r" -eq 0 ] || rc="$r"
  done
  if [ "$rc" -eq 0 ]; then
    echo "- dSYM upload: ok (exit 0), ${#dsyms[@]} file(s), tool from $where"
  else
    echo "- dSYM upload: failed (exit $rc), ${#dsyms[@]} file(s), tool from $where"
    return 1
  fi
}

# --- self-test ---------------------------------------------------------------------------------------------------

st_plist() { # <file> <body of the top dict>
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0">'
    echo '<dict>'
    printf '%s\n' "$2"
    echo '</dict>'
    echo '</plist>'
  } >"$1"
}

st_info_body() { # [key to drop] [key to set true]
  local k
  echo '<key>CFBundleIdentifier</key><string>app.napstop</string>'
  for k in "${COLLECTION_KEYS[@]}"; do
    [ "$k" = "${1:-}" ] && continue
    if [ "$k" = "${2:-}" ]; then echo "<key>$k</key><true/>"; else echo "<key>$k</key><false/>"; fi
  done
}

st_manifest_body() { # <tracking true|false> [domain]
  echo "<key>NSPrivacyTracking</key><$1/>"
  if [ -n "${2:-}" ]; then
    echo "<key>NSPrivacyTrackingDomains</key><array><string>$2</string></array>"
  else
    echo '<key>NSPrivacyTrackingDomains</key><array/>'
  fi
  echo '<key>NSPrivacyCollectedDataTypes</key><array><dict><key>NSPrivacyCollectedDataType</key>'
  echo '<string>NSPrivacyCollectedDataTypeCrashData</string><key>NSPrivacyCollectedDataTypeLinked</key><false/>'
  echo '<key>NSPrivacyCollectedDataTypePurposes</key><array><string>A &amp; B</string></array></dict></array>'
}

st_good_app() { # <dir>
  local app="$1"
  mkdir -p "$app/Frameworks/FirebaseCrashlytics.framework" "$app/Frameworks/Lib.bundle"
  st_plist "$app/Info.plist" "$(st_info_body)"
  st_plist "$app/GoogleService-Info.plist" \
    '<key>API_KEY</key><string>self-test-key</string><key>BUNDLE_ID</key><string>app.napstop</string>
<key>GOOGLE_APP_ID</key><string>1:123:ios:abc123</string><key>IS_ANALYTICS_ENABLED</key><false></false>'
  st_plist "$app/PrivacyInfo.xcprivacy" "$(st_manifest_body false)"
  st_plist "$app/Frameworks/FirebaseCrashlytics.framework/PrivacyInfo.xcprivacy" "$(st_manifest_body false)"
  st_plist "$app/Frameworks/Lib.bundle/PrivacyInfo.xcprivacy" "$(st_manifest_body false)"
  : >"$app/Runner"
  echo '/System/Library/Frameworks/UIKit.framework/UIKit (compatibility version 1.0.0)' >"$app/Runner.libs"
  : >"$app/Frameworks/FirebaseCrashlytics.framework/FirebaseCrashlytics"
  echo '/usr/lib/libz.1.dylib' >"$app/Frameworks/FirebaseCrashlytics.framework/FirebaseCrashlytics.libs"
}

cmd_self_test() {
  command -v jq >/dev/null 2>&1 || die "jq is required"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  # Fake otool: prints the sidecar <binary>.libs.
  cat >"$tmp/otool" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -L ] || exit 2
[ -f "$2" ] || exit 1
echo "$2:"
if [ -f "$2.libs" ]; then sed 's/^/	/' "$2.libs"; fi
EOF
  cat >"$tmp/dwarfdump" <<'EOF'
#!/usr/bin/env bash
echo "UUID: 01234567-89AB-CDEF-0123-456789ABCDEF (arm64) $2"
EOF
  cat >"$tmp/upload-symbols" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -gsp ] && [ -f "$2" ] && [ "$3" = -p ] && [ "$4" = ios ] && [ -d "$5" ] || exit 3
echo "uploaded $5"
EOF
  chmod +x "$tmp/otool" "$tmp/dwarfdump" "$tmp/upload-symbols"
  export NAPSTOP_OTOOL="$tmp/otool" NAPSTOP_DWARFDUMP="$tmp/dwarfdump"

  local pass=0 failed=0
  # expect <0|1> <name> <app>
  expect() {
    local want="$1" name="$2" rc=0
    (cmd_check "$3") >"$tmp/out" 2>"$tmp/err" || rc=$?
    if { [ "$want" = 0 ] && [ "$rc" = 0 ]; } || { [ "$want" = 1 ] && [ "$rc" = 1 ]; }; then
      pass=$((pass + 1))
    else
      failed=$((failed + 1))
      echo "self-test FAIL: $name -> exit $rc (want $want)" >&2
      sed 's/^/    /' "$tmp/out" "$tmp/err" >&2
    fi
  }
  mk() { rm -rf "${tmp:?}/$1"; st_good_app "$tmp/$1/Runner.app"; printf '%s\n' "$tmp/$1/Runner.app"; }

  local app
  app="$(mk good)"
  expect 0 "good bundle" "$app"
  if grep -q self-test-key "$tmp/out" "$tmp/err"; then
    failed=$((failed + 1))
    echo "self-test FAIL: the API key reached the output" >&2
  fi
  if ! grep -q 'Lib.bundle/PrivacyInfo.xcprivacy' "$tmp/out"; then
    failed=$((failed + 1))
    echo "self-test FAIL: manifest list missing in the summary" >&2
  fi

  app="$(mk tracking)"
  st_plist "$app/Frameworks/FirebaseCrashlytics.framework/PrivacyInfo.xcprivacy" "$(st_manifest_body true)"
  expect 1 "SDK manifest with NSPrivacyTracking=true" "$app"

  app="$(mk domains)"
  st_plist "$app/Frameworks/Lib.bundle/PrivacyInfo.xcprivacy" "$(st_manifest_body false tracker.example)"
  expect 1 "SDK manifest with tracking domains" "$app"

  app="$(mk no-app-manifest)"
  rm "$app/PrivacyInfo.xcprivacy"
  expect 1 "app manifest missing" "$app"

  app="$(mk missing-key)"
  st_plist "$app/Info.plist" "$(st_info_body FirebaseCrashlyticsCollectionEnabled)"
  expect 1 "Info.plist without FirebaseCrashlyticsCollectionEnabled" "$app"

  app="$(mk true-key)"
  st_plist "$app/Info.plist" "$(st_info_body '' FIREBASE_ANALYTICS_COLLECTION_ENABLED)"
  expect 1 "Info.plist with FIREBASE_ANALYTICS_COLLECTION_ENABLED=true" "$app"

  app="$(mk att-string)"
  st_plist "$app/Info.plist" "$(st_info_body)
<key>NSUserTrackingUsageDescription</key><string>x</string>"
  expect 1 "Info.plist with NSUserTrackingUsageDescription" "$app"

  app="$(mk no-gsp)"
  rm "$app/GoogleService-Info.plist"
  expect 1 "GoogleService-Info.plist missing" "$app"

  app="$(mk bundle)"
  st_plist "$app/GoogleService-Info.plist" \
    '<key>API_KEY</key><string>k</string><key>BUNDLE_ID</key><string>app.other</string>
<key>GOOGLE_APP_ID</key><string>1:123:ios:abc123</string>'
  expect 1 "GoogleService-Info.plist for another bundle id" "$app"

  app="$(mk android-id)"
  st_plist "$app/GoogleService-Info.plist" \
    '<key>API_KEY</key><string>k</string><key>BUNDLE_ID</key><string>app.napstop</string>
<key>GOOGLE_APP_ID</key><string>1:123:android:abc123</string>'
  expect 1 "GOOGLE_APP_ID not an iOS app" "$app"

  app="$(mk adsupport)"
  echo '/System/Library/Frameworks/AdSupport.framework/AdSupport' \
    >>"$app/Frameworks/FirebaseCrashlytics.framework/FirebaseCrashlytics.libs"
  expect 1 "framework links AdSupport" "$app"

  app="$(mk att)"
  echo '/System/Library/Frameworks/AppTrackingTransparency.framework/AppTrackingTransparency' >>"$app/Runner.libs"
  expect 1 "Runner links AppTrackingTransparency" "$app"

  app="$(mk no-runner)"
  rm "$app/Runner"
  expect 1 "Runner binary missing" "$app"

  # upload-dsyms with the fake tool.
  local build="$tmp/build" rc
  mkdir -p "$build/ios/Release-iphoneos"
  rc=0
  (FLUTTER_ROOT="$tmp/no-flutter" NAPSTOP_UPLOAD_SYMBOLS="$tmp/upload-symbols" NAPSTOP_DSYM_LOG="$tmp/up.log" \
    cmd_upload_dsyms "$build" "$tmp/good/Runner.app/GoogleService-Info.plist") >"$tmp/out" 2>/dev/null || rc=$?
  if [ "$rc" = 1 ] && grep -q 'dSYM: none found' "$tmp/out"; then pass=$((pass + 1)); else
    failed=$((failed + 1))
    echo "self-test FAIL: upload-dsyms without dSYM -> exit $rc" >&2
  fi
  mkdir -p "$build/ios/Release-iphoneos/Runner.app.dSYM/Contents" "$build/ios/Release-iphoneos/X.framework.dSYM" \
    "$build/ios/Release-iphoneos/a/X.framework.dSYM"
  rc=0
  (FLUTTER_ROOT="$tmp/no-flutter" NAPSTOP_UPLOAD_SYMBOLS="$tmp/upload-symbols" NAPSTOP_DSYM_LOG="$tmp/up.log" \
    NAPSTOP_DSYM_OUT="$tmp/dsyms" cmd_upload_dsyms "$build" "$tmp/good/Runner.app/GoogleService-Info.plist") \
    >"$tmp/out" 2>/dev/null || rc=$?
  if [ "$rc" = 0 ] && grep -q 'dSYM upload: ok (exit 0), 2 file(s)' "$tmp/out" \
    && grep -q 'Runner.app.dSYM 01234567-89AB-CDEF-0123-456789ABCDEF arm64' "$tmp/out" \
    && [ -d "$tmp/dsyms/Runner.app.dSYM" ] && ! grep -q uploaded "$tmp/out"; then
    pass=$((pass + 1))
  else
    failed=$((failed + 1))
    echo "self-test FAIL: upload-dsyms with 2 dSYMs -> exit $rc" >&2
    sed 's/^/    /' "$tmp/out" >&2
  fi
  printf '#!/usr/bin/env bash\nexit 7\n' >"$tmp/upload-symbols"
  rc=0
  (FLUTTER_ROOT="$tmp/no-flutter" NAPSTOP_UPLOAD_SYMBOLS="$tmp/upload-symbols" NAPSTOP_DSYM_LOG="$tmp/up.log" \
    cmd_upload_dsyms "$build" "$tmp/good/Runner.app/GoogleService-Info.plist") >"$tmp/out" 2>/dev/null || rc=$?
  if [ "$rc" = 1 ] && grep -q 'dSYM upload: failed (exit 7)' "$tmp/out"; then pass=$((pass + 1)); else
    failed=$((failed + 1))
    echo "self-test FAIL: upload-dsyms with a failing tool -> exit $rc" >&2
  fi

  echo "firebase-ci-check self-test: $pass passed, $failed failed"
  [ "$failed" -eq 0 ]
}

case "${1:-}" in
  check) shift; cmd_check "$@" ;;
  upload-dsyms) shift; cmd_upload_dsyms "$@" ;;
  --self-test) cmd_self_test ;;
  -h | --help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' ;;
  *) die "usage: firebase-ci-check.sh check <Runner.app> | upload-dsyms <build_dir> <plist> | --self-test" ;;
esac
