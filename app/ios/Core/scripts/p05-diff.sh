#!/usr/bin/env bash
# P05 mismatch hunt (docs/specs/T13.md §9.4). Run from Git Bash at the repo root:
#   app/ios/Core/scripts/p05-diff.sh [run ...]      e.g. coach_dn_langco_tunnel/distance_1000_gps_lost/all
# 1. dumps the Kotlin transcripts (T12, Gradle) into app/build/core-trip/napstop/transcripts/
# 2. dumps the Swift transcripts (+ .diag.jsonl) from WSL into build/p05/swift/
# 3. diffs the given runs (default: every run whose files differ). The first differing line tells harness (`in`)
#    from engine (`ev` / `v`); compare the .diag.jsonl files to find the first Double that differs.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
kotlin_dir="$root/app/build/core-trip/napstop/transcripts"
swift_dir="$root/build/p05/swift"

if [[ "${SKIP_KOTLIN:-0}" != "1" ]]; then
  (cd "$root/app/android" && ./gradlew :core-trip:test --tests '*P05ManifestTest*' -Pnapstop.dumpTranscripts=true --rerun) || true
fi
if [[ "${SKIP_SWIFT:-0}" != "1" ]]; then
  mkdir -p "$swift_dir"
  # Repo root as a WSL path (works wherever the repo is cloned); WSL distro from NAPSTOP_WSL_DISTRO (default Ubuntu).
  distro="${NAPSTOP_WSL_DISTRO:-Ubuntu}"
  wsl_root="$(MSYS_NO_PATHCONV=1 wsl.exe -d "$distro" -e wslpath -a "$(cygpath -w "$root")" | tr -d '\r')"
  MSYS_NO_PATHCONV=1 wsl.exe -d "$distro" -e bash -c \
    "NAPSTOP_P05_DUMP='$wsl_root/build/p05/swift' NAPSTOP_P05_DIAG=1 bash '$wsl_root/app/ios/Core/scripts/test-wsl.sh' --filter P05ManifestTests" || true
fi

runs=("$@")
if [[ ${#runs[@]} -eq 0 ]]; then
  for f in "$swift_dir"/*.jsonl; do
    name="$(basename "$f")"
    [[ "$name" == *.diag.jsonl ]] && continue
    if ! cmp -s "$f" "$kotlin_dir/$name"; then runs+=("${name%.jsonl}"); fi
  done
fi
status=0
for r in "${runs[@]}"; do
  name="${r//\//__}"
  name="${name%.jsonl}.jsonl"
  echo "=== $name"
  diff "$kotlin_dir/$name" "$swift_dir/$name" | head -20 || status=1
done
exit $status
