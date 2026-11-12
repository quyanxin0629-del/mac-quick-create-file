#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
APP_BUNDLE="$PROJECT_DIR/build/初页.app"
is_universal() {
    local binary_architectures
    binary_architectures="$(xcrun lipo -archs "$1" 2>/dev/null)" || return 1
    [[ " $binary_architectures " == *" arm64 "* && " $binary_architectures " == *" x86_64 "* ]]
}
if [[ ! -d "$APP_BUNDLE" ]] || ! is_universal "$APP_BUNDLE/Contents/MacOS/FinderNewFile"; then
    "$PROJECT_DIR/Scripts/build.sh" --universal
fi
is_universal "$APP_BUNDLE/Contents/PlugIns/FinderNewFileExtension.appex/Contents/MacOS/FinderNewFileExtension"
codesign --verify --deep --strict "$APP_BUNDLE"
RELEASE_DIR="$PROJECT_DIR/build/release"
PACKAGE_STAGE="$(mktemp -d "$PROJECT_DIR/build/.package.XXXXXX")"
mkdir -p "$RELEASE_DIR"
ditto "$APP_BUNDLE" "$PACKAGE_STAGE/初页.app"
ln -s /Applications "$PACKAGE_STAGE/Applications"
printf '%s\n' '初页 · mac快速创建文件' '' '1. 将“初页.app”拖入 Applications（应用程序）。' '2. 从“应用程序”打开“初页”，按提示启用 Finder 扩展。' '3. 在文件夹空白处右键，从“新建文件”选择 TXT 或 Markdown。' '' '此开源构建未经过 Apple 公证。首次打开可能需要在系统设置 → 隐私与安全中选择“仍要打开”。' > "$PACKAGE_STAGE/安装说明.txt"
hdiutil create -volname 初页 -srcfolder "$PACKAGE_STAGE" -ov -format UDZO "$RELEASE_DIR/Chuye-macOS-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$RELEASE_DIR/Chuye-macOS-universal.zip"
(
    cd "$RELEASE_DIR"
    shasum -a 256 Chuye-macOS-universal.dmg Chuye-macOS-universal.zip > SHA256SUMS.txt
)
rm -r "$PACKAGE_STAGE"
print -r -- "安装包：$RELEASE_DIR"
