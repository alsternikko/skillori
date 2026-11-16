import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case yours
    /// The source has changed.
    case updates
    case upToDate
    /// Kept on the installed version by the reader.
    case heldBack
    /// Nobody can say whether these are current: no source, no answer, or not asked.
    case unverified
    case managed
    /// Not a list of skills: shows which folders were read.
    case coverage

    var id: String { rawValue }

    func includes(_ status: SkillStatus) -> Bool {
        switch self {
        case .yours: !status.isManaged
        case .updates:
            switch status {
            case .updateAvailable, .differs, .ownerUpdate: true
            default: false
            }
        case .upToDate: status == .upToDate
        case .heldBack: if case .heldBack = status { true } else { false }
        case .unverified: status.isUnverified
        case .managed: status.isManaged
        case .coverage: false
        }
    }
}

struct LibraryView: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: LibraryFilter
    @State private var selection: Installation.ID?
    @State private var showsDetail: Bool
    @State private var search = ""
    /// Groups the reader has opened.
    @State private var expanded: Set<String> = []
    /// The group the keyboard is on, when it is not on a skill.
    @State private var groupCursor: String?
    /// The skill whose source the reader is pointing out, while the sheet is up.
    @State private var linking: Installation?
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool

    init(initialFilter: LibraryFilter = .yours, initialSelection: Installation.ID? = nil, showsDetail: Bool = false,
         initialGroup: String? = nil, initialExpanded: Set<String> = []) {
        _expanded = State(initialValue: initialExpanded)
        _filter = State(initialValue: initialFilter)
        _selection = State(initialValue: initialSelection)
        _showsDetail = State(initialValue: showsDetail)
        _groupCursor = State(initialValue: initialGroup)
    }

    var body: some View {
        VStack(spacing: 6) {
            topBar
            if showsDetail, let installation = selected {
                // Count within the reader's own skills or within the apps' skills, not across both.
                let rows = groups.filter { ($0.kind == .managed) == isManaged(installation) }.flatMap(\.items)
                InstallationDetail(installation: installation,
                                   number: (rows.firstIndex { $0.id == installation.id } ?? 0) + 1,
                                   total: rows.count,
                                   readAt: store.inventory?.scannedAt,
                                   agentsOnThisMac: agentsOnThisMac,
                                   onBack: { showsDetail = false },
                                   onLink: { linking = installation },
                                   onStep: { step in _ = move(step, in: rows) })
            } else {
                if !store.checksEnabled, store.trackedCount > 0 { checksOffNotice }
                tiles
                listCard
            }
        }
        .padding(EdgeInsets(top: 0, leading: 6, bottom: 6, trailing: 6))
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .font(TypeRole.sans(13))
        .ignoresSafeArea(edges: .top)
        .onChange(of: filter) {
            selection = nil
            groupCursor = nil
        }
        .sheet(item: $linking) { installation in
            LinkSourceSheet(installation: installation).environment(store)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                SkilloriMark().fill(Palette.ink).frame(width: 18, height: 18)
                Text("Library").font(TypeRole.sans(13, .medium))
            }
            .frame(width: 110, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.ink2)
                TextField("Search skills, sources, paths", text: $search)
                    .textFieldStyle(.plain)
                    .font(TypeRole.sans(13))
                    .focused($searchFocused)
                    .onExitCommand {
                        search = ""
                        searchFocused = false
                    }
                LabelText("⌘F").foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .frame(maxWidth: 360)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .circular))

            Spacer(minLength: 8)

            LabelText(stamp).foregroundStyle(Palette.ink2)
            Button("Folders") { filter = filter == .coverage ? .yours : .coverage }
                .buttonStyle(PillButtonStyle(prominent: filter == .coverage))
            Button { Task { await store.refresh() } } label: {
                SwappingText(store.isScanning ? "Reading…" : store.isChecking ? "Checking…"
                    : store.checksEnabled ? "Check now" : "Read again")
            }
            .buttonStyle(PillButtonStyle())
            .keyboardShortcut("r")
            .disabled(store.isScanning || store.isChecking)
        }
        .padding(.leading, 78)
        .padding(.trailing, 8)
        .frame(height: 52)
        .background {
            Button("Search") { searchFocused = true }.keyboardShortcut("f").opacity(0).accessibilityHidden(true)
        }
    }

    private var stamp: String {
        guard let inventory = store.inventory else { return "Reading now" }
        guard store.checksEnabled else {
            return "Read \(inventory.scannedAt.formatted(date: .omitted, time: .shortened))"
        }
        return store.checkStamp
    }

    /// Shown until the reader has decided: the app's main job needs their yes.
    private var checksOffNotice: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Update checks are off").font(TypeRole.sans(13, .medium))
                Text("Skillori can ask each source whether a skill has changed. It sends the source's name and nothing about you or your files.")
                    .font(TypeRole.sans(12))
                    .foregroundStyle(Tone.quiet.secondary)
            }
            Spacer(minLength: 12)
            Button("Turn on") { store.checksEnabled = true }
                .buttonStyle(PillButtonStyle(prominent: true, on: .quiet))
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 12))
        .foregroundStyle(Tone.quiet.foreground)
        .background(Tone.quiet.background, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
    }

    // MARK: Tiles

    private var tiles: some View {
        HStack(spacing: 6) {
            tile(.yours, "Yours", "installed by you")
            tile(.updates, "Updates", updatesCaption, tone: updateUnits > 0 ? .new : nil)
            tile(.upToDate, "Up to date", "match their source")
            tile(.heldBack, "Held back", "kept by you")
            tile(.unverified, "Not verified", "can't be checked")
            tile(.managed, "From apps", "in \(store.pluginRecords.count) plugins")
        }
    }

    private func tile(_ item: LibraryFilter, _ label: String, _ caption: String, tone: Tone? = nil) -> some View {
        // Updates counts what can be updated: a skill of yours, or a whole plugin.
        let number = item == .updates ? updateUnits : count(item)
        return StatTile(label: label, number: store.inventory == nil ? "--" : "\(number)", caption: caption,
                        tone: tone, isSelected: filter == item) { filter = item }
    }

    /// Skills of yours with something new at their source, and plugins with a newer version.
    private var updateUnits: Int { store.updateCount + store.pluginUpdates.count }

    private var updatesCaption: String {
        let skills = store.updateCount
        let plugins = store.pluginUpdates.count
        guard plugins > 0 else { return "newer at the source" }
        guard skills > 0 else { return plugins == 1 ? "1 plugin" : "\(plugins) plugins" }
        return "\(skills) skill\(skills == 1 ? "" : "s") · \(plugins) plugin\(plugins == 1 ? "" : "s")"
    }

    private func count(_ item: LibraryFilter) -> Int {
        store.inventory?.installations.filter { item.includes(store.status(for: $0)) }.count ?? 0
    }

    // MARK: List

    private var listCard: some View {
        VStack(spacing: 6) {
            Group {
                if filter == .coverage {
                    CoverageView()
                } else {
                    table
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
            .clipShape(RoundedRectangle(cornerRadius: Radius.block, style: .circular))

            // The selected skill's actions are a fixed row under the list, never over it.
            if filter != .coverage, let installation = selected {
                actionBar(installation).transition(.opacity)
            } else if filter != .coverage, let (group, updatable) = cursorGroupWithUpdates {
                // A source under the cursor offers its updates in one go.
                groupBar(group, updatable: updatable).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.swap, value: selected?.id)
        .animation(reduceMotion ? nil : Motion.swap, value: groupCursor)
    }

    private var table: some View {
        let groups = groups
        let rows = groups.flatMap(\.items)
        let entries = entries(in: groups)
        let firstManaged = groups.first { $0.kind == .managed }?.id
        let lastOwn = groups.last { $0.kind != .managed }?.id
        let lastManaged = groups.last { $0.kind == .managed }?.id
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Column.number, height: 1)
                LabelText("Name").frame(maxWidth: .infinity, alignment: .leading)
                LabelText("Source").frame(width: Column.source, alignment: .leading)
                LabelText("Revision").frame(width: Column.revision, alignment: .leading)
                LabelText("Agents").frame(width: Column.agents, alignment: .leading)
                LabelText("Status").frame(width: Column.status, alignment: .leading)
            }
            .foregroundStyle(Palette.ink2)
            .frame(height: 36)
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
            .padding(.horizontal, 16)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            let open = isExpanded(group, among: groups)
                            let lastInSection = group.id == lastOwn || group.id == lastManaged
                            if group.id == groups.first?.id, group.kind != .managed, firstManaged != nil {
                                sectionHeader("Installed by you · \(count(.yours))", note: nil)
                            }
                            if group.id == firstManaged, filter != .managed {
                                sectionHeader("From your apps · \(count(.managed)) skills",
                                              note: "Each app updates its own")
                            }
                            branch(group, guides: [], isLast: lastInSection, among: groups)
                        }
                        if rows.isEmpty, store.inventory != nil { emptyState }
                        Color.clear.frame(height: selected == nil ? 8 : 64)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                }
                .onChange(of: selection) { _, new in
                    if let new { proxy.scrollTo(new) }
                }
                .onChange(of: groupCursor) { _, new in
                    if let new { proxy.scrollTo(new) }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(.downArrow) { move(1, in: entries) }
        .onKeyPress(.upArrow) { move(-1, in: entries) }
        .onKeyPress(.rightArrow) { setCursorGroup(open: true, among: groups) }
        .onKeyPress(.leftArrow) { setCursorGroup(open: false, among: groups) }
        .onKeyPress(.return) {
            if let id = groupCursor, let group = allGroups(groups).first(where: { $0.id == id }) {
                toggle(group, among: groups)
                return .handled
            }
            guard selected != nil else { return .ignored }
            showsDetail.toggle()
            return .handled
        }
        .onKeyPress(.escape) {
            guard selection != nil || groupCursor != nil else { return .ignored }
            if showsDetail { showsDetail = false } else { selection = nil; groupCursor = nil }
            return .handled
        }
    }

    /// One branch of the tree with what is open below it: branches inside it, or its skills.
    /// `guides` are the tree lines of the branches above it.
    private func branch(_ group: SkillGroup, guides: [TreeGuide.Branch], isLast: Bool, among groups: [SkillGroup]) -> AnyView {
        let open = isExpanded(group, among: groups)
        let below = guides + [isLast ? .none : .pipe]
        return AnyView(VStack(spacing: 0) {
            GroupRow(group: group, statuses: group.items.map(store.status(for:)),
                     guides: guides + [isLast ? .corner : .tee],
                     summary: summary(of: group),
                     isOpen: open, hasCursor: groupCursor == group.id)
                .id(group.id)
                .onTapGesture { toggle(group, among: groups) }
            if open {
                if group.children.isEmpty {
                    skillRows(group.items, guides: below)
                } else {
                    ForEach(group.children) { child in
                        branch(child, guides: below, isLast: child.id == group.children.last?.id, among: groups)
                    }
                }
            }
        })
    }

    /// The skills of one branch. `guides` are the tree lines of the branches above them.
    @ViewBuilder private func skillRows(_ items: [Installation], guides: [TreeGuide.Branch]) -> some View {
        ForEach(items) { installation in
            InstallationRow(installation: installation,
                            status: store.status(for: installation),
                            link: store.link(for: installation),
                            copies: store.copies(of: installation),
                            isSelected: installation.id == selection,
                            guides: guides,
                            isLast: installation.id == items.last?.id)
                .id(installation.id)
                // A single click selects at once; it does not wait to see
                // whether a second click follows.
                .onTapGesture {
                    groupCursor = nil
                    selection = installation.id == selection ? nil : installation.id
                    listFocused = true
                }
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    selection = installation.id
                    showsDetail = true
                })
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the skill's details")
                .accessibilityAction {
                    selection = installation.id
                    showsDetail = true
                }
        }
    }

    /// What an app or plugin branch says about its plugins, counted per plugin.
    private func summary(of group: SkillGroup) -> GroupRow.Summary {
        switch group.kind {
        case .managed:
            let plugins = Set(group.items.compactMap(\.plugin?.id))
            let updates = store.pluginUpdates.filter { plugins.contains($0.id) }.count
            return .app(plugins: plugins.count, updates: updates)
        case .plugin:
            guard let plugin = group.plugin else {
                return group.children.isEmpty ? .builtIn : .fold(group.app == "Codex" ? "Updated by Codex" : "Not checked")
            }
            let state = store.checksEnabled ? store.pluginReadings[plugin.id]?.state : nil
            return .plugin(plugin, state: state)
        case .source, .unknown:
            return .none
        }
    }

    // MARK: Groups

    /// The skills that match the filter and the search, gathered by where they come from:
    /// one group per source, one for skills with no known source, one per owning app.
    private var groups: [SkillGroup] {
        var order: [String] = []
        var byID: [String: SkillGroup] = [:]
        for installation in visible {
            let (id, title, kind): (String, String, SkillGroup.Kind) = switch installation.provenance {
            case .skillsLock(let source, _, _, _, _): ("source:" + source, source, .source)
            case .unknown:
                // A skill the reader linked sits with its source, like the ones the installer recorded.
                if let link = store.link(for: installation) {
                    ("source:" + link.source.name, link.source.name, .source)
                } else {
                    ("unknown", "No known source", .unknown)
                }
            case .managed(let owner):
                // One branch per app, whether a skill came with a plugin or with the app itself.
                ("managed:" + Self.app(of: installation, owner: owner), Self.app(of: installation, owner: owner), .managed)
            }
            if byID[id] == nil {
                byID[id] = SkillGroup(id: id, title: title, kind: kind, items: [])
                order.append(id)
            }
            byID[id]?.items.append(installation)
        }
        let updating = Set(store.pluginUpdates.map(\.id))
        func updates(_ group: SkillGroup) -> Int { Set(group.items.compactMap(\.plugin?.id)).intersection(updating).count }
        return order.compactMap { byID[$0] }.map { group in
            guard group.kind == .managed else { return group }
            var group = group
            group.app = group.title
            group.children = pluginBranches(of: group, updating: updating)
            return group
        }
        .sorted { a, b in
            if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
            // Among apps, the ones with something to update come first.
            if a.kind == .managed, updates(a) != updates(b) { return updates(a) > updates(b) }
            if a.items.count != b.items.count { return a.items.count > b.items.count }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    /// The product that owns a skill, by the name people know it by. The folder a skill was
    /// found in gives an owner such as "Cursor plugin" or "Claude app"; the reader thinks of
    /// Claude Code, Claude, Cursor and Codex.
    static func app(of installation: Installation, owner: String) -> String {
        if let app = installation.plugin?.app { return app }
        switch owner {
        case "Claude Code plugin", "claude.ai": return "Claude Code"
        case "Claude app", "Claude app plugin": return "Claude"
        default:
            for suffix in [" plugin", " extension"] where owner.hasSuffix(suffix) {
                return String(owner.dropLast(suffix.count))
            }
            return owner
        }
    }

    /// The name of the branch for skills that came with an app but not in a recorded plugin.
    private static func branchTitle(owner: String) -> String {
        switch owner {
        case "claude.ai": return "Synced from claude.ai"
        case "Claude app": return "From your Claude account"
        default: return owner.hasSuffix(" plugin") || owner.hasSuffix(" extension") ? "Plugins" : "Built in"
        }
    }

    /// Whether Skillori can ask anyone about this plugin. A plugin that ships with its app,
    /// or names no source, is the app's business alone.
    private static func isCheckable(_ plugin: PluginRecord) -> Bool {
        plugin.manifestPath == nil ? plugin.marketplaceRepository != nil : plugin.repository != nil
    }

    /// An app's skills in branches: one per plugin, plugins that can't be checked folded into
    /// one, and the app's own skills by where they came from. Plugins with an update first.
    private func pluginBranches(of app: SkillGroup, updating: Set<String>) -> [SkillGroup] {
        let byPlugin = Dictionary(grouping: app.items) { $0.plugin?.id ?? "" }
        var plugins: [SkillGroup] = byPlugin.compactMap { id, items in
            guard !id.isEmpty, let record = items.first?.plugin else { return nil }
            return SkillGroup(id: app.id + "/" + id, title: record.title, kind: .plugin, items: items,
                              plugin: record, app: app.title)
        }
        .sorted { a, b in
            let x = updating.contains(a.plugin!.id), y = updating.contains(b.plugin!.id)
            if x != y { return x }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        let quiet = plugins.filter { !Self.isCheckable($0.plugin!) }
        if quiet.count > 1 {
            plugins.removeAll { !Self.isCheckable($0.plugin!) }
            let title = app.title == "Codex" ? "\(quiet.count) plugins updated by Codex" : "\(quiet.count) plugins with no source to ask"
            plugins.append(SkillGroup(id: app.id + "/quiet", title: title, kind: .plugin,
                                      items: quiet.flatMap(\.items), children: quiet, app: app.title))
        }
        let rest = (byPlugin[""] ?? []).reduce(into: [String: [Installation]]()) { result, installation in
            if case .managed(let owner) = installation.provenance { result[Self.branchTitle(owner: owner), default: []].append(installation) }
        }
        let others = rest.keys.sorted { a, b in (a == "Built in") != (b == "Built in") ? b == "Built in" : a < b }.map { title in
            SkillGroup(id: app.id + "/" + title, title: title, kind: .plugin, items: rest[title]!, app: app.title)
        }
        // An app with nothing but its own skills needs no branch level.
        if plugins.isEmpty, others.count == 1 { return [] }
        return plugins + others
    }

    /// A group is open when the reader opened it, when it is the only one, while searching,
    /// or when it holds the selected skill.
    private func isExpanded(_ group: SkillGroup, among groups: [SkillGroup]) -> Bool {
        expanded.contains(group.id) || (groups.count == 1 && group.kind != .plugin) || !search.isEmpty
            || group.items.contains { $0.id == selection }
    }

    /// Every group, with the branches inside apps, in the order they are drawn.
    private func allGroups(_ groups: [SkillGroup]) -> [SkillGroup] {
        groups.flatMap { [$0] + allGroups($0.children) }
    }

    private func toggle(_ group: SkillGroup, among groups: [SkillGroup]) {
        let open = isExpanded(group, among: groups)
        withAnimation(reduceMotion ? nil : Motion.swap) {
            if open {
                expanded.remove(group.id)
                if group.items.contains(where: { $0.id == selection }) { selection = nil }
            } else {
                expanded.insert(group.id)
            }
        }
        groupCursor = group.id
        selection = open ? selection : nil
        listFocused = true
    }

    private func setCursorGroup(open: Bool, among groups: [SkillGroup]) -> KeyPress.Result {
        guard let id = groupCursor, let group = allGroups(groups).first(where: { $0.id == id }),
              isExpanded(group, among: groups) != open else { return .ignored }
        toggle(group, among: groups)
        return .handled
    }

    /// What the arrow keys step through: every group, and the skills of the open ones.
    private func entries(in groups: [SkillGroup]) -> [Entry] {
        entries(of: groups, among: groups)
    }

    private func entries(of branches: [SkillGroup], among groups: [SkillGroup]) -> [Entry] {
        branches.flatMap { group -> [Entry] in
            guard isExpanded(group, among: groups) else { return [.group(group.id)] }
            if group.children.isEmpty { return [.group(group.id)] + group.items.map { .skill($0.id) } }
            return [.group(group.id)] + entries(of: group.children, among: groups)
        }
    }

    private func move(_ step: Int, in entries: [Entry]) -> KeyPress.Result {
        guard !entries.isEmpty else { return .ignored }
        let here: Entry? = selection.map { .skill($0) } ?? groupCursor.map { .group($0) }
        let current = here.flatMap { entries.firstIndex(of: $0) }
        let next = current.map { min(max($0 + step, 0), entries.count - 1) } ?? (step > 0 ? 0 : entries.count - 1)
        // Keyboard moves are immediate: no animation on something pressed many times.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            switch entries[next] {
            case .group(let id): selection = nil; groupCursor = id
            case .skill(let id): groupCursor = nil; selection = id
            }
        }
        return .handled
    }

    /// Steps between skills in the detail view.
    private func move(_ step: Int, in rows: [Installation]) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.id == selection }
        let next = current.map { min(max($0 + step, 0), rows.count - 1) } ?? (step > 0 ? 0 : rows.count - 1)
        selection = rows[next].id
        return .handled
    }

    @ViewBuilder private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            let nothingAtAll = search.isEmpty && (store.inventory?.installations.isEmpty ?? false)
            Text(nothingAtAll ? "No skills on this Mac yet"
                 : search.isEmpty ? "Nothing here" : "No skill matches “\(search)”")
                .font(TypeRole.sans(15, .medium))
            Text(nothingAtAll ? "Skillori only reads the folders it knows about. Skills in a project folder?"
                 : search.isEmpty ? "No skill on this Mac fits this group."
                 : "Searched names, descriptions, sources and paths in \(count(filter)) skills.")
                .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
            if nothingAtAll {
                Button("Add folder") { store.addProject() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .padding(.top, 10)
            } else if !search.isEmpty {
                Button("Clear search") { search = "" }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 28)
    }

    /// The root of a tree: the reader's own skills, or the ones apps own.
    private func sectionHeader(_ title: String, note: String?) -> some View {
        HStack {
            LabelText(title).foregroundStyle(Palette.ink)
            Spacer()
            if let note { LabelText(note).foregroundStyle(Palette.ink2) }
        }
        .frame(height: 32)
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    // MARK: Selection

    /// The source under the cursor and those of its skills the installer can update now.
    private var cursorGroupWithUpdates: (SkillGroup, [Installation])? {
        guard let groupCursor, let group = groups.first(where: { $0.id == groupCursor }), group.kind == .source else { return nil }
        let updatable = group.items.filter { isUpdate(store.status(for: $0)) }
        return updatable.isEmpty ? nil : (group, updatable)
    }

    /// One press runs the installer's update for every skill of a source that has one.
    /// Skills the reader holds back are not among them.
    private func groupBar(_ group: SkillGroup, updatable: [Installation]) -> some View {
        let runner = store.updater
        let names = updatable.map(\.directoryName)
        let mine = runner.names == names
        let count = updatable.count
        var text = count == group.items.count
            ? "\(count) skill\(count == 1 ? " has" : "s have") an update at the source"
            : "\(count) of \(group.items.count) skills \(count == 1 ? "has" : "have") an update at the source"
        if mine, runner.isRunning { text = "Running the installer's update…" }
        if mine, case .failed(let why) = runner.phase { text = "The update did not finish. \(why)" }
        return StatusLine {
            Text(group.title).font(TypeRole.sans(13, .medium)).lineLimit(1)
            Text(text)
                .font(TypeRole.sans(12))
                .foregroundStyle(Tone.rest.secondary)
                .lineLimit(1)
                .padding(.leading, 6)
            Spacer(minLength: 10)
            Button(mine && runner.isRunning ? "Updating…" : "▶ Update \(count)") { Task { await store.update(updatable) } }
                .buttonStyle(PillButtonStyle(prominent: true, on: .rest))
                .disabled(runner.isRunning)
                .help(UpdateRunner.commandText(for: names))
        }
    }

    private func actionBar(_ installation: Installation) -> some View {
        let status = store.status(for: installation)
        return StatusLine {
            Text(installation.displayName).font(TypeRole.sans(13, .medium)).lineLimit(1)
            let runner = store.updater
            let mine = runner.names == [installation.directoryName]
            Text(barText(status, running: mine && runner.isRunning, failed: mine && isFailed(runner.phase)))
                .font(TypeRole.sans(12))
                .foregroundStyle(Tone.rest.secondary)
                .lineLimit(1)
                .padding(.leading, 6)
            Spacer(minLength: 10)
            if case .updateAvailable = status {
                // One press runs the installer's update for this skill.
                Button(mine && runner.isRunning ? "Updating…" : "▶ Update") { Task { await store.update([installation]) } }
                    .buttonStyle(PillButtonStyle(prominent: true, on: .rest))
                    .disabled(runner.isRunning)
                    .help(UpdateCommand.text(for: installation))
            }
            Button(showsDetail ? "Hide details" : "Details") { showsDetail.toggle() }
                .buttonStyle(PillButtonStyle(prominent: !isUpdate(status), on: .rest))
            switch status {
            case .updateAvailable:
                Button("Hold back") { store.hold(installation) }.buttonStyle(PillButtonStyle(on: .rest))
            case .heldBack:
                Button("Release") { store.release(installation) }.buttonStyle(PillButtonStyle(on: .rest))
            case .differs:
                if let link = store.upstreamSource(for: installation)?.webURL(subpath: store.sourceSubpath(for: installation)) {
                    Button("Open source") { NSWorkspace.shared.open(link) }.buttonStyle(PillButtonStyle(on: .rest))
                }
                Button("Hold back") { store.hold(installation) }.buttonStyle(PillButtonStyle(on: .rest))
            case .noSource:
                Button("Link source…") { linking = installation }.buttonStyle(PillButtonStyle(on: .rest))
            default:
                if let link = store.upstreamSource(for: installation)?.webURL() {
                    Button("Open source") { NSWorkspace.shared.open(link) }
                        .buttonStyle(PillButtonStyle(on: .rest))
                } else {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installation.canonicalPath)])
                    }
                    .buttonStyle(PillButtonStyle(on: .rest))
                }
            }
        }
    }

    private func isUpdate(_ status: SkillStatus) -> Bool {
        if case .updateAvailable = status { true } else { false }
    }

    private func isFailed(_ phase: UpdateRunner.Phase) -> Bool {
        if case .failed = phase { true } else { false }
    }

    private func barText(_ status: SkillStatus, running: Bool, failed: Bool) -> String {
        if running { return "Running the installer's update…" }
        if failed { return "The update did not finish. Open Details to see what it printed." }
        return status.sentence
    }

    private var agentsOnThisMac: [Agent] {
        Array(Set((store.inventory?.installations ?? []).flatMap(\.installedAgents))).sorted()
    }

    private var visible: [Installation] {
        let all = store.inventory?.installations ?? []
        let filtered = all.filter { filter.includes(store.status(for: $0)) || (filter == .yours && isManaged($0)) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        guard !search.isEmpty else { return filtered }
        return filtered.filter { installation in
            if installation.displayName.localizedCaseInsensitiveContains(search) { return true }
            if (installation.frontmatter.description ?? "").localizedCaseInsensitiveContains(search) { return true }
            if installation.canonicalPath.localizedCaseInsensitiveContains(search) { return true }
            switch installation.provenance {
            case .skillsLock(let source, _, _, _, _): return source.localizedCaseInsensitiveContains(search)
            case .managed(let owner): return owner.localizedCaseInsensitiveContains(search)
            case .unknown: return store.link(for: installation)?.source.name.localizedCaseInsensitiveContains(search) ?? false
            }
        }
    }

    private func isManaged(_ installation: Installation) -> Bool {
        if case .managed = installation.provenance { return true }
        return false
    }

    private var selected: Installation? {
        guard let selection else { return nil }
        return store.inventory?.installations.first { $0.id == selection }
    }
}

