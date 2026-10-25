#!/usr/bin/env bash
# Runs tools/fbneo_bisect on a game and names what it finds (the symbol table of the fbneo_bisect binary).
# The globals of the engine, of ReplayArcade and of the tool (their C++ namespaces) are excluded from the search;
# function-local statics of FBNeo ("Function(args)::name") are searched.
#   tools/fbneo_bisect.sh <rom.zip> [frames]   (needs build/fbneo_bisect)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${FBNEO_BISECT:-$ROOT/build/fbneo_bisect}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
nm -C --defined-only -S "$BIN" | awk 'NF >= 4 && $3 ~ /^[bBdDsS]$/' > "$T/syms.txt"
grep -E '^[^ ]+ [^ ]+ [^ ]+ ((rn|rac|std|rnf|rnl|__gnu_cxx)::|\(anonymous namespace\)::|guard variable|vtable|typeinfo)' "$T/syms.txt" | awk '{printf "%s %d\n", $1, strtonum("0x" $2)}' > "$T/exclude.txt"
FBNEO_BISECT_EXCLUDE="$T/exclude.txt" "$BIN" "$1" "${2:-600}" > "$T/out.txt" || true
python3 - "$T/out.txt" "$T/syms.txt" <<'PY'
import bisect, re, sys
syms = []
for line in open(sys.argv[2]):
    a, size, _k, name = line.rstrip("\n").split(" ", 3)
    syms.append((int(a, 16), int(size, 16), name))
syms.sort()
starts = [s[0] for s in syms]
def name(off):
    i = bisect.bisect_right(starts, off) - 1
    if i >= 0 and off < syms[i][0] + max(syms[i][1], 1):
        return f"{syms[i][2]}+{off - syms[i][0]} @{syms[i][0]:x}"
    return "?"
for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    m = re.match(r"  global  offset ([0-9a-f]+)  (\d+) bytes", line)
    if m:
        print(f"  global {name(int(m.group(1), 16))}  {m.group(2)} bytes"); continue
    m = re.match(r"  block (\d+) \(held by global offset ([0-9a-f]+)\) \+ (\d+)  (\d+) bytes", line)
    if m:
        print(f"  block held by {name(int(m.group(2), 16))} at +{m.group(3)}  {m.group(4)} bytes"); continue
    print(line)
PY
