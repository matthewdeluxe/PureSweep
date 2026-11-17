import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    private let stats = SystemStats.shared
    private let settings = AppSettings.shared
    @State private var appsText = "Counting…"
    @State private var loginText = "–"
    @State private var snapText = "–"

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back").font(.system(size: 30, weight: .bold))
                Text("Here's how your Mac is doing. Run Smart Scan to find junk files you can safely remove.")
                    .font(.title3).foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    gauge(stats.diskUsedPct, "used", "Startup disk",
                          "\(Util.size(stats.diskFree)) free of \(Util.size(stats.diskTotal))", .blue)
                    gauge(stats.memUsedPct, "in use", "Memory",
                          "\(Util.size(stats.memUsed)) of \(Util.size(stats.memTotal))", .purple)
                    gauge(stats.cpu, "busy", "Processor", "\(stats.cores) cores", .green)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    tile(.cleanup, "sparkles", .blue, cleanValue, cleanLabel)
                    tile(.uninstaller, "xmark.app.fill", .red, appsText, "Installed apps")
                    tile(.loginItems, "power", .teal, loginText, "Login items")
                    tile(.snapshots, "clock.arrow.trianglehead.counterclockwise.rotate.90", .indigo, snapText, "Time Machine local snapshots")
                }

            Spacer(minLength: 0)
            BigActionButton(title: "Smart Scan") { model.smartScan() }
        }
        .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 28)
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
        .task { await loadTiles() }
    }

    private var cleanValue: String {
        guard let last = settings.lastClean else { return "Not cleaned yet" }
        return "\(Util.size(settings.lastFreed)) freed \(Util.ago(last))"
    }

    private var cleanLabel: String {
        settings.lastClean == nil ? "Last cleanup" : "Last cleanup  •  \(Util.size(settings.totalFreed)) reclaimed in total"
    }

    private func loadTiles() async {
        let (login, snaps) = await Task.detached { (LoginItem.load(), LocalSnapshot.load()) }.value
        let agents = login.filter { $0.scope != .daemons }   // same set the Login Items page shows by default
        loginText = "\(agents.filter(\.isEnabled).count) of \(agents.count) enabled"
        snapText = snaps.isEmpty ? "None on this Mac" : "\(snaps.count) snapshot\(snaps.count == 1 ? "" : "s")"
        let apps = await Task.detached { InstalledApp.load() }.value
        appsText = "\(apps.count) apps"
        let total = await Task.detached { apps.reduce(Int64(0)) { $0 + Util.treeSize($1.url) } }.value
        appsText = "\(apps.count) apps  •  \(Util.size(total))"
    }

    private func gauge(_ value: Double, _ unit: String, _ title: String, _ detail: String, _ color: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RingGauge(value: value, color: color)
                VStack(spacing: 0) {
                    Text("\(Int(value.rounded()))%").font(.system(size: 26, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
    }

    private func tile(_ page: AppModel.Page, _ symbol: String, _ color: Color, _ value: String, _ label: String) -> some View {
        Button { model.page = page } label: {
            HStack(spacing: 14) {
                IconTile(symbol: symbol, color: color, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
            }
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(.plain)
    }
}
