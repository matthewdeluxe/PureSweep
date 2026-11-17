import SwiftUI

/// Start screen → scanning → results list → cleaned, with one big round button that changes in place.
struct CleanupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.page) private var page
    private let stats = SystemStats.shared

    var body: some View {
        let model = app.cleanup
        @Bindable var bm = model
        Group {
            if model.busy {
                working(model)
            } else if model.done {
                LandingView(symbol: "checkmark", title: model.headlineText, text: model.statusText) {
                    VStack(spacing: 14) {
                        mainButton(model)
                        Button("Review what's left") { model.selectionChanged() }.buttonStyle(.link).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(32)
            } else if !model.scanned {
                LandingView(symbol: "sparkles", title: model.headline == "Scan stopped" ? "Scan stopped" : "Clean up your Mac",
                            text: "Find caches, logs, browser data, developer leftovers and other files your Mac doesn't need. Nothing is deleted until you choose to clean.") {
                    VStack(spacing: 12) {
                        mainButton(model)
                        Text("Startup disk: \(Util.size(stats.diskFree)) available of \(Util.size(stats.diskTotal))")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(32)
            } else {
                results(model)
            }
        }
        .onAppear { stats.updateDisk() }
        .alert("Clean selected items?", isPresented: $bm.confirmClean) {
            Button("Clean", role: .destructive) { Task { await model.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.confirmMessage)
        }
    }

    private func working(_ model: CleanupModel) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            HeroEmblem(symbol: "sparkles", spinning: true)
            Text(model.headlineText).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            Text(model.statusText).font(.title3).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            Spacer(minLength: 0)
            mainButton(model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func results(_ model: CleanupModel) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.headlineText)
                        .font(.system(size: 44, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(model.statusText).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button("Scan again") { Task { await model.scan() } }.buttonStyle(HeaderButtonStyle())
            }
            .foregroundStyle(.white)

            if model.blocked {
                Banner(symbol: "lock.shield", text: "The Trash and Safari's cache are protected by macOS. Give PureSweep Full Disk Access to include them, then scan again.") {
                    Button("Open Settings") { Util.openFullDiskAccessSettings() }.buttonStyle(HeaderButtonStyle())
                }
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.cats.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { Divider().overlay(.white.opacity(0.08)).padding(.leading, 64) }
                        CategoryRow(cat: c, model: model)
                    }
                }
                .card(padding: 0)
            }
            .scrollIndicators(.automatic)

            mainButton(model).padding(.top, 4)
        }
        .padding(.horizontal, 32).padding(.bottom, 24).padding(.top, 8)
    }

    private func mainButton(_ model: CleanupModel) -> some View {
        let (label, sub, enabled): (String, String?, Bool) = switch model.main {
        case .scan: ("Scan", nil, true)
        case .stop: ("Stop", nil, true)
        case .stopping: ("Stopping…", nil, false)
        case .clean(let n): ("Clean", Util.size(n), true)
        case .rescan: ("Rescan", nil, true)
        case .cleaning: ("Cleaning…", nil, false)
        }
        return BigActionButton(title: label, subtitle: sub, progress: model.busy ? model.progress : nil, enabled: enabled) {
            model.mainAction()
        }
        .keyboardShortcut(.defaultAction)
    }
}

private struct CategoryRow: View {
    @Bindable var cat: JunkCategory
    let model: CleanupModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TriCheckbox(state: cat.isChecked) {
                    cat.isChecked = cat.isChecked != true
                    model.selectionChanged()
                }
                IconTile(symbol: cat.symbol, color: cat.color)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(cat.name).font(.headline)
                        if cat.blocked {
                            Label("Full Disk Access", systemImage: "lock.fill")
                                .font(.caption2.weight(.semibold)).labelStyle(.titleAndIcon)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.22), in: Capsule()).foregroundStyle(.orange)
                        }
                    }
                    Text(cat.detail).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cat.sizeText).font(.headline).monospacedDigit()
                    Text(cat.detailText).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Button { withAnimation(.snappy) { cat.isExpanded.toggle() } } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(cat.isExpanded ? 90 : 0))
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(cat.groups.isEmpty ? 0 : 0.8)
                .disabled(cat.groups.isEmpty)
                .accessibilityLabel(cat.isExpanded ? "Hide details" : "Show details")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)

            if cat.isExpanded && !cat.groups.isEmpty {
                VStack(spacing: 0) {
                    ForEach(cat.groups) { g in
                        GroupRow(group: g, model: model)
                    }
                }
                .padding(.vertical, 4)
                .background(.black.opacity(0.15))
            }
        }
    }
}

private struct GroupRow: View {
    @Bindable var group: JunkGroup
    let model: CleanupModel

    var body: some View {
        HStack(spacing: 10) {
            TriCheckbox(state: group.isChecked) {
                group.isChecked.toggle()
                model.selectionChanged()
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).lineLimit(1)
                if !group.location.isEmpty {
                    Text(Util.pretty(group.location)).font(.caption).foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            Text(group.files == 1 ? "1 item" : "\(group.files.formatted()) items").font(.caption).foregroundStyle(.white.opacity(0.5))
            Text(Util.size(group.bytes)).monospacedDigit().frame(width: 80, alignment: .trailing)
            Button { Util.reveal([group.location]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Show in Finder")
                .opacity(group.location.isEmpty ? 0 : 0.7).disabled(group.location.isEmpty)
        }
        .foregroundStyle(.white)
        .padding(.leading, 64).padding(.trailing, 56).padding(.vertical, 5)
    }
}
