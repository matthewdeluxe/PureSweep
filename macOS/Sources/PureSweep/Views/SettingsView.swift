import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var fullDiskAccess = Util.hasFullDiskAccess

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $settings.theme) {
                    Text("Follow macOS").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Applies to Settings and the menu bar. The main window always uses its dark, colourful look.")
            }

            Section("Cleanup") {
                Toggle(isOn: $settings.keepRecentTemp) {
                    Text("Keep recent files")
                    Text("Caches, temporary files and logs changed in the last 24 hours are skipped, since apps may still be using them.")
                }
                LabeledContent {
                    if fullDiskAccess {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open Privacy Settings") { Util.openFullDiskAccessSettings() }
                    }
                } label: {
                    Text("Full Disk Access")
                    Text("Needed to measure and empty the Trash and Safari's cache.")
                }
            }

            Section("General") {
                Toggle(isOn: $settings.showMenuBarExtra) {
                    Text("Show in menu bar")
                    Text("Disk, memory and CPU at a glance, plus Smart Scan. PureSweep keeps running there when you close its window.")
                }
                Toggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)) {
                    Text("Open at login")
                    if let loginError { Text(loginError).foregroundStyle(.red) }
                }
            }

            Section("History") {
                LabeledContent("Last cleanup", value: settings.lastClean.map { "\(Util.size(settings.lastFreed)), \(Util.ago($0))" } ?? "Never")
                LabeledContent("Reclaimed in total", value: Util.size(settings.totalFreed))
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fullDiskAccess = Util.hasFullDiskAccess
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    private let stats = SystemStats.shared
    private let settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PureSweep").font(.headline)
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.borderless)
            }
            meter("Startup disk", stats.diskUsedPct, "\(Util.size(stats.diskFree)) free", .blue)
            meter("Memory", stats.memUsedPct, "\(Util.size(stats.memUsed)) used", .purple)
            meter("Processor", stats.cpu, "\(Int(stats.cpu.rounded()))% busy", .green)
            Divider()
            Text(settings.lastClean.map { "Last cleanup: \(Util.size(settings.lastFreed)) freed \(Util.ago($0))" } ?? "Not cleaned yet")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Smart Scan") { show(); model.smartScan() }.buttonStyle(.borderedProminent)
                Button("Open PureSweep") { show() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate()
    }

    private func meter(_ title: String, _ value: Double, _ detail: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: min(100, max(0, value)), total: 100).tint(color)
        }
    }
}
