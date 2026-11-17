import Foundation

@Observable
final class LargeFile: Identifiable {
    var id: String { path }
    let path: String
    let size: Int64
    let lastOpened: Date?
    var isChecked = false
    init(path: String, size: Int64, lastOpened: Date?) { self.path = path; self.size = size; self.lastOpened = lastOpened }
    var name: String { (path as NSString).lastPathComponent }
    var folder: String { Util.pretty((path as NSString).deletingLastPathComponent) }
}

enum LargeFileFinder {
    static let limit = 500

    /// Finds the largest files in the home folder at or above `minBytes`.
    /// Skips ~/Library, hidden files and the inside of app bundles and other packages (a package counts as one item).
    static func scan(minBytes: Int64, stop: @escaping @Sendable () -> Bool) -> [(String, Int64, Date?)] {
        let home = URL(fileURLWithPath: Util.home)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .totalFileAllocatedSizeKey,
                                      .fileAllocatedSizeKey, .fileSizeKey, .contentAccessDateKey]
        var found: [(String, Int64, Date?)] = []
        guard let e = FileManager.default.enumerator(at: home, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        else { return [] }
        let library = home.appendingPathComponent("Library").path
        for case let url as URL in e {
            if stop() { break }
            if url.path == library { e.skipDescendants(); continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isPackage == true {
                e.skipDescendants()
                let size = Util.treeSize(url)
                if size >= minBytes { found.append((url.path, size, v.contentAccessDate)) }
            } else if v.isRegularFile == true {
                let size = Util.allocatedSize(v)
                if size >= minBytes { found.append((url.path, size, v.contentAccessDate)) }
            }
        }
        return Array(found.sorted { $0.1 > $1.1 }.prefix(limit))
    }
}
