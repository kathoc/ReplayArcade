#!/usr/bin/env bash
# Runs tools/fbneo_diverge on a game and names the global variables it found differing after a state load
# (the symbols of the fbneo_diverge binary; variables of the engine / ReplayArcade are listed too, the
# FBNeo ones are what save states leave out).
#   tools/fbneo_diverge.sh <rom.zip> [frames]   (needs build/fbneo_diverge)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${FBNEO_DIVERGE:-$ROOT/build/fbneo_diverge}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
"$BIN" "$1" "${2:-1200}" "$T/globals.txt" || true
nm -C --defined-only -S "$BIN" | awk 'NF >= 4 && $3 ~ /^[bBdDsS]$/' > "$T/syms.txt"
python3 - "$T/globals.txt" "$T/syms.txt" <<'EOF'
import bisect, sys
syms = []
for line in open(sys.argv[2]):
    a, size, _kind, name = line.rstrip("\n").split(" ", 3)
    syms.append((int(a, 16), int(size, 16), name))
syms.sort()
starts = [s[0] for s in syms]
def name(off):
    i = bisect.bisect_right(starts, off) - 1
    if i >= 0 and off < syms[i][0] + max(syms[i][1], 1):
        return syms[i][2]
    return "?"
seen, heap = {}, {}
for line in open(sys.argv[1]):
    f = line.split()
    if f[0] == "heap":  # heap <pointer's offset> <delta> <bytes>: memory a global points into
        k = name(int(f[1], 16))
        heap[k] = heap.get(k, 0) + int(f[3])
        continue
    n = name(int(f[0], 16))
    seen[n] = seen.get(n, 0) + int(f[1])
for k, n in sorted(seen.items()):
    print(f"  {n:6d} bytes  {k}")
for k, n in sorted(heap.items(), key=lambda kv: -kv[1])[:25]:
    print(f"  {n:6d} bytes  heap after *{k}")
EOF
