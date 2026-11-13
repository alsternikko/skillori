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

    enum Command { case library, settings, addFolder, rescan, privacySettings, enableChecks }

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
    var scale: ScaleReading?
    /// Skills the installer can update now; the panel shows the command that does it.
    var updatable: [Installation] = []
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
        PanelSurface {
            HeroBlock(tone: model.tone, label: model.label, stamp: model.stamp, number: model.number,
                      dimmed: model.dimmed, lead: model.lead, note: model.note, scale: model.scale)
            if !model.rows.isEmpty {
                PlainList {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, isLast: index == model.rows.count - 1)
                    }
                }
            }
            if !model.updatable.isEmpty {
                CommandFrame(installations: model.updatable, compact: true).padding(.top, 6)
            }
            HStack(spacing: 6) {
                ForEach(model.buttons) { button in
                    Button(button.title) { run(button.command) }
                        .buttonStyle(PillButtonStyle(prominent: button.prominent))
                }
                Spacer(minLength: 8)
                Button { run(model.hintCommand) } label: {
                    // The shortcut is drawn as a key, the words before it as text.
                    let key = "⌘R"
                    if model.hint.hasSuffix(key) {
                        HStack(spacing: 6) {
                            let words = model.hint.dropLast(key.count).trimmingCharacters(in: .whitespaces)
                            if !words.isEmpty { SwappingText(words) }
                            KeyCap(key)
                        }
                    } else {
                        SwappingText(model.hint)
                    }
                }
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
            ListRow(isLast: isLast, tree: true) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(TypeRole.sans(13, .medium)).lineLimit(1)
                    DataText(detail).foregroundStyle(Palette.ink2)
                }
            } trailing: {
                DataText(data).foregroundStyle(Palette.ink2)
            }
        case let .line(text, data, muted):
            ListRow(isLast: isLast, tree: true) {
                Text(text).foregroundStyle(muted ? Palette.ink2 : Palette.ink).lineLimit(1)
            } trailing: {
                DataText(data).foregroundStyle(Palette.ink2)
            }
        case let .link(text, label, command):
            ListRow(isLast: isLast, tree: true) {
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
        case .enableChecks: store.checksEnabled = true
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
        let busy = store.isScanning || store.isChecking
        let hint = store.isScanning ? "Reading…" : store.isChecking ? "Checking…"
            : store.checksEnabled ? "Check now ⌘R" : "Read again ⌘R"
        let buttons = [Button(title: "Library", prominent: true, command: .library),
                       Button(title: "Settings", prominent: false, command: .settings)]

        // Rows that say the same thing whatever the block shows.
        var tail: [Row] = []
        if store.heldCount > 0 {
            tail.append(.line(text: "\(store.heldCount) held back", data: "BY YOU", muted: false))
        }
        if store.cantCheckCount > 0 {
            // Say why when there is one reason; the library has the rest.
            let reasons = store.cantCheckReasons
            let why = reasons.count == 1 ? reasons.first!.short.uppercased() : "SEE LIBRARY"
            tail.append(.line(text: "\(store.cantCheckCount) can't be checked", data: why, muted: true))
        }
        if unknown > 0 {
            tail.append(.link(text: "\(unknown) \(unknown == 1 ? "has" : "have") no known source",
                              label: "Show", command: .library))
        }

        // Something new at a source is the first thing the panel says.
        let updates = store.updates
        if store.checksEnabled, !updates.isEmpty {
            var rows: [Row] = updates.prefix(3).map { installation in
                var data = ""
                let source = store.upstreamSource(for: installation)?.name ?? ""
                switch store.status(for: installation) {
                case .updateAvailable(let upstream):
                    if case .skillsLock(_, _, _, let baseline, _) = installation.provenance {
                        data = "\((baseline ?? "").prefix(7)) → \(upstream.prefix(7))"
                    }
                case .differs(let upstream):
                    data = "\((store.link(for: installation)?.localHash ?? "").prefix(7)) ≠ \(upstream.prefix(7))"
                default: break
                }
                return .item(title: installation.displayName, detail: source, data: data)
            }
            if updates.count > 3 {
                rows.append(.line(text: "\(updates.count - 3) more", data: "", muted: true))
            }
            return PanelModel(
                tone: .new, label: "Updates", stamp: store.checkStamp,
                number: "\(updates.count)",
                // "Differs" is true of both kinds: a known update and a linked skill with other content.
                lead: updates.count == 1 ? "skill differs from its source" : "skills differ from their source",
                note: "of the \(tracked) with a known source",
                scale: ScaleReading(part: updates.count, whole: tracked,
                                    partLabel: "\(updates.count) differ\(updates.count == 1 ? "s" : "")", wholeLabel: "\(tracked) tracked"),
                updatable: store.updatable,
                rows: rows + tail,
                // The command frame is the main action here, so no button competes with it.
                buttons: store.updatable.isEmpty ? buttons : buttons.map { Button(title: $0.title, prominent: false, command: $0.command) },
                hint: hint, hintEnabled: !busy)
        }

        var rows: [Row] = []
        if changed > 0 {
            rows.append(.line(text: "\(changed) changed on this Mac", data: "SINCE INSTALL", muted: false))
        }
        if store.checksEnabled {
            if store.upToDateCount > 0 {
                rows.append(.line(text: "\(store.upToDateCount) up to date", data: store.checkStamp.uppercased(), muted: false))
            } else if tracked > 0 {
                rows.append(.line(text: "\(tracked) \(tracked == 1 ? "has" : "have") a known source",
                                  data: store.checkStamp.uppercased(), muted: false))
            }
        } else if tracked > 0 {
            rows.append(.line(text: "\(tracked) \(tracked == 1 ? "has" : "have") a known source",
                              data: "\(folders) FOLDERS", muted: false))
            rows.append(.link(text: "Update checks are off", label: "Turn on", command: .enableChecks))
        }
        rows += tail
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
            scale: own > 0 && managed > 0
                ? ScaleReading(part: own, whole: own + managed, partLabel: "\(own) yours", wholeLabel: "\(own + managed) on this Mac")
                : nil,
            rows: rows,
            buttons: buttons,
            hint: hint,
            hintEnabled: !busy
        )
    }
}
