import Foundation

/// Add a case and its menu metadata here to support another empty file type.
enum NewFileType: String, CaseIterable, Sendable {
    case text = "txt"
    case markdown = "md"

    var menuTitle: String {
        switch self {
        case .text: return "TXT 文本文件 (.txt)"
        case .markdown: return "Markdown (.md)"
        }
    }

    // Finder preserves item tags when forwarding submenu actions.
    var menuTag: Int {
        switch self {
        case .text: return 1
        case .markdown: return 2
        }
    }

    init?(menuTag: Int) {
        guard let type = Self.allCases.first(where: { $0.menuTag == menuTag }) else { return nil }
        self = type
    }

    func fileName(baseName: String = "未命名") -> String {
        "\(baseName).\(rawValue)"
    }
}
