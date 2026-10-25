#!/usr/bin/env bash
# Phase 0: runs fbneo_probe on the 12 target games; two processes per game also compare reproducibility from power-on.
# usage: run_probe.sh <probe> <core.so> <romdir> <outdir> [warmup] [compare] [normal|runahead]
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
