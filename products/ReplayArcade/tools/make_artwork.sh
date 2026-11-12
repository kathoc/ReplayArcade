#!/usr/bin/env bash
# Builds every PNG under packaging/linux/artwork/png from src/icon.svg (ImageMagick 6 or 7, librsvg):
# app icons (hicolor 64-512, icon.png) and the Steam artwork (capsule, wide, hero, logo).
#   tools/make_artwork.sh
set -euo pipefail
art="$(cd "$(dirname "$0")/.." && pwd)/packaging/linux/artwork"
svg="$art/src/icon.svg"
bg="#040000"  # the icon's black
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
# The emblem is the icon itself: its black is the artwork's background colour, so only the white stick
# and its red buttons show (the white is the icon's square: it must stay).
emblem() { render "$svg" "$1" "$2"; }
# The icon as a tile with rounded corners (an app icon's shape): where the stick runs off the icon's
# square, the tile's edge cuts it, not the middle of the artwork.
tile() {
  render "$svg" "$1" "$tmp/tile-src.png"
  convert "$tmp/tile-src.png" \( -size "$1x$1" xc:black -fill white -draw "roundrectangle 0,0 $(($1 - 1)),$(($1 - 1)) $(($1 / 9)),$(($1 / 9))" \) \
    -alpha off -compose CopyOpacity -composite "$2"
}

# The Steam artwork in the icon's look (user decision 2026-11-01): its black as the background, so
# the stick and its red buttons stand on it; the name in two lines, "Replay" white, "Arcade" red.
red="#e60012"
name() {  # name <width> <height of each line> <out>: "Replay" over "Arcade", fitted into the box
  convert \( -background none -fill white -font "$font" -size "$1x$2" -gravity center label:"Replay" \) \
    \( -background none -fill "$red" -font "$font" -size "$1x$2" -gravity center label:"Arcade" \) -append "$3"
}
name_line() {  # name_line <width> <height> <out>: "Replay" white + "Arcade" red on one line
  convert \( -background none -fill white -font "$font" -size "x$2" label:"Replay" \) \
    \( -background none -fill "$red" -font "$font" -size "x$2" label:"Arcade" \) +append -resize "$1x$2" "$3"
}

# Capsule 600x900: the tile over the name.
tile 500 "$tmp/e.png"; name 520 110 "$tmp/t.png"
convert -size 600x900 "xc:$bg" "$tmp/e.png" -gravity north -geometry +0+70 -composite \
  "$tmp/t.png" -gravity north -geometry +0+640 -composite "$art/png/capsule.png"

# Wide 920x430: the tile left, the name right.
tile 330 "$tmp/e.png"; name 420 115 "$tmp/t.png"
convert -size 920x430 "xc:$bg" "$tmp/e.png" -gravity west -geometry +50+0 -composite \
  "$tmp/t.png" -gravity west -geometry +440+0 -composite "$art/png/wide.png"

# Hero 1920x620 (no text: Steam draws the logo over it, bottom left): the icon 2.8 times the height of
# its square's 400 units, top at the top - the stick leaves the square at its top (on the hero's top
# edge), its left (from 222 units down: below the hero) and its bottom (below the hero), so no cut shows.
emblem 1120 "$tmp/e.png"
convert -size 1920x620 "xc:$bg" "$tmp/e.png" -gravity northeast -geometry +0+0 -composite "$art/png/hero.png"

# Logo 1280x360, transparent (over the hero): the name on one line.
name_line 1200 220 "$tmp/t.png"
convert -size 1280x360 xc:none "$tmp/t.png" -gravity west -geometry +40+0 -composite "$art/png/logo.png"
echo "artwork: $art/png"
