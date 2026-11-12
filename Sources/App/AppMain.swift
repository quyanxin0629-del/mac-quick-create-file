import AppKit
import FinderSync

@main
struct FinderNewFileApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didFinishLaunching = false
    private var receivedRequest = false
    private var isHandling = false
    private var pending: [Result<CreateRequest, Error>] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        DispatchQueue.main.async { [self] in
            if receivedRequest { handlePendingRequests() }
        }
        // URL events may arrive immediately after the launch notification.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            if !receivedRequest { showSetup() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedRequest = true
        pending.append(contentsOf: urls.map { url in
            Result { try CreateRequest(url: url, expectedAuthorization: CreateRequest.loadAuthorization()) }
        })
        handlePendingRequests()
    }

    private func handlePendingRequests() {
        guard didFinishLaunching, !isHandling else { return }
        guard !pending.isEmpty else {
            DispatchQueue.main.async { [self] in
                if !isHandling && pending.isEmpty { NSApp.terminate(nil) }
            }
            return
        }
        isHandling = true
        switch pending.removeFirst() {
        case .success(let request): createFile(for: request)
        case .failure(let error):
            showError(error)
            isHandling = false
            handlePendingRequests()
        }
    }

    private func createFile(for request: CreateRequest) {
        let preferences = UserDefaults.standard
        let legacyBaseName = preferences.string(forKey: "DefaultFileName")
            .map { ($0 as NSString).deletingPathExtension }
        let baseName = preferences.string(forKey: "DefaultBaseName") ?? legacyBaseName ?? "未命名"
        var name = request.fileType.fileName(baseName: baseName)
        if (try? FileCreator.validateName(name)) == nil { name = request.fileType.fileName() }
        let requestedName = name
        // Folder authorization or a slow volume must not block AppKit's launch
        // and event loop. Keep requests serialized until each IO finishes.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result { try FileCreator().create(in: request.directory, named: requestedName) }
            DispatchQueue.main.async { [self] in
                switch result {
                case .success(let createdFile): NSWorkspace.shared.activateFileViewerSelecting([createdFile])
                case .failure(let error): showError(error)
                }
                isHandling = false
                handlePendingRequests()
            }
        }
    }

    private func showSetup() {
        let alert = NSAlert()
        alert.messageText = "初页"
        let enabled = FIFinderSyncController.isExtensionEnabled
        alert.informativeText = enabled
            ? "扩展已启用。在本地文件夹空白处右键，将鼠标移到“新建文件”，点击 TXT 或 Markdown 即可直接创建。"
            : "请在系统设置中启用“初页”扩展，然后在本地文件夹空白处右键，从“新建文件”子菜单选择 TXT 或 Markdown。"
        alert.addButton(withTitle: enabled ? "完成" : "打开扩展设置")
        alert.addButton(withTitle: "关闭")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn && !enabled {
            FIFinderSyncController.showExtensionManagementInterface()
        }
        NSApp.terminate(nil)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "未能新建文件"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        NSApp.activate()
        alert.runModal()
    }

}
