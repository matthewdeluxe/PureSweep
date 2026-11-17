import Foundation

/// A launch agent or daemon: the macOS equivalent of a Windows Run key entry.
///
/// Turning one off uses `launchctl disable`, which records an override in launchd's own database
/// (the same mechanism as the switches in System Settings). The plist is never edited or deleted,
/// so every change is reversible. Changes take effect at the next login or restart.
@Observable
final class LoginItem: Identifiable {
    enum Scope: String { case user = "Your account", agents = "All users", daemons = "System daemon" }

    var id: String { scope.rawValue + label }
    let label: String
    let name: String
    let program: String
    let plistPath: String
    let scope: Scope
    let runsAtLoad: Bool
    private(set) var isEnabled: Bool

    init(label: String, name: String, program: String, plistPath: String, scope: Scope, runsAtLoad: Bool, isEnabled: Bool) {
        self.label = label; self.name = name; self.program = program; self.plistPath = plistPath
        self.scope = scope; self.runsAtLoad = runsAtLoad; self.isEnabled = isEnabled
    }

    var needsAdmin: Bool { scope == .daemons }

    private var target: String { scope == .daemons ? "system/\(label)" : "gui/\(getuid())/\(label)" }

    /// Returns nil on success, otherwise an error message.
    func toggle() async -> String? {
        let verb = isEnabled ? "disable" : "enable"
        let target = target, admin = needsAdmin
        let error: String? = await Task.detached {
            if admin { return Util.runAsAdmin("/bin/launchctl \(verb) \(Util.shellQuote(target))") }
            let r = Util.run("/bin/launchctl", [verb, target])
            return r.status == 0 ? nil : r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
        if error == nil { isEnabled.toggle() }
        return error
    }

    static func load() -> [LoginItem] {
        let userOverrides = overrides("gui/\(getuid())")
        let systemOverrides = overrides("system")
        var items: [LoginItem] = []
        for (dir, scope) in [("~/Library/LaunchAgents", Scope.user), ("/Library/LaunchAgents", .agents), ("/Library/LaunchDaemons", .daemons)] {
            let path = Util.expand(dir)
            for f in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] where f.hasSuffix(".plist") {
                let p = (path as NSString).appendingPathComponent(f)
                guard let d = NSDictionary(contentsOfFile: p) as? [String: Any], let label = d["Label"] as? String else { continue }
                let program = (d["Program"] as? String) ?? ((d["ProgramArguments"] as? [String])?.first ?? "")
                let disabledInPlist = (d["Disabled"] as? Bool) ?? false
                let o = (scope == .daemons ? systemOverrides : userOverrides)[label]
                items.append(LoginItem(label: label, name: displayName(label: label, program: program), program: program,
                                       plistPath: p, scope: scope, runsAtLoad: (d["RunAtLoad"] as? Bool) ?? false,
                                       isEnabled: !(o ?? disabledInPlist)))
            }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Parses `launchctl print-disabled`: lines like `"com.example.agent" => disabled` (or `=> true` on older macOS).
    private static func overrides(_ domain: String) -> [String: Bool] {
        var map: [String: Bool] = [:]
        for line in Util.run("/bin/launchctl", ["print-disabled", domain]).output.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let v = parts[1].trimmingCharacters(in: .whitespaces)
            map[label] = v == "disabled" || v == "true"
        }
        return map
    }

    /// The enclosing app's name when the program lives inside a .app bundle, else the label.
    private static func displayName(label: String, program: String) -> String {
        var url = URL(fileURLWithPath: program)
        while url.path != "/" && !url.path.isEmpty {
            if url.pathExtension == "app" { return url.deletingPathExtension().lastPathComponent }
            url.deleteLastPathComponent()
        }
        return label
    }
}