/// Skills that share an origin.
struct SkillGroup: Identifiable {
    /// `managed` is one app; `plugin` is one plugin of that app, or the app's own skills.
    enum Kind: Int { case source, unknown, managed, plugin }
    let id: String
    let title: String
    let kind: Kind
    var items: [Installation]
    /// For an app: one branch per plugin, and one for what the app ships itself.
    var children: [SkillGroup] = []
    /// For a plugin branch: what its app recorded about it.
    var plugin: PluginRecord? = nil
    /// For an app and its branches: the app's name.
    var app: String? = nil

    @MainActor var agents: Set<Agent> { Set(items.flatMap(\.installedAgents)) }
    var changed: Int {
        items.filter { if case .skillsLock(_, _, _, _, .modified) = $0.provenance { true } else { false } }.count
    }
}

private enum Entry: Equatable {
    case group(String)
    case skill(Installation.ID)
}

/// One line per level of the tree, drawn as real lines so they join from row to row.
private struct TreeGuide: Shape {
    enum Branch { case none, pipe, tee, corner }
    var branches: [Branch]
    static let first: CGFloat = 7
    static let step: CGFloat = 22
    static let stub: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (level, branch) in branches.enumerated() {
            let x = rect.minX + Self.first + CGFloat(level) * Self.step + 0.5
            let mid = rect.midY.rounded() + 0.5
            switch branch {
            case .none: continue
            case .pipe:
                path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
            case .tee:
                path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
                path.move(to: CGPoint(x: x, y: mid)); path.addLine(to: CGPoint(x: x + Self.stub, y: mid))
            case .corner:
                path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: mid))
                path.addLine(to: CGPoint(x: x + Self.stub, y: mid))
            }
        }
        return path
    }
}

