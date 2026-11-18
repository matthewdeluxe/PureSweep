import Foundation

/// One-click fixes that reset a system cache with a command instead of deleting files.
/// They rarely free much space; they fix glitches. Deliberately absent: "free up RAM" (`purge`),
/// which only makes the Mac reload what it just threw away.
struct MaintenanceTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    /// Runs through the macOS administrator prompt.
    let needsAdmin: Bool
    /// Shown in a confirmation dialog first, for tasks with a side effect worth knowing about.
    var confirm: String? = nil
    /// Shown after it succeeds.
    var doneNote: String? = nil
    /// Shell command (run through /bin/sh, or through the admin prompt).
    let command: String

    private static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static let all: [MaintenanceTask] = [
        MaintenanceTask(
            id: "dns", title: "Flush DNS cache",
            detail: "Forgets remembered website addresses. Helps when sites won't load after a network or DNS change.",
            symbol: "network", needsAdmin: true,
            command: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"),
        MaintenanceTask(
            id: "quicklook", title: "Reset Quick Look previews",
            detail: "Clears the thumbnail cache and reloads preview plug-ins. Helps when Finder shows wrong or blank previews.",
            symbol: "eye", needsAdmin: false,
            command: "/usr/bin/qlmanage -r cache && /usr/bin/qlmanage -r"),
        MaintenanceTask(
            id: "fonts", title: "Rebuild font caches",
            detail: "Removes your font databases so macOS rebuilds them. Helps with garbled text or fonts that won't show up.",
            symbol: "textformat", needsAdmin: false,
            doneNote: "Restart your Mac to finish rebuilding the font caches.",
            command: "/usr/bin/atsutil databases -removeUser"),
        MaintenanceTask(
            id: "launchservices", title: "Fix the \"Open With\" menu",
            detail: "Re-registers your apps and drops entries for apps that are gone. Helps with duplicates in \"Open With\" and wrong default apps.",
            symbol: "filemenu.and.selection", needsAdmin: false,
            command: "\(lsregister) -gc -r -f -apps u,l,s"),
        MaintenanceTask(
            id: "spotlight", title: "Rebuild Spotlight index",
            detail: "Erases and rebuilds the search index for your startup disk. Helps when Spotlight misses files or shows stale results.",
            symbol: "magnifyingglass", needsAdmin: true,
            confirm: "Spotlight and Mail search will be incomplete while macOS reindexes, which can take an hour or more, and your Mac may run warm meanwhile.",
            doneNote: "Reindexing has started and runs in the background.",
            command: "/usr/bin/mdutil -E /"),
    ]

    /// Returns nil on success, otherwise an error message ("User canceled." when the password prompt was dismissed).
    func run() -> String? {
        if needsAdmin { return Util.runAsAdmin(command) }
        let r = Util.run("/bin/sh", ["-c", command])
        return r.status == 0 ? nil : r.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
