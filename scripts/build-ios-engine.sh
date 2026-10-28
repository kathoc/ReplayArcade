#!/bin/sh
# Builds ReplayArcade's engine for the iPhone app: ReplayNES's engine and shared frontend core with
# ReplayArcade's product profile, FinalBurn Neo (patched) and ReplayArcade's core and start-up hook,
# from the same CMake as the Linux build, as one static library per SDK:
#   build-ios/<sdk>/libreplaynes_all.a  (+ build-ios/<sdk>/generated/replaynes/product.h)
#   <sdk> = iphoneos | iphonesimulator, arm64
# The Xcode project (packaging/ios, scripts/build-ios.sh) runs it as its "Engine" target with
# PLATFORM_NAME set; by hand: scripts/build-ios-engine.sh [iphoneos|iphonesimulator|all]
# REPLAYNES_DIR: the ReplayNES tree whose apps/ios the app is built from (default: the submodule);
# the engine is built from the same tree, so the Swift code and the C API always match.
# Always Release: the cores are far too slow unoptimized for real-time play.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPLAYNES_DIR="$(cd "${REPLAYNES_DIR:-$ROOT/third_party/replaynes}" && pwd)"
OUT="${RN_ENGINE_BUILD_DIR:-$ROOT/build-ios}"
WANT="${1:-${PLATFORM_NAME:-iphonesimulator}}"

find_tool() {
  for c in "$(command -v "$1" 2>/dev/null || true)" "/opt/homebrew/bin/$1" "/usr/local/bin/$1" "$HOME/.local/bin/$1"; do
    if [ -n "$c" ] && [ -x "$c" ]; then echo "$c"; return 0; fi
  done
  return 1
}
CMAKE="$(find_tool cmake)" || { echo "error: cmake not found (brew install cmake)"; exit 1; }
GEN="Unix Makefiles"; MAKEPROG=""
if NINJA="$(find_tool ninja)"; then GEN="Ninja"; MAKEPROG="-DCMAKE_MAKE_PROGRAM=$NINJA"; fi

# Xcode exports variables that would leak into the CMake toolchain detection (and FBNeo's make).
unset CC CXX LD LDPLUSPLUS CFLAGS CXXFLAGS LDFLAGS CPATH LIBRARY_PATH SDKROOT
unset IPHONEOS_DEPLOYMENT_TARGET MACOSX_DEPLOYMENT_TARGET

build_sdk() {
  sdk="$1"; dir="$OUT/$sdk"
  # A different ReplayNES tree than the configured one: configure again.
  if [ -f "$dir/CMakeCache.txt" ] && ! grep -qx "REPLAYNES_DIR:PATH=$REPLAYNES_DIR" "$dir/CMakeCache.txt"; then
    rm -f "$dir/CMakeCache.txt"
  fi
  if [ ! -f "$dir/CMakeCache.txt" ]; then
    "$CMAKE" -S "$ROOT" -B "$dir" -G "$GEN" $MAKEPROG \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_SYSROOT="$sdk" \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
      -DCMAKE_BUILD_TYPE=Release \
      -DREPLAYNES_DIR="$REPLAYNES_DIR" \
      -DREPLAYARCADE_BUILD_TESTS=OFF -DREPLAYNES_BUILD_CLI=OFF \
      -DREPLAYNES_BUILD_DESKTOP=OFF -DREPLAYNES_BUILD_WINDOWS_PROBE=OFF -DREPLAYNES_BUILD_WINDOWS_APP=OFF
  fi
  "$CMAKE" --build "$dir" --target replaynes_engine replaynes_frontend replayarcade_core replayarcade_startup \
    fbneo_build fbneo_libretro_common
  fbneo="$dir/fbneo-src/src/burner/libretro/fbneo_libretro_static.a"
  set -- "$dir/replaynes/libreplayarcade_startup.a" "$dir/replaynes/libreplayarcade_core.a" \
    "$dir/replaynes/frontend/libreplaynes_frontend.a" "$dir/replaynes/engine/libreplaynes_engine.a" \
    "$fbneo" "$dir/replaynes/libfbneo_libretro_common.a"
  for a in "$@"; do test -f "$a" || { echo "error: missing $a"; exit 1; }; done
  # One archive per SDK, the name the app links (-lreplaynes_all, ReplayNES apps/ios/common.yml).
  libtool -static -no_warning_for_no_symbols -o "$dir/libreplaynes_all.a" "$@"
  test -f "$dir/generated/replaynes/product.h"
}

case "$WANT" in
  all) build_sdk iphoneos; build_sdk iphonesimulator ;;
  iphoneos|iphonesimulator) build_sdk "$WANT" ;;
  *) echo "error: unknown SDK '$WANT' (iphoneos | iphonesimulator | all)"; exit 1 ;;
esac
