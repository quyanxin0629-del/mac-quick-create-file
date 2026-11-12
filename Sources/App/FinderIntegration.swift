import AppKit
import FinderSync
import CryptoKit

/// Registration and enablement are not a Finder reload acknowledgement.
/// Refresh only during setup/repair, and never force-quit a busy Finder.
struct FinderIntegration: Sendable {
    private let extensionURL: URL
    private let extensionIdentifier: String

    static func generation(in bundle: Bundle = .main) throws -> String {
        let authorization = try CreateRequest.loadAuthorization(in: bundle)
        let digest = SHA256.hash(data: Data(authorization.utf8)).map { String(format: "%02x", $0) }.joined()
        return digest
    }

    init(bundle: Bundle = .main) throws {
        let applicationURL = bundle.bundleURL.standardizedFileURL
        let applicationsDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        guard applicationsDirectories.contains(applicationURL.deletingLastPathComponent()),
              let applicationIdentifier = bundle.bundleIdentifier,
              let plugins = bundle.builtInPlugInsURL,
              let extensionBundle = Bundle(url: plugins.appendingPathComponent("FinderNewFileExtension.appex")),
              extensionBundle.bundleIdentifier == applicationIdentifier + ".extension" else {
            throw IntegrationError.installationLocation
        }
        extensionURL = extensionBundle.bundleURL
        extensionIdentifier = applicationIdentifier + ".extension"
    }

    @MainActor
    func refresh() async throws {
        let extensionURL = self.extensionURL
        let identifier = extensionIdentifier
        try await Task.detached(priority: .userInitiated) {
            try Self.runPluginKit(["-a", extensionURL.path])
            try Self.runPluginKit(["-e", "use", "-i", identifier])
        }.value

        // Give the settings notification a chance to reach the app's run loop.
        let enableDeadline = Date().addingTimeInterval(5)
        while !FIFinderSyncController.isExtensionEnabled {
            guard Date() < enableDeadline else { throw IntegrationError.notEnabled }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let workspace = NSWorkspace.shared
        let previous = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        guard let finderURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.finder") else {
            throw IntegrationError.finderUnavailable
        }
        for finder in previous where !finder.isTerminated {
            guard finder.terminate() || finder.isTerminated else { throw IntegrationError.finderBusy }
        }
        let quitDeadline = Date().addingTimeInterval(10)
        while previous.contains(where: { !$0.isTerminated }) {
            guard Date() < quitDeadline else { throw IntegrationError.finderBusy }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        let newProcessIdentifier: pid_t = try await withCheckedThrowingContinuation { continuation in
            workspace.openApplication(at: finderURL, configuration: configuration) { application, error in
                if let application {
                    continuation.resume(returning: application.processIdentifier)
                } else {
                    continuation.resume(throwing: error ?? IntegrationError.finderUnavailable)
                }
            }
        }
        guard !previous.contains(where: { $0.processIdentifier == newProcessIdentifier }) else {
            throw IntegrationError.finderBusy
        }
        // Record only an acknowledged restart; an enablement flag alone is insufficient.
        UserDefaults.standard.set(try Self.generation(), forKey: "LastFinderRefreshGeneration")
    }

    private static func runPluginKit(_ arguments: [String]) throws {
        let process = Process()
        let completion = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in completion.signal() }
        try process.run()
        guard completion.wait(timeout: .now() + 10) == .success else {
            process.terminate()
            throw IntegrationError.registrationTimedOut
        }
        guard process.terminationStatus == 0 else { throw IntegrationError.registrationFailed }
    }

    enum IntegrationError: LocalizedError {
        case installationLocation, registrationFailed, registrationTimedOut
        case notEnabled, finderBusy, finderUnavailable

        var errorDescription: String? {
            switch self {
            case .installationLocation:
                return "请先将“初页.app”移入“应用程序”文件夹，再从那里打开并完成安装。"
            case .registrationFailed:
                return "Finder 扩展未能完成登记，请重新安装“初页”后重试。"
            case .registrationTimedOut:
                return "系统暂未完成扩展登记，请稍后重试。"
            case .notEnabled:
                return "系统尚未启用扩展。请到系统设置启用“初页”，再打开 App 点击“修复右键菜单”。"
            case .finderBusy:
                return "访达尚未退出，可能仍有文件操作或确认窗口。请完成操作后重试，或按 Command+Option+Esc 选择“访达”并重新启动。"
            case .finderUnavailable:
                return "暂时无法重新打开访达，请手动打开访达后重试。"
            }
        }
    }
}
