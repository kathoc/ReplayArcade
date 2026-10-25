# Writes ReplayArcade's game database (data/arcadedb.tsv, the format of ReplayNES's nesdb.tsv) from
# FBNeo's driver table: one G row per arcade set (its title without the version in parentheses,
# maker, year, genre; the set name as the alias the ROM file is matched by), after the hand-written
# rows of data/arcadedb-base.tsv (those sets keep them). Japanese titles, readings and maker names
# come from data/arcadedb-ja.tsv. Console drivers, BIOS sets and the like are left out.
#
# usage: python3 -I make_arcadedb.py [--check] <FBNeo src/burn/drv> <data dir>
#   --check: write nothing, fail when data/arcadedb.tsv differs from what would be written
import pathlib
import re
import sys

CONSOLE_DIRS = {"channelf", "coleco", "gba", "megadrive", "msx", "nes", "pce", "sg1000", "sms", "snes", "spectrum"}
# FBNeo genre flags (burn.h) -> ReplayNES genre codes, the first that matches.
GENRES = [
    (1 << 3, "fighting"), (1 << 0 | 1 << 1 | 1 << 19 | 1 << 20, "shooter"), (1 << 18, "racing"),
    (1 << 12, "puzzle"), (1 << 14 | 1 << 15, "sports"), (1 << 25, "rpg"), (1 << 27, "adventure"),
    (1 << 23, "strategy"), (1 << 6 | 1 << 17 | 1 << 28 | 1 << 29, "table"),
    (1 << 2 | 1 << 5 | 1 << 7 | 1 << 8 | 1 << 11 | 1 << 21 | 1 << 22 | 1 << 10, "action"),
]
GBF_BIOS = 1 << 4
DRIVER = re.compile(r'struct\s+BurnDriver\w*\s+BurnDrv\w+\s*=\s*\{(.*?)\};', re.S)
TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|([^,"\s][^,"]*)')


def fields(body):
    out = []
    for m in TOKEN.finditer(body):
        if m.group(1) is not None:
            out.append(m.group(1).replace("\\0", "").replace('\\"', '"'))
        else:
            v = m.group(2).strip()
            out.append(None if v == "NULL" else v)
        if len(out) == 17:
            break
    return out


def flags(expr, names):
    v = 0
    for part in (expr or "").split("|"):
        part = part.strip()
        if part in names:
            v |= names[part]
        elif re.fullmatch(r"0x[0-9a-fA-F]+|\d+", part):
            v |= int(part, 0)
    return v


def title(full):
    """The name without the version in (nested) parentheses at its end, nor an " / " alternative."""
    t = full.split(" / ")[0].strip()
    while t.endswith(")"):
        depth = 0
        for i in range(len(t) - 1, -1, -1):
            depth += {")": 1, "(": -1}.get(t[i], 0)
            if depth == 0:
                break
        if depth or i == 0:
            break
        t = t[:i].rstrip()
    return t


def main():
    args = sys.argv[1:]
    check = args[:1] == ["--check"]
    drv, data = map(pathlib.Path, args[1:3] if check else args[:2])
    burn_h = (drv.parent / "burn.h").read_text(errors="ignore")
    names = {m.group(1): int(m.group(2), 0) for m in re.finditer(r"#define\s+(GBF_\w+|BDF_\w+)\s+\(?\s*(?:1\s*<<\s*)?(\d+|0x[0-9a-fA-F]+)", burn_h)}
    for m in re.finditer(r"#define\s+(GBF_\w+|BDF_\w+)\s+\(\s*1\s*<<\s*(\d+)\s*\)", burn_h):
        names[m.group(1)] = 1 << int(m.group(2))
    sets, bios = {}, set()
    for p in sorted(drv.rglob("d_*.cpp")):
        if p.relative_to(drv).parts[0] in CONSOLE_DIRS:
            continue
        for m in DRIVER.finditer(p.read_text(errors="ignore")):
            f = fields(m.group(1))
            if len(f) < 17 or not f[0] or not f[5]:
                continue
            bdf, genre = flags(f[13], names), flags(f[16], names)
            if bdf & names.get("BDF_BOARDROM", 0) or genre & GBF_BIOS:
                bios.add(f[0])  # also when another driver of that name (#if'd) is a system
                continue
            year = re.match(r"\d{4}", f[4] or "")
            sets[f[0]] = dict(parent=f[1], en=title(f[5]), maker=(f[7] or "").strip(), year=year.group(0) if year else "",
                              genre=next((g for bits, g in GENRES if genre & bits), "other" if genre else ""))
    for s in bios:
        sets.pop(s, None)
    # Japanese: "G set ja reading" (also its clones of the same English title), "M maker ja".
    ja, makers_ja = {}, {}
    for line in (data / "arcadedb-ja.tsv").read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            continue
        c = line.split("\t")
        if c[0] == "G" and len(c) >= 4:
            ja[c[1]] = (c[2], c[3])
        elif c[0] == "M" and len(c) >= 3:
            makers_ja[c[1]] = c[2]
    unknown = [s for s in ja if s not in sets]
    if unknown:
        sys.exit("arcadedb-ja.tsv: not FBNeo sets: " + " ".join(unknown))
    for s, (t, r) in list(ja.items()):
        fam = sets[s]["parent"] or s
        for o, g in sets.items():
            if o not in ja and (o == fam or g["parent"] == fam) and g["en"] == sets[s]["en"]:
                ja[o] = (t, r)
    base = (data / "arcadedb-base.tsv").read_text(encoding="utf-8")
    taken = set()
    for line in base.splitlines():
        c = line.split("\t")
        if c[0] == "G" and len(c) >= 10:
            taken.update(c[9].split("|"))
    makers = sorted({g["maker"] for s, g in sets.items() if s not in taken and g["maker"]})
    out = [base.rstrip("\n")]
    out += [f"P\tm:{m}\t{m}\t{makers_ja.get(m, '')}" for m in makers]
    for s in sorted(sets):
        if s in taken:
            continue
        g = sets[s]
        t, r = ja.get(s, ("", ""))
        out.append("\t".join(["G", "a-" + s, g["en"], t, r, "m:" + g["maker"] if g["maker"] else "", g["year"], g["genre"], "", s]))
    text = "\n".join(out) + "\n"
    target = data / "arcadedb.tsv"
    if check:
        if not target.exists() or target.read_text(encoding="utf-8") != text:
            sys.exit(f"{target} is out of date: run tools/make_arcadedb.py")
        print(f"{target}: up to date")
        return
    target.write_text(text, encoding="utf-8")
    print(f"{len(sets) - len(taken & set(sets))} sets, {len(makers)} makers, {sum(1 for s in ja if s not in taken)} with Japanese titles")


if __name__ == "__main__":
    main()
