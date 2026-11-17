import Foundation
import SwiftUI

/// A folder to scan. `path` may start with ~ and contain * segments (e.g. Chrome profiles).
struct JunkRoot: Sendable {
    var path: String
    var pattern = "*"              // fnmatch pattern for file names
    var recurse = true
    var label: String? = nil       // drill-down group name; nil = one group per top-level subfolder
    var skip: Set<String> = []     // top-level subfolder names owned by another category
}

/// One line in a category's drill-down list: files that are kept or cleaned together.
@Observable
final class JunkGroup: Identifiable {
    let id = UUID()
    let name: String
    let location: String
    let bytes: Int64
    let files: Int
    let found: [String]
    var isChecked = true

    init(_ r: ScanGroup) {
        name = r.name; location = r.location; bytes = r.bytes; files = r.files; found = r.found
    }
}

struct ScanGroup: Sendable {
    var name: String
    var location: String
    var bytes: Int64 = 0
    var files = 0
    var found: [String] = []
}

struct ScanResult: Sendable {
    var groups: [ScanGroup] = []
    var pruneDirs: [String] = []
    var blocked = false            // some location exists but macOS privacy protection refused to list it
}

@Observable
final class JunkCategory: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let symbol: String
    let color: Color
    var ageGuard = false           // skip files modified in the last 24 hours (they may be in use)
    let roots: [JunkRoot]

    private(set) var groups: [JunkGroup] = []
    private(set) var bytes: Int64 = 0
    private(set) var files = 0
    private(set) var scanned = false
    private(set) var blocked = false
    private var pruneDirs: [String] = []
    private var checkedWhenEmpty: Bool
    var isExpanded = false

    init(_ name: String, _ detail: String, symbol: String, color: Color, ageGuard: Bool = false, checked: Bool = true, roots: [JunkRoot]) {
        self.name = name; self.detail = detail; self.symbol = symbol; self.color = color
        self.ageGuard = ageGuard; self.roots = roots; self.checkedWhenEmpty = checked
    }

    /// true = everything, false = nothing, nil = some of the drill-down groups.
    var isChecked: Bool? {
        get {
            if groups.isEmpty { return checkedWhenEmpty }
            let n = groups.filter(\.isChecked).count
            return n == 0 ? false : n == groups.count ? true : nil
        }
        set {
            checkedWhenEmpty = newValue == true
            for g in groups { g.isChecked = checkedWhenEmpty }
        }
    }

    var selectedBytes: Int64 { groups.filter(\.isChecked).reduce(0) { $0 + $1.bytes } }
    var sizeText: String { scanned ? Util.size(bytes) : "—" }
    var detailText: String {
        !scanned ? "Not scanned" : files == 0 ? (blocked ? "Needs Full Disk Access" : "Nothing to clean")
            : files == 1 ? "1 item" : "\(files.formatted()) items"
    }

    private var cutoff: Date {
        ageGuard && AppSettings.shared.keepRecentTemp ? Date().addingTimeInterval(-24 * 3600) : .distantFuture
    }

    @MainActor
    func scan() async {
        // Remember what was deselected so a rescan doesn't silently re-tick it.
        let wasOff = isChecked == false
        let off = Set(groups.filter { !$0.isChecked }.map(\.name))
        let roots = roots, cutoff = cutoff
        let r = await Task.detached(priority: .userInitiated) { JunkScanner.scan(roots, cutoff: cutoff) }.value
        groups = r.groups.map(JunkGroup.init)
        for g in groups where wasOff || off.contains(g.name) { g.isChecked = false }
        bytes = r.groups.reduce(0) { $0 + $1.bytes }
        files = r.groups.reduce(0) { $0 + $1.files }
        pruneDirs = r.pruneDirs
        blocked = r.blocked
        scanned = true
    }

    /// Deletes the selected results of the last scan. Returns the bytes actually freed.
    @MainActor
    func clean() async -> Int64 {
        let paths = groups.filter(\.isChecked).flatMap(\.found)
        let prune = pruneDirs, cutoff = cutoff
        return await Task.detached(priority: .userInitiated) { JunkScanner.delete(paths, prune: prune, cutoff: cutoff) }.value
    }
}

