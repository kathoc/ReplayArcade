#!/usr/bin/env bash
# Runs the Linux app built in build-linux-sdk inside the Freedesktop SDK on a virtual X display
# (Xvfb) with Mesa's software Vulkan (lavapipe), for scripted screenshots without a real screen.
#   scripts/run-app-headless.sh <work dir> <app args...>
# <work dir> holds lvp.json (written when missing), gl/ (bind point), home/ and receives the screenshots.
# RUN_HOME: another home folder (a fresh one per run avoids the previous session's resume prompt).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(cd "$1" && pwd); shift
arch=${SDK_ARCH:-$(uname -m)}
sdk="$HOME/.local/share/flatpak/runtime/org.freedesktop.Sdk/$arch/25.08/active/files"
gl="$HOME/.local/share/flatpak/runtime/org.freedesktop.Platform.GL.default/$arch/25.08/active/files"
disp=:${DISPLAY_NUM:-91}
home=${RUN_HOME:-$work/home}
mkdir -p "$home" "$work/gl"
# Mesa's lavapipe (software Vulkan) from the GL extension, mounted at $work/gl: the extension ships no ICD file.
[ -f "$work/lvp.json" ] || cat > "$work/lvp.json" <<EOF
{"file_format_version": "1.0.1", "ICD": {"library_path": "$work/gl/lib/libvulkan_lvp.so", "library_arch": "64", "api_version": "1.4.354"}}
EOF
Xvfb "$disp" -screen 0 1280x800x24 -nolisten tcp >/dev/null 2>&1 &
xvfb=$!
trap 'kill $xvfb 2>/dev/null || true' EXIT
sleep 1
# The host's CJK fonts where Flatpak puts them (/run/host/fonts): without them the app falls back to English.
fonts=()
[ -d /usr/share/fonts/opentype/noto ] && fonts=(--tmpfs /run --ro-bind /usr/share/fonts/opentype/noto /run/host/fonts/noto-cjk)
bwrap --ro-bind / / --ro-bind "$sdk" /usr --bind "$here" "$here" --bind /tmp /tmp --ro-bind "$gl" "$work/gl" "${fonts[@]}" \
  --proc /proc --dev-bind /dev /dev --chdir "$work" \
  --setenv PATH /usr/bin --setenv HOME "$home" --setenv DISPLAY "$disp" \
  --setenv XDG_RUNTIME_DIR "$home" --setenv SDL_VIDEO_DRIVER x11 --setenv SDL_AUDIO_DRIVER dummy \
  --setenv VK_ICD_FILENAMES "$work/lvp.json" --setenv LD_LIBRARY_PATH "$work/gl/lib" \
  -- "$here/build-linux-sdk/replayarcade-linux" "$@"
