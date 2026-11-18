import SwiftUI

/// System caches that are reset with a command rather than cleaned as files.
struct MaintenanceView: View {
    private enum RunState { case running, done(Date), failed(String) }

    @State private var state: [String: RunState] = [:]
    @State private var confirm: MaintenanceTask?
    @Environment(\.page) private var page

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(title: "Maintenance", subtitle: "Reset system caches that can cause glitches.",
                       symbol: AppModel.Page.maintenance.symbol)

            Text("These don't free much space. Each one resets a cache macOS rebuilds on its own, which fixes problems like websites not loading, wrong previews or duplicate apps in menus. Run one when you have that problem.")
                .font(.callout).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(MaintenanceTask.all) { row($0) }
                }
            }
            .scrollIndicators(.automatic)
        }
        .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 24)
        .alert("\(confirm?.title ?? "")?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Run") { if let t = confirm { start(t) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirm?.confirm ?? "")
        }
    }

    private func row(_ t: MaintenanceTask) -> some View {
        let s = state[t.id]
        let running = if case .running = s { true } else { false }
        return HStack(spacing: 14) {
            Image(systemName: t.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(page.accent)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(t.title).font(.headline)
                    if t.needsAdmin {
                        Text("Needs password").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.orange.opacity(0.2), in: Capsule())
                    }
                }
                Text(t.detail).font(.callout).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                switch s {
                case .done(let when):
                    Label(t.doneNote.map { "Done \(Util.ago(when)). \($0)" } ?? "Done \(Util.ago(when)).", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(page.accent)
                case .failed(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                        .lineLimit(3)
                default: EmptyView()
                }
            }
            Spacer(minLength: 12)
            if running {
                ProgressView().controlSize(.small).frame(width: 64)
            } else {
                Button("Run") { t.confirm == nil ? start(t) : (confirm = t) }
                    .buttonStyle(HeaderButtonStyle())
                    .accessibilityLabel("Run \(t.title)")
            }
        }
        .foregroundStyle(.white)
        .card()
    }

    private func start(_ t: MaintenanceTask) {
        state[t.id] = .running
        Task {
            let error = await Task.detached { t.run() }.value
            if let error {
                state[t.id] = error.localizedCaseInsensitiveContains("canceled") ? nil : .failed(error)
            } else {
                state[t.id] = .done(Date())
            }
        }
    }
}
