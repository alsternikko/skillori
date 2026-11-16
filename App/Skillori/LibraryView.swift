import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// The library, first take: three tiles over one list. The tile that is chosen lights up, and
/// the list under it shows what that tile counts: what needs you, your skills, or the apps'.
struct LibraryView: View {
    enum Shelf: String { case todo, mine, apps }

    @Environment(InventoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The chosen tile; nil until the reader picks one, which opens on what needs them.
    @State private var shelf: Shelf?
    /// The pages the reader has clicked into, the latest last.
    @State private var path: [LibraryPage]
    @State private var search = ""
    @State private var linking: Installation?

    init(shelf: Shelf? = nil, path: [LibraryPage] = []) {
        _shelf = State(initialValue: shelf)
        _path = State(initialValue: path)
    }

    var body: some View {
        VStack(spacing: 6) {
            LibraryTopBar(search: $search, onFolders: { open(.folders) })
            if !search.isEmpty {
                ListCard { SearchResults(query: search, open: { search = ""; open($0) }) }
            } else if let page = path.last {
                LibraryPageView(page: page, backTitle: backTitle, back: back, open: open, onLink: { linking = $0 })
                    .transition(.opacity)
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
        .sheet(item: $linking) { installation in
            LinkSourceSheet(installation: installation).environment(store)
        }
    }

    // MARK: Pages

    private func open(_ page: LibraryPage) {
        switch page {
        case .home: path = []
        case .mine: shelf = .mine; path = []
        case .apps: shelf = .apps; path = []
        default: if path.last != page { path.append(page) }
        }
    }

    private func back() { if !path.isEmpty { path.removeLast() } }

    private var backTitle: String {
        path.count >= 2 ? LibraryPaging.title(path[path.count - 2], store: store) : title(current)
    }

    // MARK: Home

    private var current: Shelf { shelf ?? (Assist.todos(store).isEmpty ? .mine : .todo) }

    private var home: some View {
        let todos = Assist.todos(store)
        let mine = Assist.mine(store)
        let fromApps = (store.inventory?.installations ?? []).filter(Assist.isManaged).count
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                tile(.todo, number: todos.count, caption: todos.isEmpty ? "nothing to do" : todos.count == 1 ? "thing to do" : "things to do")
                tile(.mine, number: mine.count, caption: "installed by you")
                tile(.apps, number: fromApps, caption: "kept current by " + Assist.names(Assist.apps(store).map(\.name)))
            }
            .fixedSize(horizontal: false, vertical: true)
            ListCard {
                switch current {
                case .todo: todoList(todos)
                case .mine: MySkillsList(open: open)
                case .apps: AppsList(open: open)
                }
            }
        }
    }

    private func title(_ shelf: Shelf) -> String {
        switch shelf {
        case .todo: "For you"
        case .mine: "Your skills"
        case .apps: "From your apps"
        }
    }

    private func tile(_ item: Shelf, number: Int, caption: String) -> some View {
        let on = current == item
        let tone: Tone = item == .todo && number > 0 ? .new : .rest
        return Button {
            withAnimation(reduceMotion ? nil : Motion.swap) { shelf = item }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    LabelText(title(item)).foregroundStyle(on ? tone.blockSecondary : Palette.ink2)
                    if item == .todo, !on, number > 0 {
                        Circle().fill(Color(hex: 0xC555DD)).frame(width: 7, height: 7).accessibilityHidden(true)
                    }
                }
                DotNumber(store.inventory == nil ? "--" : "\(number)", size: 40).padding(.top, 14)
                Text(caption).font(TypeRole.sans(12)).lineLimit(1)
                    .foregroundStyle(on ? tone.blockSecondary : Palette.ink2)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .foregroundStyle(on ? tone.blockForeground : Palette.ink)
            .background {
                if on {
                    tone.blockBackground(phase: item == .todo ? 3 : item == .mine ? 31 : 61)
                } else {
                    RoundedRectangle(cornerRadius: Radius.block, style: .circular).fill(Palette.card)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.block, style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private func todoList(_ todos: [Todo]) -> some View {
        if todos.isEmpty {
            VStack(spacing: 6) {
                Text("Nothing needs you").font(TypeRole.sans(15, .medium))
                Text(store.checksEnabled ? store.checkStamp + ". Skillori keeps looking." : "Skillori keeps looking.")
                    .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in
                        if index > 0 { Palette.line.frame(height: 1).padding(.horizontal, 12) }
                        TodoLine(todo: todo, open: open)
                    }
                    Text("That’s all for now.").font(TypeRole.sans(12)).foregroundStyle(Palette.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 14)
                }
                .padding(6)
            }
            .scrollIndicators(.never)
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
        let twice = store.differingCopyNames.first.flatMap { name in
            Assist.mine(store).first { $0.name.lowercased() == name.lowercased() }?.primary
        }
        let plugin = all.first { if case .ownerUpdate = store.status(for: $0) { true } else { false } }
        var list: [(String, LibraryView)] = [
            ("library", LibraryView()),
            ("library-mine", LibraryView(shelf: .mine)),
            ("library-apps", LibraryView(shelf: .apps)),
            ("library-app-cursor", LibraryView(shelf: .apps, path: [.app("Cursor")])),
            ("library-app-claude-code", LibraryView(shelf: .apps, path: [.app("Claude Code")])),
            ("library-folders", LibraryView(path: [.folders])),
        ]
        if let tracked {
            list.append(("library-skill", LibraryView(shelf: .mine, path: [.skill(tracked.id)])))
            list.append(("library-details", LibraryView(shelf: .mine, path: [.skill(tracked.id), .details(tracked.id)])))
        }
        if let unknown { list.append(("library-skill-unknown", LibraryView(shelf: .mine, path: [.skill(unknown.id)]))) }
        if let twice { list.append(("library-skill-twice", LibraryView(shelf: .mine, path: [.skill(twice.id)]))) }
        if let plugin { list.append(("library-skill-plugin", LibraryView(shelf: .apps, path: [.app(Assist.app(of: plugin)), .skill(plugin.id)]))) }
        return list
    }
}
