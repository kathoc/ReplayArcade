# PoC 用の ROM フォルダを作る。元の ROM フォルダには書き込まない。
# 使い方: python3 -I make_romdir.py <元の ROM フォルダ> <作るフォルダ>
import pathlib, sys, zipfile
src, dst = map(pathlib.Path, sys.argv[1:3])
dst.mkdir(parents=True, exist_ok=True)
# FBNeo が読む zip（ゲーム自身と親）。merged セットのクローンは親の zip に入っている。
LINKS = ['aburner2', 'gforce2ja', 'sharrier', 'splatter', 'dspirit', 'genpeitd', 'ghouls',
         'nemesis', 'gradius', 'vulcan', 'salamand', 'aliens']
for n in LINKS:
    link = dst / f'{n}.zip'
    if not link.exists():
        link.symlink_to(src / f'{n}.zip')
# ordyneje = 手持ちの ordyne.zip（日本・英語版）+ assault.zip の C65 MCU（sys2c65b.bin = sys2_c65b.3f）
out = dst / 'ordyneje.zip'
if not out.exists():
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for i in zipfile.ZipFile(src / 'ordyne.zip').infolist():
            if not i.is_dir():
                z.writestr(i.filename, zipfile.ZipFile(src / 'ordyne.zip').read(i))
        z.writestr('sys2_c65b.3f', zipfile.ZipFile(src / 'assault.zip').read('sys2c65b.bin'))
print(dst)
