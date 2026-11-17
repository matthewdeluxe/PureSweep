import SwiftUI

final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

struct LargeFilesView: View {
    @State private var files: [LargeFile] = []
    @State private var minMB = 100
    @State private var scanning = false
    @State private var scanned = false
    @State private var flag = StopFlag()
    @State private var confirm = false
    @State private var error: String?

    private var selected: [LargeFile] { files.filter(\.isChecked) }

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(title: "Large Files", subtitle: "Find the biggest files in your home folder and decide what to keep.",
                       symbol: "doc.viewfinder", colors: [Color(red: 0.95, green: 0.55, blue: 0.10), Color(red: 0.90, green: 0.33, blue: 0.15)]) {
                if scanning || scanned {
                    Button(scanning ? "Stop" : "Scan again") {
                        if scanning { flag.set() } else { Task { await scan() } }
                    }
                    .buttonStyle(HeaderButtonStyle())
                }
            }

            HStack {
                Picker("At least", selection: $minMB) {
                    Text("50 MB").tag(50); Text("100 MB").tag(100); Text("500 MB").tag(500); Text("1 GB").tag(1024)
                }
                .frame(width: 180).disabled(scanning)
                Spacer()
                if !selected.isEmpty {
                    Text("\(selected.count) selected  •  \(Util.size(selected.reduce(0) { $0 + $1.size }))").foregroundStyle(.secondary)
                    Button("Show in Finder") { Util.reveal(selected.map(\.path)) }
                    Button("Move to Trash…") { confirm = true }
                }
            }

            Group {
                if scanning {
                    VStack(spacing: 16) {
                        HeroEmblem(symbol: "doc.viewfinder", spinning: true)
                        Text("Looking through your home folder…").font(.title3).foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !scanned {
                    LandingView(symbol: "doc.viewfinder", title: "Find large files",
                                text: "List files of \(minMB >= 1024 ? "1 GB" : "\(minMB) MB") or more in your home folder, biggest first. macOS may ask for access to folders such as Documents and Downloads.") {
                        BigActionButton(title: "Scan") { Task { await scan() } }
                    }
                } else if files.isEmpty {
                    VStack(spacing: 12) {
                        HeroEmblem(symbol: "checkmark", size: 150)
                        Text("No large files").font(.title2.weight(.semibold)).foregroundStyle(.white)
                        Text("Nothing that big in your home folder.").foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(files) { f in FileRow(file: f) }
                        .glassList()
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
        }
        .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 24)
        .alert("Move \(selected.count) item\(selected.count == 1 ? "" : "s") to the Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { Task { await trash() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can put them back from the Trash until you empty it.")
        }
    }

    private func scan() async {
        flag = StopFlag()
        let f = flag, min = Int64(minMB) * 1024 * 1024
        scanning = true
        error = nil
        let found = await Task.detached { LargeFileFinder.scan(minBytes: min, stop: { f.isSet }) }.value
        files = found.map { LargeFile(path: $0.0, size: $0.1, lastOpened: $0.2) }
        scanning = false
        scanned = true
    }

    private func trash() async {
        let chosen = selected
        let failed = await Trash.move(chosen.map { URL(fileURLWithPath: $0.path) })
        files.removeAll { f in chosen.contains { $0 === f } && !FileManager.default.fileExists(atPath: f.path) }
        error = failed.isEmpty ? nil : "Some items couldn't be moved: " + failed.joined(separator: "; ")
    }
}

private struct FileRow: View {
    @Bindable var file: LargeFile

    var body: some View {
        HStack(spacing: 10) {
            RoundCheckbox(isOn: $file.isChecked)
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).lineLimit(1)
                Text(file.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let d = file.lastOpened {
                Text("Opened \(d.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
            }
            Text(Util.size(file.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
            Button { Util.reveal([file.path]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Show in Finder")
        }
        .padding(.vertical, 3)
    }
}
