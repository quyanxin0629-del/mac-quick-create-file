#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
BUILD_PRODUCT="$PROJECT_DIR/build/初页.app"
INSTALL_TARGET="/Applications/初页.app"
EXTENSION_ID="com.cyrix.finder-new-file.extension"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
APP_CANDIDATES=("$INSTALL_TARGET" "/Applications/Finder新建文件.app" "$HOME/Applications/初页.app" "$HOME/Applications/Finder新建文件.app")
[[ -d "$BUILD_PRODUCT" ]] || "$PROJECT_DIR/Scripts/build.sh"
codesign --verify --deep --strict "$BUILD_PRODUCT"
[[ -w /Applications ]] || { print -u2 '应用程序目录不可写。请用 Finder 将 build/初页.app 拖入“应用程序”，完成系统授权后打开并启用扩展。'; exit 1; }
for candidate in "${APP_CANDIDATES[@]}"; do
    if [[ -e "$candidate" ]]; then
        CURRENT_ID="$(plutil -extract CFBundleIdentifier raw -o - "$candidate/Contents/Info.plist")"
        [[ "$CURRENT_ID" == "com.cyrix.finder-new-file" ]] || { print -u2 "发现其他同名程序，已停止：$candidate"; exit 1; }
    fi
done
INSTALL_STAGE="$(mktemp -d /Applications/.chuye-install.XXXXXX)"
ditto "$BUILD_PRODUCT" "$INSTALL_STAGE/初页.app"
codesign --verify --deep --strict "$INSTALL_STAGE/初页.app"
mkdir -p "$PROJECT_DIR/build/installation-backups"
BACKUP_DIR="$(mktemp -d "$PROJECT_DIR/build/installation-backups/update.XXXXXX")"
backup_index=0
for candidate in "${APP_CANDIDATES[@]}"; do
    if [[ ! -e "$candidate" ]]; then continue; fi
    pluginkit -r "$candidate/Contents/PlugIns/FinderNewFileExtension.appex" || true
    while read -r extension_pid extension_path; do
        if [[ "$extension_path" == "$candidate/Contents/PlugIns/FinderNewFileExtension.appex/Contents/MacOS/FinderNewFileExtension" ]]; then
            kill -TERM "$extension_pid" 2>/dev/null || true
        fi
    done < <(/bin/ps -axo pid=,comm=)
    "$LSREGISTER" -u "$candidate" || true
    backup_index=$((backup_index + 1))
    mv "$candidate" "$BACKUP_DIR/$backup_index-${candidate:t}"
done
mv "$INSTALL_STAGE/初页.app" "$INSTALL_TARGET"
rmdir "$INSTALL_STAGE"
"$LSREGISTER" -f "$INSTALL_TARGET"
pluginkit -a "$INSTALL_TARGET/Contents/PlugIns/FinderNewFileExtension.appex"
pluginkit -e use -i "$EXTENSION_ID"
pluginkit -m -A -D -i "$EXTENSION_ID"
print -r -- "Installed: $INSTALL_TARGET"
print -r -- '请在本地文件夹空白处右键，从“新建文件”子菜单选择 TXT 或 Markdown。'
