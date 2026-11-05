#!/usr/bin/env bash
# Publishes the text results of an ios-compile.yml run to the branch ci-results/<ref_name> (docs/specs/T01.2.md §7).
# The orchestrator reads them with `git fetch` (no token, no gh).
#
# usage: publish-ci-results.sh <results_dir> <ref_name>
#   <results_dir>/result-<job>/...  one directory per job artifact (actions/download-artifact, pattern result-*)
# environment:
#   REMOTE_URL     push target; default https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git
#                  (the test uses a local bare repository)
#   SECRET_VALUES  values that must never be published, one per line (empty lines ignored)
#   NEEDS_JSON     ${{ toJSON(needs) }}: job -> {result}; gives the result column
#   RUN_URL, RUN_ID, SHA   shown in summary.md / meta.json
# Each job may leave timing.env (start_epoch=, end_epoch=) and summary.md in its artifact.
#
# Safety (D7): files over 1 MB are dropped, *.log files are cut to their last 400 lines, and any file holding a
# SECRET_VALUES entry, "GMSApiKey" or an "AIza..." key is dropped; each drop is a warning in summary.md.
# The branch holds one orphan commit, replaced on every run (force push).
# Needs bash, git, jq (preinstalled on ubuntu-24.04 runners), GNU date.
set -euo pipefail

fail() {
  echo "::error::$*" >&2
  # No result branch then: say why on the run page (review T01.2 #10).
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "publish-ci-results: not published: $*" >>"$GITHUB_STEP_SUMMARY"; fi
  exit 1
}

results_dir="${1:-}"
ref_name="${2:-}"
[ -n "$results_dir" ] && [ -n "$ref_name" ] || fail "usage: publish-ci-results.sh <results_dir> <ref_name>"
[[ "$ref_name" =~ ^[A-Za-z0-9._/-]+$ ]] && [[ "$ref_name" != *..* ]] || fail "unsupported ref name '$ref_name'"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v git >/dev/null 2>&1 || fail "git is required"

if [ -z "${REMOTE_URL:-}" ]; then
  [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] || fail "set REMOTE_URL, or GITHUB_TOKEN and GITHUB_REPOSITORY"
  REMOTE_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
fi
needs_json="${NEEDS_JSON:-}"
[ -n "$needs_json" ] || needs_json='{}'
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$needs_json" || fail "NEEDS_JSON is not a JSON object"

max_bytes=$((1024 * 1024))
max_log_lines=400
branch="ci-results/$ref_name"
sha="${SHA:-unknown}"
run_url="${RUN_URL:-}"
run_id="${RUN_ID:-}"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
warnings=()

# The secret values, without empty lines (an empty pattern would match every file).
secrets=()
while IFS= read -r v; do
  v="${v%$'\r'}"
  [ -n "$v" ] && secrets+=("$v")
done <<<"${SECRET_VALUES:-}"

# 1. Gather result-<job>/** into out/<job>/.
if [ -d "$results_dir" ]; then
  for dir in "$results_dir"/result-*/; do
    [ -d "$dir" ] || continue
    job="$(basename "$dir")"
    job="${job#result-}"
    mkdir -p "$out/$job"
    cp -R "$dir". "$out/$job/"
  done
fi

# 2. Filter every gathered file.
while IFS= read -r -d '' f; do
  rel="${f#"$out"/}"
  size="$(wc -c <"$f" | tr -d ' ')"
  if [ "$size" -gt "$max_bytes" ]; then
    rm -f "$f"
    warnings+=("dropped $rel: $size bytes (> 1 MB)")
    continue
  fi
  reason=""
  for v in "${secrets[@]+"${secrets[@]}"}"; do
    if grep -qaF -- "$v" "$f"; then reason="a secret value"; break; fi
  done
  if [ -z "$reason" ] && grep -qaF 'GMSApiKey' "$f"; then reason="GMSApiKey"; fi
  if [ -z "$reason" ] && grep -qaE 'AIza[0-9A-Za-z_-]{20,}' "$f"; then reason="a Google API key"; fi
  if [ -n "$reason" ]; then
    rm -f "$f"
    warnings+=("dropped $rel: contains $reason")
    continue
  fi
  case "$f" in
    *.log)
      if [ "$(wc -l <"$f" | tr -d ' ')" -gt "$max_log_lines" ]; then
        tail -n "$max_log_lines" "$f" >"$f.tail" && mv "$f.tail" "$f"
      fi
      ;;
  esac
