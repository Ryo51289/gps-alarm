#!/usr/bin/env bash
# Builds the iOS alarm sounds app/ios/Runner/Sounds/alarm_{horn,bell,beep}.wav (docs/specs/T17.2.md D10) from the
# Android loops app/android/app/src/main/res/raw/alarm_*.wav (CC0, docs/third_party/alarm_sounds.md).
#
# Output format = the S3 probe tone that rang through AlarmKit (`WavTone.make`, spikes/ios-probe): WAV PCM 16-bit mono
# 44 100 Hz (review T17.2 #1). The 22 050 Hz sources are upsampled 2x by linear interpolation, wrapping from the last
# sample to the first so the loop stays seamless: out[2i] = s[i], out[2i+1] = trunc((s[i] + s[(i+1) mod n]) / 2). The
# loop is then repeated whole N times, N = the largest count that stays <= 29.5 s (must reach >= 28.0 s); < 30 s so the
# same file also works as a notification sound (T17.3, [I19]). Deterministic: same input bytes -> same output bytes
# (AU13 recomputes the same bytes in Swift).
#
# Tools: bash, od, awk, head, tail, cmp, mktemp (coreutils / BSD). No ffmpeg or sox needed.
#
# Usage (repo root or anywhere):
#   bash app/ios/scripts/make-alarm-sounds.sh                # writes app/ios/Runner/Sounds/
#   bash app/ios/scripts/make-alarm-sounds.sh --out DIR      # writes DIR/ (tests)
#   bash app/ios/scripts/make-alarm-sounds.sh --check        # rebuilds into a temp dir, compares with Runner/Sounds/
set -euo pipefail
export LC_ALL=C

ios_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_dir="$(cd "$ios_dir/../.." && pwd)"
src_dir="$repo_dir/app/android/app/src/main/res/raw"
committed_dir="$ios_dir/Runner/Sounds"
names=(horn bell beep)
out_rate=44100
max_ms=29500
min_ms=28000

die() {
  echo "error: $*" >&2
  exit 2
}

mode=write
out_dir="$committed_dir"
case "${1:-}" in
  '') ;;
  --out)
    [ -n "${2:-}" ] || die "--out needs a directory"
    out_dir="$2"
    ;;
  --check) mode=check ;;
  *) die "usage: make-alarm-sounds.sh [--out DIR | --check]" ;;
esac

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# u_le <file> <offset> <bytes>: unsigned little-endian integer.
u_le() {
  local v=0 i=0 b
  for b in $(od -An -tu1 -v -j "$2" -N "$3" "$1"); do
    v=$((v + (b << (8 * i))))
    i=$((i + 1))
  done
  [ "$i" -eq "$3" ] || die "$1: short read at $2"
  echo "$v"
}

# tag <file> <offset>: 4 ASCII bytes.
tag() { head -c $(($2 + 4)) "$1" | tail -c 4; }

# le16 / le32 <n>: little-endian bytes on stdout.
le16() { printf "\\x$(printf %02x $(($1 & 255)))\\x$(printf %02x $((($1 >> 8) & 255)))"; }
le32() {
  le16 $(($1 & 65535))
  le16 $((($1 >> 16) & 65535))
}

# upsample2 <src> <data bytes>: the source loop (16-bit mono) at twice the rate, on stdout.
upsample2() {
  tail -c +45 "$1" | head -c "$2" | od -An -v -tu1 | awk '
    { for (i = 1; i <= NF; i++) b[nb++] = $i }
    function hex(v) {
      if (v < 0) v += 65536
      return sprintf("\\x%02x\\x%02x", v % 256, int(v / 256))
    }
    END {
      n = int(nb / 2)
      for (i = 0; i < n; i++) {
        v = b[2 * i] + 256 * b[2 * i + 1]
        s[i] = v >= 32768 ? v - 65536 : v
      }
      line = ""
      for (i = 0; i < n; i++) {
        a = s[i]
        c = s[(i + 1) % n]
        line = line hex(a) hex(int((a + c) / 2))
        if (i % 256 == 255 || i == n - 1) {
          print line
          line = ""
        }
      }
    }' | while IFS= read -r l; do printf '%b' "$l"; done
}

build() {
  local name="$1" dest="$2" src len rate loop loop_len byte_rate n total ms k
  src="$src_dir/alarm_$name.wav"
  [ -f "$src" ] || die "missing $src"
  # Canonical 44-byte PCM header only (what the Android generator writes).
  [ "$(tag "$src" 0)" = RIFF ] && [ "$(tag "$src" 8)" = WAVE ] && [ "$(tag "$src" 12)" = "fmt " ] ||
    die "$src: not a RIFF/WAVE file"
  [ "$(u_le "$src" 16 4)" -eq 16 ] && [ "$(u_le "$src" 20 2)" -eq 1 ] || die "$src: not plain PCM (fmt size 16, tag 1)"
  [ "$(u_le "$src" 22 2)" -eq 1 ] && [ "$(u_le "$src" 34 2)" -eq 16 ] || die "$src: not 16-bit mono"
  [ "$(tag "$src" 36)" = data ] || die "$src: data chunk not at offset 36"
  len="$(u_le "$src" 40 4)"
  rate="$(u_le "$src" 24 4)"
  [ "$len" -gt 0 ] && [ $((len % 2)) -eq 0 ] || die "$src: bad data size"
  loop="$work/$name.loop"
  case "$rate" in
    "$out_rate") tail -c +45 "$src" | head -c "$len" >"$loop" ;;
    $((out_rate / 2))) upsample2 "$src" "$len" >"$loop" ;;
    *) die "$src: sample rate $rate (need $out_rate or $((out_rate / 2)))" ;;
  esac
  loop_len="$(wc -c <"$loop" | tr -d ' ')"
  byte_rate=$((out_rate * 2))
  [ "$loop_len" -eq $((len * out_rate / rate)) ] || die "$name: upsampled loop is $loop_len bytes"
  n=$((max_ms * byte_rate / (1000 * loop_len)))
  total=$((n * loop_len))
  ms=$((total * 1000 / byte_rate))
  [ "$ms" -ge "$min_ms" ] || die "$name: $n loops = $ms ms < $min_ms ms"
  {
    printf RIFF
    le32 $((36 + total))
    printf 'WAVEfmt '
    le32 16
    le16 1 # PCM
    le16 1 # mono
    le32 "$out_rate"
    le32 "$byte_rate"
    le16 2  # block align
    le16 16 # bits per sample
    printf data
    le32 "$total"
    k=0
    while [ "$k" -lt "$n" ]; do
      cat "$loop"
      k=$((k + 1))
    done
  } >"$dest.tmp"
  mv "$dest.tmp" "$dest"
  echo "alarm_$name.wav: $n x $loop_len bytes, $out_rate Hz, $ms ms"
}

if [ "$mode" = check ]; then
  mkdir -p "$work/out"
  for name in "${names[@]}"; do build "$name" "$work/out/alarm_$name.wav" >/dev/null; done
  bad=0
  for name in "${names[@]}"; do
    if ! cmp -s "$work/out/alarm_$name.wav" "$committed_dir/alarm_$name.wav"; then
      echo "differs: Runner/Sounds/alarm_$name.wav (run make-alarm-sounds.sh)" >&2
      bad=1
    fi
  done
  [ "$bad" -eq 0 ] || exit 1
  echo "check OK: Runner/Sounds matches the generator"
  exit 0
fi

mkdir -p "$out_dir"
for name in "${names[@]}"; do build "$name" "$out_dir/alarm_$name.wav"; done
