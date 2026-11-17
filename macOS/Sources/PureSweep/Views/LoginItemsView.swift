import SwiftUI

struct LoginItemsView: View {
    @State private var items: [LoginItem] = []
    @State private var loading = true
    @State private var showSystem = false
    @State private var error: String?

    private var shown: [LoginItem] { showSystem ? items : items.filter { $0.scope != .daemons } }

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(title: "Login Items", subtitle: "Background helpers that start when you log in or your Mac starts up.",
                       symbol: "power", colors: [Color(red: 0.04, green: 0.56, blue: 0.48), Color(red: 0.05, green: 0.42, blue: 0.62)])

            Banner(symbol: "info.circle", text: "Turning an item off asks launchd not to load it. Nothing is deleted, and it takes effect the next time you log in. Apps you added yourself, and helpers registered by apps, are managed in System Settings.", tint: .blue) {
                Button("Open Login Items") { Util.openLoginItemsSettings() }
            }

            HStack {
                Toggle("Show system daemons", isOn: $showSystem)
                Spacer()
                Text("\(shown.filter(\.isEnabled).count) of \(shown.count) enabled").foregroundStyle(.secondary)
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                ContentUnavailableView("No launch agents", systemImage: "checkmark.circle", description: Text("Nothing extra starts when you log in."))
            } else {
                List(shown) { item in LoginRow(item: item, error: $error) }
                    .glassList()
            }
        }
        .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 24)
        .task { await load() }
        .alert("Couldn't change this item", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func load() async {
        loading = items.isEmpty
        items = await Task.detached { LoginItem.load() }.value
        loading = false
    }
}

private struct LoginRow: View {
    let item: LoginItem
    @Binding var error: String?
    @State private var busy = false

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: item.scope == .daemons ? "gearshape.2.fill" : item.scope == .agents ? "person.2.fill" : "person.fill",
                     color: item.isEnabled ? .teal : .gray, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.headline)
                Text(item.label + (item.program.isEmpty ? "" : "  •  " + Util.pretty(item.program)))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(item.scope.rawValue).font(.caption).foregroundStyle(.secondary)
            if item.needsAdmin { Image(systemName: "lock.fill").foregroundStyle(.secondary).help("Asks for an administrator password") }
            Button { Util.reveal([item.plistPath]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Show the plist in Finder")
            Toggle("", isOn: Binding(get: { item.isEnabled }, set: { _ in
                busy = true
                Task {
                    let e = await item.toggle()
                    if let e, !e.contains("canceled") { error = e }
                    busy = false
                }
            }))
            .toggleStyle(.switch).labelsHidden().disabled(busy)
        }
        .opacity(item.isEnabled ? 1 : 0.6)
        .padding(.vertical, 4)
    }
}
