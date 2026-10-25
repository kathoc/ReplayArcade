#!/usr/bin/env bash
# Refuses game data (ROM images, archives, CHDs, NVRAM, projects) and any file over 5 MB.
# Used by the pre-commit hook (staged files) and the pre-push hook (every file of the pushed commits).
#   check-no-roms.sh <file list on stdin, one path per line> [rev]   (rev: read sizes from that commit)
set -euo pipefail
rev="${1:-}"
bad=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "${f,,}" in
    *.zip|*.7z|*.rar|*.chd|*.nes|*.fds|*.unf|*.bin|*.rom|*.fs|*.nv|*.arcrec/*|roms/*|*/roms/*|rom/*|*/rom/*)
      echo "refused (game data): $f" >&2; bad=1; continue ;;
  esac
  if [ -n "$rev" ]; then size=$(git cat-file -s "$rev:$f" 2>/dev/null || echo 0)
  else size=$(git cat-file -s ":$f" 2>/dev/null || echo 0); fi
  if [ "$size" -gt 5000000 ]; then echo "refused (over 5 MB): $f ($size bytes)" >&2; bad=1; fi
done
exit $bad
