#!/usr/bin/env bash
# Table test for ios-ci-plan.sh (docs/specs/T01.2.md §2, §3, CI01). Run: bash .github/scripts/ios-ci-plan.test.sh
set -euo pipefail
script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios-ci-plan.sh"

pass=0
failed=0

# check <expected exit> <expected stdout as "swift sim ipa diag telemetry" or "-"> <args...>
check() {
  local want_rc="$1" want="$2" out rc got
  shift 2
  set +e
  out="$(bash "$script" "$@" 2>/dev/null)"
  rc=$?
  set -e
  if [ "$want" = "-" ]; then
    got="-"
    [ -z "$out" ] || got="unexpected stdout: $out"
  else
    got="$(printf '%s\n' "$out" | sed -n 's/^\(swift\|sim\|ipa\|diag\|telemetry\)=//p' | paste -sd ' ' -)"
    # The five keys, in this order, and nothing else.
    if [ "$(printf '%s\n' "$out" | cut -d= -f1 | paste -sd ' ' -)" != "swift sim ipa diag telemetry" ]; then
      got="bad keys: $out"
    fi
  fi
  if [ "$rc" = "$want_rc" ] && [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: $* -> rc=$rc '$got' (want rc=$want_rc '$want')"
  fi
}

#     rc  swift sim   ipa   diag  telemetry     event / ref / target / diag / telemetry
check 0 "true false false false false" push ci/ios-swift-x
check 0 "false true false false false" push ci/ios-sim-t17-r1
check 0 "false false true true false" push ci/ios-ipa-t012
check 0 "true true true true false" push ci/ios-all-t17-r1
check 0 "true true true true false" push ci/ios-all-a.b_c-1
check 2 - push ci/ios-foo
check 2 - push ci/ios-foo-t012
check 2 - push ci/ios-
check 2 - push ci/ios-swift-
check 2 - push ci/iosall-x
check 2 - push ci/ios-all-x/y
check 2 - push feature/x
check 2 - push main
check 0 "true false false false false" workflow_dispatch main swift
check 0 "false true false false false" workflow_dispatch main simulator
check 0 "false true false false false" workflow_dispatch main simulator true
check 0 "false false true false false" workflow_dispatch main device
check 0 "false false true false false" workflow_dispatch main device false
check 0 "false false true true false" workflow_dispatch main device true
check 0 "false true true false false" workflow_dispatch main both
check 0 "false true true true false" workflow_dispatch main both true
check 0 "true true true false false" workflow_dispatch main all
check 0 "true true true true false" workflow_dispatch main all true
check 2 - workflow_dispatch main nope
check 2 - workflow_dispatch main both maybe
check 2 - pull_request ci/ios-all-x
check 2 -
# T29.2 FU09: telemetry ("fb" test IPA) only with ipa; the other lines do not change.
check 0 "false false true true true" push ci/ios-ipa-fb-x
check 0 "true true true true true" push ci/ios-all-fb-x
check 0 "false false true true false" push ci/ios-ipa-x
check 0 "false true false false false" push ci/ios-sim-fb-x
check 0 "true false false false false" push ci/ios-swift-fb-x
check 0 "false false true true false" push ci/ios-ipa-xfb-1
check 2 - push ci/ios-fb-x
check 0 "false false true false true" workflow_dispatch main device false true
check 0 "false false true false false" workflow_dispatch main device false false
check 0 "false false true true true" workflow_dispatch main device true true
check 0 "false true true false true" workflow_dispatch main both '' true
check 0 "true false false false false" workflow_dispatch main swift false true
check 0 "false true false false false" workflow_dispatch main simulator false true
check 2 - workflow_dispatch main device false maybe

# An error says what to do.
msg="$(bash "$script" push ci/ios-foo 2>&1 >/dev/null || true)"
if grep -q 'unknown prefix' <<<"$msg" && grep -q 'swift-/sim-/ipa-/all-' <<<"$msg"; then
  pass=$((pass + 1))
else
  failed=$((failed + 1))
  echo "FAIL: error message for ci/ios-foo: $msg"
fi

echo "ios-ci-plan: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
