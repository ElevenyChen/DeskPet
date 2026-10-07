#!/usr/bin/env bash
# Build DeskPet (Release), verify the bundle, and produce a DMG.
#
#   scripts/release.sh            -> dist/DeskPet.dmg
#   scripts/release.sh 1.2.0      -> dist/DeskPet-1.2.0.dmg
#
# Always does a clean build so newly added Sprites are copied (see CLAUDE.md,
# 已踩过的坑 #9: incremental builds don't sync new resource files).
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-}"
PROJECT="DeskPet.xcodeproj"
SCHEME="DeskPet"
BUILD_DIR="$PWD/build/release"
DIST_DIR="$PWD/dist"

XCODEBUILD="$(command -v xcodebuild || true)"
if [[ -z "$XCODEBUILD" && -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
  XCODEBUILD=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
fi
if [[ -z "$XCODEBUILD" ]]; then
  echo "xcodebuild not found. Install Xcode or run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

step() { printf '\n==> %s\n' "$*"; }

step "Validating Sprites/"
if command -v python3 >/dev/null && python3 -c 'import PIL' 2>/dev/null; then
  python3 scripts/prepare_sprites.py check
else
  echo "python3 + Pillow not available, skipping sprite validation (python3 -m pip install pillow)"
fi

step "Clean Release build"
"$XCODEBUILD" -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" clean build | tail -n 5

APP="$BUILD_DIR/Build/Products/Release/DeskPet.app"
[[ -d "$APP" ]] || { echo "Build product not found at $APP" >&2; exit 1; }

step "Verifying bundle resources"
BUNDLE_SPRITES="$APP/Contents/Resources/Sprites"
[[ -d "$BUNDLE_SPRITES" ]] || { echo "Sprites folder missing from bundle" >&2; exit 1; }
src_count=$(find DeskPet/Sprites -name '*.png' | wc -l | tr -d ' ')
dst_count=$(find "$BUNDLE_SPRITES" -name '*.png' | wc -l | tr -d ' ')
echo "Sprites PNGs: source=$src_count bundle=$dst_count"
if [[ "$src_count" != "$dst_count" ]]; then
  echo "Bundle sprite count differs from source; resources were not fully copied" >&2
  exit 1
fi

step "Creating DMG"
mkdir -p "$DIST_DIR"
DMG="$DIST_DIR/DeskPet${VERSION:+-$VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname DeskPet -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
echo "$DMG"