done < <(find "$out" -type f -print0 | sort -z)

# Value of key in out/<job>/timing.env, or empty.
timing() {
  local file="$out/$1/timing.env"
  [ -f "$file" ] || return 0
  sed -n "s/^$2=\([0-9][0-9]*\)\$/\1/p" "$file" | head -n 1
}

iso() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ
}

# Jobs: those in NEEDS_JSON in their order, then any other result directory.
mapfile -t jobs < <(jq -r 'keys_unsorted[]' <<<"$needs_json")
for dir in "$out"/*/; do
  [ -d "$dir" ] || continue
  j="$(basename "$dir")"
  known=false
  for k in "${jobs[@]+"${jobs[@]}"}"; do [ "$k" = "$j" ] && known=true; done
  [ "$known" = true ] || jobs+=("$j")
done

# 3. summary.md and meta.json.
{
  echo "# CI iOS — $ref_name"
  echo
  echo "commit $sha · run ${run_url:-n/a} · $now"
  echo
  echo "| job | result | start (UTC) | end (UTC) | minutes |"
  echo "|---|---|---|---|---|"
  for j in "${jobs[@]+"${jobs[@]}"}"; do
    result="$(jq -r --arg j "$j" '.[$j].result // "n/a"' <<<"$needs_json")"
    s="$(timing "$j" start_epoch)"
    e="$(timing "$j" end_epoch)"
    start="—" end="—" minutes="—"
    [ -n "$s" ] && start="$(iso "$s")"
    [ -n "$e" ] && end="$(iso "$e")"
    if [ -n "$s" ] && [ -n "$e" ] && [ "$e" -ge "$s" ]; then
      minutes=$(((e - s + 59) / 60))
    fi
    echo "| $j | $result | $start | $end | $minutes |"
  done
  if [ "${#warnings[@]}" -gt 0 ]; then
    echo
    echo "## Warnings"
    echo
    for w in "${warnings[@]}"; do echo "- WARNING: $w"; done
  fi
  for j in "${jobs[@]+"${jobs[@]}"}"; do
    if [ -f "$out/$j/summary.md" ]; then
      echo
      cat "$out/$j/summary.md"
    fi
  done
} >"$out/summary.md.new"
mv "$out/summary.md.new" "$out/summary.md"

jobs_json="$(
  for j in "${jobs[@]+"${jobs[@]}"}"; do
    jq -n --arg j "$j" --arg r "$(jq -r --arg j "$j" '.[$j].result // "n/a"' <<<"$needs_json")" '{($j): $r}'
  done | jq -s 'add // {}'
)"
jq -n --arg ref "$ref_name" --arg sha "$sha" --arg runId "$run_id" --arg runUrl "$run_url" \
  --arg at "$now" --argjson jobs "$jobs_json" --argjson warnings "${#warnings[@]}" \
  '{ref: $ref, sha: $sha, runId: $runId, runUrl: $runUrl, publishedAt: $at, jobs: $jobs, warnings: $warnings}' \
  >"$out/meta.json"

# 4. One orphan commit, force-pushed.
git_q() {
  git -C "$out" -c core.autocrlf=false -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
git_q init -q
git_q symbolic-ref HEAD refs/heads/results
git_q add -A
git_q -c user.name='napstop-ci' -c user.email='napstop-ci@users.noreply.github.com' \
  commit -qm "ci-results: $ref_name ${sha:0:12}"
git_q push -q --force "$REMOTE_URL" "HEAD:refs/heads/$branch"

# 5. Where to read it.
msg="Results: branch \`$branch\` (git fetch origin $branch && git show FETCH_HEAD:summary.md)"
echo "$msg"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "$msg"
    for w in "${warnings[@]+"${warnings[@]}"}"; do echo "- WARNING: $w"; done
  } >>"$GITHUB_STEP_SUMMARY"
fi
