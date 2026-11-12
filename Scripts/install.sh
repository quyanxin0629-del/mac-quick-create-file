#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
BUILD_PRODUCT="$PROJECT_DIR/build/Finder新建文件.app"
INSTALL_TARGET="$HOME/Applications/Finder新建文件.app"
EXTENSION_ID="com.cyrix.finder-new-file.extension"
[[ -d "$BUILD_PRODUCT" ]] || "$PROJECT_DIR/Scripts/build.sh"
codesign --verify --deep --strict "$BUILD_PRODUCT"
mkdir -p "$HOME/Applications" "$PROJECT_DIR/build/installation-backups"
if [[ -e "$INSTALL_TARGET" ]]; then
    CURRENT_ID="$(plutil -extract CFBundleIdentifier raw -o - "$INSTALL_TARGET/Contents/Info.plist")"
    [[ "$CURRENT_ID" == "com.cyrix.finder-new-file" ]] || { print -u2 '安装位置已有其他程序，已停止。'; exit 1; }
    pluginkit -r "$INSTALL_TARGET/Contents/PlugIns/FinderNewFileExtension.appex" || true
    # Reload only our extension; do not restart Finder or other extensions.
    while read -r extension_pid extension_path; do
        if [[ "$extension_path" == "$INSTALL_TARGET/Contents/PlugIns/FinderNewFileExtension.appex/Contents/MacOS/FinderNewFileExtension" ]]; then
            kill -TERM "$extension_pid" 2>/dev/null || true
        fi
    done < <(/bin/ps -axo pid=,comm=)
    mv "$INSTALL_TARGET" "$PROJECT_DIR/build/installation-backups/Finder新建文件.$(date +%Y%m%d%H%M%S).app"
fi
ditto "$BUILD_PRODUCT" "$INSTALL_TARGET"
codesign --verify --deep --strict "$INSTALL_TARGET"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_TARGET"
pluginkit -a "$INSTALL_TARGET/Contents/PlugIns/FinderNewFileExtension.appex"
pluginkit -e use -i "$EXTENSION_ID"
pluginkit -m -A -D -i "$EXTENSION_ID"
print -r -- "Installed: $INSTALL_TARGET"
print -r -- '请打开一个本地文件夹，在空白处右键，从“新建文件”子菜单选择 TXT 或 Markdown。'
