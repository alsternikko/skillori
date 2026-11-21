import SkilloriCore
import SkilloriUI
import SwiftUI

/// What the panel can ask the app to do. The panel lives in an AppKit window, so it gets
/// these instead of SwiftUI's scene actions.
struct PanelActions {
    var openLibrary: () -> Void = {}
    /// Opens the library at one skill's page, by installation id.
    var openSkill: (String) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var addFolder: () -> Void = {}
    var rescan: () -> Void = {}
    var openPrivacySettings: () -> Void = {}
    /// Set by the window that shows the panel: it follows the content's height, which arrives here.
    var contentHeightChanged: ((CGFloat) -> Void)?
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

    enum Command { case library, skill(String), settings, addFolder, rescan, privacySettings, enableChecks, installAppUpdate }

    /// The skills of one source that differ from it: one row with the command that updates them
    /// all under it. Open, it also lists the skills, each with its own run button.
    struct UpdateGroup: Identifiable {
        struct Item: Identifiable {
            let title: String
            let data: String
            /// Set when the installer can update this skill now.
            var installation: Installation?
            /// Tells apart skills with the same name, such as two copies in different folders.
            var key: String = ""
            var id: String { key.isEmpty ? title : key }
        }

        /// The source's name.
        let title: String
        let items: [Item]
        /// The skills the installer can update now. Empty when the group only differs.
        var updatable: [Installation] = []
        /// Mono caps to the right of the name, such as "18 UPDATES".
        let count: String
        var id: String { title }
    }

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
    /// What differs from its source, one group per source. They come before `rows`.
    var groups: [UpdateGroup] = []
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
    /// The sources whose skills are listed. A source is closed until the reader opens it.
    @State private var opened: Set<String>

    init(actions: PanelActions = PanelActions(), fixedModel: PanelModel? = nil, opened: Set<String> = []) {
        self.actions = actions
        self.fixedModel = fixedModel
        _opened = State(initialValue: opened)
    }

