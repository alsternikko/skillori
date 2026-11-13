import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case yours
    case tracked
    case localChanges
    case unknown
    case managed
    /// Not a list of skills: shows which folders were read.
    case coverage

    var id: String { rawValue }

    func includes(_ installation: Installation) -> Bool {
        switch (self, installation.provenance) {
        case (.yours, .skillsLock), (.yours, .unknown): true
        case (.tracked, .skillsLock): true
        case (.localChanges, .skillsLock(_, _, _, _, .modified)): true
        case (.unknown, .unknown): true
        case (.managed, .managed): true
        default: false
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
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool

    init(initialFilter: LibraryFilter = .yours, initialSelection: Installation.ID? = nil, showsDetail: Bool = false) {
        _filter = State(initialValue: initialFilter)
        _selection = State(initialValue: initialSelection)
        _showsDetail = State(initialValue: showsDetail)
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
                                   onStep: { step in _ = move(step, in: rows) })
            } else {
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
            .background(Palette.card, in: Capsule())

            Spacer(minLength: 8)

            LabelText(stamp).foregroundStyle(Palette.ink2)
            Button("Folders") { filter = filter == .coverage ? .yours : .coverage }
                .buttonStyle(PillButtonStyle(prominent: filter == .coverage))
            Button { Task { await store.rescan() } } label: {
                SwappingText(store.isScanning ? "Reading…" : "Read again")
            }
            .buttonStyle(PillButtonStyle())
            .keyboardShortcut("r")
            .disabled(store.isScanning)
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
        return "Read \(inventory.scannedAt.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: Tiles

    private var tiles: some View {
        HStack(spacing: 6) {
            tile(.yours, "Yours", "installed by you")
            tile(.tracked, "Known source", "can be followed")
            tile(.localChanges, "Changed here", "differ from install", tone: count(.localChanges) > 0 ? .new : nil)
            tile(.unknown, "Unknown", "no known source")
            tile(.managed, "Managed", "owned by apps")
        }
    }

    private func tile(_ item: LibraryFilter, _ label: String, _ caption: String, tone: Tone? = nil) -> some View {
        StatTile(label: label, number: store.inventory == nil ? "--" : "\(count(item))", caption: caption,
                 tone: tone, isSelected: filter == item) { filter = item }
    }

    private func count(_ item: LibraryFilter) -> Int {
        store.inventory?.installations.filter(item.includes).count ?? 0
    }

    // MARK: List

    private var listCard: some View {
        ZStack(alignment: .bottom) {
            Group {
                if filter == .coverage {
                    CoverageView()
                } else {
                    table
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if filter != .coverage, let installation = selected {
                actionBar(installation)
                    .padding(.bottom, 14)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(Motion.swap, value: selected?.id)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var table: some View {
        let groups = groups
        let rows = groups.flatMap(\.items)
        let entries = entries(in: groups)
        let copies = Dictionary(rows.map { ($0.displayName, 1) }, uniquingKeysWith: +)
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
                                sectionHeader("Managed by apps · \(count(.managed))",
                                              note: "Read-only here. Each app updates its own.")
                            }
                            GroupRow(group: group, isOpen: open, isLast: lastInSection, hasCursor: groupCursor == group.id)
                                .id(group.id)
                                .onTapGesture { toggle(group, among: groups) }
                            if open {
                                ForEach(group.items) { installation in
                                    InstallationRow(installation: installation,
                                                    copies: copies[installation.displayName] ?? 1,
                                                    isSelected: installation.id == selection,
                                                    trunk: !lastInSection,
                                                    isLast: installation.id == group.items.last?.id)
                                        .id(installation.id)
                                        .onTapGesture(count: 2) {
                                            selection = installation.id
                                            showsDetail = true
                                        }
                                        .onTapGesture {
                                            groupCursor = nil
                                            selection = installation.id == selection ? nil : installation.id
                                            listFocused = true
                                        }
                                }
                            }
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
            if let id = groupCursor, let group = groups.first(where: { $0.id == id }) {
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

    // MARK: Groups

    /// The skills that match the filter and the search, gathered by where they come from:
    /// one group per source, one for skills with no known source, one per owning app.
    private var groups: [SkillGroup] {
        var order: [String] = []
        var byID: [String: SkillGroup] = [:]
        for installation in visible {
            let (id, title, kind): (String, String, SkillGroup.Kind) = switch installation.provenance {
            case .skillsLock(let source, _, _, _, _): ("source:" + source, source, .source)
            case .unknown: ("unknown", "No known source", .unknown)
            case .managed(let owner): ("managed:" + owner, owner, .managed)
            }
            if byID[id] == nil {
                byID[id] = SkillGroup(id: id, title: title, kind: kind, items: [])
                order.append(id)
            }
            byID[id]?.items.append(installation)
        }
        return order.compactMap { byID[$0] }.sorted { a, b in
            if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
            if a.items.count != b.items.count { return a.items.count > b.items.count }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    /// A group is open when the reader opened it, when it is the only one, while searching,
    /// or when it holds the selected skill.
    private func isExpanded(_ group: SkillGroup, among groups: [SkillGroup]) -> Bool {
        expanded.contains(group.id) || groups.count == 1 || !search.isEmpty
            || group.items.contains { $0.id == selection }
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
        guard let id = groupCursor, let group = groups.first(where: { $0.id == id }),
              isExpanded(group, among: groups) != open else { return .ignored }
        toggle(group, among: groups)
        return .handled
    }

    /// What the arrow keys step through: every group, and the skills of the open ones.
    private func entries(in groups: [SkillGroup]) -> [Entry] {
        groups.flatMap { group in
            [Entry.group(group.id)] + (isExpanded(group, among: groups) ? group.items.map { .skill($0.id) } : [])
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

    private func actionBar(_ installation: Installation) -> some View {
        FloatingBar {
            Text(installation.displayName).font(TypeRole.sans(13, .medium)).lineLimit(1)
            DataText(barNote(installation))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.leading, 6)
                .padding(.trailing, 10)
            Button(showsDetail ? "Hide details" : "Details") { showsDetail.toggle() }
                .buttonStyle(DarkPillButtonStyle(prominent: true))
            if case .skillsLock(_, let url?, _, _, _) = installation.provenance, let link = URL(string: url) {
                Button("Open source") { NSWorkspace.shared.open(link) }
                    .buttonStyle(DarkPillButtonStyle())
            } else {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installation.canonicalPath)])
                }
                .buttonStyle(DarkPillButtonStyle())
            }
        }
        .frame(maxWidth: 560)
    }

    private func barNote(_ installation: Installation) -> String {
        if case .skillsLock(_, _, _, _, .modified) = installation.provenance { return "CHANGED SINCE INSTALL" }
        let n = installation.bindings.count
        return "\(n) LOCATION\(n == 1 ? "" : "S")"
    }

    private var agentsOnThisMac: [Agent] {
        Array(Set((store.inventory?.installations ?? []).flatMap(\.agents))).sorted()
    }

    private var visible: [Installation] {
        let all = store.inventory?.installations ?? []
        let filtered = all.filter { filter.includes($0) || (filter == .yours && isManaged($0)) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        guard !search.isEmpty else { return filtered }
        return filtered.filter { installation in
            if installation.displayName.localizedCaseInsensitiveContains(search) { return true }
            if (installation.frontmatter.description ?? "").localizedCaseInsensitiveContains(search) { return true }
            if installation.canonicalPath.localizedCaseInsensitiveContains(search) { return true }
            switch installation.provenance {
            case .skillsLock(let source, _, _, _, _): return source.localizedCaseInsensitiveContains(search)
            case .managed(let owner): return owner.localizedCaseInsensitiveContains(search)
            case .unknown: return false
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
    enum Kind: Int { case source, unknown, managed }
    let id: String
    let title: String
    let kind: Kind
    var items: [Installation]

    var agents: Set<Agent> { Set(items.flatMap(\.agents)) }
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
    let group: SkillGroup
    let isOpen: Bool
    let isLast: Bool
    let hasCursor: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                // An open branch sends a line down from its sign to its skills.
                TreeGuide(branches: [isLast ? .corner : .tee]).stroke(Palette.ink2, lineWidth: 1)
                if isOpen {
                    TreeGuide(branches: [.none, .pipe]).stroke(Palette.ink2, lineWidth: 1)
                        .mask(alignment: .bottom) { Rectangle().frame(height: 12) }
                }
                DataText(isOpen ? "−" : "+")
                    .foregroundStyle(Palette.ink)
                    .frame(width: 14)
                    .offset(x: TreeGuide.first + TreeGuide.step - 7)
            }
            .frame(width: Column.number)
            .frame(maxHeight: .infinity)
            Text(group.title).font(TypeRole.sans(13, .medium)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            DataText("\(group.items.count) skill\(group.items.count == 1 ? "" : "s")")
                .foregroundStyle(Palette.ink2)
                .frame(width: Column.source, alignment: .leading)
            DataText(note)
                .foregroundStyle(Palette.ink3)
                .frame(width: Column.revision, alignment: .leading)
            TickCount(group.agents.count)
                .frame(width: Column.agents, alignment: .leading)
                .help(group.agents.sorted().map(\.displayName).joined(separator: ", "))
            chip.frame(width: Column.status, alignment: .leading)
        }
        .frame(height: 40)
        .padding(.horizontal, 10)
        .background(Palette.ink.opacity(hovering || hasCursor ? 0.04 : 0),
                    in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay {
            if hasCursor {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Palette.ink.opacity(0.28), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOpen ? "Open" : "Closed")
    }

    private var note: String {
        switch group.kind {
        case .source: ""
        case .unknown: "not linked"
        case .managed: "set by the app"
        }
    }

    @ViewBuilder private var chip: some View {
        switch group.kind {
        case .source where group.changed > 0: StatusChip("\(group.changed) changed here", kind: .new)
        case .source: StatusChip("Tracked")
        case .unknown: StatusChip("Source unknown", kind: .outline)
        case .managed: StatusChip("Managed")
        }
    }
}

private enum Column {
    static let number: CGFloat = 44
    static let source: CGFloat = 190
    static let revision: CGFloat = 160
    static let agents: CGFloat = 96
    static let status: CGFloat = 150
}

private struct InstallationRow: View {
    let installation: Installation
    let copies: Int
    let isSelected: Bool
    /// The branch this skill hangs from has more branches below it.
    let trunk: Bool
    /// The last skill of its branch.
    let isLast: Bool
    @State private var hovering = false

    var body: some View {
        let strong = isSelected ? Tone.rest.foreground : Palette.ink
        let quiet = isSelected ? Tone.rest.foreground.opacity(0.72) : Palette.ink2
        let faint = isSelected ? Tone.rest.secondary : Palette.ink3
        HStack(spacing: 0) {
            TreeGuide(branches: [trunk ? .pipe : .none, isLast ? .corner : .tee])
                .stroke(isSelected ? quiet : Palette.ink2, lineWidth: 1)
                .frame(width: Column.number + 6)
                .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                Text(installation.displayName).font(TypeRole.sans(13, .medium)).lineLimit(1)
                if copies > 1 {
                    Text("· \(copies) copies").foregroundStyle(quiet).lineLimit(1).layoutPriority(-1)
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
            TickCount(installation.agents.count)
                .foregroundStyle(strong)
                .frame(width: Column.agents, alignment: .leading)
                .help(installation.agents.map(\.displayName).joined(separator: ", "))
            StatusBadge(provenance: installation.provenance)
                .frame(width: Column.status, alignment: .leading)
        }
        .foregroundStyle(strong)
        .frame(height: 34)
        .padding(.horizontal, 10)
        .background(isSelected ? Tone.rest.background : Palette.ink.opacity(hovering ? 0.04 : 0),
                    in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
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
        case .unknown: ("not linked", false)
        }
    }

    private var revision: (text: String, known: Bool) {
        switch installation.provenance {
        case .skillsLock(_, _, _, let baseline?, .modified(let local)):
            ("\(baseline.prefix(7)) → \(local.prefix(7))", true)
        case .skillsLock(_, _, _, let baseline?, _): (String(baseline.prefix(7)), true)
        case .skillsLock: ("no baseline", false)
        case .managed: ("set by the app", false)
        case .unknown: ("no baseline", false)
        }
    }
}

struct StatusBadge: View {
    let provenance: Provenance

    var body: some View {
        switch provenance {
        case .skillsLock(_, _, _, _, .matchesBaseline): StatusChip("Tracked")
        case .skillsLock(_, _, _, _, .modified): StatusChip("Changed here", kind: .new)
        case .skillsLock(_, _, _, _, .hashFailed): StatusChip("Check failed", kind: .attention)
        case .managed: StatusChip("Managed")
        case .unknown: StatusChip("Source unknown", kind: .outline)
        }
    }
}

private extension String {
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}
