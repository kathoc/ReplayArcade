#!/bin/bash
# Builds and installs ReplayArcade's Flatpak on the Steam Deck (as ReplayNES's
# scripts/build-linux-flatpak.sh does for ReplayNES): copies ReplayArcade and ReplayNES's source
# tree to ~/ReplayArcade-dev/src on the Deck and runs flatpak-builder there (--user install).
# The build goes to the branch "dev" (flatpak run --branch=dev ...), never over the published "master":
# installed from the Deck's local repository it would take over the app's origin, and the releases on
# GitHub would no longer reach it (2026-11-03: the Deck stayed at 0.3.4 that way). The published install
# stays the one Steam and "flatpak run" start.
#   scripts/build-deck-flatpak.sh [user@host]      (default deck@steamdeck.local)
# Env: REPLAYNES_DIR (default: the submodule third_party/replaynes), NO_INSTALL=1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:-deck@steamdeck.local}"
RN="${REPLAYNES_DIR:-$ROOT/third_party/replaynes}"
RDIR=ReplayArcade-dev
APP_ID=io.github.kathoc.ReplayArcade
"$ROOT/scripts/fbneo-patches.sh" --check >/dev/null || { echo "FBNeo patches are not applied" >&2; exit 1; }
COMMON=(--exclude=/.git --exclude=.git --exclude='/build/' --exclude='/build-*/' --exclude=/.flatpak-builder/
  --exclude=/dist/ --exclude='*.o' --exclude='*.d' --exclude='*.a' --exclude='*.so' --exclude='*.zip' --exclude='*.7z'
  --exclude='*.nes' --exclude=/roms/)
echo "==> sync ReplayArcade and ReplayNES ($RN) -> $HOST:~/$RDIR/src"
ssh "$HOST" "mkdir -p ~/$RDIR/src/third_party/replaynes"
rsync -a --delete "${COMMON[@]}" --exclude=/third_party/replaynes/ -e ssh "$ROOT/" "$HOST:$RDIR/src/"
# apps/macos holds the localization table every app builds from (Resources/Localizable.xcstrings).
rsync -a --delete "${COMMON[@]}" --exclude=/.claude/ --exclude=/third_party/nestopia/ --exclude=/third_party/syphon/ \
  --exclude=/third_party/SDL/ --include=/apps/macos/ --include=/apps/macos/Resources/ \
  --include=/apps/macos/Resources/Localizable.xcstrings --exclude='/apps/macos/**' --exclude=/apps/windows/ -e ssh "$RN/" "$HOST:$RDIR/src/third_party/replaynes/"
INSTALL="--install"
[ "${NO_INSTALL:-0}" = "1" ] && INSTALL=""
echo "==> flatpak-builder on $HOST"
ssh "$HOST" "cd ~/$RDIR && (flatpak info --user org.flatpak.Builder >/dev/null 2>&1 || flatpak install --user -y --noninteractive flathub org.flatpak.Builder) && \
  flatpak run org.flatpak.Builder --user $INSTALL --force-clean --disable-updates --state-dir=.flatpak-builder \
  --default-branch=dev --repo=repo build-flatpak src/packaging/linux/$APP_ID.yml && \
  if flatpak info --user $APP_ID//master >/dev/null 2>&1; then flatpak make-current --user $APP_ID master; fi"
echo "==> done. Run the build on $HOST: flatpak run --branch=dev $APP_ID (the published one stays current)"