    var body: some View {
        let model = fixedModel ?? PanelModel.live(from: store)
        PanelSurface(reportHeight: actions.contentHeightChanged) {
            HeroBlock(tone: model.tone, label: model.label, stamp: model.stamp, number: model.number,
                      dimmed: model.dimmed, lead: model.lead, note: model.note, scale: model.scale)
            if !model.groups.isEmpty || !model.rows.isEmpty {
                PlainList {
                    ForEach(model.groups) { group in
                        groupView(group, isLast: model.rows.isEmpty && group.id == model.groups.last?.id)
                    }
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

    // MARK: Sources with updates

    /// How many skills an open source shows before its list scrolls.
    private static let openRows = 7
    private static let itemHeight: CGFloat = 26

    @ViewBuilder
    private func groupView(_ group: PanelModel.UpdateGroup, isLast: Bool) -> some View {
        let runner = store.updater
        let names = Set(group.updatable.map(\.directoryName))
        // A run of the whole source or of one of its skills.
        let running = runner.isRunning && !runner.names.isEmpty && Set(runner.names).isSubset(of: names)
        let open = opened.contains(group.id)
        let hasCommand = !group.updatable.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            // The row is the same open and closed, so nothing in it moves when the list appears.
            ListRow(isLast: isLast && !open && !hasCommand, tree: true, rule: false) {
                Button {
                    if open { opened.remove(group.id) } else { opened.insert(group.id) }
                } label: {
                    HStack(spacing: 8) {
                        DataText(open ? "−" : "+").frame(width: 8)
                        Text(group.title).font(TypeRole.sans(13, .medium)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        DataText(running ? "UPDATING…" : group.count).foregroundStyle(Palette.ink2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.title), \(group.count.lowercased())")
                .accessibilityValue(open ? "Open" : "Closed")
            } trailing: {
                EmptyView()
            }
            if open {
                let list = VStack(spacing: 0) {
                    ForEach(group.items) { item in itemRow(item, reservesButton: hasCommand) }
                }
                Group {
                    if group.items.count > Self.openRows {
                        // Half a row shows at the bottom edge, which says the list goes on.
                        ScrollView { list }.frame(height: (CGFloat(Self.openRows) + 0.5) * Self.itemHeight)
                    } else {
                        list
                    }
                }
                // The list starts under the source's name.
                .padding(EdgeInsets(top: 0, leading: 46, bottom: hasCommand ? 8 : 6, trailing: 10))
                .padding(.top, -4)
            }
            if hasCommand {
                // The command for the whole source, as wide as the block above the list.
                CommandFrame(installations: group.updatable, compact: true)
                    .padding(.top, open ? 0 : -2)
                    .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .bottom) { ListRule() }
    }

    private func itemRow(_ item: PanelModel.UpdateGroup.Item, reservesButton: Bool) -> some View {
        HStack(spacing: 8) {
            Text(item.title).font(TypeRole.sans(13)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 2)
            // The revision is the data; a long name gives way to it.
            DataText(item.data).foregroundStyle(Palette.ink2).fixedSize()
            if let installation = item.installation {
                Button("▶") { Task { await store.update([installation]) } }
                    .buttonStyle(IconButtonStyle(ghost: true))
                    .disabled(store.updater.isRunning)
                    .help(store.updateCommandText(for: [installation]))
                    .accessibilityLabel("Update \(item.title)")
            } else if reservesButton {
                // Keeps the revisions in one column when some skills here cannot be updated.
                Color.clear.frame(width: 22, height: 1)
            }
        }
        .frame(height: Self.itemHeight)
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
        case .skill(let id): actions.openSkill(id)
        case .settings: actions.openSettings()
        case .addFolder: actions.addFolder()
        case .rescan: actions.rescan()
        case .privacySettings: actions.openPrivacySettings()
        case .enableChecks: store.checksEnabled = true
        case .installAppUpdate: AppUpdater.shared.install()
        }
    }
}

extension PanelModel {
    /// The panel for the inventory, with a line about Skillori itself on top of the list when
    /// a newer version is out or on its way in.
    @MainActor
    static func live(from store: InventoryStore) -> PanelModel {
        var model = skills(from: store)
        if let row = appUpdateRow(AppUpdater.shared) { model.rows.insert(row, at: 0) }
        return model
    }

    /// Skillori's own update, as one row. Nothing when there is nothing new: settings has the rest.
    @MainActor
    static func appUpdateRow(_ updates: AppUpdater) -> Row? {
        switch updates.phase {
        case let .available(version, _):
            .link(text: "Skillori \(version) is out", label: "Install", command: .installAppUpdate)
        case let .downloading(version, fraction):
            .line(text: "Downloading Skillori \(version)", data: fraction.map { "\(Int($0 * 100))%" } ?? "…", muted: false)
        case let .preparing(version):
            .line(text: "Downloading Skillori \(version)", data: "CHECKING", muted: false)
        case let .installing(version):
            .line(text: "Installing Skillori \(version)", data: "RESTARTING", muted: false)
        default:
            nil
        }
    }

    /// How many sources with updates the panel lists before it points to the library.
    static let maxGroups = 5

    /// The panel for what the app can truthfully say today: a local reading. Skillori does
    /// not ask sources about changes yet (backlog, etapp 2), so this never claims "in sync".
    @MainActor
    static func skills(from store: InventoryStore) -> PanelModel {
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
        let pluginUpdates = store.pluginUpdates
        if !pluginUpdates.isEmpty {
            // Claude Code plugins, which the library can update.
            let text = pluginUpdates.count == 1 ? "\(pluginUpdates[0].title) has a plugin update"
                : "\(pluginUpdates.count) plugins have updates"
            tail.append(.link(text: text + " in Claude Code", label: "Show", command: .library))
        }
        let moved = store.codexMoved
        if !moved.isEmpty {
            // Codex plugins Codex no longer reads; the library opens each one's page in Codex.
            let text = moved.count == 1 ? "Codex no longer loads \(moved[0].plugin.title)" : "Codex no longer loads \(moved.count) plugins"
            tail.append(.link(text: text, label: "Show", command: .library))
        }
        if store.heldCount > 0 {
            tail.append(.line(text: "\(store.heldCount) held back", data: "BY YOU", muted: false))
        }
        // A recorded source that is gone has a way on, from the skill's page: link a new one,
        // look for it, or keep the copy as local.
        let lost = store.lostSources
        if let first = lost.first {
            let one: String = switch store.lostSource(of: first) {
            case .folderGone: "\(first.displayName) is gone from its source"
            case .unsupported: "\(first.displayName)’s source can’t be asked"
            case .noBaseline: "\(first.displayName) has nothing to compare with"
            default: "\(first.displayName)’s source is gone"
            }
            let text = lost.count > 1 ? "\(lost.count) skills’ sources are gone" : one
            tail.append(.link(text: text, label: "Show", command: lost.count == 1 ? .skill(first.id) : .library))
        }
        let (unchecked, reasons) = store.unansweredCantCheck
        if unchecked > 0 {
            // Say why when there is one reason; the library has the rest.
            let why = reasons.count == 1 ? reasons.first!.short.uppercased() : "SEE LIBRARY"
            tail.append(.line(text: "\(unchecked) can't be checked", data: why, muted: true))
        }
        let versions = store.differingCopyNames
        if !versions.isEmpty {
            // The same name in two folders with other files: an agent may load either one.
            let text = versions.count == 1 ? "\(versions[0]) exists in more than one version"
                : "\(versions.count) skills exist in different versions"
            tail.append(.link(text: text, label: "Show", command: .library))
        }
        if unknown > 0 {
            tail.append(.link(text: "\(unknown) \(unknown == 1 ? "has" : "have") no known source",
                              label: "Show", command: .library))
        }

        // Something new at a source is the first thing the panel says.
        let updates = store.updates
        if store.checksEnabled, !updates.isEmpty {
            // One group per source, the one with most to say first.
            var bySource: [String: [Installation]] = [:]
            for installation in updates {
                bySource[store.upstreamSource(for: installation)?.name ?? "", default: []].append(installation)
            }
            let groups: [UpdateGroup] = bySource.map { source, members in
                let members = members.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                let updatable = members.filter { if case .updateAvailable = store.status(for: $0) { true } else { false } }
                // The row has room for a name, one revision and a button: the one at the source.
                // Both revisions are in the library.
                let items = members.map { installation -> UpdateGroup.Item in
                    switch store.status(for: installation) {
                    case .updateAvailable(let upstream):
                        UpdateGroup.Item(title: installation.displayName, data: "→ \(upstream.prefix(7))", installation: installation,
                                         key: installation.id)
                    case .differs(let upstream):
                        UpdateGroup.Item(title: installation.displayName, data: "≠ \(upstream.prefix(7))", key: installation.id)
                    default:
                        UpdateGroup.Item(title: installation.displayName, data: "", key: installation.id)
                    }
                }
                // "Updates" when the installer can fetch them all; otherwise the word that is true of every one.
                let count = updatable.count == members.count
                    ? "\(members.count) UPDATE\(members.count == 1 ? "" : "S")"
                    : "\(members.count) DIFFER\(members.count == 1 ? "S" : "")"
                return UpdateGroup(title: source.isEmpty ? "Unknown source" : source, items: items, updatable: updatable, count: count)
            }
            .sorted { a, b in
                a.items.count != b.items.count ? a.items.count > b.items.count
                    : a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
            // Each source takes a row and a command, so the panel lists the largest few and
            // leaves the rest to the library, where there is room. It stays on screen that way.
            let shown = Array(groups.prefix(Self.maxGroups))
            let hidden = groups.dropFirst(Self.maxGroups)
            var tail = tail
            if !hidden.isEmpty {
                let skills = hidden.reduce(0) { $0 + $1.items.count }
                tail.insert(.link(text: "\(hidden.count) more source\(hidden.count == 1 ? "" : "s"), \(skills) skill\(skills == 1 ? "" : "s")",
                                  label: "Open library", command: .library), at: 0)
            }
            return PanelModel(
                tone: .new, label: "Updates", stamp: store.checkStamp,
                number: "\(updates.count)",
                // "Differs" is true of both kinds: a known update and a linked skill with other content.
                lead: updates.count == 1 ? "skill differs from its source" : "skills differ from their source",
                note: "of the \(tracked) with a known source",
                scale: ScaleReading(part: updates.count, whole: tracked,
                                    partLabel: "\(updates.count) differ\(updates.count == 1 ? "s" : "")", wholeLabel: "\(tracked) tracked"),
                groups: shown,
                rows: tail,
                // Running the update is the main action here, so no button competes with it.
                buttons: store.updatable.isEmpty ? buttons : buttons.map { Button(title: $0.title, prominent: false, command: $0.command) },
                hint: hint, hintEnabled: !busy)
        }

        // The sources did not answer, so whatever the statuses say is from the last time they did.
        if store.isStale, let reason = store.lastProblem {
            var rows: [Row] = [.line(text: "Last attempt", data: reason.short.uppercased(), muted: true)]
            if let last = store.lastCheck {
                rows.append(.line(text: "Statuses shown are from", data: InventoryStore.stamp(last).uppercased(), muted: true))
            }
            // A source that said how long to wait: trying before then only lengthens the wait.
            let waiting = store.isWaiting
            if waiting, let until = store.waitUntil {
                rows.append(.line(text: "Skillori asks again at", data: InventoryStore.stamp(until).uppercased(), muted: true))
            }
            rows += tail
            return PanelModel(
                tone: .attention, label: reason == .rateLimited ? "Asked to wait" : "No contact",
                stamp: store.checkStamp, number: "\(tracked)", dimmed: true,
                lead: tracked == 1 ? "source could not be asked" : "sources could not be asked",
                note: store.lastCheck == nil ? "No status yet." : "The statuses are older than they look.",
                rows: rows,
                buttons: waiting ? [Button(title: "Library", prominent: false, command: .library)]
                    : [Button(title: "Try again", prominent: true, command: .rescan),
                       Button(title: "Library", prominent: false, command: .library)],
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
