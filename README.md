# mac快速创建文件

一个使用 Swift 编写的轻量 macOS Finder 扩展，在文件夹空白处的右键菜单中添加“新建文件”子菜单。

鼠标移到“新建文件”，点击 **TXT** 或 **Markdown** 即可直接创建，无需输入文件名或再次确认。

## 功能

- 创建空白 `.txt`、`.md` 文件，默认名称为“未命名.txt”“未命名.md”。
- 重名自动编号，例如“未命名 1.md”，不覆盖已有文件、文件夹或符号链接。
- 创建后在 Finder 中自动选中，可按回车重命名。
- 主程序没有 Dock 图标或菜单栏状态图标，完成后退出。
- 不添加登录启动项、不扫描文件、不读取文档内容、不联网。

## 环境要求

- macOS 14 或更新版本。
- Apple Command Line Tools，包含 Swift 编译器。
- 无第三方依赖，无需安装完整 Xcode。

在 Apple Silicon、macOS 27.0.1、Swift 6.4 环境构建并使用；其他系统版本和架构需自行确认兼容性。

## 构建与安装

```sh
git clone https://github.com/quyanxin0629-del/mac-quick-create-file.git
cd mac-quick-create-file
./Scripts/build.sh
./Scripts/install.sh
```

构建当前机器架构，产物为 `build/Finder新建文件.app`，安装到 `~/Applications/Finder新建文件.app`。

安装脚本注册并启用 Finder 扩展。如果菜单没有显示，打开已安装的 App，按提示前往系统设置启用“Finder新建文件”，然后重新打开本地文件夹。

使用本机临时签名，不含开发者证书或公证。适合从源码在本机构建；直接把生成的 App 分发给其他机器可能受到系统签名和安全策略限制。

## 使用

1. 在本地文件夹的空白处右键。
2. 将鼠标放到“新建文件”上。
3. 点击“TXT 文本文件 (.txt)”或“Markdown (.md)”，立即创建。

Finder 决定菜单项的位置，无法固定到“新建文件夹”正下方。

## 配置默认名称

设置不带后缀的基础名称：

```sh
defaults write com.cyrix.finder-new-file DefaultBaseName -string '笔记'
```

分别创建“笔记.txt”“笔记.md”。恢复默认：

```sh
defaults delete com.cyrix.finder-new-file DefaultBaseName
```

## 扩展文件类型

在 `Sources/FileCreationCore/NewFileType.swift` 中增加类型、菜单名称、后缀和唯一的菜单 tag，再重新构建安装。

当前创建的是空白文件。Word、Excel、PDF 等格式需要有效模板，不能通过添加后缀直接支持。

## 项目结构

```text
Sources/
  App/AppMain.swift                    # 创建入口、错误提示和结果选中
  FinderExtension/FinderExtension.swift # Finder 原生右键子菜单
  FileCreationCore/
    NewFileType.swift                  # 类型和菜单定义
    FileCreator.swift                  # 原子创建与重名保护
    CreateRequest.swift                # 目录、类型和请求凭据校验
Resources/                             # App/扩展配置与沙盒权限
Scripts/                               # 构建、安装和卸载
```

扩展使用 App Sandbox，只处理 Finder 菜单上下文并唤起承载程序。承载程序使用当前用户权限创建文件，受保护目录可能需要 macOS 文件夹访问授权。

请求凭据在每次构建时随机生成，存放在生成的 App 中，不包含在源码仓库中。

## 卸载

```sh
./Scripts/uninstall.sh
```

停用扩展并将 App 移到项目内的备份目录。源码、偏好设置和已经创建的文件保留。

## 已知限制

- “最近使用”、搜索结果等虚拟位置不能作为创建目标。
- iCloud、Google Drive 等 File Provider 位置可能不显示 Finder Sync 菜单。
- 外置磁盘和网络共享目录未单独确认兼容性。
- Finder Sync 主要面向同步工具；Mac App Store 分发需要另行评估扩展使用场景及审核要求。

## 许可证

[MIT](LICENSE)

## 相关文档

- [Apple Finder Sync](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html)
- [Finder 空白处右键菜单接口](https://developer.apple.com/documentation/findersync/fimenukind/contextualmenuforcontainer)
