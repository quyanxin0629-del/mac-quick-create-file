#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
case "${1:-}" in
    '') BUILD_ARCHS=("$(uname -m)") ;;
    --universal) BUILD_ARCHS=(arm64 x86_64) ;;
    *) print -u2 '用法：./Scripts/build.sh [--universal]'; exit 64 ;;
esac
mkdir -p "$PROJECT_DIR/build" "$PROJECT_DIR/.build/module-cache"
BUILD_STAGE="$(mktemp -d "$PROJECT_DIR/build/.staging.XXXXXX")"
APP_BUNDLE="$BUILD_STAGE/初页.app"
EXTENSION_BUNDLE="$APP_BUNDLE/Contents/PlugIns/FinderNewFileExtension.appex"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$EXTENSION_BUNDLE/Contents/MacOS" "$EXTENSION_BUNDLE/Contents/Resources"

APP_SLICES=()
EXTENSION_SLICES=()
for BUILD_ARCH in "${BUILD_ARCHS[@]}"; do
    APP_SLICE="$BUILD_STAGE/FinderNewFile-$BUILD_ARCH"
    EXTENSION_SLICE="$BUILD_STAGE/FinderNewFileExtension-$BUILD_ARCH"
    xcrun swiftc -swift-version 5 -O -parse-as-library \
    -module-cache-path "$PROJECT_DIR/.build/module-cache" \
    -target "$BUILD_ARCH-apple-macosx14.0" -module-name FinderNewFile \
    -framework AppKit -framework FinderSync \
    "$PROJECT_DIR"/Sources/FileCreationCore/*.swift "$PROJECT_DIR"/Sources/App/*.swift \
    -o "$APP_SLICE"

    xcrun swiftc -swift-version 5 -O -parse-as-library -emit-executable -application-extension \
    -module-cache-path "$PROJECT_DIR/.build/module-cache" \
    -target "$BUILD_ARCH-apple-macosx14.0" -module-name FinderNewFileExtension \
    -framework AppKit -framework FinderSync -framework OSLog \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "$PROJECT_DIR/Sources/FileCreationCore/CreateRequest.swift" \
    "$PROJECT_DIR/Sources/FileCreationCore/NewFileType.swift" "$PROJECT_DIR"/Sources/FinderExtension/*.swift \
    -o "$EXTENSION_SLICE"
    APP_SLICES+=("$APP_SLICE")
    EXTENSION_SLICES+=("$EXTENSION_SLICE")
done
xcrun lipo -create "${APP_SLICES[@]}" -output "$APP_BUNDLE/Contents/MacOS/FinderNewFile"
xcrun lipo -create "${EXTENSION_SLICES[@]}" -output "$EXTENSION_BUNDLE/Contents/MacOS/FinderNewFileExtension"
rm "${APP_SLICES[@]}" "${EXTENSION_SLICES[@]}"

ICONSET_DIR="$BUILD_STAGE/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
for ICON_SIZE in 16 32 128 256 512; do
    sips -z "$ICON_SIZE" "$ICON_SIZE" "$PROJECT_DIR/Resources/AppIcon.png" \
        --out "$ICONSET_DIR/icon_${ICON_SIZE}x${ICON_SIZE}.png" >/dev/null
    ICON_RETINA=$((ICON_SIZE * 2))
    sips -z "$ICON_RETINA" "$ICON_RETINA" "$PROJECT_DIR/Resources/AppIcon.png" \
        --out "$ICONSET_DIR/icon_${ICON_SIZE}x${ICON_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$EXTENSION_BUNDLE/Contents/Resources/AppIcon.icns"
rm -r "$ICONSET_DIR"

cp "$PROJECT_DIR/Resources/App-Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/Extension-Info.plist" "$EXTENSION_BUNDLE/Contents/Info.plist"
REQUEST_TOKEN="$(/usr/bin/openssl rand -hex 32)"
printf '%s\n' "$REQUEST_TOKEN" > "$APP_BUNDLE/Contents/Resources/CreateRequestToken"
printf '%s\n' "$REQUEST_TOKEN" > "$EXTENSION_BUNDLE/Contents/Resources/CreateRequestToken"
chmod 644 "$APP_BUNDLE/Contents/Resources/CreateRequestToken" "$EXTENSION_BUNDLE/Contents/Resources/CreateRequestToken"
plutil -lint "$APP_BUNDLE/Contents/Info.plist" "$EXTENSION_BUNDLE/Contents/Info.plist"
codesign --force --sign - --entitlements "$PROJECT_DIR/Resources/Extension.entitlements" "$EXTENSION_BUNDLE"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

BUILD_PRODUCT="$PROJECT_DIR/build/初页.app"
if [[ -e "$BUILD_PRODUCT" ]]; then
    "$PROJECT_DIR/Scripts/archive-app.sh" "$BUILD_PRODUCT" "$PROJECT_DIR/build/archived-builds/初页-$(date +%Y%m%d%H%M%S)-$RANDOM.zip"
fi
mv "$APP_BUNDLE" "$BUILD_PRODUCT"
rmdir "$BUILD_STAGE"
print -r -- "Built: $BUILD_PRODUCT"