/// A branch of the tree: where a set of skills comes from, how many there are, and a
/// plus or minus that opens it one level further.
private struct GroupRow: View {
    /// What a branch of apps' skills has to say about plugins, counted per plugin.
    enum Summary {
        case none
        case app(plugins: Int, updates: Int)
        case plugin(PluginRecord, state: UpstreamState?)
        case builtIn
        /// Plugins nobody can be asked about, folded into one branch.
        case fold(String)
    }

    let group: SkillGroup
    /// The status of each skill in the group.
    let statuses: [SkillStatus]
    /// The tree lines of the branches above this one, and this branch's own as the last.
    let guides: [TreeGuide.Branch]
    let summary: Summary
    let isOpen: Bool
    let hasCursor: Bool
    @State private var hovering = false

    var body: some View {
        let depth = CGFloat(guides.count - 1)
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                // An open branch sends a line down from its sign to its skills.
                TreeGuide(branches: guides).stroke(Palette.ink2, lineWidth: 1)
                if isOpen {
                    TreeGuide(branches: Array(repeating: .none, count: guides.count) + [.pipe]).stroke(Palette.ink2, lineWidth: 1)
                        .mask(alignment: .bottom) { Rectangle().frame(height: 12) }
                }
                DataText(isOpen ? "−" : "+")
                    .foregroundStyle(Palette.ink)
                    .frame(width: 14)
                    .offset(x: TreeGuide.first + TreeGuide.step * CGFloat(guides.count) - 7)
            }
            .frame(width: Column.number + depth * TreeGuide.step)
            .frame(maxHeight: .infinity)
            Text(group.title).font(TypeRole.sans(13, .medium)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            DataText("\(group.items.count) skill\(group.items.count == 1 ? "" : "s")")
                .foregroundStyle(Palette.ink2)
                .frame(width: Column.source, alignment: .leading)
            DataText(note)
                .foregroundStyle(noteIsData ? Palette.ink2 : Palette.ink3)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Column.revision, alignment: .leading)
            TickCount(group.agents.count, unit: group.agents.count == 1 ? "agent" : "agents")
                .frame(width: Column.agents, alignment: .leading)
                .help(group.agents.sorted().map(\.displayName).joined(separator: ", "))
            chip.frame(width: Column.status, alignment: .leading)
        }
        .frame(height: 40)
        .padding(.horizontal, 10)
        .background(Palette.ink.opacity(hovering || hasCursor ? 0.04 : 0),
                    in: RoundedRectangle(cornerRadius: Radius.row, style: .circular))
        .overlay {
            if hasCursor {
                RoundedRectangle(cornerRadius: Radius.row, style: .circular).strokeBorder(Palette.ink.opacity(0.28), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOpen ? "Open" : "Closed")
    }

    private var note: String {
        switch summary {
        case .app(let plugins, _) where plugins > 0: return "\(plugins) plugin\(plugins == 1 ? "" : "s")"
        case .plugin(let plugin, let state):
            let installed = plugin.version ?? plugin.commit.map { String($0.prefix(7)) } ?? "?"
            guard case .updateAvailable(let latest) = state else { return installed }
            // A version reads as one; a tree id only says that something is newer.
            return Self.isVersion(latest) ? "\(installed) → \(latest)" : "\(installed) → newer"
        default:
            switch group.kind {
            case .source: return ""
            case .unknown: return "not linked"
            case .managed, .plugin: return "set by the app"
            }
        }
    }

    private var noteIsData: Bool {
        if case .plugin = summary { return true }
        if case .app(let plugins, _) = summary, plugins > 0 { return true }
        return false
    }

    static func isVersion(_ text: String) -> Bool {
        text.count < 24 && text.contains(".") && !(text.count == 40 && text.allSatisfy(\.isHexDigit))
    }

    /// What the branch says about its skills: the state that most needs a look comes first.
    @ViewBuilder private var chip: some View {
        let updates = statuses.filter { if case .updateAvailable = $0 { true } else { false } }.count
        let differing = statuses.filter { if case .differs = $0 { true } else { false } }.count
        let held = statuses.filter { if case .heldBack = $0 { true } else { false } }.count
        let cant = statuses.filter { if case .cantCheck = $0 { true } else { false } }.count
        switch group.kind {
        case .unknown: StatusBadge(status: .noSource)
        case .managed, .plugin:
            switch summary {
            case .app(_, let updates) where updates > 0:
                StatusChip("\(updates) plugin update\(updates == 1 ? "" : "s")", kind: .new, mark: "▲")
            case .plugin(let plugin, .updateAvailable?):
                StatusChip("Update in \(plugin.app)", kind: .new, mark: "▲")
            case .plugin(_, .upToDate?):
                StatusBadge(status: .upToDate)
            case .fold(let text):
                StatusChip(text, mark: "■")
            default:
                StatusBadge(status: .managed)
            }
        case .source:
            if updates > 0 {
                StatusChip("\(updates) update\(updates == 1 ? "" : "s")", kind: .new, mark: "▲")
            } else if differing > 0 {
                StatusChip("\(differing) differ\(differing == 1 ? "s" : "")", kind: .new, mark: "≠")
            } else if group.changed > 0 {
                StatusChip("\(group.changed) changed here", kind: .attention, mark: "◐")
            } else if cant > 0 {
                StatusChip("Can't check", kind: .outline, mark: "✕")
            } else if held > 0 {
                StatusChip("\(held) held back", mark: "◆")
            } else if statuses.contains(.notChecked) {
                StatusBadge(status: .notChecked)
            } else {
                StatusBadge(status: .upToDate)
            }
        }
    }
}

