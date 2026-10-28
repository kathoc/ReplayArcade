#!/usr/bin/env bash
# Each game of a ROM folder in its own processes: does it open in ReplayArcade (dump_layout: a session, so
# FBNeo can save its state), and does test_fbneo_core pass (record / seek / rewind / export / reopen)?
#   tools/check_games.sh <ROM dir> <out.tsv> [games...]   (default: every zip)
# Prints "<set>\t<open|no:reason>\t<pass|fail N|crash|timeout>" lines into out.tsv as it goes.
# Run inside the SDK the tree was built with (scripts/sdk-run.sh). BUILD_DIR (default build), TIMEOUT (240 s).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROMS=$1; OUT=$2; shift 2
B=${BUILD_DIR:-$ROOT/build}
games=("$@")
[ ${#games[@]} -eq 0 ] && games=($(ls "$ROMS" | sed -n 's/\.zip$//p'))
: > "$OUT"
for g in "${games[@]}"; do
  o=$(timeout 60 "$B/dump_layout" "$ROMS/$g.zip" 2>&1 | head -1)
  if [[ "$o" == *": "* ]]; then printf '%s\tno:%s\t-\n' "$g" "${o#*: }" >> "$OUT"; continue; fi
  log=$(REPLAYARCADE_ROMS=$ROMS REPLAYARCADE_GAMES=$g timeout "${TIMEOUT:-240}" "$B/test_fbneo_core" 2>&1); rc=$?
  case $rc in
    0) r=pass ;;
    124) r=timeout ;;
    1) r="fail $(grep -c FAILED <<< "$log")" ;;
    *) r="crash rc=$rc" ;;
  esac
  printf '%s\topen\t%s\n' "$g" "$r" >> "$OUT"
done
echo finished >> "$OUT.done"
