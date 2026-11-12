import SkilloriCore
import SkilloriUI
import SwiftUI

/// What the panel can ask the app to do. The panel lives in an AppKit window, so it gets
/// these instead of SwiftUI's scene actions.
struct PanelActions {
    var openLibrary: () -> Void = {}
    var openSettings: () -> Void = {}
    var addFolder: () -> Void = {}
    var rescan: () -> Void = {}
    var openPrivacySettings: () -> Void = {}
}

/// Everything the panel shows, as plain values. The live model comes from the inventory;
/// the samples in `PanelModel+Samples` are the three states in the design sketch.
struct PanelModel {
    enum Row: Identifiable {
        /// A named thing with a mono line under it and mono data to the right.
        case item(title: String, detail: String, data: String)
        /// One line of text with mono data to the right.
        case line(text: String, data: String, muted: Bool)
        /// One muted line with a link to the right.
        case link(text: String, label: String, command: Command)

        var id: String {
            switch self {
            case let .item(title, detail, _): "item-\(title)-\(detail)"
            case let .line(text, _, _): "line-\(text)"
            case let .link(text, _, _): "link-\(text)"
            }
        }
    }

    enum Command { case library, settings, addFolder, rescan, privacySettings }

    struct Button: Identifiable {
        let title: String
        let prominent: Bool
        let command: Command
        var id: String { title }
    }

    var tone: Tone
    var label: String
    var stamp: String
    var number: String
    var dimmed = false
    var lead: String
    var note: String
    var rows: [Row]
    var buttons: [Button]
    var hint: String
    var hintCommand: Command = .rescan
    var hintEnabled = true
}

struct MenuPanel: View {
    @Environment(InventoryStore.self) private var store
    var actions = PanelActions()
    /// Set in debug snapshots to show a fixed state instead of the inventory.
    var fixedModel: PanelModel?

    var body: some View {
        let model = fixedModel ?? PanelModel.live(from: store)
        GlassPanel {
            HeroBlock(tone: model.tone, label: model.label, stamp: model.stamp, number: model.number,
                      dimmed: model.dimmed, lead: model.lead, note: model.note)
            if !model.rows.isEmpty {
                GlassList(behind: model.tone.background) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, isLast: index == model.rows.count - 1)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(model.buttons) { button in
                    Button(button.title) { run(button.command) }
                        .buttonStyle(PillButtonStyle(prominent: button.prominent))
                }
                Spacer(minLength: 8)
                Button { run(model.hintCommand) } label: { SwappingText(model.hint) }
                    .buttonStyle(HintButtonStyle())
                    .keyboardShortcut("r")
                    .disabled(!model.hintEnabled)
            }
            .padding(EdgeInsets(top: 10, leading: 4, bottom: 4, trailing: 6))
        }
        .background {
            // Keyboard commands that have no visible control in the panel.
            Group {
                Button("Settings") { actions.openSettings() }.keyboardShortcut(",")
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func rowView(_ row: PanelModel.Row, isLast: Bool) -> some View {
        switch row {
        case let .item(title, detail, data):
            ListRow(isLast: isLast) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(TypeRole.sans(13, .medium)).lineLimit(1)
                    DataText(detail).foregroundStyle(Palette.ink2)
                }
            } trailing: {
                DataText(data).foregroundStyle(Palette.ink2)
            }
        case let .line(text, data, muted):
            ListRow(isLast: isLast) {
                Text(text).foregroundStyle(muted ? Palette.ink2 : Palette.ink).lineLimit(1)
            } trailing: {
                DataText(data).foregroundStyle(Palette.ink2)
            }
        case let .link(text, label, command):
            ListRow(isLast: isLast) {
                Text(text).foregroundStyle(Palette.ink2).lineLimit(1)
            } trailing: {
                Button(label) { run(command) }.buttonStyle(HintButtonStyle(underlined: true))
            }
        }
    }

    private func run(_ command: PanelModel.Command) {
        switch command {
        case .library: actions.openLibrary()
        case .settings: actions.openSettings()
        case .addFolder: actions.addFolder()
        case .rescan: actions.rescan()
        case .privacySettings: actions.openPrivacySettings()
        }
    }
}

extension PanelModel {
    /// The panel for what the app can truthfully say today: a local reading. Skillori does
    /// not ask sources about changes yet (backlog, etapp 2), so this never claims "in sync".
    @MainActor
    static func live(from store: InventoryStore) -> PanelModel {
        guard let inventory = store.inventory else {
            return PanelModel(tone: .quiet, label: "No reading", stamp: "Reading now",
                              number: "--", dimmed: true,
                              lead: "Reading this Mac", note: "Looking in the skill folders Skillori knows.",
                              rows: [], buttons: [Button(title: "Library", prominent: false, command: .library)],
                              hint: "Reading…", hintEnabled: false)
        }

        // A folder that cannot be read comes first: the count below it would look complete and not be.
        let unreadable = inventory.roots.filter { if case .unreadable = $0.state { true } else { false } }
        if !unreadable.isEmpty {
            let time = inventory.scannedAt.formatted(date: .omitted, time: .shortened)
            return PanelModel(
                tone: .attention, label: "No access", stamp: "Read \(time)",
                number: "\(unreadable.count)",
                lead: unreadable.count == 1 ? "folder could not be read" : "folders could not be read",
                note: "Its skills are missing from the count.",
                rows: unreadable.prefix(3).map {
                    .item(title: ($0.path as NSString).lastPathComponent,
                          detail: ($0.path as NSString).abbreviatingWithTildeInPath, data: "NO ACCESS")
                },
                buttons: [Button(title: "Open Privacy Settings", prominent: true, command: .privacySettings),
                          Button(title: "Library", prominent: false, command: .library)],
                hint: store.isScanning ? "Reading…" : "⌘R", hintEnabled: !store.isScanning)
        }

        let tracked = store.trackedCount
        let unknown = store.unknownCount
        let managed = store.managedCount
        let changed = store.localChangeCount
        let own = tracked + unknown
        let time = inventory.scannedAt.formatted(date: .omitted, time: .shortened)
        let folders = inventory.roots.filter { $0.state == .found }.count

        var rows: [Row] = []
        if changed > 0 {
            rows.append(.line(text: "\(changed) changed on this Mac", data: "SINCE INSTALL", muted: false))
        }
        if tracked > 0 {
            rows.append(.line(text: "\(tracked) \(tracked == 1 ? "has" : "have") a known source",
                              data: "\(folders) FOLDERS", muted: false))
        }
        if unknown > 0 {
            rows.append(.link(text: "\(unknown) \(unknown == 1 ? "has" : "have") no known source",
                              label: "Show", command: .library))
        }
        if own == 0 {
            rows.append(.link(text: "Skills in a project folder?", label: "Add folder", command: .addFolder))
        }

        return PanelModel(
            tone: own == 0 ? .quiet : .rest,
            label: "On this Mac",
            stamp: "Read \(time)",
            number: "\(own)",
            lead: own == 0 ? "skills on this Mac" : own == 1 ? "skill installed by you" : "skills installed by you",
            note: managed > 0 ? "\(managed) more are managed by apps" : "Looked in \(folders) folders.",
            rows: rows,
            buttons: [Button(title: "Library", prominent: true, command: .library),
                      Button(title: "Settings", prominent: false, command: .settings)],
            hint: store.isScanning ? "Reading…" : "Read again ⌘R",
            hintEnabled: !store.isScanning
        )
    }
}
