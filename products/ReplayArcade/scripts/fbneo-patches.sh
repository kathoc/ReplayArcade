#!/usr/bin/env bash
# Applies ReplayArcade's patches to third_party/fbneo (the libretro/FBNeo submodule). Safe to run repeatedly.
#   scripts/fbneo-patches.sh          apply (nothing to do when already applied)
#   scripts/fbneo-patches.sh --check  only check (exit 1 when not applied)
#   scripts/fbneo-patches.sh --export write the working tree's changes back to the patch file (after fixing it)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
sub=$root/third_party/fbneo
patch=$root/patches/fbneo/0001-replayarcade-determinism.patch
case "${1:-}" in
  --export) git -C "$sub" diff > "$patch"; echo "exported: $patch"; exit 0 ;;
esac
if git -C "$sub" apply --reverse --check "$patch" 2>/dev/null; then
  echo "already applied"; exit 0
fi
[ "${1:-}" = "--check" ] && { echo "not applied"; exit 1; }
git -C "$sub" apply --check "$patch"
git -C "$sub" apply "$patch"
echo "applied: $patch"
