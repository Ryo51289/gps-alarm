#!/usr/bin/env bash
# Spike T23.8-B0 (docs/spikes/T23.8.md): adds NSLocationAlwaysAndWhenInUseUsageDescription to the Info.plist of a built
# NAPSTOP_DIAG app, so the region probe (Runner/Native/DiagCommuteProbe.swift) can ask for "Always". The source
# Info.plist stays without the key until T23.8 C2 (T29.2 FU03 forbids it there today). macOS only (plutil).
#   bash ios/scripts/diag-always-key.sh build/ios/iphoneos/Runner.app
set -euo pipefail

app="${1:?usage: diag-always-key.sh <Runner.app>}"
plist="$app/Info.plist"
key=NSLocationAlwaysAndWhenInUseUsageDescription
# Same text as docs/specs/T23.8.md §5.12 (vi, the source language).
text='NapStop dùng vị trí cả khi app đang đóng để tự bật báo thức khi bạn tới điểm đón của tuyến đi làm, trong khung giờ bạn chọn. Vị trí không rời khỏi máy.'

[ -f "$plist" ] || { echo "error: $plist not found" >&2; exit 1; }
if plutil -extract "$key" raw "$plist" >/dev/null 2>&1; then
  echo "- $key: already present"
  exit 0
fi
plutil -insert "$key" -string "$text" "$plist"
plutil -extract "$key" raw "$plist" >/dev/null
plutil -lint "$plist"
echo "- $key: added (diag build only, T23.8 B0)"
