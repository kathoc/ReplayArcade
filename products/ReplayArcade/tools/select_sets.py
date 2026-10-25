# Picks the FinalBurn Neo set to use for each game of a wish list and builds it: of the game's sets (the
# parent and its clones), a Japanese one first ("Japan" in FBNeo's name), then the parent, then the other
# clones; bootlegs, hacks and prototypes last. The first set make_romdir.py can build completely from the
# source ROM folder wins. Prints "<wish> <set> <title>" per game, or "<wish> - <reason>".
#
# usage: python3 -I select_sets.py <FBNeo src/burn/drv> <source ROM dir> <output dir> <wish...>
#   a wish is any set of the game (usually its parent); "-n N" stops after N games are built.
import pathlib
import re
import subprocess
import sys

DRIVER = re.compile(r'struct\s+BurnDriver\w*\s+BurnDrv\w+\s*=\s*\{\s*"(\w+)"\s*,\s*("?\w*"?|NULL)\s*,[^,]*,[^,]*,\s*"[^"]*"\s*,\s*"((?:[^"\\]|\\.)*)"', re.S)
CONSOLE_DIRS = {"channelf", "coleco", "gba", "megadrive", "msx", "nes", "pce", "sg1000", "sms", "snes", "spectrum"}


def main():
    args = sys.argv[1:]
    limit = None
    if args[:1] == ["-n"]:
        limit, args = int(args[1]), args[2:]
    drv, src, dst = map(pathlib.Path, args[:3])
    wishes = args[3:]
    sets = {}
    for p in drv.rglob("d_*.cpp"):
        if p.relative_to(drv).parts[0] in CONSOLE_DIRS:
            continue
        for m in DRIVER.finditer(p.read_text(errors="ignore")):
            parent = m.group(2).strip('"')
            sets[m.group(1)] = (None if parent in ("", "NULL") else parent, m.group(3).replace("\\0", ""))
    tool = pathlib.Path(__file__).resolve().parent / "make_romdir.py"
    built = 0
    for wish in wishes:
        if limit is not None and built >= limit:
            break
        if wish not in sets:
            print(f"{wish} - not an FBNeo arcade set")
            continue
        family = sets[wish][0] or wish
        members = [s for s, (par, _) in sets.items() if s == family or par == family]

        def rank(s):
            name = sets[s][1].lower()
            odd = any(w in name for w in ("bootleg", "hack", "prototype", "location test", "demo"))
            # Japanese: "Japan" in the name, or a version ending in J ("Ver 2.2J"), or the set name's j suffix.
            japanese = "japan" in name or re.search(r"\bver[^)]*\dj\b", name) or (s.endswith("j") and s[:-1] in members)
            return (odd, not japanese, s != family, s)

        for s in sorted(members, key=rank):
            r = subprocess.run([sys.executable, "-I", str(tool), str(drv), str(src), str(dst), s],
                               capture_output=True, text=True)
            if r.returncode == 0:
                print(f"{wish} {s} {sets[s][1]}", flush=True)
                built += 1
                break
        else:
            print(f"{wish} - no complete set in the source folder", flush=True)


if __name__ == "__main__":
    main()
