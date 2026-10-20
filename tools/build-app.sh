#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
bundle="$PWD/build/AULA F108Pro.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
python3 tools/prepare-assets.py "$bundle/Contents/Resources/Assets"
cp tools/Info.plist "$bundle/Contents/Info.plist"
swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
cp "$binary_dir/F108Pro" "$bundle/Contents/MacOS/F108Pro"
codesign --force --sign - --timestamp=none "$bundle"
printf '\n%s\n' "$bundle"
