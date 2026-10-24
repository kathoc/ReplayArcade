#!/usr/bin/env bash
# Runs Windows (x64) builds on the Steam Deck with Steam's Proton, as a stand-in for a Windows machine
# (the Windows VM is on the Mac). Everything lives in ~/winetest on the Deck.
#   scripts/windows-on-deck.sh test [games...]     build/win64 test_fbneo_core.exe on the Deck's ROMs
#   scripts/windows-on-deck.sh app <app args...>   ReplayArcade.exe (build/windows) via `proton run`
# Env: DECK (deck@steamdeck.local), PROTON ("Proton 11.0").
# Notes: tests run with Proton's wine directly (no GPU needed); the app needs `proton run` (DXVK for
# Direct3D 11). Proton's Media Foundation has no H.264 encoder: MP4 export cannot be checked here.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DECK="${DECK:-deck@steamdeck.local}"
PROTON="${PROTON:-Proton 11.0}"
P="\$HOME/.local/share/Steam/steamapps/common/$PROTON"
ROMS='Z:\home\deck\Documents\ReplayArcade\ROM'
cmd="${1:?test or app}"; shift
ssh "$DECK" 'mkdir -p ~/winetest/shots'
case "$cmd" in
  test)
    scp -q "$ROOT/build-win64/test_fbneo_core.exe" "$DECK:winetest/"
    ssh "$DECK" "cd ~/winetest; export WINEPREFIX=\$HOME/winetest/prefix WINEDEBUG=-all REPLAYARCADE_ROMS='$ROMS' ${*:+REPLAYARCADE_GAMES='$*'}; \"$P/files/bin/wine\" test_fbneo_core.exe 2>&1"
    ;;
  app)
    scp -q "$ROOT/build/windows/windows-x86_64/apps/windows/ReplayArcade.exe" "$DECK:winetest/"
    args=$(printf '%q ' "$@")
    ssh "$DECK" "cd ~/winetest; export STEAM_COMPAT_DATA_PATH=\$HOME/winetest/compat STEAM_COMPAT_CLIENT_INSTALL_PATH=\$HOME/.local/share/Steam DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000; mkdir -p compat; \"$P/proton\" run ReplayArcade.exe $args"
    ;;
  *) echo "usage: $0 test [games...] | app <args...>" >&2; exit 2 ;;
esac
