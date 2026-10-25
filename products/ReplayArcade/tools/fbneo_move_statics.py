#!/usr/bin/env python3
"""Moves FBNeo function statics to file scope, registered with REPLAYARCADE_STATE (state.h).
   tools/fbneo_move_statics.py <third_party/fbneo/src/burn> <decls.txt: "file:line: <the static declaration>">
   The list comes from tools/fbneo_function_statics.sh (checked by hand: only emulation state). After it,
   scripts/fbneo-patches.sh --export."""
import os, re, sys, collections
root, listing = sys.argv[1], sys.argv[2]
sites = collections.defaultdict(list)
for line in open(listing):
    f, n, _ = line.split(':', 2)
    sites[f].append(int(n))

def split_top(s):
    out, depth, cur = [], 0, ''
    for c in s:
        if c in '{[(': depth += 1
        if c in '}])': depth -= 1
        if c == ',' and depth == 0:
            out.append(cur); cur = ''
        else:
            cur += c
    out.append(cur)
    return [x.strip() for x in out if x.strip()]

for f, nums in sites.items():
    path = os.path.join(root, f)
    raw = open(path, encoding='latin-1', newline='').read()
    eol = '\r\n' if '\r\n' in raw else '\n'
    lines = raw.split(eol)
    base = os.path.splitext(os.path.basename(f))[0]
    used = set()
    inserts = collections.defaultdict(list)  # function line index -> file-scope lines
    for n in sorted(nums):
        i = n - 1
        text = lines[i]
        m = re.match(r'^(\s*)static\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.*?);(\s*(//.*)?)$', text)
        assert m, (f, n, text)
        indent, typ, rest, comment = m.group(1), m.group(2), m.group(3), (m.group(4) or '').strip()
        fn = i
        while fn > 0 and not re.match(r'^[A-Za-z].*\(', lines[fn]): fn -= 1
        fname = re.search(r'([A-Za-z_][A-Za-z0-9_]*)\s*\(', lines[fn]).group(1)
        locals_ = []
        for d in split_top(rest):
            dm = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*((?:\[[^\]]*\]\s*)*)(=.*)?$', d)
            assert dm, (f, n, d)
            name, dims, init = dm.group(1), dm.group(2).replace(' ', ''), (dm.group(3) or '').strip()
            g = f'{base}_{fname}_{name}'
            k = 2
            while g in used:
                g = f'{base}_{fname}_{name}{k}'; k += 1
            used.add(g)
            inserts[fn].append(f'static {typ} {g}{dims}{(" " + init) if init else ""}; REPLAYARCADE_STATE({g});')
            locals_.append(f'{typ} (&{name}){dims} = {g};' if dims else f'{typ} &{name} = {g};')
        lines[i] = indent + ' '.join(locals_) + (' ' + comment if comment else '')
    for fn in sorted(inserts, reverse=True):
        block = ['// ReplayArcade: emulation state of ' + re.search(r'([A-Za-z_][A-Za-z0-9_]*)\s*\(', lines[fn]).group(1)
                 + '() (was a function static; state.h, REPLAYARCADE_STATE)'] + inserts[fn]
        lines[fn:fn] = block
    open(path, 'w', encoding='latin-1', newline='').write(eol.join(lines))
    print(f, len(nums))
