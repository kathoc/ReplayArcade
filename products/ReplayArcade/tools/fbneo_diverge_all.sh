#!/usr/bin/env bash
# tools/fbneo_diverge on many games, one process each: one line per game, "<set>\t<first picture/sound
# difference>\t<first state difference>\t<state areas differing there>" ("-1": none), to group the games
# by what their state loads leave out.
#   tools/fbneo_diverge_all.sh <ROM dir> <out.tsv> <games...>
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROMS=$1; OUT=$2; shift 2
: > "$OUT"
for g in "$@"; do
  o=$(timeout 300 "$ROOT/build/fbneo_diverge" "$ROMS/$g.zip" 1200 2>&1)
  rc=$?
  first=$(sed -n 's/.*first picture\/sound difference: \(-\?[0-9]*\); first state difference: \(-\?[0-9]*\).*/\1\t\2/p' <<< "$o")
  [ -z "$first" ] && first="error rc=$rc	-"
  areas=$(grep -o 'area [0-9]* "[^"]*"' <<< "$o" | sed 's/area [0-9]* //' | sort -u | paste -sd, -)
  printf '%s\t%s\t%s\n' "$g" "$first" "$areas" >> "$OUT"
done
