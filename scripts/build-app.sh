#!/bin/sh
# Builds NotchNull.app into ./build (release, ad-hoc signed).
# Usage: scripts/build-app.sh [--install] [--dev]
#   --install  copies the built app to /Applications
#   --dev      debug build as NotchNull-dev.app instead, for testing a branch
#              without touching the release app (same bundle id: quit the
#              release app before opening the dev one)
set -eu

DEV=0
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --dev) DEV=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
if [ "$DEV" -eq 1 ]; then
    APP="$BUILD/NotchNull-dev.app"
    NAME="NotchNull-dev"
else
    APP="$BUILD/NotchNull.app"
    NAME="NotchNull"
fi

cd "$ROOT"
if [ "$DEV" -eq 1 ]; then
    swift build --product NotchNull
    BIN="$(swift build --show-bin-path)/NotchNull"
else
    swift build -c release --product NotchNull
    BIN="$(swift build -c release --show-bin-path)/NotchNull"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchNull"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# The agent skill, copied to ~/.notchnull/skill on every launch.
cp -R "$ROOT/skills/notchnull" "$APP/Contents/Resources/skill"

# Now Playing bridge: a dylib run inside /usr/bin/perl (see MediaBridge/NowPlayingBridge.m).
mkdir -p "$BUILD/bridge"
clang -dynamiclib -fobjc-arc -O2 -mmacosx-version-min=14.0 -Wno-arc-performSelector-leaks \
  -framework Foundation -framework AppKit \
  -o "$BUILD/bridge/NowPlayingBridge.dylib" "$ROOT/MediaBridge/NowPlayingBridge.m"
codesign --force --sign - "$BUILD/bridge/NowPlayingBridge.dylib"
cp "$ROOT/MediaBridge/now-playing.pl" "$BUILD/bridge/now-playing.pl"
cp "$BUILD/bridge/NowPlayingBridge.dylib" "$BUILD/bridge/now-playing.pl" "$APP/Contents/Resources/"

# App icon rendered from AppIconArt.swift.
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
"$BIN" --icon "$BUILD/icon-1024.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$BUILD/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$BUILD/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [ "$INSTALL" -eq 1 ]; then
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" /Applications/
  echo "Installed /Applications/$NAME.app"
fi
