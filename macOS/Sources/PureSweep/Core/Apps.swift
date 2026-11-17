import AppKit
import Foundation

/// An app bundle in /Applications or ~/Applications.
@Observable
final class InstalledApp: Identifiable {
    let id: String               // bundle path
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let isAppStore: Bool
    var size: Int64? = nil       // filled in the background

    init(url: URL, name: String, bundleID: String, version: String, isAppStore: Bool) {
        id = url.path; self.url = url; self.name = name; self.bundleID = bundleID; self.version = version; self.isAppStore = isAppStore
    }

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    static func load() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        let ownID = Bundle.main.bundleIdentifier
        for root in ["/Applications", Util.expand("~/Applications")] {
            for url in bundles(in: URL(fileURLWithPath: root), depth: 2) {
                guard let b = Bundle(url: url), let id = b.bundleIdentifier,
                      !id.hasPrefix("com.apple."), id != ownID, seen.insert(url.path).inserted else { continue }
                let info = b.infoDictionary ?? [:]
                apps.append(InstalledApp(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    bundleID: id,
                    version: (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String) ?? "",
                    isAppStore: FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path)))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// .app bundles directly inside `dir`, and one folder level down (e.g. /Applications/Utilities, vendor folders).
    private static func bundles(in dir: URL, depth: Int) -> [URL] {
        guard depth > 0, let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        else { return [] }
        var out: [URL] = []
        for u in items {
            if u.pathExtension == "app" { out.append(u) }
            else if (try? u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))
                .map({ $0.isDirectory == true && $0.isSymbolicLink != true }) == true {
                out += bundles(in: u, depth: depth - 1)
            }
        }
        return out
    }

    /// Support files the app left in ~/Library. Matched only by exact bundle identifier or exact app name.
    func leftovers() -> [Leftover] {
        let lib = Util.expand("~/Library")
        let fm = FileManager.default
        var out: [Leftover] = []
        var seen = Set<String>()
        func add(_ rel: String, _ kind: String) {
            let p = (lib as NSString).appendingPathComponent(rel)
            guard fm.fileExists(atPath: p), seen.insert(p).inserted else { return }
            out.append(Leftover(path: p, kind: kind, size: Util.treeSize(URL(fileURLWithPath: p))))
        }
        for key in [bundleID, name] where !key.isEmpty {
            add("Application Support/\(key)", "App data")
            add("Caches/\(key)", "Cache")
            add("Logs/\(key)", "Logs")
        }
        add("Preferences/\(bundleID).plist", "Preferences")
        add("Saved Application State/\(bundleID).savedState", "Window state")
        add("HTTPStorages/\(bundleID)", "Web data")
        add("HTTPStorages/\(bundleID).binarycookies", "Cookies")
        add("WebKit/\(bundleID)", "Web data")
        add("Containers/\(bundleID)", "Sandbox container")
        add("Application Scripts/\(bundleID)", "Scripts")
        for (dir, kind) in [("Preferences/ByHost", "Preferences"), ("LaunchAgents", "Login item")] {
            for f in (try? fm.contentsOfDirectory(atPath: (lib as NSString).appendingPathComponent(dir))) ?? []
            where f.hasPrefix(bundleID + ".") && f.hasSuffix(".plist") {
                add("\(dir)/\(f)", kind)
            }
        }
        return out
    }
}

@Observable
final class Leftover: Identifiable {
    var id: String { path }
    let path: String
    let kind: String
    let size: Int64
    var isChecked = true
    init(path: String, kind: String, size: Int64) { self.path = path; self.kind = kind; self.size = size }
}

enum Trash {
    /// Moves items to the Trash, so an uninstall can be undone from Finder.
    /// Items NSWorkspace can't move (apps owned by root, such as App Store apps) are retried through Finder,
    /// which asks for an administrator password the same way dragging to the Trash does.
    static func move(_ urls: [URL]) async -> [String] {
        var failed: [String] = []
        for u in urls {
            do {
                try FileManager.default.trashItem(at: u, resultingItemURL: nil)
            } catch {
                let script = "tell application \"Finder\" to delete (POSIX file \(appleScriptString(u.path)))"
                let r = await Task.detached { Util.run("/usr/bin/osascript", ["-e", script]) }.value
                if r.status != 0 { failed.append("\(u.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        return failed
    }

    static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
