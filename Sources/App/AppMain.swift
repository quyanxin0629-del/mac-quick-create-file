import AppKit
import FinderSync
import Darwin

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
    private let repairOnly = CommandLine.arguments.contains("--refresh-finder")
    private var didFinishLaunching = false
    private var receivedRequest = false
    private var isHandling = false
    private var isRepairingIntegration = false
    private var repairProgress: NSAlert?
    private var repairResultAlert: NSAlert?
    private var pending: [Result<CreateRequest, Error>] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        if repairOnly {
            repairIntegration(commandLine: true)
            return
        }
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
        guard didFinishLaunching, !isHandling, !isRepairingIntegration else { return }
        guard !pending.isEmpty else {
            DispatchQueue.main.async { [self] in
                if !isHandling && !isRepairingIntegration && pending.isEmpty { NSApp.terminate(nil) }
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
        let generation = try? FinderIntegration.generation()
        let needsRefresh = !enabled || generation == nil || UserDefaults.standard.string(forKey: "LastFinderRefreshGeneration") != generation
        alert.informativeText = needsRefresh
            ? "安装或更新后，需要让访达重新加载“初页”扩展。请先等待文件复制、移动操作完成，再点击“完成安装并刷新菜单”。"
            : "在本地文件夹空白处右键，从“新建文件”选择 TXT 或 Markdown。如果菜单缺失，可点击“修复右键菜单”重新加载扩展和访达。修复前请等待文件复制、移动操作完成。"
        alert.addButton(withTitle: needsRefresh ? "完成安装并刷新菜单" : "完成")
        alert.addButton(withTitle: needsRefresh ? "打开扩展设置" : "修复右键菜单")
        alert.addButton(withTitle: needsRefresh ? "稍后" : "打开扩展设置")
        NSApp.activate()
        let response = alert.runModal()
        if (needsRefresh && response == .alertFirstButtonReturn) || (!needsRefresh && response == .alertSecondButtonReturn) {
            repairIntegration(commandLine: false)
            return
        }
        if (needsRefresh && response == .alertSecondButtonReturn) || (!needsRefresh && response == .alertThirdButtonReturn) {
            FIFinderSyncController.showExtensionManagementInterface()
        }
        handlePendingRequests()
    }

    private func repairIntegration(commandLine: Bool) {
        guard !isRepairingIntegration, !isHandling else { return }
        isRepairingIntegration = true
        if !commandLine {
            let progress = NSAlert()
            progress.messageText = "正在重新加载右键菜单"
            progress.informativeText = "正在登记扩展并重新启动访达，请稍候。"
            progress.addButton(withTitle: "正在处理…").isEnabled = false
            progress.layout()
            progress.window.center()
            progress.window.makeKeyAndOrderFront(nil)
            repairProgress = progress
        }
        Task { @MainActor [self] in
            let result: Result<Void, Error>
            do {
                try await FinderIntegration().refresh()
                result = .success(())
            } catch {
                result = .failure(error)
            }
            repairProgress?.window.orderOut(nil)
            repairProgress = nil
            isRepairingIntegration = false
            if commandLine {
                let text: String
                let status: Int32
                switch result {
                case .success: text = "扩展已重新登记并启用，访达已重新启动。\n"; status = 0
                case .failure(let error): text = "访达刷新未完成：\(error.localizedDescription)\n"; status = 1
                }
                FileHandle.standardError.write(Data(text.utf8))
                Darwin.exit(status)
            }
            // Present outside the async operation and keep the result window
            // alive explicitly; a nested modal loop must not dismiss it early.
            DispatchQueue.main.async { [self] in showRepairResult(result) }
        }
    }

    private func showRepairResult(_ result: Result<Void, Error>) {
        let alert = NSAlert()
        switch result {
        case .success:
            alert.messageText = "访达已重新加载"
            alert.informativeText = "扩展已重新登记并启用，访达已重新启动。请在本地文件夹空白处右键，从“新建文件”选择 TXT 或 Markdown 验证。"
        case .failure(let error):
            alert.alertStyle = .warning
            alert.messageText = "菜单刷新尚未完成"
            alert.informativeText = error.localizedDescription
        }
        let done = alert.addButton(withTitle: "好")
        done.target = self
        done.action = #selector(closeRepairResult(_:))
        let settings = alert.addButton(withTitle: "打开扩展设置")
        settings.target = self
        settings.action = #selector(openSettingsAfterRepair(_:))
        alert.layout()
        repairResultAlert = alert
        NSApp.activate()
        alert.window.center()
        alert.window.makeKeyAndOrderFront(nil)
    }

    @objc private func closeRepairResult(_ sender: Any?) {
        repairResultAlert?.window.orderOut(nil)
        repairResultAlert = nil
        handlePendingRequests()
    }

    @objc private func openSettingsAfterRepair(_ sender: Any?) {
        FIFinderSyncController.showExtensionManagementInterface()
        closeRepairResult(sender)
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
