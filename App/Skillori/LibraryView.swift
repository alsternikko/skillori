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
                let rows = visible
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
        .onChange(of: filter) { selection = nil }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                SkilloriMark().fill(Palette.ink).frame(width: 13, height: 18)
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
        let rows = visible
        // With the detail card open there is no room for every column; it shows source and revision.
        let compact = showsDetail && selected != nil
        let copies = Dictionary(rows.map { ($0.displayName, 1) }, uniquingKeysWith: +)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                LabelText("No").frame(width: Column.number, alignment: .leading)
                LabelText("Name").frame(maxWidth: .infinity, alignment: .leading)
                if !compact {
                    LabelText("Source").frame(width: Column.source, alignment: .leading)
                    LabelText("Revision").frame(width: Column.revision, alignment: .leading)
                }
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
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, installation in
                            InstallationRow(number: index + 1, installation: installation,
                                            copies: copies[installation.displayName] ?? 1,
                                            isSelected: installation.id == selection, compact: compact)
                                .id(installation.id)
                                .onTapGesture(count: 2) {
                                    selection = installation.id
                                    showsDetail = true
                                }
                                .onTapGesture {
                                    selection = installation.id == selection ? nil : installation.id
                                    listFocused = true
                                }
                        }
                        if rows.isEmpty, store.inventory != nil { emptyState }
                        if filter != .managed, search.isEmpty { managedSection }
                        Color.clear.frame(height: selected == nil ? 8 : 64)
                    }
                    .padding(.horizontal, 6)
                }
                .onChange(of: selection) { _, new in
                    if let new { proxy.scrollTo(new) }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(.downArrow) { move(1, in: rows) }
        .onKeyPress(.upArrow) { move(-1, in: rows) }
        .onKeyPress(.return) {
            guard selected != nil else { return .ignored }
            showsDetail.toggle()
            return .handled
        }
        .onKeyPress(.escape) {
            guard selection != nil else { return .ignored }
            if showsDetail { showsDetail = false } else { selection = nil }
            return .handled
        }
    }

    private func move(_ step: Int, in rows: [Installation]) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.id == selection }
        let next = current.map { min(max($0 + step, 0), rows.count - 1) } ?? (step > 0 ? 0 : rows.count - 1)
        // Keyboard moves are immediate: no animation on something pressed many times.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { selection = rows[next].id }
        return .handled
    }

    @ViewBuilder private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(search.isEmpty ? "Nothing here" : "No skill matches “\(search)”")
                .font(TypeRole.sans(15, .medium))
            Text(search.isEmpty
                 ? "No skill on this Mac fits this group."
                 : "Searched names, descriptions, sources and paths in \(count(filter)) skills.")
                .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
            if !search.isEmpty {
                Button("Clear search") { search = "" }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 28)
    }

    /// Skills owned by apps, grouped by owner. Read-only here.
    @ViewBuilder private var managedSection: some View {
        let groups = managedGroups
        if !groups.isEmpty {
            HStack {
                LabelText("Managed by apps · \(groups.reduce(0) { $0 + $1.count })").foregroundStyle(Palette.ink)
                Spacer()
                LabelText("Read-only here. Each app updates its own.").foregroundStyle(Palette.ink2)
            }
            .frame(height: 40)
            .overlay(alignment: .top) { Palette.line.frame(height: 1) }
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            ForEach(Array(groups.enumerated()), id: \.element.owner) { index, group in
                HStack(spacing: 0) {
                    DataText(index == groups.count - 1 ? "└─" : "├─")
                        .foregroundStyle(Palette.ink3)
                        .frame(width: Column.number, alignment: .leading)
                    Text(group.owner).font(TypeRole.sans(13, .medium)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DataText("\(group.count) skill\(group.count == 1 ? "" : "s")")
                        .frame(width: showsDetail && selected != nil ? Column.agents : Column.source, alignment: .leading)
                    if !(showsDetail && selected != nil) {
                        DataText(group.path).truncationMode(.middle)
                            .frame(width: Column.revision + Column.agents, alignment: .leading)
                    }
                    StatusChip("Managed").frame(width: Column.status, alignment: .leading)
                }
                .foregroundStyle(Palette.ink2)
                .frame(height: 40)
                .overlay(alignment: .bottom) {
                    if index < groups.count - 1 { Palette.line.frame(height: 1) }
                }
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    search = ""
                    filter = .managed
                }
                .help("Show the skills managed by apps")
            }
        }
    }

    private var managedGroups: [(owner: String, count: Int, path: String)] {
        var byOwner: [String: [Installation]] = [:]
        for installation in store.inventory?.installations ?? [] {
            if case .managed(let owner) = installation.provenance { byOwner[owner, default: []].append(installation) }
        }
        return byOwner
            .map { (owner: $0.key, count: $0.value.count, path: Self.commonFolder(of: $0.value.map(\.canonicalPath))) }
            .sorted { $0.count > $1.count }
    }

    private static func commonFolder(of paths: [String]) -> String {
        guard var common = paths.first.map({ URL(fileURLWithPath: $0).deletingLastPathComponent().pathComponents }) else {
            return ""
        }
        for path in paths.dropFirst() {
            let parts = URL(fileURLWithPath: path).pathComponents
            common = Array(zip(common, parts).prefix { $0 == $1 }.map(\.0))
        }
        return NSString.path(withComponents: common).abbreviatingHome
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
        let filtered = all.filter(filter.includes)
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

    private var selected: Installation? {
        guard let selection else { return nil }
        return store.inventory?.installations.first { $0.id == selection }
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
    let number: Int
    let installation: Installation
    let copies: Int
    let isSelected: Bool
    var compact = false
    @State private var hovering = false

    var body: some View {
        let strong = isSelected ? Tone.rest.foreground : Palette.ink
        let quiet = isSelected ? Tone.rest.foreground.opacity(0.72) : Palette.ink2
        let faint = isSelected ? Tone.rest.secondary : Palette.ink3
        HStack(spacing: 0) {
            DataText(String(format: "%03d", number))
                .foregroundStyle(faint)
                .frame(width: Column.number, alignment: .leading)
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
            if !compact {
                DataText(source.text).truncationMode(.middle)
                    .foregroundStyle(source.known ? quiet : faint)
                    .frame(width: Column.source - 12, alignment: .leading)
                    .padding(.trailing, 12)
                DataText(revision.text)
                    .foregroundStyle(revision.known ? quiet : faint)
                    .frame(width: Column.revision, alignment: .leading)
            }
            TickCount(installation.agents.count)
                .foregroundStyle(strong)
                .frame(width: Column.agents, alignment: .leading)
                .help(installation.agents.map(\.displayName).joined(separator: ", "))
            StatusBadge(provenance: installation.provenance)
                .frame(width: Column.status, alignment: .leading)
        }
        .foregroundStyle(strong)
        .frame(height: 40)
        .padding(.horizontal, 10)
        .background(isSelected ? Tone.rest.background : Palette.ink.opacity(hovering ? 0.04 : 0),
                    in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(alignment: .bottom) {
            if !isSelected { Palette.line.frame(height: 1).padding(.horizontal, 10) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var source: (text: String, known: Bool) {
        switch installation.provenance {
        case .skillsLock(let source, _, _, _, _): (source, true)
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
