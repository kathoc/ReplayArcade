#!/usr/bin/env bash
# third_party/fbneo（libretro/FBNeo の submodule）に ReplayArcade のパッチを当てる。何度実行してもよい。
#   scripts/fbneo-patches.sh          当てる（当て済みなら何もしない）
#   scripts/fbneo-patches.sh --check  当て済みか確認するだけ（未適用なら exit 1）
#   scripts/fbneo-patches.sh --export 作業ツリーの差分をパッチファイルへ書き戻す（パッチを直したとき）
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
sub=$root/third_party/fbneo
patch=$root/patches/fbneo/0001-replayarcade-determinism.patch
case "${1:-}" in
  --export) git -C "$sub" diff > "$patch"; echo "exported: $patch"; exit 0 ;;
esac
if git -C "$sub" apply --reverse --check "$patch" 2>/dev/null; then
  echo "already applied"; exit 0
fi
[ "${1:-}" = "--check" ] && { echo "not applied"; exit 1; }
git -C "$sub" apply --check "$patch"
git -C "$sub" apply "$patch"
echo "applied: $patch"
