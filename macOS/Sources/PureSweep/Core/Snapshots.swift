import Foundation

/// Time Machine local snapshots on the startup disk. They hold on to deleted files and show up as
/// "purgeable" space; macOS removes them on its own after 24 hours or when space runs low.
struct LocalSnapshot: Identifiable, Hashable {
    var id: String { name }
    let name: String           // com.apple.TimeMachine.2026-11-17-101010.local
    let stamp: String          // 2026-11-17-101010
    let date: Date?

    static func load() -> [LocalSnapshot] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return Util.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).output
            .split(separator: "\n").map(String.init)
            .filter { $0.hasPrefix("com.apple.TimeMachine.") }
            .map { name in
                let stamp = name.replacingOccurrences(of: "com.apple.TimeMachine.", with: "").replacingOccurrences(of: ".local", with: "")
                return LocalSnapshot(name: name, stamp: stamp, date: f.date(from: stamp))
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Deletes snapshots. Tries without privileges first, then through the macOS administrator prompt.
    /// Returns nil on success, otherwise an error message.
    static func delete(_ snaps: [LocalSnapshot]) -> String? {
        var needAdmin: [LocalSnapshot] = []
        for s in snaps where Util.run("/usr/bin/tmutil", ["deletelocalsnapshots", s.stamp]).status != 0 { needAdmin.append(s) }
        guard !needAdmin.isEmpty else { return nil }
        let cmd = needAdmin.map { "/usr/bin/tmutil deletelocalsnapshots \(Util.shellQuote($0.stamp))" }.joined(separator: " && ")
        return Util.runAsAdmin(cmd)
    }
}
