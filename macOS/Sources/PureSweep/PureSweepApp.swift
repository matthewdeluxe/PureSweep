import AppKit
import SwiftUI

@main
struct PureSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel()
    @Bindable private var settings = AppSettings.shared

    var body: some Scene {
        Window("PureSweep", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 600)
                #if DEBUG
                .onAppear { DebugSnapshots.runIfRequested(model) }
                #endif
        }
        .defaultSize(width: 1080, height: 740)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Smart Scan") { model.smartScan() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu("Go") {
                ForEach(Array(AppModel.Page.allCases.enumerated()), id: \.element) { i, p in
                    Button(p.rawValue) { model.page = p }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra("PureSweep", systemImage: "sparkles", isInserted: $settings.showMenuBarExtra) {
            MenuBarView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.apply()
    }

    /// With the menu bar extra on, closing the window keeps PureSweep running there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppSettings.shared.showMenuBarExtra
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let page = model.page ?? .home
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 216)
            Group {
                switch page {
                case .home: HomeView()
                case .cleanup: CleanupView()
                case .uninstaller: UninstallerView()
                case .loginItems: LoginItemsView()
                case .largeFiles: LargeFilesView()
                case .snapshots: SnapshotsView()
                case .shredder: ShredderView()
                }
            }
            .padding(.top, 28)                      // clear of the transparent title bar
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .id(page)
        }
        .background(ImmersiveBackground(page: page))
        .environment(\.page, page)
        .environment(\.colorScheme, .dark)
        .tint(page.accent)
        .animation(.easeInOut(duration: 0.25), value: page)
        .background(WindowStyler())
        .ignoresSafeArea()
    }
}

/// Sidebar grouped by kind of task, on a darker translucent strip.
private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    private let sections: [(String?, [AppModel.Page])] = [
        (nil, [.home]),
        ("Cleanup", [.cleanup, .snapshots]),
        ("Applications", [.uninstaller, .loginItems]),
        ("Files", [.largeFiles, .shredder]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle((model.page ?? .home).accent)
                Text("PureSweep").font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.top, 48).padding(.bottom, 14)

            ForEach(sections, id: \.1) { title, pages in
                if let title {
                    Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 2)
                }
                ForEach(pages) { p in row(p) }
            }
            Spacer()
            SettingsLink {
                Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 12).padding(.bottom, 16)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.22))
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
    }

    private func row(_ p: AppModel.Page) -> some View {
        let selected = (model.page ?? .home) == p
        return Button { model.page = p } label: {
            HStack(spacing: 10) {
                Image(systemName: p.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(LinearGradient(colors: [p.accent.opacity(0.9), p.palette[2]], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(p.rawValue).foregroundStyle(.white.opacity(selected ? 1 : 0.8))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selected ? .white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Transparent, full-size-content title bar with a dark appearance, so the gradient runs to the window edge.
private struct WindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.appearance = NSAppearance(named: .darkAqua)
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.12, alpha: 1)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

#if DEBUG
/// Debug builds only: PURESWEEP_SNAPSHOT=<dir> renders every page of the main window to PNG files, then quits.
/// Used to check layouts without screen-recording permission.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(_ model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["PURESWEEP_SNAPSHOT"] else { return }
        Task {
            try? await Task.sleep(for: .seconds(2))
            let dark = ProcessInfo.processInfo.environment["PURESWEEP_DARK"] != nil
            if dark { AppSettings.shared.theme = 2 }
            for p in AppModel.Page.allCases {
                model.page = p
                if p == .cleanup { Task { await model.cleanup.scan() } }
                try? await Task.sleep(for: .seconds(p == .cleanup ? 12 : 4))
                if p == .cleanup { model.cleanup.cats[0].isExpanded = true; try? await Task.sleep(for: .seconds(1)) }
                guard let w = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true || $0.title == p.rawValue }),
                      let v = w.contentView?.superview ?? w.contentView,
                      let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(p.rawValue)\(dark ? "-dark" : "").png"))
            }
            if dark { AppSettings.shared.theme = 0 }
            NSApp.terminate(nil)
        }
    }
}
#endif
