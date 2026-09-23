#!/bin/sh
# Copyright (C) 2026 Shitty team
# MIT licensed
# See the file LICENSE.MIT for the full license.
#
# Wraps an already-built st/pt binary in a minimal macOS .app bundle: an
# Info.plist, a generated .icns (rasterized from the same SVG the Linux
# .desktop entry points at), and the binary itself under Contents/MacOS.
# Used by CI (.github/workflows/release.yml) and works the same locally.
#
# usage: package_macos_app.sh APP_NAME BUNDLE_ID EXECUTABLE_NAME SVG_ICON BINARY OUTPUT_APP
#
#   APP_NAME         display name, e.g. Shitty
#   BUNDLE_ID        reverse-DNS identifier, e.g. com.pg83.shitty
#   EXECUTABLE_NAME  the binary's own name inside the bundle, e.g. st
#   SVG_ICON         source icon, e.g. bin/st/shitty.svg
#   BINARY           the built executable to copy in
#   OUTPUT_APP       path to create, e.g. .build-darwin/Shitty.app
set -eu

app_name=$1
bundle_id=$2
executable_name=$3
svg_icon=$4
binary=$5
output_app=$6

command -v rsvg-convert >/dev/null || {
    echo "rsvg-convert is required (brew install librsvg)" >&2
    exit 1
}
command -v iconutil >/dev/null || {
    echo "iconutil is required (part of the Xcode command line tools)" >&2
    exit 1
}

rm -rf "$output_app"
mkdir -p "$output_app/Contents/MacOS" "$output_app/Contents/Resources"

cp -L "$binary" "$output_app/Contents/MacOS/$executable_name"
chmod 755 "$output_app/Contents/MacOS/$executable_name"

# CFBundleShortVersionString/CFBundleVersion come from the binary itself
# (build.py stamps -DSHITTY_VERSION as today's date), so the plist can never
# drift from what `-version` actually reports.
version=$("$output_app/Contents/MacOS/$executable_name" -version | awk '{print $2}')
if [ -z "$version" ]; then
    echo "could not read a version out of $executable_name -version" >&2
    exit 1
fi

icon_name=$(printf '%s' "$app_name" | tr '[:upper:]' '[:lower:]')
iconset="$(mktemp -d)/$icon_name.iconset"
mkdir -p "$iconset"
trap 'rm -rf "$(dirname "$iconset")"' EXIT

for spec in \
    16:icon_16x16.png \
    32:icon_16x16@2x.png \
    32:icon_32x32.png \
    64:icon_32x32@2x.png \
    128:icon_128x128.png \
    256:icon_128x128@2x.png \
    256:icon_256x256.png \
    512:icon_256x256@2x.png \
    512:icon_512x512.png \
    1024:icon_512x512@2x.png \
; do
    size=${spec%%:*}
    name=${spec#*:}
    rsvg-convert -w "$size" -h "$size" "$svg_icon" -o "$iconset/$name"
done
iconutil -c icns "$iconset" -o "$output_app/Contents/Resources/$icon_name.icns"

cat > "$output_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$executable_name</string>
    <key>CFBundleIconFile</key>
    <string>$icon_name</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_id</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$app_name</string>
    <key>CFBundleDisplayName</key>
    <string>$app_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$version</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

chmod 644 "$output_app/Contents/Info.plist" "$output_app/Contents/Resources/$icon_name.icns"
