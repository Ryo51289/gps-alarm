#!/usr/bin/env bash
# macOS helper for the jobs of .github/workflows/ios-compile.yml (docs/specs/T01.2.md §5). macOS only
# (xcrun simctl, xcode-select, jq, perl; all on the GitHub macOS runner images).
#
#   ci-sim.sh xcode                     select the newest release Xcode 26.x (else the newest release >= 26, with a
#                                       warning), check it has an iOS >= 26 SDK; prints "id=<version>-<build>" on stdout
#                                       (for $GITHUB_OUTPUT / cache keys), details on stderr
#   ci-sim.sh select                    print the UDID of an available iPhone on the newest iOS runtime (>= 26 preferred);
#                                       the choice (name, runtime) goes to stderr
#   ci-sim.sh prepare <udid> <bundle>   boot, wait, print `simctl help location|privacy`, then `grant`
#   ci-sim.sh grant <udid> <bundle>     fake-alarm switch (T17 §5.13) + location permission; failures are warnings.
#                                       Run again once the app is installed (the grant may need an installed app).
#   ci-sim.sh location <udid> <lat,lng> set the simulated location
#   ci-sim.sh timeout <seconds> <cmd...> run cmd with a time limit; on expiry the whole process group gets TERM, then
#                                       KILL 30 s later, exit 124 (GNU timeout or gtimeout if present, else perl)
#   ci-sim.sh shutdown                  shut down every simulator
#
# Coordinates only come from app/integration_test/ios_suite.txt (public fixture points); they are never written to the
# result summary.
set -euo pipefail

warn() {
  echo "::warning::$*" >&2
}

die() {
  echo "::error::$*" >&2
  exit 1
}

need_jq() {
  command -v jq >/dev/null 2>&1 || die "ci-sim.sh needs jq"
}

cmd_xcode() {
  local root="${NAPSTOP_XCODE_ROOT:-/Applications}" list pick ver path id
  # "<version> <path>" for release bundles only: Xcode_26.6.app, Xcode_26.4.1.app; Xcode_27.0_beta_2.app is skipped.
  list="$(
    for x in "$root"/Xcode_*.app; do
      [ -d "$x" ] || continue
      ver="${x##*/Xcode_}"
      ver="${ver%.app}"
      case "$ver" in '' | *[!0-9.]*) continue ;; esac
      echo "$ver $x"
    done | sort -V -k1,1
  )"
  pick="$(awk '$1 ~ /^26(\.|$)/' <<<"$list" | tail -n 1)"
  if [ -z "$pick" ]; then
    pick="$(awk '{ split($1, v, "."); if (v[1] + 0 >= 26) print }' <<<"$list" | tail -n 1)"
    [ -n "$pick" ] || die "no release Xcode >= 26 under $root (found: $(awk '{print $1}' <<<"$list" | paste -sd ' ' -))"
    warn "no Xcode 26.x on this runner; using Xcode ${pick%% *}"
  fi
  ver="${pick%% *}"
  path="${pick#* }"
  sudo xcode-select -s "$path/Contents/Developer"
  xcodebuild -version >&2
  # Read the whole list first: under pipefail, `xcodebuild | grep -q` fails with SIGPIPE when grep exits early
  # (first CI run, 06/11).
  local sdks
  sdks="$(xcodebuild -showsdks 2>/dev/null || true)"
  if ! grep -qE 'iphoneos(2[6-9]|[3-9][0-9])' <<<"$sdks"; then
    die "Xcode $ver at $path has no iOS >= 26 SDK"
  fi
  id="$(xcodebuild -version | tr '\n' ' ' | sed -nE 's/^Xcode ([^ ]+) Build version ([^ ]+).*/\1-\2/p')"
  echo "Xcode selected: $path (${id:-$ver})" >&2
  echo "id=${id:-$ver}"
}

cmd_select() {
  need_jq
  local json best
  json="$(xcrun simctl list devices available -j)"
  # major<TAB>minor<TAB>name<TAB>udid for every available iPhone on an iOS runtime.
  best="$(jq -r '
      .devices | to_entries[]
      | select(.key | test("SimRuntime\\.iOS-[0-9]+-[0-9]+"))
      | (.key | capture("iOS-(?<maj>[0-9]+)-(?<min>[0-9]+)")) as $v
      | .value[]
      | select(.isAvailable != false and (.name | startswith("iPhone")))
      | [$v.maj, $v.min, .name, .udid] | @tsv' <<<"$json" |
    sort -t $'\t' -k1,1n -k2,2n -k3,3 | tail -n 1)"
  [ -n "$best" ] || die "no available iPhone simulator on an iOS runtime (xcrun simctl list devices available)"
  local maj min name udid
  IFS=$'\t' read -r maj min name udid <<<"$best"
  if [ "$maj" -lt 26 ]; then
    warn "no iOS 26+ simulator runtime on this runner; using iOS $maj.$min"
  fi
  echo "Simulator: $name, iOS $maj.$min ($udid)" >&2
  echo "$udid"
}

