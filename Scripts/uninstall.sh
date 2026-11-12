#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
INSTALL_TARGET="$HOME/Applications/Finder新建文件.app"
EXTENSION_ID="com.cyrix.finder-new-file.extension"
if [[ ! -d "$INSTALL_TARGET" ]]; then
    print -r -- '未找到已安装的 Finder新建文件.app。'
    exit 0
fi
CURRENT_ID="$(plutil -extract CFBundleIdentifier raw -o - "$INSTALL_TARGET/Contents/Info.plist")"
[[ "$CURRENT_ID" == "com.cyrix.finder-new-file" ]] || { print -u2 '安装位置不是本项目，已停止。'; exit 1; }
pluginkit -e ignore -i "$EXTENSION_ID"
pluginkit -r "$INSTALL_TARGET/Contents/PlugIns/FinderNewFileExtension.appex"
BACKUP_DIR="$PROJECT_DIR/build/uninstalled-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
mv "$INSTALL_TARGET" "$BACKUP_DIR/"
print -r -- "已停用并移出安装目录，程序保留在：$BACKUP_DIR"
print -r -- '源码、偏好设置和已创建的文件均保留。'
