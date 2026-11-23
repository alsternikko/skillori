import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// The library, second take: what needs you first, in one block of light, and under it two
/// ways into the library, your skills and the apps'. With nothing to do the block says so.
struct LibraryView: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The pages the reader has clicked into, the latest last.
    @State private var path: [LibraryPage]
    @State private var search = ""
    @State private var linking: Installation?
    @State private var findingSources = false
    /// A skill whose source is being looked for from its own page.
    @State private var findingFor: Installation?
    /// The skill whose installer key the reader is adding.
    @State private var keyFor: Installation?
    /// The share sheet, for every skill or opened on one.
    @State private var sharing: ShareRequest?
    /// The tone the block of things to do shows. It follows the real one a moment later, so the
    /// light turns after the line that changed it has folded away.
    @State private var shownTone: Tone?

    init(path: [LibraryPage] = []) {
        _path = State(initialValue: path)
    }

    /// Posted with a `LibraryPage` to open it in the library that is already showing.
    static let openPage = Notification.Name("SkilloriLibraryOpenPage")

    var body: some View {
        VStack(spacing: 6) {
            // On top, and opaque: the home's scroll view reaches up under the window's title bar,
            // which is where this bar is drawn. Below it, the scroll view took the clicks meant
            // for Folders and Check now, and scrolled content would show through.
            LibraryTopBar(search: $search, onFolders: { open(.folders) })
                .background(Palette.panel)
                .zIndex(1)
            if !search.isEmpty {
                ListCard { SearchResults(query: search, open: { search = ""; open($0) }) }
            } else if let page = path.last {
                pageView(page).transition(.opacity)
            } else {
                home
            }
        }
        .padding(EdgeInsets(top: 0, leading: 6, bottom: 6, trailing: 6))
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .font(TypeRole.sans(13))
        .ignoresSafeArea(edges: .top)
        .animation(reduceMotion ? nil : Motion.swap, value: path)
        // A link's receipt is said on the page where it was made, until the reader leaves it.
        .onChange(of: path) { store.clearLinkReceipt() }
        .onDisappear { store.clearLinkReceipt() }
        .onReceive(NotificationCenter.default.publisher(for: Self.openPage)) { note in
            if let page = note.object as? LibraryPage { search = ""; open(page) }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: DebugLibraryProbe.openPage)) { note in
            if let page = note.object as? LibraryPage { open(page) }
        }
        .onChange(of: path, initial: true) { DebugLibraryProbe.path = path }
        #endif
        .sheet(item: $linking) { installation in
            LinkSourceSheet(installation: installation).environment(store)
        }
        .sheet(isPresented: $findingSources) {
            FindSourcesSheet().environment(store)
        }
        .sheet(item: $keyFor) { installation in
            InstallerKeySheet(installation: installation).environment(store)
        }
        .sheet(item: $findingFor) { installation in
            FindSourcesSheet(only: installation).environment(store)
        }
        .sheet(item: $sharing) { request in
            ShareSheet(only: request.only).environment(store)
        }
    }

    // MARK: Pages

    private func open(_ page: LibraryPage) {
        if page == .home { path = [] } else if path.last != page { path.append(page) }
    }

    private func back() { if !path.isEmpty { path.removeLast() } }

    private var backTitle: String {
        path.count >= 2 ? LibraryPaging.title(path[path.count - 2], store: store) : "Library"
    }

    @ViewBuilder private func pageView(_ page: LibraryPage) -> some View {
        switch page {
        case .mine:
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    Crumb(title: backTitle, action: back)
                    if !Assist.mine(store).isEmpty {
                        Button("Share skills…") { sharing = ShareRequest() }
                            .buttonStyle(PillButtonStyle())
                            .help("Make a command that adds your skills on someone else’s computer")
                            .padding(.trailing, 2)
                    }
                }
                if let linked = store.linkReceipt { linkedCard(linked).transition(.opacity) }
                if store.unknownCount > 0 { findSourcesCard }
                ListCard { MySkillsList(open: open) }
            }
        case .apps:
            VStack(spacing: 6) {
                Crumb(title: backTitle, action: back)
                ListCard { AppsList(open: open) }
            }
        default:
            LibraryPageView(page: page, backTitle: backTitle, back: back, open: open, onLink: { linking = $0 },
                            onFindSources: { findingFor = $0 }, onAddKey: { keyFor = $0 },
                            onShare: { sharing = ShareRequest(only: $0) })
        }
    }

    /// What Find sources just linked, above the list it changed, until the reader leaves the page.
    private func linkedCard(_ linked: InventoryStore.LinkReceipt) -> some View {
        let one = linked.names.count == 1
        return VStack(alignment: .leading, spacing: 3) {
            Text(one ? "Linked \(linked.names[0])" : "Linked \(Assist.spelled(linked.names.count).lowercased()) skills")
                .font(TypeRole.sans(16, .medium))
            Text((one ? "" : Assist.names(linked.names) + ". ") + "To \(Assist.names(linked.sources)). Open a skill to see what its source means for it.")
                .font(TypeRole.sans(12.5))
                .foregroundStyle(Tone.new.blockSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 18))
        .foregroundStyle(Tone.new.blockForeground)
        .background { Tone.new.blockBackground(phase: 41) }
    }

    /// Above your skills while some have no known source: one line and the way to find them.
    private var findSourcesCard: some View {
        let count = store.unknownNameCount
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "One skill has no known source" : "\(Assist.spelled(count).capitalized) skills have no known source")
                    .font(TypeRole.sans(13, .medium))
                Text("Skillori can look for where they came from and link them, so it can tell you when they change.")
                    .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 12)
            Button("Find sources…") { findingSources = true }
                .buttonStyle(PillButtonStyle(prominent: true))
        }
        .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
    }

    // MARK: Home

    private var home: some View {
        let todos = Assist.todos(store)
        // What changes the block's height: lines coming and going, a run unfolding under its line,
        // and what the installer prints. The doors below move with it.
        let shape = todos.map { $0.id + ($0.command == nil ? "" : "+") } + Assist.notices(store).map(\.id)
            + [String(store.updater.lastLines(3).count)]
        return ScrollView {
            VStack(spacing: 6) {
                if store.inventory != nil { today(todos) }
                door(apps: [nil], title: "Your skills", note: mineNote, number: Assist.mine(store).count) { open(.mine) }
                door(apps: Assist.apps(store).prefix(3).map(\.name), title: "From your apps",
                     note: Assist.names(Assist.apps(store).map(\.name)) + " keep these current themselves.",
                     number: (store.inventory?.installations ?? []).filter(Assist.isManaged).count) { open(.apps) }
            }
            .animation(Motion.fold, value: shape)
        }
        .scrollIndicators(.never)
    }

    private var mineNote: String {
        let mine = Assist.mine(store)
        // What the block of things for you lists too: updates and things to look at, not choices made.
        let off = mine.filter { Assist.note(for: $0, store: store).map { $0.kind == .new || $0.kind == .attention } ?? false }.count
        return off == 0 ? "Installed by you. Skillori checks them against their source."
            : "Installed by you. \(off == 1 ? "One needs" : "\(off) need") a look."
    }

    /// One block for what needs the reader: a sentence and a button per thing. With nothing to
    /// do it says so, in the resting light.
    private func today(_ todos: [Todo]) -> some View {
        let notices = Assist.notices(store)
        let updates = todos.contains { $0.id.hasPrefix("skills:") || $0.id.hasPrefix("plugins:") || $0.id.hasPrefix("receipt:") }
        let real: Tone = todos.isEmpty ? .rest : updates ? .new : .attention
        let tone = shownTone ?? real
        // A receipt is not a thing to do, so it isn't counted; while it shows, the title waits.
        let pending = todos.filter { !$0.done }
        let title = todos.isEmpty ? "You’re all set" : pending.count <= 1 ? "One thing for you" : "\(Assist.spelled(pending.count)) things for you"
        return VStack(alignment: .leading, spacing: 0) {
            SwappingLabel(store.checksEnabled ? store.checkStamp : "Today").foregroundStyle(tone.blockSecondary)
            // After the line that changed it has folded away.
            SwappingText(title, alignment: .leading, delay: 0.24)
                .font(TypeRole.sans(24, .medium)).tracking(-0.4)
                .padding(.top, 8)
            if todos.isEmpty {
                Text("\(Assist.mine(store).count) skills of yours and \((store.inventory?.installations ?? []).filter(Assist.isManaged).count) from your apps. Nothing needs you.")
                    .font(TypeRole.sans(13)).foregroundStyle(tone.blockSecondary)
                    .padding(.top, 4).padding(.bottom, notices.isEmpty ? 6 : 0)
                    .transition(.opacity.animation(.easeOut(duration: 0.24).delay(0.3)))
            }
            if !todos.isEmpty || !notices.isEmpty {
                VStack(spacing: 0) {
                    ForEach(todos + notices) { todo in
                        VStack(spacing: 0) {
                            tone.blockForeground.opacity(0.2).frame(height: 1)
                            TodoLine(todo: todo, tone: tone, open: open)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.top, 12)
            }
        }
        .task(id: real) {
            // The first time, at once. After that, a moment after the change, as the line folds.
            guard shownTone != nil else { shownTone = real; return }
            try? await Task.sleep(for: .milliseconds(360))
            shownTone = real
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: 22, bottom: todos.isEmpty && notices.isEmpty ? 18 : 6, trailing: 22))
        .foregroundStyle(tone.blockForeground)
        .background { tone.blockBackground(phase: 3) }
    }

    /// A way into the library: a name, one line on what is there, and how many.
    private func door(apps: [String?], title: String, note: String, number: Int, action: @escaping () -> Void) -> some View {
        Door(apps: apps, title: title, note: note, number: number, action: action)
    }

    private struct Door: View {
        /// The marks the door carries: the apps behind it, overlapping, or the reader's own.
        let apps: [String?]
        let title: String
        let note: String
        let number: Int
        var action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 14) {
                    HStack(spacing: -8) {
                        ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                            AppMark(app: app)
                                .padding(2)
                                .background(Palette.card, in: RoundedRectangle(cornerRadius: 7, style: .circular))
                        }
                    }
                    .frame(minWidth: 26, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(TypeRole.sans(15, .medium))
                        Text(note).font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    DotNumber("\(number)", size: 22)
                    DataText("›").foregroundStyle(Palette.ink3)
                }
                .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
                .background(hovering ? Palette.card.opacity(0.7) : Palette.card,
                            in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
                .contentShape(RoundedRectangle(cornerRadius: Radius.block, style: .circular))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

extension LibraryView {
    /// The library's states and pages, for the snapshot run (SKILLORI_SNAPSHOT_DIR).
    static func snapshots(store: InventoryStore) -> [(String, LibraryView)] {
        let all = store.inventory?.installations ?? []
        let mine = all.filter { !Assist.isManaged($0) }
        let tracked = mine.first { if case .skillsLock = $0.provenance { true } else { false } }
        let unknown = mine.first { store.status(for: $0) == .noSource }
        let linkedUpdate = mine.first { skill in store.link(for: skill) != nil && store.updatable.contains { $0.id == skill.id } }
        let twice = store.differingCopyNames.first.flatMap { name in
            Assist.mine(store).first { $0.name.lowercased() == name.lowercased() }?.primary
        }
        let plugin = all.first { if case .ownerUpdate = store.status(for: $0) { true } else { false } }
        let ahead = all.first { if case .sourceAhead = store.status(for: $0) { true } else { false } }
        let behind = all.first { if case .leftBehind = store.status(for: $0) { true } else { false } }
        var list: [(String, LibraryView)] = [
            ("library", LibraryView()),
            ("library-mine", LibraryView(path: [.mine])),
            ("library-apps", LibraryView(path: [.apps])),
            ("library-app-cursor", LibraryView(path: [.apps, .app("Cursor")])),
            ("library-app-codex", LibraryView(path: [.apps, .app("Codex")])),
            ("library-app-claude-code", LibraryView(path: [.apps, .app("Claude Code")])),
            ("library-folders", LibraryView(path: [.folders])),
        ]
        if let ahead { list.append(("library-skill-source-ahead", LibraryView(path: [.apps, .app(Assist.app(of: ahead)), .skill(ahead.id)]))) }
        if let behind { list.append(("library-skill-left-behind", LibraryView(path: [.apps, .app(Assist.app(of: behind)), .skill(behind.id)]))) }
        if let tracked {
            list.append(("library-skill", LibraryView(path: [.mine, .skill(tracked.id)])))
            list.append(("library-details", LibraryView(path: [.mine, .skill(tracked.id), .details(tracked.id)])))
        }
        if let unknown { list.append(("library-skill-unknown", LibraryView(path: [.mine, .skill(unknown.id)]))) }
        if let linkedUpdate { list.append(("library-skill-linked-update", LibraryView(path: [.mine, .skill(linkedUpdate.id)]))) }
        if let twice { list.append(("library-skill-twice", LibraryView(path: [.skill(twice.id)]))) }
        if let plugin { list.append(("library-skill-plugin", LibraryView(path: [.apps, .app(Assist.app(of: plugin)), .skill(plugin.id)]))) }
        return list
    }
}
