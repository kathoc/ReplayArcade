#!/usr/bin/env bash
# Cross-builds ReplayArcade for Windows with llvm-mingw: ReplayNES's scripts/build-windows.sh with
# ReplayArcade's product profile (cmake/product.cmake: FinalBurn Neo, no updates, the icon).
#   scripts/build-windows.sh [x86_64|aarch64|all]   (default x86_64) -> build/windows/windows-<arch>/
# Env: REPLAYNES_DIR (default: the ReplayNES worktree used by CMakeLists.txt), other variables as in
# ReplayNES's script (BUILD_TYPE, ...). Needs llvm-mingw (~/.local/opt/llvm-mingw) and ninja on PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RN="${REPLAYNES_DIR:-$HOME/Playground/ReplayNES/.claude/worktrees/generalize}"
export PATH="$HOME/.local/bin:$PATH"
"$ROOT/scripts/fbneo-patches.sh" --check >/dev/null || "$ROOT/scripts/fbneo-patches.sh"
cd "$RN"
NO_PACKAGE=1 BUILD_BASE="$ROOT/build/windows" \
  EXTRA_CMAKE_ARGS="-DRN_PRODUCT_FILE=$ROOT/cmake/product.cmake ${EXTRA_CMAKE_ARGS:-}" \
  scripts/build-windows.sh "${1:-x86_64}"
ls -la "$ROOT"/build/windows/windows-*/apps/windows/*.exe
