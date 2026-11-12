#!/usr/bin/env bash
# Fallback for installing with xtool when it cannot sign the widget extension (docs/specs/T23.6.md §6.2, Q7 = A):
# copies <in.ipa> to <out.ipa> without Payload/*.app/PlugIns/. The app still runs; ActivityKit errors are swallowed
# (spec D1), so there is simply no Live Activity. Never changes <in.ipa>.
#
# usage: strip-appex.sh <in.ipa> <out.ipa>
#        strip-appex.sh --self-test
# Needs zip and unzip (WSL: apt install zip unzip). Run from WSL next to `xtool install`, e.g.
#   bash app/ios/scripts/strip-appex.sh NapStop-unsigned.ipa NapStop-noappex.ipa && xtool install NapStop-noappex.ipa
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 2
}

need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found (apt install zip unzip)"; }

# strip <in> <out>
strip_ipa() {
  local in="$1" out="$2" plugins
  [ -f "$in" ] || die "no such file: $in"
  [ "$(cd "$(dirname "$in")" && pwd)/$(basename "$in")" != "$(cd "$(dirname "$out")" 2>/dev/null && pwd)/$(basename "$out")" ] ||
    die "<out.ipa> must differ from <in.ipa>"
  unzip -Z1 "$in" | grep -q '^Payload/[^/]*\.app/Info.plist$' || die "$in is not an app ipa (no Payload/*.app/Info.plist)"
  plugins="$(unzip -Z1 "$in" | grep -E '^Payload/[^/]*\.app/PlugIns/' || true)"
  cp -f "$in" "$out"
  if [ -z "$plugins" ]; then
    echo "no PlugIns in $in; copied unchanged to $out"
    return 0
  fi
  # zip -d takes entry names (wildcards are matched by zip, not the shell).
  zip -q -d "$out" 'Payload/*.app/PlugIns/*' >/dev/null
  if unzip -Z1 "$out" | grep -qE '^Payload/[^/]*\.app/PlugIns/'; then
    rm -f "$out"
    die "PlugIns still in $out"
  fi
  unzip -Z1 "$out" | grep -q '^Payload/[^/]*\.app/Info.plist$' || { rm -f "$out"; die "app lost from $out"; }
  echo "removed $(grep -c . <<<"$plugins") PlugIns entries: $(grep -oE 'PlugIns/[^/]+' <<<"$plugins" | sort -u | tr '\n' ' ')"
  echo "wrote $out"
}

self_test() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/src/Payload/Runner.app/PlugIns/NapStopLiveActivity.appex" "$tmp/src/Payload/Runner.app/Frameworks"
  echo app >"$tmp/src/Payload/Runner.app/Info.plist"
  echo bin >"$tmp/src/Payload/Runner.app/Runner"
  echo fw >"$tmp/src/Payload/Runner.app/Frameworks/x"
  echo ext >"$tmp/src/Payload/Runner.app/PlugIns/NapStopLiveActivity.appex/Info.plist"
  (cd "$tmp/src" && zip -qry ../in.ipa Payload)
  strip_ipa "$tmp/in.ipa" "$tmp/out.ipa" >/dev/null
  if unzip -Z1 "$tmp/out.ipa" | grep -q 'PlugIns/'; then echo "self-test FAILED: PlugIns kept" >&2; return 1; fi
  for f in Info.plist Runner Frameworks/x; do
    unzip -Z1 "$tmp/out.ipa" | grep -qx "Payload/Runner.app/$f" || { echo "self-test FAILED: lost $f" >&2; return 1; }
  done
  unzip -Z1 "$tmp/in.ipa" | grep -q 'PlugIns/NapStopLiveActivity.appex/Info.plist' ||
    { echo "self-test FAILED: input changed" >&2; return 1; }
  # An ipa without PlugIns is copied unchanged; a non-ipa is refused.
  strip_ipa "$tmp/out.ipa" "$tmp/out2.ipa" >/dev/null
  cmp -s "$tmp/out.ipa" "$tmp/out2.ipa" || { echo "self-test FAILED: ipa without PlugIns changed" >&2; return 1; }
  echo junk >"$tmp/junk.txt"
  (cd "$tmp" && zip -q bad.ipa junk.txt)
  if (strip_ipa "$tmp/bad.ipa" "$tmp/bad-out.ipa") >/dev/null 2>&1; then
    echo "self-test FAILED: a zip without an app was accepted" >&2
    return 1
  fi
  echo "self-test OK"
}

need zip
need unzip
case "${1:-}" in
  --self-test) self_test ;;
  -h | --help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' ;;
  *)
    [ "$#" -eq 2 ] || die "usage: strip-appex.sh <in.ipa> <out.ipa> | --self-test"
    strip_ipa "$1" "$2"
    ;;
esac
