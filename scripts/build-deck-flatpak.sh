#!/bin/bash
# Builds and installs ReplayArcade's Flatpak on the Steam Deck (as ReplayNES's
# scripts/build-linux-flatpak.sh does for ReplayNES): copies ReplayArcade and ReplayNES's source
# tree to ~/ReplayArcade-dev/src on the Deck and runs flatpak-builder there (--user install).
#   scripts/build-deck-flatpak.sh [user@host]      (default deck@steamdeck.local)
# Env: REPLAYNES_DIR (default: the ReplayNES worktree used by CMakeLists.txt), NO_INSTALL=1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:-deck@steamdeck.local}"
RN="${REPLAYNES_DIR:-$HOME/Playground/ReplayNES/.claude/worktrees/generalize}"
RDIR=ReplayArcade-dev
APP_ID=io.github.kathoc.ReplayArcade
"$ROOT/scripts/fbneo-patches.sh" --check >/dev/null || { echo "FBNeo patches are not applied" >&2; exit 1; }
COMMON=(--exclude=/.git --exclude=.git --exclude='/build/' --exclude='/build-*/' --exclude=/.flatpak-builder/
  --exclude=/dist/ --exclude='*.o' --exclude='*.d' --exclude='*.a' --exclude='*.so' --exclude='*.zip' --exclude='*.7z'
  --exclude='*.nes' --exclude=/roms/)
echo "==> sync ReplayArcade and ReplayNES ($RN) -> $HOST:~/$RDIR/src"
ssh "$HOST" "mkdir -p ~/$RDIR/src/third_party/replaynes"
rsync -a --delete "${COMMON[@]}" --exclude=/third_party/replaynes/ -e ssh "$ROOT/" "$HOST:$RDIR/src/"
rsync -a --delete "${COMMON[@]}" --exclude=/.claude/ --exclude=/third_party/nestopia/ --exclude=/third_party/syphon/ \
  --exclude=/third_party/SDL/ --exclude=/apps/macos/ --exclude=/apps/windows/ -e ssh "$RN/" "$HOST:$RDIR/src/third_party/replaynes/"
INSTALL="--install"
[ "${NO_INSTALL:-0}" = "1" ] && INSTALL=""
echo "==> flatpak-builder on $HOST"
ssh "$HOST" "cd ~/$RDIR && (flatpak info --user org.flatpak.Builder >/dev/null 2>&1 || flatpak install --user -y --noninteractive flathub org.flatpak.Builder) && \
  flatpak run org.flatpak.Builder --user $INSTALL --force-clean --disable-updates --state-dir=.flatpak-builder \
  --repo=repo build-flatpak src/packaging/linux/$APP_ID.yml"
echo "==> done. Run on $HOST: flatpak run $APP_ID"
