import SwiftUI

struct UninstallerView: View {
    @State private var apps: [InstalledApp] = []
    @State private var loading = true
    @State private var search = ""
    @State private var sortBySize = false
    @State private var target: InstalledApp?

    private var shown: [InstalledApp] {
        let f = search.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search)
        }
        return sortBySize ? f.sorted { ($0.size ?? 0) > ($1.size ?? 0) } : f
    }

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(title: "Uninstaller", subtitle: "Remove apps together with the support files they leave in your Library.",
                       symbol: "xmark.app.fill", colors: [Color(red: 0.91, green: 0.30, blue: 0.22), Color(red: 0.80, green: 0.18, blue: 0.40)])

            HStack {
                TextField("Search apps", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                Picker("Sort", selection: $sortBySize) {
                    Text("Name").tag(false)
                    Text("Size").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 160).labelsHidden()
                Spacer()
                Text(summary).foregroundStyle(.secondary).font(.callout)
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
            }

            if loading {
                VStack(spacing: 16) {
                    HeroEmblem(symbol: "xmark.app", spinning: true)
                    Text("Finding apps…").font(.title3).foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { app in
                    AppRow(app: app) { target = app }
                }
                .glassList()
            }
        }
        .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 24)
        .task { if apps.isEmpty { await load() } }
        .sheet(item: $target) { app in
            UninstallSheet(app: app) { removed in
                if removed { apps.removeAll { $0.id == app.id } }
            }
        }
    }

    private var summary: String {
        let total = apps.compactMap(\.size).reduce(0, +)
        return "\(apps.count) apps" + (total > 0 ? "  •  \(Util.size(total))" : "")
    }

    private func load() async {
        loading = true
        let list = await Task.detached { InstalledApp.load() }.value
        apps = list
        loading = false
        // Sizes are slow for big bundles, so fill them in afterwards, a few at a time.
        await withTaskGroup(of: (String, Int64).self) { group in
            var it = list.makeIterator()
            for _ in 0..<4 { if let a = it.next() { let url = a.url, id = a.id; group.addTask { (id, Util.treeSize(url)) } } }
            while let (id, size) = await group.next() {
                list.first { $0.id == id }?.size = size
                if let a = it.next() { let url = a.url, id = a.id; group.addTask { (id, Util.treeSize(url)) } }
            }
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let uninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: app.icon).resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.headline)
                    if app.isAppStore {
                        Text("App Store").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.blue.opacity(0.15), in: Capsule()).foregroundStyle(.blue)
                    }
                }
                Text([app.version.isEmpty ? nil : "Version \(app.version)", app.bundleID].compactMap { $0 }.joined(separator: "  •  "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(app.size.map(Util.size) ?? "…").monospacedDigit().foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
            Button { Util.reveal([app.url.path]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Show in Finder")
            Button("Uninstall…", action: uninstall).buttonStyle(HeaderButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

private struct UninstallSheet: View {
    let app: InstalledApp
    let finished: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var leftovers: [Leftover]?
    @State private var working = false
    @State private var error: String?

    private var total: Int64 {
        (app.size ?? 0) + (leftovers ?? []).filter(\.isChecked).reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: app.icon).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstall \(app.name)?").font(.title2.weight(.bold))
                    Text("Everything below moves to the Trash, so you can still put it back from Finder.")
                        .foregroundStyle(.secondary)
                }
            }

            if app.isRunning {
                Banner(symbol: "exclamationmark.triangle.fill", text: "\(app.name) is running. It will be asked to quit first.") { EmptyView() }
            }

            VStack(spacing: 0) {
                row(checked: .constant(true), title: app.url.lastPathComponent, sub: Util.pretty(app.url.path), kind: "Application", size: app.size, locked: true)
                if let leftovers {
                    ForEach(leftovers) { l in
                        Divider()
                        @Bindable var l = l
                        row(checked: $l.isChecked, title: (l.path as NSString).lastPathComponent, sub: Util.pretty(l.path), kind: l.kind, size: l.size, locked: false)
                    }
                    if leftovers.isEmpty {
                        Divider()
                        Text("No support files found in your Library.").foregroundStyle(.secondary).padding(10)
                    }
                } else {
                    Divider()
                    ProgressView().controlSize(.small).padding(10)
                }
            }
            .card(padding: 0)

            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Text("Total: \(Util.size(total))").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move to Trash") { Task { await uninstall() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || leftovers == nil)
            }
        }
        .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 24)
        .frame(width: 620)
        .task {
            let app = app
            leftovers = await Task.detached { app.leftovers() }.value
        }
    }

    private func row(checked: Binding<Bool>, title: String, sub: String, kind: String, size: Int64?, locked: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: checked).labelsHidden().disabled(locked)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(kind).font(.caption).foregroundStyle(.secondary)
            Text(size.map(Util.size) ?? "…").monospacedDigit().frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    private func uninstall() async {
        working = true
        error = nil
        for r in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
            r.terminate()
        }
        // Give it a moment to quit (and save) before moving it.
        for _ in 0..<20 where app.isRunning { try? await Task.sleep(for: .milliseconds(250)) }
        if app.isRunning {
            error = "\(app.name) didn't quit. Quit it yourself, then try again."
            working = false
            return
        }
        let urls = [app.url] + (leftovers ?? []).filter(\.isChecked).map { URL(fileURLWithPath: $0.path) }
        let failed = await Trash.move(urls)
        working = false
        let appGone = !FileManager.default.fileExists(atPath: app.url.path)
        if failed.isEmpty || appGone {
            finished(appGone)
            if failed.isEmpty { dismiss() } else { error = "Some files couldn't be moved:\n" + failed.joined(separator: "\n") }
        } else {
            error = failed.joined(separator: "\n")
        }
    }
}
