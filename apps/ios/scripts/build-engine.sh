#!/bin/sh
# Builds the portable engine and the shared frontend core for iOS from the same CMake source lists
# as every other platform (single source of truth), as static libraries per SDK:
#   $RN_ENGINE_BUILD_DIR/<sdk>/engine/libreplaynes_engine.a, .../frontend/libreplaynes_frontend.a,
#   .../libnestopia_core.a      (<sdk> = iphoneos | iphonesimulator, arm64)
# Called by the Xcode "Engine" aggregate target with PLATFORM_NAME set; by hand:
#   apps/ios/Scripts/build-engine.sh [iphoneos|iphonesimulator|all] [--xcframework]
# Always Release: the emulator core is far too slow unoptimized for real-time play.
set -eu
# The repository this script is in (not SRCROOT: another product's project includes common.yml).
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="${RN_ENGINE_BUILD_DIR:-$REPO/build/ios-engine}"
WANT="${1:-${PLATFORM_NAME:-iphonesimulator}}"
XCF=0
for a in "$@"; do [ "$a" = "--xcframework" ] && XCF=1; done

find_tool() {
  for c in "$(command -v "$1" 2>/dev/null || true)" "/opt/homebrew/bin/$1" "/usr/local/bin/$1" "$HOME/.local/bin/$1"; do
    if [ -n "$c" ] && [ -x "$c" ]; then echo "$c"; return 0; fi
  done
  return 1
}
CMAKE="$(find_tool cmake)" || { echo "error: cmake not found (brew install cmake)"; exit 1; }
GEN="Unix Makefiles"; MAKEPROG=""
if NINJA="$(find_tool ninja)"; then GEN="Ninja"; MAKEPROG="-DCMAKE_MAKE_PROGRAM=$NINJA"; fi

# Xcode exports variables that would leak into the CMake toolchain detection.
unset CC CXX LD LDPLUSPLUS CFLAGS CXXFLAGS LDFLAGS CPATH LIBRARY_PATH SDKROOT
unset IPHONEOS_DEPLOYMENT_TARGET MACOSX_DEPLOYMENT_TARGET

build_sdk() {
  sdk="$1"; dir="$OUT/$sdk"
  if [ ! -f "$dir/CMakeCache.txt" ]; then
    "$CMAKE" -S "$REPO" -B "$dir" -G "$GEN" $MAKEPROG \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_SYSROOT="$sdk" \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
      -DCMAKE_BUILD_TYPE=Release \
      -DREPLAYNES_BUILD_TESTS=OFF -DREPLAYNES_BUILD_CLI=OFF \
      -DREPLAYNES_BUILD_DESKTOP=OFF -DREPLAYNES_BUILD_WINDOWS_PROBE=OFF -DREPLAYNES_BUILD_WINDOWS_APP=OFF
  fi
  "$CMAKE" --build "$dir" --target replaynes_engine replaynes_frontend
  test -f "$dir/engine/libreplaynes_engine.a"
  test -f "$dir/frontend/libreplaynes_frontend.a"
  test -f "$dir/libnestopia_core.a"
  # One archive per SDK (what an XCFramework slice holds).
  libtool -static -no_warning_for_no_symbols -o "$dir/libreplaynes_all.a" \
    "$dir/frontend/libreplaynes_frontend.a" "$dir/engine/libreplaynes_engine.a" "$dir/libnestopia_core.a"
}

case "$WANT" in
  all) build_sdk iphoneos; build_sdk iphonesimulator ;;
  iphoneos|iphonesimulator) build_sdk "$WANT" ;;
  *) echo "error: unknown SDK '$WANT' (iphoneos | iphonesimulator | all)"; exit 1 ;;
esac

if [ "$XCF" = 1 ]; then
  rm -rf "$OUT/ReplayNESCore.xcframework"
  hdr="$OUT/headers"; rm -rf "$hdr"; mkdir -p "$hdr"
  cp "$REPO/engine/include/replaynes/replaynes.h" "$REPO/frontend/include/replaynes/frontend.h" "$hdr/"
  args=""
  for sdk in iphoneos iphonesimulator; do
    [ -f "$OUT/$sdk/libreplaynes_all.a" ] && args="$args -library $OUT/$sdk/libreplaynes_all.a -headers $hdr"
  done
  xcodebuild -create-xcframework $args -output "$OUT/ReplayNESCore.xcframework"
fi
