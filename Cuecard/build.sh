#!/bin/bash
set -euo pipefail

project="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "$project/.build.XXXXXX")"
trap 'rm -rf "$work"' EXIT
app="$work/Cuecard.app"
macos="$app/Contents/MacOS"
resources="$app/Contents/Resources"
mkdir -p "$macos" "$resources" "$project/build"
cp "$project/Info.plist" "$app/Contents/Info.plist"

/usr/bin/xcrun swiftc "$project/Tools/DrawIcon.swift" -module-cache-path "$project/.module-cache" -o "$work/draw-icon"
"$work/draw-icon" "$resources/Cuecard.icns"

for architecture in arm64 x86_64; do
    echo "Building Cuecard for ${architecture}…"
    /usr/bin/xcrun --sdk macosx swiftc -swift-version 5 -O -parse-as-library \
        -target "$architecture-apple-macos13.0" -module-cache-path "$project/.module-cache" \
        "$project"/Sources/*.swift -o "$work/Cuecard-$architecture"
done
/usr/bin/lipo -create "$work/Cuecard-arm64" "$work/Cuecard-x86_64" -output "$macos/Cuecard"
chmod 755 "$macos/Cuecard"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
rm -rf "$project/build/Cuecard.app"
mv "$app" "$project/build/Cuecard.app"
echo "Built $project/build/Cuecard.app"
