#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build" "$PROJECT_DIR/.build/module-cache"
BUILD_STAGE="$(mktemp -d "$PROJECT_DIR/build/.staging.XXXXXX")"
APP_BUNDLE="$BUILD_STAGE/Finder新建文件.app"
EXTENSION_BUNDLE="$APP_BUNDLE/Contents/PlugIns/FinderNewFileExtension.appex"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$EXTENSION_BUNDLE/Contents/MacOS" "$EXTENSION_BUNDLE/Contents/Resources"

xcrun swiftc -swift-version 5 -O -parse-as-library \
    -module-cache-path "$PROJECT_DIR/.build/module-cache" \
    -target "$(uname -m)-apple-macosx14.0" -module-name FinderNewFile \
    -framework AppKit -framework FinderSync \
    "$PROJECT_DIR"/Sources/FileCreationCore/*.swift "$PROJECT_DIR"/Sources/App/*.swift \
    -o "$APP_BUNDLE/Contents/MacOS/FinderNewFile"

xcrun swiftc -swift-version 5 -O -parse-as-library -emit-executable -application-extension \
    -module-cache-path "$PROJECT_DIR/.build/module-cache" \
    -target "$(uname -m)-apple-macosx14.0" -module-name FinderNewFileExtension \
    -framework AppKit -framework FinderSync -framework OSLog \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "$PROJECT_DIR/Sources/FileCreationCore/CreateRequest.swift" \
    "$PROJECT_DIR/Sources/FileCreationCore/NewFileType.swift" "$PROJECT_DIR"/Sources/FinderExtension/*.swift \
    -o "$EXTENSION_BUNDLE/Contents/MacOS/FinderNewFileExtension"

cp "$PROJECT_DIR/Resources/App-Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/Extension-Info.plist" "$EXTENSION_BUNDLE/Contents/Info.plist"
REQUEST_TOKEN="$(/usr/bin/openssl rand -hex 32)"
printf '%s\n' "$REQUEST_TOKEN" > "$APP_BUNDLE/Contents/Resources/CreateRequestToken"
printf '%s\n' "$REQUEST_TOKEN" > "$EXTENSION_BUNDLE/Contents/Resources/CreateRequestToken"
chmod 600 "$APP_BUNDLE/Contents/Resources/CreateRequestToken" "$EXTENSION_BUNDLE/Contents/Resources/CreateRequestToken"
plutil -lint "$APP_BUNDLE/Contents/Info.plist" "$EXTENSION_BUNDLE/Contents/Info.plist"
codesign --force --sign - --entitlements "$PROJECT_DIR/Resources/Extension.entitlements" "$EXTENSION_BUNDLE"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

BUILD_PRODUCT="$PROJECT_DIR/build/Finder新建文件.app"
if [[ -e "$BUILD_PRODUCT" ]]; then
    mv "$BUILD_PRODUCT" "$PROJECT_DIR/build/Finder新建文件.previous.$(date +%Y%m%d%H%M%S).app"
fi
mv "$APP_BUNDLE" "$BUILD_PRODUCT"
rmdir "$BUILD_STAGE"
print -r -- "Built: $BUILD_PRODUCT"
