#!/usr/bin/env bash
# Test for publish-ci-results.sh (docs/specs/T01.2.md §7, CI02): fake results, a local bare repository as the remote,
# two runs. Needs bash, git, jq. Run: bash .github/scripts/publish-ci-results.test.sh
# Checks are strings run by eval in ok(), so variables used only there look unused (SC2034) and the
# single quotes are on purpose (SC2016).
# shellcheck disable=SC2034,SC2016
set -euo pipefail
script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/publish-ci-results.sh"
command -v jq >/dev/null 2>&1 || { echo "publish-ci-results.test: jq is required on PATH" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
remote="$tmp/remote.git"
git init -q --bare "$remote"
ref="ci/ios-all-x"
branch="refs/heads/ci-results/$ref"

pass=0
failed=0
ok() {
  if eval "$2"; then
    pass=$((pass + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: $1"
  fi
}
rgit() { git -C "$remote" "$@"; }

needs='{
  "plan": {"result": "success", "outputs": {"swift": "true", "sim": "true", "ipa": "false", "diag": "false"}},
  "swift-macos": {"result": "success", "outputs": {}},
  "ios-sim": {"result": "failure", "outputs": {}},
  "ios-device": {"result": "skipped", "outputs": {}}
}'

# --- Run 1: two jobs, one file of 2 MB, one file with an AIza key, one with GMSApiKey, one long log.
r1="$tmp/r1"
mkdir -p "$r1/result-swift-macos" "$r1/result-ios-sim" "$r1/result-plan"
printf 'start_epoch=1762300000\nend_epoch=1762300421\n' >"$r1/result-swift-macos/timing.env"
printf '## swift-macos\n\nTest run with 303 tests passed\n' >"$r1/result-swift-macos/summary.md"
seq 1 1000 >"$r1/result-swift-macos/swift-test.tail.log"
printf 'start_epoch=1762300000\nend_epoch=1762301500\n' >"$r1/result-ios-sim/timing.env"
printf '## ios-sim\n\nXCTest: failed\n' >"$r1/result-ios-sim/summary.md"
head -c $((2 * 1024 * 1024)) /dev/zero | tr '\0' 'x' >"$r1/result-ios-sim/big.log"
printf 'line\nkey=AIzaTESTabcdefghijklmnopqrstuvwxyz012345\n' >"$r1/result-ios-sim/xctest.tail.log"
printf '<key>GMSApiKey</key>\n' >"$r1/result-ios-sim/Info.plist.txt"
printf 'swift=true\n' >"$r1/result-plan/summary.md"

REMOTE_URL="$remote" NEEDS_JSON="$needs" SHA=0123456789abcdef0123 RUN_URL=https://example.invalid/run/1 RUN_ID=1 \
  SECRET_VALUES='' GITHUB_STEP_SUMMARY="$tmp/step1.md" bash "$script" "$r1" "$ref" >"$tmp/out1.txt"

ok "branch exists after run 1" 'rgit rev-parse -q --verify "$branch" >/dev/null'
files1="$(rgit ls-tree -r --name-only "$branch")"
ok "summary.md and meta.json at the root" 'grep -qx summary.md <<<"$files1" && grep -qx meta.json <<<"$files1"'
ok "job files kept" 'grep -qx swift-macos/summary.md <<<"$files1" && grep -qx ios-sim/timing.env <<<"$files1"'
ok "2 MB file dropped" '! grep -q big.log <<<"$files1"'
ok "file with AIza key dropped" '! grep -q xctest.tail.log <<<"$files1"'
ok "no AIza anywhere" '! rgit grep -q AIza "$branch" --'
ok "long log cut to 400 lines" '[ "$(rgit show "$branch:swift-macos/swift-test.tail.log" | wc -l | tr -d " ")" = 400 ]'
ok "long log keeps its tail" '[ "$(rgit show "$branch:swift-macos/swift-test.tail.log" | tail -n 1)" = 1000 ]'
s1="$(rgit show "$branch:summary.md")"
ok "summary title" 'grep -qF "# CI iOS — $ref" <<<"$s1"'
ok "summary commit and run" 'grep -qF "commit 0123456789abcdef0123 · run https://example.invalid/run/1" <<<"$s1"'
ok "job table header" 'grep -qF "| job | result | start (UTC) | end (UTC) | minutes |" <<<"$s1"'
ok "row swift-macos (421 s -> 8 min)" 'grep -qF "| swift-macos | success | 2025-11-04T23:46:40Z | 2025-11-04T23:53:41Z | 8 |" <<<"$s1"'
ok "row ios-sim failure (25 min)" 'grep -qE "^\| ios-sim \| failure \| .* \| 25 \|$" <<<"$s1"'
ok "row ios-device skipped, no timing" 'grep -qF "| ios-device | skipped | — | — | — |" <<<"$s1"'
ok "row plan" 'grep -qE "^\| plan \| success \|" <<<"$s1"'
ok "exactly 3 warnings" '[ "$(grep -c "^- WARNING:" <<<"$s1")" = 3 ]'
ok "file with GMSApiKey dropped" '! grep -q Info.plist.txt <<<"$files1" && grep -qF "dropped ios-sim/Info.plist.txt: contains GMSApiKey" <<<"$s1"'
ok "warning for the big file" 'grep -qF "dropped ios-sim/big.log" <<<"$s1"'
ok "warning for the key" 'grep -qF "dropped ios-sim/xctest.tail.log: contains a Google API key" <<<"$s1"'
ok "job summaries appended" 'grep -qF "Test run with 303 tests passed" <<<"$s1" && grep -qF "XCTest: failed" <<<"$s1"'
m1="$(rgit show "$branch:meta.json")"
ok "meta.json fields" '[ "$(jq -r ".ref, .sha, .runId, .jobs[\"ios-sim\"], .jobs.plan" <<<"$m1" | paste -sd " " -)" = "$ref 0123456789abcdef0123 1 failure success" ]'
ok "step summary names the branch" 'grep -qF "ci-results/$ref" "$tmp/step1.md"'
ok "stdout names the branch" 'grep -qF "ci-results/$ref" "$tmp/out1.txt"'
c1="$(rgit rev-parse "$branch")"

# --- Run 2: other content, a secret value in one file; the branch is replaced (still one orphan commit).
r2="$tmp/r2"
mkdir -p "$r2/result-ios-device"
printf '## ios-device\n\nSWIFT_ACTIVE_COMPILATION_CONDITIONS = NAPSTOP_DIAG\n' >"$r2/result-ios-device/summary.md"
printf 'build ok\nkey s3cr3t-value-123\n' >"$r2/result-ios-device/build.tail.log"
needs2='{"plan": {"result": "success"}, "ios-device": {"result": "success"}}'
REMOTE_URL="$remote" NEEDS_JSON="$needs2" SHA=fedcba9876543210 RUN_URL=https://example.invalid/run/2 RUN_ID=2 \
  SECRET_VALUES=$'\n s3cr3t-value-123\ns3cr3t-value-123\n' bash "$script" "$r2" "$ref" >/dev/null

c2="$(rgit rev-parse "$branch")"
ok "run 2 replaced the commit" '[ "$c1" != "$c2" ]'
ok "one commit on the branch" '[ "$(rgit rev-list --count "$branch")" = 1 ]'
ok "orphan (no parent)" '[ "$(rgit rev-list --max-parents=0 "$branch")" = "$c2" ]'
files2="$(rgit ls-tree -r --name-only "$branch")"
ok "run 1 files gone" '! grep -q swift-macos <<<"$files2"'
ok "file with secret value dropped" '! grep -q build.tail.log <<<"$files2" && ! rgit grep -q s3cr3t "$branch" --'
s2="$(rgit show "$branch:summary.md")"
ok "run 2 summary" 'grep -qF "commit fedcba9876543210" <<<"$s2" && grep -qF "NAPSTOP_DIAG" <<<"$s2"'
ok "run 2: one warning (secret)" '[ "$(grep -c "^- WARNING:" <<<"$s2")" = 1 ] && grep -qF "contains a secret value" <<<"$s2"'
ok "commit message" '[ "$(rgit log -1 --format=%s "$branch")" = "ci-results: $ref fedcba987654" ]'

# --- Plan failed (unknown prefix): still a summary, no job artifacts besides plan.
r3="$tmp/r3"
mkdir -p "$r3/result-plan"
printf '## plan\n\nerror: unknown prefix in branch ci/ios-foo-1\n' >"$r3/result-plan/summary.md"
needs3='{"plan": {"result": "failure"}, "swift-macos": {"result": "skipped"}, "ios-sim": {"result": "skipped"}, "ios-device": {"result": "skipped"}}'
REMOTE_URL="$remote" NEEDS_JSON="$needs3" SHA=abc bash "$script" "$r3" ci/ios-foo-1 >/dev/null
s3="$(rgit show refs/heads/ci-results/ci/ios-foo-1:summary.md)"
ok "plan failure recorded" 'grep -qF "| plan | failure |" <<<"$s3" && grep -qF "unknown prefix" <<<"$s3"'

# --- Bad input.
ok "rejects ref with .." '! REMOTE_URL="$remote" GITHUB_STEP_SUMMARY="$tmp/bad.md" bash "$script" "$r3" "ci/../x" 2>/dev/null'
ok "says why on the run page" 'grep -qF "not published: unsupported ref name" "$tmp/bad.md"'
ok "rejects bad NEEDS_JSON" '! REMOTE_URL="$remote" NEEDS_JSON="[1]" bash "$script" "$r3" ci/ios-x-1 2>/dev/null'
ok "missing results dir still publishes" 'REMOTE_URL="$remote" bash "$script" "$tmp/none" ci/ios-sim-empty >/dev/null && rgit rev-parse -q --verify refs/heads/ci-results/ci/ios-sim-empty >/dev/null'

echo "publish-ci-results: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
