import SwiftUI

/// The macOS counterpart of the Windows Hibernation page: space the system holds back that you can reclaim.
struct SnapshotsView: View {
    private let stats = SystemStats.shared
    @State private var snaps: [LocalSnapshot] = []
    @State private var loading = true
    @State private var confirm: [LocalSnapshot]?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(title: "Snapshots", subtitle: "Time Machine local snapshots and purgeable space on your startup disk.",
                       symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                       colors: [Color(red: 0.42, green: 0.31, blue: 0.78), Color(red: 0.25, green: 0.25, blue: 0.70)]) {
                if !snaps.isEmpty {
                    Button("Delete All…") { confirm = snaps }.buttonStyle(HeaderButtonStyle()).disabled(working)
                }
            }

            HStack(spacing: 12) {
                stat("\(snaps.count)", "Local snapshots", "clock.arrow.circlepath", .indigo)
                stat(Util.size(stats.purgeable), "Purgeable space", "arrow.3.trianglepath", .purple)
                stat(Util.size(stats.diskFree), "Available", "internaldrive", .blue)
            }

            Text("Time Machine keeps hourly snapshots on your startup disk so it can restore files while the backup disk is away. They hold on to deleted files, which shows up as purgeable space. macOS removes them on its own after 24 hours or when space runs low, so delete them only when you need the space right away. Your Time Machine backups are not affected.")
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if snaps.isEmpty {
                    VStack(spacing: 12) {
                        HeroEmblem(symbol: "checkmark", size: 150)
                        Text("No local snapshots").font(.title2.weight(.semibold)).foregroundStyle(.white)
                        Text("There are no Time Machine snapshots on this Mac's startup disk.").foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(snaps) { s in
                        HStack {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.indigo)
                            VStack(alignment: .leading) {
                                Text(s.date?.formatted(date: .abbreviated, time: .shortened) ?? s.stamp)
                                Text(s.name).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let d = s.date { Text(d.formatted(.relative(presentation: .named))).foregroundStyle(.secondary).font(.caption) }
                            Button("Delete…") { confirm = [s] }.disabled(working)
                        }
                        .padding(.vertical, 3)
                    }
                    .glassList()
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
        }
        .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 24)
        .task { await load() }
        .alert(confirm?.count == 1 ? "Delete this snapshot?" : "Delete \(confirm?.count ?? 0) snapshots?",
               isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Delete", role: .destructive) { if let c = confirm { Task { await delete(c) } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS may ask for an administrator password. Deleted snapshots can't be restored.")
        }
    }

    private func stat(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color, size: 40)
            VStack(alignment: .leading) {
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card()
    }

    private func load() async {
        stats.updateDisk()
        snaps = await Task.detached { LocalSnapshot.load() }.value
        loading = false
    }

    private func delete(_ list: [LocalSnapshot]) async {
        working = true
        let e = await Task.detached { LocalSnapshot.delete(list) }.value
        error = (e == nil || e!.contains("canceled")) ? nil : e
        await load()
        working = false
    }
}
