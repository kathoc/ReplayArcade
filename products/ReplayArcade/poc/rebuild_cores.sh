#!/usr/bin/env bash
# Rebuilds FBNeo (libretro) and links a diagnostic variant (only retro_memory.cpp with -DFBNEO_DEBUG) under another name.
# usage: rebuild_cores.sh <work dir>   (fbneo-build.log is the make output of the first full build)
set -euo pipefail
work=$1
lib=$(cd "$(dirname "$0")/../third_party/fbneo/src/burner/libretro" && pwd)
log=$work/fbneo-build.log
cd "$lib"
make -j12 2>&1 | grep -E "error|Error" || true
mem=$(grep -m1 -- "-o../../burner/libretro/retro_memory.o" "$log" \
  | sed "s|-o../../burner/libretro/retro_memory.o|-o$work/retro_memory_dbg.o|; s|-DNDEBUG|-DNDEBUG -DFBNEO_DEBUG|")
eval "$mem"
link=$(grep -m1 -- "-ofbneo_libretro.so" "$log" \
  | sed "s|-ofbneo_libretro.so|-o$work/fbneo_dbg.so|; s|\.\./\.\./burner/libretro/retro_memory\.o|$work/retro_memory_dbg.o|")
eval "$link"
echo "$lib/fbneo_libretro.so $work/fbneo_dbg.so"
