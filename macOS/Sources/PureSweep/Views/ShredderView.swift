import SwiftUI
import UniformTypeIdentifiers

struct ShredderView: View {
    @State private var items: [String] = []
    @State private var passes = 1
    @State private var status = ""
    @State private var working = false
    @State private var confirm = false
    @State private var failures: [String] = []
    @State private var targeted = false
    @State private var fileVault: Bool?

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(title: "Shredder", subtitle: "Overwrite files with random data before deleting them.",
                       symbol: "scissors", colors: [Color(red: 0.35, green: 0.38, blue: 0.45), Color(red: 0.20, green: 0.22, blue: 0.28)])

            if fileVault == true {
                Banner(symbol: "lock.shield.fill", text: "FileVault is on. Your disk is encrypted, which is the dependable protection on a Mac: overwriting can't reach every copy on a solid-state disk, and Time Machine snapshots or iCloud may keep others.", tint: .green) { EmptyView() }
            } else if fileVault == false {
                Banner(symbol: "exclamationmark.shield", text: "FileVault is off. On a solid-state disk, overwriting can't reach every copy of a file. Turning on FileVault encryption is the dependable protection.") {
                    Button("FileVault Settings") { Util.openFileVaultSettings() }
                }
            }

            dropZone

            HStack {
                Picker("Passes", selection: $passes) {
                    Text("1 pass (quick)").tag(1); Text("3 passes").tag(3); Text("7 passes").tag(7)
                }
                .frame(width: 220)
                Text(status).foregroundStyle(.secondary)
                Spacer()
                Button { confirm = true } label: { Label("Shred…", systemImage: "scissors") }
                    .buttonStyle(HeaderButtonStyle())
                    .disabled(items.isEmpty || working)
            }
        }
        .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 24)
        .task { fileVault = await Task.detached { Shredder.fileVaultOn() }.value }
        .alert("Shred \(items.count) item\(items.count == 1 ? "" : "s")?", isPresented: $confirm) {
            Button("Shred", role: .destructive) { Task { await shred() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected files and everything inside the selected folders will be overwritten and deleted. This can't be undone, and nothing goes to the Trash.\n\n"
                 + items.prefix(5).map(Util.pretty).joined(separator: "\n")
                 + (items.count > 5 ? "\n…and \(items.count - 5) more" : ""))
        }
        .alert("Some items couldn't be shredded", isPresented: Binding(get: { !failures.isEmpty }, set: { if !$0 { failures = [] } })) {
            Button("OK") {}
        } message: { Text(failures.prefix(8).joined(separator: "\n")) }
    }

    private var dropZone: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                VStack(spacing: 10) {
                    HeroEmblem(symbol: "tray.and.arrow.down", size: 160)
                    Text("Drop files or folders here").font(.title2.weight(.semibold)).foregroundStyle(.white)
                    Text("or").foregroundStyle(.white.opacity(0.6))
                    Button("Choose…") { choose() }.buttonStyle(HeaderButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items, id: \.self) { p in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 24, height: 24)
                            Text(Util.pretty(p)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { items.removeAll { $0 == p } } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove from list")
                        }
                    }
                }
                .listStyle(.inset)
                HStack {
                    Button("Add…") { choose() }.buttonStyle(HeaderButtonStyle())
                    Button("Clear") { items = [] }.buttonStyle(HeaderButtonStyle())
                    Spacer()
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? Color.accentColor.opacity(0.08) : .clear)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: items.isEmpty ? [6, 4] : [])))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .dropDestination(for: URL.self) { urls, _ in
            add(urls.filter(\.isFileURL).map(\.path)); return true
        } isTargeted: { targeted = $0 }
    }

    private func add(_ paths: [String]) {
        for p in paths where !items.contains(p) { items.append(p) }
        status = ""
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose files or folders to shred"
        if panel.runModal() == .OK { add(panel.urls.map(\.path)) }
    }

    private func shred() async {
        working = true
        status = "Shredding…"
        let targets = items, passes = passes
        let (count, failed) = await Task.detached { () -> (Int, [(String, String)]) in
            var count = 0
            var failed: [(String, String)] = []
            for t in targets {
                do { count += try Shredder.shred(t, passes: passes) }
                catch { failed.append((t, error.localizedDescription)) }
            }
            return (count, failed)
        }.value
        items = items.filter { p in failed.contains { $0.0 == p } }
        status = "\(count) file\(count == 1 ? "" : "s") shredded" + (failed.isEmpty ? "." : ", \(failed.count) failed.")
        failures = failed.map { "\(Util.pretty($0.0)) — \($0.1)" }
        working = false
    }
}
