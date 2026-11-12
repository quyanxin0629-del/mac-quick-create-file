import Darwin
import Foundation

enum FileCreationError: LocalizedError {
    case invalidName(String)
    case invalidDirectory
    case system(Int32)
    case tooManyDuplicates

    var errorDescription: String? {
        switch self {
        case .invalidName(let explanation): return explanation
        case .invalidDirectory: return "请选择一个真实的文件夹。"
        case .system(let code):
            switch code {
            case EACCES, EPERM: return "没有此文件夹的写入权限。请检查 macOS 的文件夹访问授权。"
            case EROFS: return "此位置为只读，无法创建文件。"
            case ENOSPC, EDQUOT: return "磁盘空间或配额不足，无法创建文件。"
            case ENOENT, ENOTDIR: return "目标文件夹已移动、已删除或不是文件夹。"
            case ENAMETOOLONG: return "文件名过长，请缩短后重试。"
            default: return "无法创建文件：\(String(cString: strerror(code)))（\(code)）。"
            }
        case .tooManyDuplicates: return "同名文件过多，请使用其他文件名。"
        }
    }
}

/// Creates empty files with the operating system's exclusive-create operation.
/// Neither an existing file nor a symbolic link is ever opened for writing.
struct FileCreator: Sendable {
    static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != ".." else {
            throw FileCreationError.invalidName("请输入有效的文件名。")
        }
        guard !name.contains("/"), !name.contains(":"),
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw FileCreationError.invalidName("文件名不能包含 /、:、换行或控制字符。请输入名称，不要输入路径。")
        }
        guard name.utf8.count <= 255 else {
            throw FileCreationError.invalidName("文件名过长，请缩短后重试。")
        }
    }

    func create(in directory: URL, named name: String) throws -> URL {
        try Self.validateName(name)
        guard directory.isFileURL, directory.path.hasPrefix("/"),
              !directory.path.contains("\0") else {
            throw FileCreationError.invalidDirectory
        }
        let directoryFD = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            // A directory is only an anchor for openat, not a source of data.
            // O_EVTONLY avoids requesting access to read its existing contents.
            return Darwin.open(path, O_EVTONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard directoryFD >= 0 else { throw FileCreationError.system(errno) }
        defer { Darwin.close(directoryFD) }

        let extensionPart = (name as NSString).pathExtension
        let stem = extensionPart.isEmpty ? name : (name as NSString).deletingPathExtension
        let suffix = extensionPart.isEmpty ? "" : ".\(extensionPart)"

        for index in 0..<10_000 {
            let candidate = index == 0 ? name : "\(stem) \(index)\(suffix)"
            guard candidate.utf8.count <= 255 else {
                throw FileCreationError.invalidName("重名编号后文件名过长，请缩短文件名。")
            }
            let descriptor = candidate.withCString { filename in
                Darwin.openat(directoryFD, filename,
                              O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                              mode_t(0o666))
            }
            if descriptor >= 0 {
                Darwin.close(descriptor)
                return directory.appendingPathComponent(candidate, isDirectory: false)
            }
            let code = errno
            if code == EEXIST { continue }
            throw FileCreationError.system(code)
        }
        throw FileCreationError.tooManyDuplicates
    }
}
