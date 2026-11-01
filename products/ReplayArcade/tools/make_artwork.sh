#!/usr/bin/env bash
# Builds every PNG under packaging/linux/artwork/png from src/icon.svg (ImageMagick 6 or 7, librsvg):
# app icons (hicolor 64-512, icon.png) and the Steam artwork (capsule, wide, hero, logo).
#   tools/make_artwork.sh
set -euo pipefail
art="$(cd "$(dirname "$0")/.." && pwd)/packaging/linux/artwork"
svg="$art/src/icon.svg"
bg="#000000"  # the icon's black
font="${ARTWORK_FONT:-DejaVu-Sans-Bold}"  # a name ImageMagick knows, or a font file
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

im=$(command -v magick || command -v convert)
convert() { "$im" "$@"; }
render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

# The icon (square, it fills its square: no backdrop of its own).
for s in 64 128 256 512; do render "$svg" $s "$art/png/hicolor/$s.png"; done
cp "$art/png/hicolor/256.png" "$art/png/icon.png"
# Windows icon: 16-256 px in one .ico.
for s in 16 24 32 48; do render "$svg" $s "$tmp/ico-$s.png"; done
convert "$tmp"/ico-16.png "$tmp"/ico-24.png "$tmp"/ico-32.png "$tmp"/ico-48.png \
  "$art/png/hicolor/64.png" "$art/png/hicolor/128.png" "$art/png/hicolor/256.png" "$art/replayarcade.ico"
emblem() { render "$svg" "$1" "$2"; }

# Text fitted into a box (the point size follows the box).
text() { convert -background none -fill white -font "$font" -gravity center -size "$1x$2" label:"ReplayArcade" "$3"; }

# Capsule 600x900: emblem over the name.
emblem 420 "$tmp/e.png"; text 500 110 "$tmp/t.png"
convert -size 600x900 "xc:$bg" "$tmp/e.png" -gravity north -geometry +0+150 -composite \
  "$tmp/t.png" -gravity north -geometry +0+620 -composite "$art/png/capsule.png"

# Wide 920x430: emblem left, name right.
emblem 300 "$tmp/e.png"; text 520 120 "$tmp/t.png"
convert -size 920x430 "xc:$bg" "$tmp/e.png" -gravity west -geometry +50+0 -composite \
  "$tmp/t.png" -gravity west -geometry +370+0 -composite "$art/png/wide.png"

# Hero 1920x620 (no text: Steam draws the logo over it).
emblem 520 "$tmp/e.png"
convert -size 1920x620 "xc:$bg" "$tmp/e.png" -gravity center -geometry +0+0 -composite "$art/png/hero.png"

# Logo 1280x360, transparent: emblem and name.
emblem 300 "$tmp/e.png"; text 860 160 "$tmp/t.png"
convert -size 1280x360 xc:none "$tmp/e.png" -gravity west -geometry +40+0 -composite \
  "$tmp/t.png" -gravity west -geometry +380+0 -composite "$art/png/logo.png"
echo "artwork: $art/png"
