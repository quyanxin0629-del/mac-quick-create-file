#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
EXTENSION_ID="io.github.mac-quick-create-file.extension"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
APP_CANDIDATES=("/Applications/初页.app" "/Applications/Finder新建文件.app" "$HOME/Applications/初页.app" "$HOME/Applications/Finder新建文件.app")
INSTALLED_APPS=()
for candidate in "${APP_CANDIDATES[@]}"; do
    if [[ ! -e "$candidate" ]]; then continue; fi
    CURRENT_ID="$(plutil -extract CFBundleIdentifier raw -o - "$candidate/Contents/Info.plist")"
    [[ "$CURRENT_ID" == "io.github.mac-quick-create-file" ]] || { print -u2 "同名程序不是本项目，已停止：$candidate"; exit 1; }
    [[ -w "${candidate:h}" ]] || { print -u2 "没有权限移除此程序，请通过 Finder 卸载：$candidate"; exit 1; }
    INSTALLED_APPS+=("$candidate")
done
if (( ${#INSTALLED_APPS[@]} == 0 )); then print -r -- '未找到已安装的“初页”。'; exit 0; fi
pluginkit -e ignore -i "$EXTENSION_ID"
BACKUP_DIR="$PROJECT_DIR/build/uninstalled-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
backup_index=0
for candidate in "${INSTALLED_APPS[@]}"; do
    pluginkit -r "$candidate/Contents/PlugIns/FinderNewFileExtension.appex" || true
    "$LSREGISTER" -u "$candidate" || true
    backup_index=$((backup_index + 1))
    "$PROJECT_DIR/Scripts/archive-app.sh" "$candidate" "$BACKUP_DIR/$backup_index-${candidate:t}.zip"
done
print -r -- "已停用并保留程序备份：$BACKUP_DIR"
print -r -- '源码、偏好设置和已创建的文件均保留。'
