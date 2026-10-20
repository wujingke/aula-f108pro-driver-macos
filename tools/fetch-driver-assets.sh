#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if ! command -v innoextract >/dev/null 2>&1; then
    printf '%s\n' 'innoextract is required. Install it with: brew install innoextract' >&2
    exit 1
fi

archive='artifacts/AULA F108Pro Driver-1.0.0.3.exe'
expected='62babdfdca614e5c27919d26278c845c549f3943bf2076cef0b7d56ae7e2afe8'
mkdir -p artifacts
if [ ! -f "$archive" ]; then
    temporary=$(mktemp artifacts/.driver-download.XXXXXX)
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    curl --fail --location --retry 2 \
        --output "$temporary" \
        'https://cdn.aulacn.com/keyboard/AULA%20F108Pro%20Driver-1.0.0.3.exe'
    actual=$(shasum -a 256 "$temporary")
    actual=${actual%% *}
    if [ "$actual" != "$expected" ]; then
        printf '%s\n' 'Driver checksum mismatch; refusing to extract an unknown installer.' >&2
        exit 1
    fi
    mv "$temporary" "$archive"
    trap - EXIT HUP INT TERM
fi

actual=$(shasum -a 256 "$archive")
actual=${actual%% *}
if [ "$actual" != "$expected" ]; then
    printf '%s\n' 'Existing driver checksum mismatch; leaving it unchanged.' >&2
    exit 1
fi

# Extract only resources used by the app; never run the Windows installer.
innoextract --silent --output-dir artifacts/unpacked \
    --include app/skins \
    --include app/device \
    --include app/font \
    --include app/layouts \
    --include app/language \
    "$archive"

for required in \
    app/skins/theme1/main_bkg.png \
    app/skins/theme1/logo/logo.png \
    app/skins/theme1/keyboard/img_keyboard_layout.png \
    app/device/home_keyboard_connected.png \
    app/font/OpenSans-Regular.ttf \
    app/layouts/rgb-keyboard.xml \
    app/language/2052.lan
do
    if [ ! -f "artifacts/unpacked/$required" ]; then
        printf 'Required driver resource missing: %s\n' "$required" >&2
        exit 1
    fi
done
printf '%s\n' 'Verified driver resources are ready in artifacts/unpacked/app.'
