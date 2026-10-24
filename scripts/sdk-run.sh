#!/usr/bin/env bash
# Run a command inside the Freedesktop SDK (the one the ReplayNES Linux app builds with) without
# flatpak-builder: the SDK's files are mounted read-only at /usr, the given directory and /tmp are
# writable. `flatpak run` cannot start in this sandbox (NETLINK_ROUTE socket), bwrap can.
#   scripts/sdk-run.sh <writable dir> <command...>
# FFMPEG_EXTRA=1 adds codecs-extra (libx264) to LD_LIBRARY_PATH.
set -euo pipefail
dir=$(cd "$1" && pwd); shift
sdk=${SDK_VERSION:-25.08}
root="$HOME/.local/share/flatpak/runtime/org.freedesktop.Sdk/x86_64/$sdk/active/files"
[ -d "$root" ] || { echo "SDK $sdk not installed at $root" >&2; exit 2; }
ld=""
if [ "${FFMPEG_EXTRA:-0}" = 1 ]; then
  ld="$HOME/.local/share/flatpak/runtime/org.freedesktop.Platform.codecs-extra/x86_64/$sdk-extra/active/files/lib"
fi
exec bwrap --ro-bind / / --ro-bind "$root" /usr --bind "$dir" "$dir" --bind /tmp /tmp \
  --proc /proc --dev-bind /dev /dev --chdir "$dir" \
  --setenv PATH /usr/bin --setenv LD_LIBRARY_PATH "$ld" -- /usr/bin/bash -c "$*"
