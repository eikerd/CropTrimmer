#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
mkdir -p build
app="build/Crop Trimmer.app"
if [[ -e "$app" && ! -f "$app/Contents/Resources/.croptrimmer-local-build" ]]; then
    echo "Refusing to replace an unrelated app at $app" >&2
    exit 1
fi
stage=$(mktemp -d "build/.croptrimmer-build.XXXXXX")
trap 'rm -rf "$stage"' EXIT
bundle="$stage/Crop Trimmer.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin_dir/CropTrimmer" "$bundle/Contents/MacOS/CropTrimmer"
touch "$bundle/Contents/Resources/.croptrimmer-local-build"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CropTrimmer</string>
<key>CFBundleIdentifier</key><string>com.croptrimmer.mac</string>
<key>CFBundleName</key><string>Crop Trimmer</string>
<key>CFBundleDisplayName</key><string>Crop Trimmer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Movie</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>public.movie</string></array>
</dict></array>
</dict></plist>
PLIST
python3 scripts/bundle-tools.py "$bundle"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
"$bundle/Contents/Helpers/ffmpeg" -version >/dev/null
"$bundle/Contents/Helpers/ffprobe" -version >/dev/null
if [[ -e "$app" ]]; then rm -rf "$app"; fi
mv "$bundle" "$app"
printf 'Built local application: %s/%s\n' "$PWD" "$app"
