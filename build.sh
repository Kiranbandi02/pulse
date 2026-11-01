#!/bin/bash
# Builds Pulse.app (with its widget extension) using only the Xcode Command Line Tools.
#   ./build.sh          build into ./build/Pulse.app
#   ./build.sh run      build, then launch
#   ./build.sh install  build, then copy to /Applications and launch
#   ./build.sh package  build, then zip to build/Pulse.zip (attach to a GitHub release)
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=${ARCHS:-"arm64 x86_64"}
MIN=14.0
SDK=$(xcrun --show-sdk-path)
OUT=build
APP=$OUT/Pulse.app
APPEX=$APP/Contents/PlugIns/PulseWidgets.appex

rm -rf "$OUT"; mkdir -p "$OUT/tmp"

# Icon (cached in Resources/)
if [ ! -f Resources/AppIcon.icns ]; then
  swiftc tools/make_icon.swift -o "$OUT/tmp/mkicon" 2>/dev/null
  "$OUT/tmp/mkicon" "$OUT/tmp/AppIcon.iconset"
  iconutil -c icns "$OUT/tmp/AppIcon.iconset" -o Resources/AppIcon.icns
fi

compile() { # name, extra flags..., sources via SRC env
  local name=$1; shift
  local bins=()
  for arch in $ARCHS; do
    swiftc -swift-version 5 -O -parse-as-library -sdk "$SDK" -target "$arch-apple-macos$MIN" \
      "$@" $SRC -o "$OUT/tmp/$name-$arch"
    bins+=("$OUT/tmp/$name-$arch")
  done
  lipo -create "${bins[@]}" -output "$OUT/tmp/$name"
}

echo "▸ Compiling app"
SRC="Sources/Shared/*.swift Sources/App/*.swift" compile Pulse
echo "▸ Compiling widget extension"
SRC="Sources/Shared/*.swift Sources/Widget/*.swift" compile PulseWidgets \
  -application-extension -Xlinker -e -Xlinker _NSExtensionMain

echo "▸ Assembling bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"
cp "$OUT/tmp/Pulse" "$APP/Contents/MacOS/Pulse"
cp "$OUT/tmp/PulseWidgets" "$APPEX/Contents/MacOS/PulseWidgets"
cp Resources/App-Info.plist "$APP/Contents/Info.plist"
cp Resources/Widget-Info.plist "$APPEX/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad-hoc)"
codesign --force --sign - --entitlements Resources/Widget.entitlements "$APPEX"
codesign --force --sign - "$APP"
rm -rf "$OUT/tmp"
echo "✓ Built $APP"

case "${1:-}" in
  run) open "$APP" ;;
  package)
    ditto -c -k --keepParent "$APP" "$OUT/Pulse.zip"
    echo "✓ Packaged $OUT/Pulse.zip" ;;
  install)
    rm -rf /Applications/Pulse.app
    cp -R "$APP" /Applications/Pulse.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Pulse.app
    open /Applications/Pulse.app
    echo "✓ Installed to /Applications/Pulse.app" ;;
esac
