#!/usr/bin/env bash
# Runs the NapStopCore tests inside WSL (docs/specs/T13.md §10.1).
# From Git Bash: MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -e bash /mnt/d/work/gps-alarm/app/ios/Core/scripts/test-wsl.sh [swift test args]
set -euo pipefail
SWIFT_BIN="${NAPSTOP_SWIFT_BIN:-$HOME/opt/swift-6.4.1/usr/bin}"
export PATH="$SWIFT_BIN:$PATH"
version="$(swift --version 2>&1)"
echo "$version" | head -n 1
if ! grep -qF 'Swift version 6.4.1' <<<"$version"; then
  echo "error: Swift 6.4.1 required (set NAPSTOP_SWIFT_BIN)" >&2
  exit 1
fi
cd "$(dirname "${BASH_SOURCE[0]}")/.."
SCRATCH="${NAPSTOP_SCRATCH:-$HOME/.cache/napstop/core-build}"
mode="${NAPSTOP_CONFIG:-release}"
export NAPSTOP_REPORT_DIR="${NAPSTOP_REPORT_DIR:-$SCRATCH/napstop-report}"
echo "report dir: $NAPSTOP_REPORT_DIR"
exec swift test -c "$mode" --enable-testable-imports --scratch-path "$SCRATCH" "$@"
