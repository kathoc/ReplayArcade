#!/usr/bin/env bash
# Runs the Phase 0 acceptance checks, two independent methods:
#   A. Determinism: save -> N frames -> load -> N frames with the same input; compares picture, sound and every
#      frame's state, the state round trip, and two processes from power-on (diagnostic core).
#   B. Random seek: runs from power-on taking a checkpoint every 300 frames, loads them in a scrambled order and
#      compares with the recording (normal core; close to how ReplayNES uses it).
# usage: verify_all.sh <work dir> <ROM dir> [games...]
#   The work dir holds fbneo_dbg.so and fbneo-build.log made by rebuild_cores.sh.
set -u
work=$1 romdir=$2; shift 2
games=${*:-aburner2 gforce2ja sharrier splatter ordyneje dspirit genpeitd daimakai gradius gradius2 salamand aliens}
here=$(cd "$(dirname "$0")" && pwd)
core=$here/../third_party/fbneo/src/burner/libretro/fbneo_libretro.so
probe=$work/fbneo_probe
g++ -std=c++17 -O2 -Wall -o "$probe" "$here/fbneo_probe.cpp" \
  -I"$here/../third_party/fbneo/src/burner/libretro/libretro-common/include" -ldl || exit 2
out=$work/verify-$(date +%Y%m%d-%H%M%S)
mkdir -p "$out/system"
fail=0
printf '%-10s %-6s %-6s %-6s %-6s %-6s  %s\n' game det rt boot seek trace detail
for g in $games; do
  for run in 1 2; do
    d=$out/$g/det$run; mkdir -p "$d/save"
    PROBE_TRACE=1 PROBE_AREAS=1 timeout 900 "$probe" "$work/fbneo_dbg.so" "$romdir/$g.zip" "$out/system" "$d/save" "$d" 900 3600 \
      > "$d/result.json" 2> "$d/stderr.log"
  done
  d=$out/$g/seek; mkdir -p "$d/save"
  PROBE_SEEK_DETAIL=1 PROBE_SEEK=7200 timeout 900 "$probe" "$core" "$romdir/$g.zip" "$out/system" "$d/save" "$d" \
    > "$d/result.json" 2> "$d/stderr.log"
  python3 -I - "$out/$g" "$g" <<'EOF' || fail=1
import json, sys
d, g = sys.argv[1:]
def load(p):
    try: return json.load(open(p))
    except Exception: return {}
a, b, s = load(d + '/det1/result.json'), load(d + '/det2/result.json'), load(d + '/seek/result.json')
trace = 'equal' if 'states equal on every frame' in open(d + '/det1/stderr.log', errors='ignore').read() else 'DIFF'
det = a.get('deterministic') is True and b.get('deterministic') is True
rt = a.get('roundtrip_equal') is True
boot = bool(a.get('boot_hash')) and a.get('boot_hash') == b.get('boot_hash')
seek = s.get('deterministic') is True
detail = '' if det and rt and boot and seek and trace == 'equal' else \
    f"vmis={a.get('video_mismatch')} amis={a.get('audio_mismatch')} sdiff={a.get('end_state_diff_bytes')} seek_bad={s.get('bad_frames')} first={s.get('first_bad_frame')}"
ok = lambda v: 'ok' if v else 'NG'
print(f"{g:10} {ok(det):6} {ok(rt):6} {ok(boot):6} {ok(seek):6} {trace:6}  {detail}")
sys.exit(0 if det and rt and boot and seek and trace == 'equal' else 1)
EOF
done
echo "results: $out"
exit $fail
