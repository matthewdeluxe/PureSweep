import Foundation
import SwiftUI

/// State for the Cleanup page. Lives in AppModel so Smart Scan (Home, menu bar) can drive it.
@MainActor
@Observable
final class CleanupModel {
    let cats = JunkCatalog.create()
    private(set) var scanned = false
    private(set) var busy = false
    private(set) var scanning = false     // a scan the user may stop is running
    private(set) var stopping = false
    private(set) var done = false         // just cleaned: show the result until the selection changes or a new scan starts
    private(set) var progress: Double = 0 // 0-100
    private(set) var headline = "Ready to scan"
    private(set) var status = "Scan to see how much space junk files are taking up."
    private(set) var freedLast: Int64 = 0
    var confirmClean = false

    private let cleanShare = 60.0          // cleaning fills the bar to here; the refresh scan fills the rest

    var selected: Int64 { cats.reduce(0) { $0 + $1.selectedBytes } }
    var blocked: Bool { cats.contains(where: \.blocked) }

    enum Main { case scan, stop, stopping, clean(Int64), rescan, cleaning }

    /// The page's single primary action, which changes in place.
    var main: Main {
        if stopping { return .stopping }
        if scanning { return .stop }
        if busy { return .cleaning }
        if scanned && !done { return selected > 0 ? .clean(selected) : .rescan }
        return scanned ? .rescan : .scan
    }

    var headlineText: String {
        if busy || !scanned || done { return headline }
        return Util.size(selected)
    }

    var statusText: String {
        if busy || !scanned || done { return status }
        return selected > 0 ? "selected and ready to clean. Open a category to choose exactly what goes."
                            : "Nothing selected. Tick a category, or scan again."
    }

    func mainAction() {
        switch main {
        case .stop: stopping = true
        case .clean: confirmClean = true
        case .scan, .rescan: Task { await scan() }
        case .stopping, .cleaning: break
        }
    }

    /// Any change to the selection leaves the "just cleaned" result state.
    func selectionChanged() { done = false }

    func scan(canStop: Bool = true) async {
        guard !busy else { return }
        done = false
        stopping = false
        scanning = canStop
        busy = true
        if canStop { headline = "Scanning…"; progress = 0 } else { headline = "Finishing up…" }
        let from = canStop ? 0 : cleanShare
        for (i, c) in cats.enumerated() {
            if stopping { break }
            status = "Checking: " + c.name
            await c.scan()
            withAnimation(.easeOut(duration: 0.45)) { progress = from + (100 - from) * Double(i + 1) / Double(cats.count) }
        }
        if !stopping {
            scanning = false   // too late to stop
            try? await Task.sleep(for: .milliseconds(500))
        }
        scanning = false
        busy = false
        if stopping {
            // sizes are only partly refreshed, so don't offer to clean from them
            stopping = false
            scanned = false
            headline = "Scan stopped"
            status = "Press Scan to start again."
            return
        }
        scanned = true
        SystemStats.shared.updateDisk()
    }

    var confirmMessage: String {
        let names = cats.filter { $0.selectedBytes > 0 }.map(\.name).joined(separator: ", ")
        return "About \(Util.size(selected)) will be permanently deleted from: \(names). This can't be undone."
    }

    func clean() async {
        let chosen = cats.filter { $0.selectedBytes > 0 }
        let expected = chosen.reduce(0) { $0 + $1.selectedBytes }
        busy = true
        headline = "Cleaning…"
        status = "Removing selected junk files."
        progress = 0
        var freed: Int64 = 0
        for (i, c) in chosen.enumerated() {
            status = "Cleaning: " + c.name
            freed += await c.clean()
            withAnimation(.easeOut(duration: 0.45)) { progress = cleanShare * Double(i + 1) / Double(chosen.count) }
        }
        busy = false
        AppSettings.shared.recordClean(freed: freed)

        await scan(canStop: false)
        done = true
        freedLast = freed
        headline = Util.size(freed) + " freed"
        status = freed < expected ? "Some files were in use or protected and were left in place." : "Your Mac is clean."
    }
}

@MainActor
@Observable
final class AppModel {
    enum Page: String, CaseIterable, Identifiable {
        case home = "Home", cleanup = "Cleanup", uninstaller = "Uninstaller", loginItems = "Login Items",
             largeFiles = "Large Files", snapshots = "Snapshots", maintenance = "Maintenance", shredder = "Shredder"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .home: return "house"
            case .cleanup: return "sparkles"
            case .uninstaller: return "xmark.app"
            case .loginItems: return "power"
            case .largeFiles: return "doc.viewfinder"
            case .snapshots: return "clock.arrow.circlepath"
            case .maintenance: return "wrench.and.screwdriver"
            case .shredder: return "scissors"
            }
        }
    }

    var page: Page? = .home
    let cleanup = CleanupModel()

    func smartScan() {
        page = .cleanup
        Task { await cleanup.scan() }
    }
}
