import AppKit
import FinderSync
import OSLog

@objc(FinderNewFileExtension)
final class FinderNewFileExtension: FIFinderSync {
    private let logger = Logger(subsystem: "io.github.mac-quick-create-file", category: "FinderExtension")

    override init() {
        super.init()
        // Finder calls us only for visible folders. No filesystem scanning,
        // badge generation, polling, file reading, or network access is used.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
        logger.notice("Finder new-file extension initialized")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer,
              let directory = FIFinderSyncController.default().targetedURL(),
              directory.isFileURL else { return nil }

        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: "新建文件")
        let submenu = NSMenu(title: "新建文件")
        submenu.autoenablesItems = false
        for type in NewFileType.allCases {
            let typeItem = NSMenuItem(title: type.menuTitle, action: #selector(createFile(_:)), keyEquivalent: "")
            typeItem.tag = type.menuTag
            typeItem.target = self
            submenu.addItem(typeItem)
        }
        item.submenu = submenu
        menu.addItem(item)
        return menu
    }

    @objc private func createFile(_ sender: NSMenuItem) {
        // Finder guarantees that targetedURL is available inside menu actions.
        // Read it again here rather than using a mutable, last-observed folder.
        guard let directory = FIFinderSyncController.default().targetedURL(),
              let fileType = NewFileType(menuTag: sender.tag),
              let authorization = try? CreateRequest.loadAuthorization(),
              let request = try? CreateRequest(directory: directory, fileType: fileType,
                                               authorization: authorization) else { return }
        let host = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard host.pathExtension == "app" else {
            logger.error("Containing application could not be located")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        // Choose our containing application explicitly instead of trusting an
        // arbitrary application registered for the custom URL scheme.
        NSWorkspace.shared.open([request.url], withApplicationAt: host, configuration: configuration) { [logger] _, error in
            if let error {
                logger.error("Could not open new-file helper; error code \((error as NSError).code)")
            }
        }
    }
}
