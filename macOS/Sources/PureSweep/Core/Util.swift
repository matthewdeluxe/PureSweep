import AppKit
import Foundation

enum Util {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Expands a leading ~ to the home folder.
    static func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

    /// Replaces the home folder with ~ for display.
    static func pretty(_ path: String) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static func ago(_ date: Date) -> String {
        let t = Date().timeIntervalSince(date)
        if t < 120 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// Bytes actually used on disk (allocated size), falling back to the logical size.
    static func allocatedSize(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    /// Total allocated size of a file or folder. Never follows symbolic links.
    static func treeSize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        var total: Int64 = 0
        if let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { return allocatedSize(v) }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return 0 }
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { total += allocatedSize(v) }
        }
        return total
    }

    /// Runs a command and returns (exit status, stdout + stderr).
    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Runs a shell command with administrator rights. macOS shows its own password prompt.
    /// Returns nil on success, otherwise an error message ("User canceled." when the prompt was dismissed).
    static func runAsAdmin(_ command: String) -> String? {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let r = run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
        return r.status == 0 ? nil : r.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Quotes a value for /bin/sh.
    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func reveal(_ paths: [String]) {
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
    }

    // MARK: Privacy

    /// True when the app can read a TCC-protected location (the Trash and Safari's data need Full Disk Access).
    static var hasFullDiskAccess: Bool {
        for p in ["~/Library/Safari", "~/.Trash"] {
            let path = expand(p)
            if FileManager.default.fileExists(atPath: path) {
                return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
            }
        }
        return true
    }

    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    static func openLoginItemsSettings() {
        open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    static func openFileVaultSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?FileVault")
    }

    static func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}

/// Settings and cleaning history, kept in UserDefaults (~/Library/Preferences/<bundle id>.plist).
@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    /// 0 = follow macOS, 1 = light, 2 = dark
    var theme: Int { didSet { d.set(theme, forKey: "theme"); apply() } }
    var keepRecentTemp: Bool { didSet { d.set(keepRecentTemp, forKey: "keepRecentTemp") } }
    var showMenuBarExtra: Bool { didSet { d.set(showMenuBarExtra, forKey: "showMenuBarExtra") } }
    var lastClean: Date? { didSet { d.set(lastClean, forKey: "lastClean") } }
    var lastFreed: Int64 { didSet { d.set(lastFreed, forKey: "lastFreed") } }
    var totalFreed: Int64 { didSet { d.set(totalFreed, forKey: "totalFreed") } }

    private init() {
        d.register(defaults: ["keepRecentTemp": true, "showMenuBarExtra": true])
        theme = d.integer(forKey: "theme")
        keepRecentTemp = d.bool(forKey: "keepRecentTemp")
        showMenuBarExtra = d.bool(forKey: "showMenuBarExtra")
        lastClean = d.object(forKey: "lastClean") as? Date
        lastFreed = Int64(d.integer(forKey: "lastFreed"))
        totalFreed = Int64(d.integer(forKey: "totalFreed"))
    }

    func apply() {
        NSApp?.appearance = theme == 1 ? NSAppearance(named: .aqua) : theme == 2 ? NSAppearance(named: .darkAqua) : nil
    }

    func recordClean(freed: Int64) {
        lastClean = Date()
        lastFreed = freed
        totalFreed += freed
    }
}
