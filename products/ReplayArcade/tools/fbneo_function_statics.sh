#!/usr/bin/env bash
# Lists FinalBurn Neo's mutable function statics ("Function()::name" in the data / bss of a binary that
# links FBNeo): a static inside a function survives a state load, so emulation state kept there makes
# replays differ (docs: REPLAYARCADE_STATE in third_party/fbneo/src/burn/state.h). Run after updating
# FBNeo; read each one, and move those that are emulation state with tools/fbneo_move_statics.py.
#   tools/fbneo_function_statics.sh [binary=build/fbneo_bisect]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/build/fbneo_bisect}"
nm -C --defined-only -S "$BIN" | awk 'NF >= 4 && $3 ~ /^[bBdD]$/' |
  grep -E '\)::[A-Za-z_]' |
  grep -vE '^[^ ]+ [^ ]+ [^ ]+ ((rn|rac|std|rnf|rnl|__gnu_cxx)::|\(anonymous namespace\)::|guard variable)' |
  cut -d' ' -f4- | sort -u
