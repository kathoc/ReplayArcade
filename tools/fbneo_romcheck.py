# Reads the ROM CRCs a game needs from FBNeo's driver source and checks them against the zips (its own and its parent's) in a ROM folder.
# usage: python3 -I fbneo_romcheck.py <FBNeo src/burn/drv> <ROM dir> <games...>
# driver() / roms() are also used by tools/make_romdir.py (load() reads the FBNeo drivers).
import re, sys, zipfile, pathlib
src = {}
def load(drvroot):
    src.clear()
    src.update({p: p.read_text(errors='ignore') for p in pathlib.Path(drvroot).rglob('d_*.cpp')})
def driver(name):
    for p, t in src.items():
        m = re.search(r'struct BurnDriver\w*\s+\w+\s*=\s*\{\s*"%s"\s*,\s*("?\w*"?|NULL)\s*,\s*("?\w*"?|NULL)\s*,(.*?)\};' % re.escape(name), t, re.S)
        if m:
            parent = m.group(1).strip('"'); parent = None if parent == 'NULL' else parent
            bios = m.group(2).strip('"'); bios = None if bios == 'NULL' else bios
            info = re.search(r'(\w+)RomInfo\s*,', m.group(3)).group(1)
            return p, t, parent, bios, info
    return None
def roms(t, info):
    # also follows STD_ROM_PICK / STDROMPICKEXT that chain other descriptors
    out = []
    m = re.search(r'STDROMPICKEXT\(\s*%s\s*,\s*(\w+)\s*,\s*(\w+)\s*\)' % info, t)
    descs = [m.group(1), m.group(2)] if m else [info]
    for d in descs:
        a = re.search(r'struct BurnRomInfo\s+%sRomDesc\[\]\s*=\s*\{(.*?)\n\};' % d, t, re.S)
        if not a:
            for tt in src.values():
                a = re.search(r'struct BurnRomInfo\s+%sRomDesc\[\]\s*=\s*\{(.*?)\n\};' % d, tt, re.S)
                if a: break
        if not a: out.append(('?desc '+d, 0, 0)); continue
        for e in re.finditer(r'\{\s*"([^"]*)"\s*,\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*(0x[0-9a-fA-F]+)\s*,([^}]*)\}', a.group(1)):
            if 'NODUMP' in e.group(4) or 'BRF_OPT' in e.group(4) or int(e.group(3),16) == 0: continue
            out.append((e.group(1), int(e.group(2),0), int(e.group(3),16)))
    return out
def zcrcs(names, romdir):
    s = {}
    for n in filter(None, names):
        z = pathlib.Path(romdir, n + '.zip')
        if z.exists():
            for i in zipfile.ZipFile(z).infolist(): s[i.CRC] = z.name
    return s
def main():
    drvroot, romdir, *games = sys.argv[1:]
    load(drvroot)
    for g in games:
        d = driver(g)
        if not d: print(f'{g}: no FBNeo driver'); continue
        p, t, parent, bios, info = d
        need = roms(t, info)
        have = zcrcs([g, parent, bios], romdir)
        miss = [r for r in need if r[2] not in have]
        zips = [n for n in [g, parent, bios] if n and pathlib.Path(romdir, n+'.zip').exists()]
        print(f'{g}: needed {len(need)} / missing {len(miss)}  (parent={parent}, BIOS={bios}, zip={zips})')
        for r in miss[:8]: print(f'    missing: {r[0]} crc={r[2]:08x}')

if __name__ == '__main__':
    main()
