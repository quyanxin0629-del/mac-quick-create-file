#!/bin/zsh
set -euo pipefail
if (( $# != 2 )); then print -u2 '用法：archive-app.sh APP_BUNDLE BACKUP.zip'; exit 64; fi
APP_BUNDLE="${1:A}"
BACKUP_ZIP="${2:A}"
[[ -d "$APP_BUNDLE" && ! -L "$1" && "${APP_BUNDLE:e}" == app && "${BACKUP_ZIP:e}" == zip && ! -e "$BACKUP_ZIP" ]] || { print -u2 'App 或备份路径无效。'; exit 1; }
[[ "$BACKUP_ZIP" != "$APP_BUNDLE"/* ]] || { print -u2 '备份文件必须保存在 App 之外。'; exit 1; }
APP_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_BUNDLE/Contents/Info.plist")"
APP_EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$APP_BUNDLE/Contents/Info.plist")"
EXTENSION_PLIST="$APP_BUNDLE/Contents/PlugIns/FinderNewFileExtension.appex/Contents/Info.plist"
EXTENSION_ID="$(plutil -extract CFBundleIdentifier raw -o - "$EXTENSION_PLIST")"
[[ "$APP_EXECUTABLE" == FinderNewFile && "$EXTENSION_ID" == "$APP_ID.extension" ]] || { print -u2 '此 App 不是本项目，已停止归档。'; exit 1; }
codesign --verify --deep --strict "$APP_BUNDLE"
mkdir -p "${BACKUP_ZIP:h}"
ARCHIVE_STAGE="$(mktemp "$BACKUP_ZIP.tmp.XXXXXX")"
trap 'rm -f "$ARCHIVE_STAGE"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE_STAGE"
unzip -t -q "$ARCHIVE_STAGE" >/dev/null
pluginkit -r "$APP_BUNDLE/Contents/PlugIns/FinderNewFileExtension.appex" >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP_BUNDLE" >/dev/null 2>&1 || true
mv "$ARCHIVE_STAGE" "$BACKUP_ZIP"
# Remove only after the archive has passed its integrity check. The old App
# must not remain discoverable as another executable copy of this extension.
rm -r "$APP_BUNDLE"