private enum Column {
    static let number: CGFloat = 44
    static let source: CGFloat = 190
    static let revision: CGFloat = 160
    static let agents: CGFloat = 96
    static let status: CGFloat = 158
}

private struct InstallationRow: View {
    let installation: Installation
    let status: SkillStatus
    /// Set when the reader, not the installer, said where this skill comes from.
    let link: SourceLink?
    let copies: InventoryStore.Copies?
    let isSelected: Bool
    /// The tree lines of the branches this skill hangs from.
    let guides: [TreeGuide.Branch]
    /// The last skill of its branch.
    let isLast: Bool
    @State private var hovering = false

    var body: some View {
        let strong = isSelected ? Tone.rest.foreground : Palette.ink
        let quiet = isSelected ? Tone.rest.foreground.opacity(0.72) : Palette.ink2
        let faint = isSelected ? Tone.rest.secondary : Palette.ink3
        HStack(spacing: 0) {
            TreeGuide(branches: guides + [isLast ? .corner : .tee])
                .stroke(isSelected ? quiet : Palette.ink2, lineWidth: 1)
                .frame(width: Column.number + 6 + CGFloat(guides.count - 1) * TreeGuide.step)
                .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                Text(installation.displayName).font(TypeRole.sans(13, .medium)).lineLimit(1)
                switch copies {
                case .identical(let count):
                    Text("· \(count) identical copies").foregroundStyle(quiet).lineLimit(1).layoutPriority(-1)
                        .help("The same name and the same files in \(count) folders.")
                case .different(let count):
                    Text("· \(count) versions").foregroundStyle(Palette.ink).lineLimit(1).layoutPriority(-1)
                        .help("\(count) folders have a skill with this name, and their files differ. An agent may load another one than you think.")
                case nil:
                    EmptyView()
                }
                if !installation.frontmatter.problems.isEmpty {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(quiet)
                        .help(installation.frontmatter.problems.joined(separator: "\n"))
                        .accessibilityLabel("Has validation problems")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DataText(source.text).truncationMode(.middle)
                .foregroundStyle(source.known ? quiet : faint)
                .frame(width: Column.source - 12, alignment: .leading)
                .padding(.trailing, 12)
            DataText(revision.text)
                .foregroundStyle(revision.known ? quiet : faint)
                .frame(width: Column.revision, alignment: .leading)
            TickCount(installation.installedAgents.count, unit: installation.installedAgents.count == 1 ? "agent" : "agents")
                .foregroundStyle(strong)
                .frame(width: Column.agents, alignment: .leading)
                .help(installation.installedAgents.map(\.displayName).joined(separator: ", "))
            StatusBadge(status: status)
                .frame(width: Column.status, alignment: .leading)
        }
        .foregroundStyle(strong)
        .frame(height: 34)
        .padding(.horizontal, 10)
        .background(isSelected ? Tone.rest.background : Palette.ink.opacity(hovering ? 0.04 : 0),
                    in: RoundedRectangle(cornerRadius: Radius.row, style: .circular))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var source: (text: String, known: Bool) {
        switch installation.provenance {
        // The branch already names the source; the skill shows where in it the skill lives.
        case .skillsLock(let source, _, let subpath, _, _): (subpath ?? source, true)
        case .managed(let owner): (owner, true)
        case .unknown:
            if let link { (link.subpath.isEmpty ? "top level" : link.subpath, true) } else { ("not linked", false) }
        }
    }

    private var revision: (text: String, known: Bool) {
        if case .updateAvailable(let upstream) = status,
           case .skillsLock(_, _, _, let baseline?, _) = installation.provenance {
            return ("\(baseline.prefix(7)) → \(upstream.prefix(7))", true)
        }
        if let local = link?.localHash {
            if case .differs(let upstream) = status { return ("\(local.prefix(7)) ≠ \(upstream.prefix(7))", true) }
            return (String(local.prefix(7)), true)
        }
        return switch installation.provenance {
        case .skillsLock(_, _, _, let baseline?, .modified(let local)):
            ("\(baseline.prefix(7)) → \(local.prefix(7))", true)
        case .skillsLock(_, _, _, let baseline?, _): (String(baseline.prefix(7)), true)
        case .skillsLock: ("no baseline", false)
        case .managed: ("set by the app", false)
        case .unknown: ("no baseline", false)
        }
    }
}

private extension String {
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}
