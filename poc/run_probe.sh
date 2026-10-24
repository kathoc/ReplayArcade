#!/usr/bin/env bash
# Phase 0: 対象 12 本で fbneo_probe を回す。ゲームごとに 2 プロセス走らせ、電源投入からの再現性も比べる。
# 使い方: run_probe.sh <probe> <core.so> <romdir> <outdir> [warmup] [compare] [normal|runahead]
set -u
probe=$1 core=$2 romdir=$3 out=$4 warm=${5:-900} cmp=${6:-600} ctx=${7:-normal}
games="aburner2 gforce2ja sharrier splatter ordyneje dspirit genpeitd daimakai gradius gradius2 salamand aliens"
mkdir -p "$out/system"
for g in $games; do
  for run in 1 2; do
    d="$out/$g/run$run"; mkdir -p "$d/save"
    timeout 600 "$probe" "$core" "$romdir/$g.zip" "$out/system" "$d/save" "$d" "$warm" "$cmp" "$ctx" \
      > "$d/result.json" 2> "$d/stderr.log"
    echo "$? $(cat "$d/result.json")"
  done
done
