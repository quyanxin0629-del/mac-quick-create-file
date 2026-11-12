#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
case "${1:-}" in
    ''|--no-refresh-finder) ;;
    *) print -u2 '用法：./Scripts/install.sh [--no-refresh-finder]'; exit 64 ;;
esac
BUILD_PRODUCT="$PROJECT_DIR/build/初页.app"
INSTALL_TARGET="/Applications/初页.app"
EXTENSION_ID="io.github.mac-quick-create-file.extension"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
APP_CANDIDATES=("$INSTALL_TARGET" "/Applications/Finder新建文件.app" "$HOME/Applications/初页.app" "$HOME/Applications/Finder新建文件.app")
[[ -d "$BUILD_PRODUCT" ]] || "$PROJECT_DIR/Scripts/build.sh"
codesign --verify --deep --strict "$BUILD_PRODUCT"
[[ -w /Applications ]] || { print -u2 '应用程序目录不可写。请用 Finder 将 build/初页.app 拖入“应用程序”，完成系统授权后打开并启用扩展。'; exit 1; }
for candidate in "${APP_CANDIDATES[@]}"; do
    if [[ -e "$candidate" ]]; then
        CURRENT_ID="$(plutil -extract CFBundleIdentifier raw -o - "$candidate/Contents/Info.plist")"
        [[ "$CURRENT_ID" == "io.github.mac-quick-create-file" ]] || { print -u2 "发现其他同名程序，已停止：$candidate"; exit 1; }
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
        if [[ "$extension_path" == "$candidate/Contents/PlugIns/FinderNewFileExtension.appex/Contents/MacOS/FinderNewFileExtension" || "$extension_path" == "$candidate/Contents/MacOS/FinderNewFile" ]]; then
            kill -TERM "$extension_pid" 2>/dev/null || true
        fi
    done < <(/bin/ps -axo pid=,comm=)
    "$LSREGISTER" -u "$candidate" || true
    backup_index=$((backup_index + 1))
    "$PROJECT_DIR/Scripts/archive-app.sh" "$candidate" "$BACKUP_DIR/$backup_index-${candidate:t}.zip"
done
mv "$INSTALL_STAGE/初页.app" "$INSTALL_TARGET"
rmdir "$INSTALL_STAGE"
# Keep the installed copy as the preferred registration, rather than leaving
# a second registered build product with the same bundle identifiers.
pluginkit -r "$BUILD_PRODUCT/Contents/PlugIns/FinderNewFileExtension.appex" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$BUILD_PRODUCT" >/dev/null 2>&1 || true
REGISTERED_EXTENSION=""
for registration_attempt in 1 2 3 4 5; do
    "$LSREGISTER" -f "$INSTALL_TARGET"
    pluginkit -a "$INSTALL_TARGET/Contents/PlugIns/FinderNewFileExtension.appex"
    pluginkit -e use -i "$EXTENSION_ID"
    sleep 0.2
    REGISTERED_EXTENSION="$(pluginkit -m -A -D -v -i "$EXTENSION_ID")"
    if [[ "$REGISTERED_EXTENSION" == *"$INSTALL_TARGET/Contents/PlugIns/FinderNewFileExtension.appex"* ]]; then
        break
    fi
done
if [[ "$REGISTERED_EXTENSION" != *"$INSTALL_TARGET/Contents/PlugIns/FinderNewFileExtension.appex"* ]]; then
    print -u2 'App 已复制，但 Finder 扩展暂未完成注册。请打开“初页”，从系统设置手动启用扩展。'
    exit 1
fi
print -r -- "$REGISTERED_EXTENSION"
print -r -- "Installed: $INSTALL_TARGET"
if [[ "${1:-}" == --no-refresh-finder ]]; then
    print -r -- '已跳过访达刷新。请打开“初页”，点击“完成安装并刷新菜单”或“修复右键菜单”。'
else
    print -r -- '正在让访达重新加载扩展；若有文件操作或系统确认，请先完成它。'
    if ! "$INSTALL_TARGET/Contents/MacOS/FinderNewFile" --refresh-finder; then
        print -u2 'App 已安装，但访达刷新未完成。请打开“初页”点击“修复右键菜单”重试。'
        exit 1
    fi
fi
print -r -- '请在本地文件夹空白处右键，从“新建文件”子菜单选择 TXT 或 Markdown 验证。'