cmd_prepare() {
  local udid="${1:?udid}" bundle="${2:?bundle id}"
  # Already booted -> boot fails; bootstatus -b boots if needed and waits either way.
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b
  echo "--- xcrun simctl help location"
  xcrun simctl help location 2>&1 || true
  echo "--- xcrun simctl help privacy"
  xcrun simctl help privacy 2>&1 || true
  echo "---"
  cmd_grant "$udid" "$bundle"
}

cmd_grant() {
  local udid="${1:?udid}" bundle="${2:?bundle id}"
  if xcrun simctl spawn "$udid" defaults write "$bundle" napstop.diag.fakeAlarms -bool YES; then
    echo "fakeAlarms: set for $bundle"
  else
    warn "could not set napstop.diag.fakeAlarms for $bundle"
  fi
  if xcrun simctl privacy "$udid" grant location "$bundle"; then
    echo "privacy grant location: ok for $bundle"
  else
    warn "simctl privacy grant location failed for $bundle (app not installed yet?)"
  fi
}

cmd_location() {
  local udid="${1:?udid}" point="${2:?lat,lng}"
  [[ "$point" =~ ^-?[0-9]+(\.[0-9]+)?,-?[0-9]+(\.[0-9]+)?$ ]] || die "location must be <lat>,<lng>, got '$point'"
  xcrun simctl location "$udid" set "$point"
}

cmd_timeout() {
  local secs="${1:?seconds}"
  shift
  [ "$#" -gt 0 ] || die "timeout needs a command"
  [[ "$secs" =~ ^[0-9]+$ ]] || die "timeout seconds must be an integer, got '$secs'"
  # GNU timeout runs the command in its own process group and signals the whole group.
  if command -v timeout >/dev/null 2>&1; then
    echo "ci-sim timeout: GNU timeout, ${secs}s" >&2
    exec timeout -k 30 "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    echo "ci-sim timeout: gtimeout, ${secs}s" >&2
    exec gtimeout -k 30 "$secs" "$@"
  fi
  # Same behaviour in perl (on every macOS image): the command leads a new process group, so on expiry its children
  # (xcodebuild, flutter tool, simulator helpers) die too and the `| tee` of the step sees EOF.
  echo "ci-sim timeout: perl process-group fallback, ${secs}s" >&2
  exec perl -e '
    use strict;
    use POSIX ();
    my $secs = shift @ARGV;
    my $pid = fork();
    die "fork: $!\n" unless defined $pid;
    if ($pid == 0) {
      setpgrp(0, 0);
      exec { $ARGV[0] } @ARGV or die "exec $ARGV[0]: $!\n";
    }
    setpgrp($pid, $pid);    # also from the parent: no window where the group does not exist yet
    for my $sig (qw(TERM INT HUP)) {
      $SIG{$sig} = sub { kill $sig, -$pid; };
    }
    $SIG{ALRM} = sub {
      print STDERR "ci-sim timeout: ${secs}s elapsed, terminating process group $pid\n";
      kill "TERM", -$pid;
      for (1 .. 30) { waitpid($pid, POSIX::WNOHANG()); last unless kill 0, -$pid; sleep 1; }
      kill "KILL", -$pid;
      exit 124;
    };
    alarm $secs;
    while (1) {
      my $w = waitpid($pid, 0);
      last if $w == $pid;
      next if $w == -1 && $!{EINTR};
      last;
    }
    alarm 0;
    exit(($? & 127) ? 128 + ($? & 127) : ($? >> 8));
  ' "$secs" "$@"
}

sub="${1:-}"
[ "$#" -gt 0 ] && shift
case "$sub" in
  xcode) cmd_xcode "$@" ;;
  select) cmd_select "$@" ;;
  prepare) cmd_prepare "$@" ;;
  grant) cmd_grant "$@" ;;
  location) cmd_location "$@" ;;
  timeout) cmd_timeout "$@" ;;
  shutdown) xcrun simctl shutdown all ;;
  *) die "usage: ci-sim.sh xcode | select | prepare <udid> <bundle> | grant <udid> <bundle> | location <udid> <lat,lng> | timeout <s> <cmd...> | shutdown" ;;
esac
