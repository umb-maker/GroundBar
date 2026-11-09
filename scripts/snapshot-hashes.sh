#!/bin/sh
# Renders every surface in demo mode and prints a SHA-256 per PNG.
# Run it before and after a refactor: the two lists must match line for line.
#
#   swift build && scripts/snapshot-hashes.sh /tmp/before > before.txt
#   (refactor)
#   swift build && scripts/snapshot-hashes.sh /tmp/after > after.txt && diff before.txt after.txt
set -e
OUT="${1:?usage: snapshot-hashes.sh <output-dir> [binary]}"
BIN="${2:-.build/debug/Groundbar}"
cd "$(dirname "$0")/.."
rm -rf "${OUT:?}"; mkdir -p "$OUT"
GROUNDBAR_DEMO=1 \
GROUNDBAR_SNAPSHOT_STEPS=bar,start,quick,btc,toast,preview,welcome,settings-general,settings-appearance,settings-taskbar,settings-shortcuts,settings-permissions,settings-about \
  "$BIN" --snapshot "$OUT" -AppleLanguages "(en)" -theme dark >/dev/null 2>&1 &
PID=$!
# 13 steps, 3 seconds each, plus launch.
sleep 48
kill "$PID" 2>/dev/null || true
# bar-layers.png carries the animated seasonal decorations: not repeatable.
rm -f "$OUT/bar-layers.png"
cd "$OUT" && shasum -a 256 ./*.png | awk '{print $1, $2}'
