#!/usr/bin/env bash
# Picks the jobs of ios-compile.yml from the event and the branch name (docs/specs/T01.2.md §2, §3).
#
# usage: ios-ci-plan.sh <event_name> <ref_name> [dispatch_target] [dispatch_diag]
# stdout: four lines "swift=true|false", "sim=...", "ipa=...", "diag=..." (the plan job appends them to $GITHUB_OUTPUT)
# exit 2 with a message on stderr for an unknown branch prefix, dispatch target or event; stdout stays empty then.
#
# push ci/ios-swift-<id> -> swift; ci/ios-sim-<id> -> sim; ci/ios-ipa-<id> -> ipa + diag; ci/ios-all-<id> -> everything.
# workflow_dispatch: target swift | simulator | device | both | all; diag comes from the `diag` input and only applies with ipa.
# <id> is [A-Za-z0-9._-]+. No network, bash only.
set -euo pipefail

fail() {
  echo "::error::$*" >&2
  exit 2
}

event="${1:-}"
ref="${2:-}"
target="${3:-}"
diag_in="${4:-}"

swift=false
sim=false
ipa=false
diag=false

case "$event" in
  push)
    prefix=""
    id=""
    case "$ref" in
      ci/ios-swift-* | ci/ios-sim-* | ci/ios-ipa-* | ci/ios-all-*)
        rest="${ref#ci/ios-}"
        prefix="${rest%%-*}"
        id="${rest#*-}"
        ;;
      *)
        fail "unknown prefix in branch '$ref'; use ci/ios-swift-<id>, ci/ios-sim-<id>, ci/ios-ipa-<id> or ci/ios-all-<id> (swift-/sim-/ipa-/all-)"
        ;;
    esac
    if [[ ! "$id" =~ ^[A-Za-z0-9._-]+$ ]]; then
      fail "branch '$ref' needs an id after ci/ios-$prefix- made of [A-Za-z0-9._-]"
    fi
    case "$prefix" in
      swift) swift=true ;;
      sim) sim=true ;;
      ipa) ipa=true; diag=true ;;
      all) swift=true; sim=true; ipa=true; diag=true ;;
    esac
    ;;
  workflow_dispatch)
    case "$diag_in" in
      '' | false) d=false ;;
      true) d=true ;;
      *) fail "dispatch input diag must be true or false, got '$diag_in'" ;;
    esac
    case "$target" in
      swift) swift=true ;;
      simulator) sim=true ;;
      device) ipa=true ;;
      both) sim=true; ipa=true ;;
      all) swift=true; sim=true; ipa=true ;;
      *) fail "unknown dispatch target '$target'; use swift, simulator, device, both or all" ;;
    esac
    if [ "$ipa" = true ]; then diag="$d"; fi
    ;;
  *)
    fail "unsupported event '$event' (push to ci/ios-** or workflow_dispatch)"
    ;;
esac

printf 'swift=%s\nsim=%s\nipa=%s\ndiag=%s\n' "$swift" "$sim" "$ipa" "$diag"