enum JunkScanner {
    static let maxGroups = 40
    static let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                         .contentModificationDateKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]

    static func scan(_ roots: [JunkRoot], cutoff: Date) -> ScanResult {
        var result = ScanResult()
        var byName: [String: ScanGroup] = [:]
        var order: [String] = []
        func add(_ name: String, _ location: String, _ body: (inout ScanGroup) -> Void) {
            if byName[name] == nil { byName[name] = ScanGroup(name: name, location: location); order.append(name) }
            body(&byName[name]!)
        }

        let fm = FileManager.default
        for r in roots {
            for dir in expand(r.path) {
                let items: [String]
                do { items = try fm.contentsOfDirectory(atPath: dir) }
                catch { if (error as NSError).code == NSFileReadNoPermissionError { result.blocked = true }; continue }
                if r.recurse { result.pruneDirs.append(dir) }
                for item in items where !r.skip.contains(item) {
                    let url = URL(fileURLWithPath: dir).appendingPathComponent(item)
                    guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else { continue }
                    if v.isDirectory == true {
                        guard r.recurse else { continue }
                        let name = r.label ?? item
                        add(name, r.label != nil ? dir : url.path) { collect(url, r, cutoff, &$0) }
                    } else if v.isRegularFile == true, matches(item, r.pattern) {
                        add(r.label ?? "Loose files", dir) { take(url, v, cutoff, &$0) }
                    }
                }
            }
        }

        var groups = order.compactMap { byName[$0] }.filter { $0.files > 0 }.sorted { $0.bytes > $1.bytes }
        if groups.count > maxGroups {
            var rest = ScanGroup(name: "Everything else (\(groups.count - maxGroups + 1) more folders)", location: "")
            for g in groups.dropFirst(maxGroups - 1) { rest.bytes += g.bytes; rest.files += g.files; rest.found += g.found }
            groups = Array(groups.prefix(maxGroups - 1)) + [rest]
        }
        result.groups = groups
        return result
    }

    private static func collect(_ dir: URL, _ r: JunkRoot, _ cutoff: Date, _ g: inout ScanGroup) {
        // The enumerator never descends into symbolic links.
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return }
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, matches(url.lastPathComponent, r.pattern)
            else { continue }
            take(url, v, cutoff, &g)
        }
    }

    private static func take(_ url: URL, _ v: URLResourceValues, _ cutoff: Date, _ g: inout ScanGroup) {
        if let m = v.contentModificationDate, m > cutoff { return }
        g.bytes += Util.allocatedSize(v)
        g.files += 1
        g.found.append(url.path)
    }

    static func delete(_ paths: [String], prune: [String], cutoff: Date) -> Int64 {
        var freed: Int64 = 0
        var emptied = Set<String>()     // folders this clean deleted from, and their parents
        let fm = FileManager.default
        for p in paths {
            let url = URL(fileURLWithPath: p)
            // Re-apply the age guard now: a file may have been written to since the scan.
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            if let m = v.contentModificationDate, m > cutoff { continue }
            do { try fm.removeItem(at: url); freed += Util.allocatedSize(v) } catch { continue /* in use or protected: leave it */ }
            var dir = (p as NSString).deletingLastPathComponent
            while dir.count > 1, emptied.insert(dir).inserted { dir = (dir as NSString).deletingLastPathComponent }
        }
        for d in prune { pruneEmpty(d, cutoff, emptied) }
        return freed
    }

    /// Removes empty folders below `root` (never `root` itself). A folder is removed when this clean emptied it,
    /// or when it is older than the cutoff. Deleting a file updates its folder's modification date, so the date
    /// alone would keep every folder we just emptied; an empty folder an app made recently is still left alone.
    private static func pruneEmpty(_ root: String, _ cutoff: Date, _ emptied: Set<String>) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: root) else { return }
        for item in items {
            let url = URL(fileURLWithPath: root).appendingPathComponent(item)
            guard let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey]),
                  v.isDirectory == true, v.isSymbolicLink != true else { continue }
            pruneEmpty(url.path, cutoff, emptied)
            if emptied.contains(url.path) || (v.contentModificationDate ?? .distantPast) <= cutoff,
               let rest = try? fm.contentsOfDirectory(atPath: url.path), rest.allSatisfy({ $0 == ".DS_Store" }) {
                try? fm.removeItem(at: url)
            }
        }
    }

    static func matches(_ name: String, _ pattern: String) -> Bool {
        pattern == "*" || fnmatch(pattern, name, 0) == 0
    }

    /// Expands ~ and * directory segments into the folders that exist.
    static func expand(_ pattern: String) -> [String] {
        let full = Util.expand(pattern)
        var cur = ["/"]
        for part in full.split(separator: "/").map(String.init) {
            var next: [String] = []
            for d in cur {
                if part.contains("*") {
                    let kids = (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []
                    for k in kids where fnmatch(part, k, 0) == 0 {
                        let p = (d as NSString).appendingPathComponent(k)
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue { next.append(p) }
                    }
                } else {
                    let p = (d as NSString).appendingPathComponent(part)
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue { next.append(p) }
                }
            }
            cur = next
        }
        return cur
    }
}

