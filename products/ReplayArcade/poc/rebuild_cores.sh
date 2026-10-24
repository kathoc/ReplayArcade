#!/usr/bin/env bash
# FBNeo libretro を再ビルドし、診断版（retro_memory.cpp だけ -DFBNEO_DEBUG）を別名でリンクする。
# 使い方: rebuild_cores.sh <作業フォルダ>   （fbneo-build.log は初回フルビルドの make 出力）
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
