import Foundation

struct CreateRequest: Equatable, Sendable {
    static let scheme = "chuye-create-file"
    let directory: URL
    let fileType: NewFileType
    let authorization: String

    init(directory: URL, fileType: NewFileType, authorization: String) throws {
        guard directory.isFileURL, directory.path.hasPrefix("/"),
              !directory.path.contains("\0"), Self.validAuthorization(authorization) else {
            throw RequestError.invalid
        }
        self.directory = directory.standardizedFileURL
        self.fileType = fileType
        self.authorization = authorization
    }

    init(url: URL, expectedAuthorization: String) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme, components.host == "create",
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil, components.path.isEmpty,
              let items = components.queryItems, items.count == 3,
              Set(items.map(\.name)) == Set(["directory", "type", "authorization"]),
              let path = items.first(where: { $0.name == "directory" })?.value,
              let rawType = items.first(where: { $0.name == "type" })?.value,
              let fileType = NewFileType(rawValue: rawType),
              let authorization = items.first(where: { $0.name == "authorization" })?.value,
              Self.validAuthorization(expectedAuthorization), authorization == expectedAuthorization,
              path.hasPrefix("/"), !path.contains("\0") else {
            throw RequestError.invalid
        }
        try self.init(directory: URL(fileURLWithPath: path, isDirectory: true),
                      fileType: fileType, authorization: authorization)
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "create"
        components.queryItems = [
            URLQueryItem(name: "directory", value: directory.path),
            URLQueryItem(name: "type", value: fileType.rawValue),
            URLQueryItem(name: "authorization", value: authorization)
        ]
        // The fixed scheme/host and URLQueryItem encoding always form a valid URL.
        return components.url!
    }

    /// Each build gives the containing app and extension the same random
    /// capability. External custom-scheme links cannot create files without it.
    static func loadAuthorization(in bundle: Bundle = .main) throws -> String {
        guard let resource = bundle.url(forResource: "CreateRequestToken", withExtension: nil),
              let contents = try? String(contentsOf: resource, encoding: .utf8) else {
            throw RequestError.missingComponent
        }
        let token = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validAuthorization(token) else { throw RequestError.missingComponent }
        return token
    }

    private static func validAuthorization(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    enum RequestError: LocalizedError {
        case invalid
        case missingComponent
        var errorDescription: String? {
            switch self {
            case .invalid: return "新建文件请求无效，请从 Finder 右键菜单重新操作。"
            case .missingComponent: return "新建文件组件不完整，请重新构建并安装。"
            }
        }
    }
}