enum JunkCatalog {
    static func create() -> [JunkCategory] {
        // Chromium browsers keep their HTTP cache under ~/Library/Caches and the rest under Application Support.
        var browserRoots = [
            JunkRoot(path: "~/Library/Caches/com.apple.Safari", label: "Safari"),
            JunkRoot(path: "~/Library/Caches/Firefox/Profiles/*/cache2", label: "Firefox"),
        ]
        for (dir, name) in [("Google/Chrome", "Google Chrome"), ("Microsoft Edge", "Microsoft Edge"), ("BraveSoftware/Brave-Browser", "Brave"), ("Arc/User Data", "Arc")] {
            browserRoots.append(JunkRoot(path: "~/Library/Caches/\(dir)", label: name))
            for c in ["Code Cache", "GPUCache", "Service Worker/CacheStorage", "DawnGraphiteCache", "DawnWebGPUCache"] {
                browserRoots.append(JunkRoot(path: "~/Library/Application Support/\(dir)/*/\(c)", label: name))
            }
        }

        let devRoots = [
            JunkRoot(path: "~/Library/Developer/Xcode/DerivedData", label: "Xcode DerivedData"),
            JunkRoot(path: "~/Library/Developer/Xcode/iOS DeviceSupport", label: "iOS device support files"),
            JunkRoot(path: "~/Library/Developer/Xcode/watchOS DeviceSupport", label: "watchOS device support files"),
            JunkRoot(path: "~/Library/Developer/CoreSimulator/Caches", label: "Simulator caches"),
            JunkRoot(path: "~/Library/Caches/Homebrew", label: "Homebrew downloads"),
            JunkRoot(path: "~/Library/Caches/pip", label: "pip"),
            JunkRoot(path: "~/Library/Caches/Yarn", label: "Yarn"),
            JunkRoot(path: "~/.npm/_cacache", label: "npm"),
        ]

        // Folders in ~/Library/Caches that another category handles, or that are not safe to empty.
        let cacheSkip: Set<String> = [
            "com.apple.Safari", "Google", "Microsoft Edge", "BraveSoftware", "Arc", "Firefox",
            "Homebrew", "pip", "Yarn",
            "CloudKit", "com.apple.bird", "com.apple.akd", "FamilyCircle", "com.apple.HomeKit",
            "com.apple.ap.adprivacyd", "com.apple.containermanagerd",
            Bundle.main.bundleIdentifier ?? "com.puresweep.mac",
        ]

        return [
            JunkCategory("User caches", "Data apps keep to load faster. They rebuild what they need. Quit apps first for the best result.",
                         symbol: "archivebox", color: .orange, ageGuard: true,
                         roots: [JunkRoot(path: "~/Library/Caches", skip: cacheSkip)]),
            JunkCategory("Temporary files", "Leftovers apps wrote to your temporary folder.",
                         symbol: "clock.arrow.circlepath", color: .blue, ageGuard: true,
                         roots: [JunkRoot(path: NSTemporaryDirectory())]),
            JunkCategory("Browser caches", "Cached pages, scripts and images from Safari, Chrome, Edge, Brave, Arc and Firefox. History, cookies and logins are not touched.",
                         symbol: "globe", color: .green, roots: browserRoots),
            JunkCategory("App logs", "Log files apps keep in your Library folder.",
                         symbol: "doc.text", color: .gray, ageGuard: true,
                         roots: [JunkRoot(path: "~/Library/Logs", skip: ["DiagnosticReports"])]),
            JunkCategory("Crash reports", "Reports from apps that crashed or hung.",
                         symbol: "exclamationmark.triangle", color: .red,
                         roots: [JunkRoot(path: "~/Library/Logs/DiagnosticReports", label: "Crash and hang reports")]),
            JunkCategory("Developer caches", "Xcode build data, device support files, simulator caches and package-manager downloads. Tools re-create them when needed.",
                         symbol: "hammer", color: .purple, roots: devRoots),
            JunkCategory("Trash", "Files you have already moved to the Trash.",
                         symbol: "trash", color: .pink, checked: false,   // off by default: it is the safety net for deleted files
                         roots: [JunkRoot(path: "~/.Trash")]),
        ]
    }
}
