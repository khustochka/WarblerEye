#!/bin/bash
#
# make-icon.sh — build a macOS app icon from a photo.
#
# Crops the source to a square, rounds it to the corner radius macOS uses,
# insets it on the canvas the way system icons are inset, and writes every
# size an .icns needs. Installs the result into the asset catalog unless
# told otherwise.
#
# Usage:
#   Tools/make-icon.sh photo.jpg
#   Tools/make-icon.sh photo.jpg --gravity north      # crop toward the top
#   Tools/make-icon.sh photo.jpg --background '#1a1a1a'
#   Tools/make-icon.sh photo.jpg --no-install --preview
#
set -euo pipefail

usage() {
    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-1}"
}

source_image=""
gravity="center"
background="none"
install_icon=1
preview=0
# How much of the canvas the rounded square occupies. Apple's own icons leave
# a margin so that a Dock full of them shares one optical size.
scale_percent=82

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gravity)    gravity="$2"; shift 2 ;;
        --background) background="$2"; shift 2 ;;
        --scale)      scale_percent="$2"; shift 2 ;;
        --no-install) install_icon=0; shift ;;
        --preview)    preview=1; shift ;;
        -h|--help)    usage 0 ;;
        -*)           echo "unknown option: $1" >&2; usage ;;
        *)            source_image="$1"; shift ;;
    esac
done

[[ -n "$source_image" ]] || usage
[[ -f "$source_image" ]] || { echo "no such file: $source_image" >&2; exit 1; }
command -v magick >/dev/null || {
    echo "needs ImageMagick for the rounded mask: brew install imagemagick" >&2
    exit 1
}

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
appiconset="$project_root/PloceusView/Assets.xcassets/AppIcon.appiconset"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

canvas=1024
# The artwork itself, inset within the canvas.
art=$(( canvas * scale_percent / 100 ))
# macOS rounds icon corners to a little under a quarter of the artwork.
radius=$(( art * 45 / 200 ))

echo "Source:     $source_image"
echo "Canvas:     ${canvas}px, artwork ${art}px (${scale_percent}%), radius ${radius}px"

# Square crop from the requested part of the frame, then the rounded mask.
magick "$source_image" \
    -auto-orient \
    -gravity "$gravity" \
    -resize "${art}x${art}^" \
    -extent "${art}x${art}" \
    \( -size "${art}x${art}" xc:none \
       -draw "roundrectangle 0,0,$((art-1)),$((art-1)),$radius,$radius" \) \
    -compose CopyOpacity -composite \
    "$work/art.png"

# Centre the artwork on a transparent (or filled) canvas at full icon size.
magick -size "${canvas}x${canvas}" "xc:$background" \
    "$work/art.png" -gravity center -compose over -composite \
    "$work/icon_1024.png"

# The ten representations an .icns carries: each size at 1x and 2x.
iconset="$work/icon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    magick "$work/icon_1024.png" -resize "${size}x${size}" \
        "$iconset/icon_${size}x${size}.png"
    magick "$work/icon_1024.png" -resize "$((size*2))x$((size*2))" \
        "$iconset/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$iconset" -o "$work/PloceusView.icns"
echo "Built:      $(du -h "$work/PloceusView.icns" | cut -f1) icns"

if (( install_icon )); then
    rm -rf "$appiconset"
    mkdir -p "$appiconset"

    # A macOS icon set declares five sizes at both scales. There is no
    # 1024x1024@1x slot: the largest is 512x512@2x.
    {
        printf '{\n  "images" : [\n'
        first=1
        for size in 16 32 128 256 512; do
            for scale in 1 2; do
                name="icon_${size}x${size}"
                [[ $scale == 2 ]] && name="${name}@2x"
                cp "$iconset/${name}.png" "$appiconset/${name}.png"
                (( first )) || printf ',\n'
                first=0
                printf '    {\n'
                printf '      "filename" : "%s.png",\n' "$name"
                printf '      "idiom" : "mac",\n'
                printf '      "scale" : "%dx",\n' "$scale"
                printf '      "size" : "%dx%d"\n' "$size" "$size"
                printf '    }'
            done
        done
        printf '\n  ],\n  "info" : {\n    "author" : "make-icon.sh",\n    "version" : 1\n  }\n}\n'
    } > "$appiconset/Contents.json"

    echo "Installed:  $appiconset (10 sizes)"
    echo "            Rebuild to see it in the Dock."
fi

if (( preview )); then
    # A strip of the sizes that matter, so the small end can be judged.
    magick "$iconset/icon_16x16.png" "$iconset/icon_32x32.png" \
           "$iconset/icon_128x128.png" "$iconset/icon_256x256.png" \
        -background '#3a3a3a' -gravity south +append -bordercolor '#3a3a3a' \
        -border 12 "$work/preview.png"
    cp "$work/preview.png" "${TMPDIR:-/tmp}/icon-preview.png"
    echo "Preview:    ${TMPDIR:-/tmp}/icon-preview.png"
    open "${TMPDIR:-/tmp}/icon-preview.png"
fi

# Keep the .icns beside the project for anyone who wants it directly.
cp "$work/PloceusView.icns" "$project_root/Tools/PloceusView.icns"
echo "Also wrote: Tools/PloceusView.icns"
