import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

// The parts both library layouts are built from. The library takes a stand for the reader:
// each thing that needs them is one sentence and one button, statuses are only named when
// something is off, and everything else waits on the page of the skill or app it belongs to.

/// Where in the library the reader is.
enum LibraryPage: Hashable {
    case home
    /// The reader's own skills, as one list.
    case mine
    /// The apps that bring skills of their own.
    case apps
    case skill(Installation.ID)
    case app(String)
    /// Everything Skillori knows about one skill: the full record.
    case details(Installation.ID)
    case folders
}

// MARK: What needs the reader

/// One thing that needs the reader, said as a sentence, with the one thing to do about it.
struct Todo: Identifiable {
    enum Act {
        case updateSkills([Installation])
        case updatePlugins([PluginRecord])
        /// Adds Codex plugins again from Codex's current catalog, by their ids there.
        case addCodexPlugins([String])
        case keepNewer([String])
        case open(LibraryPage)
        case refresh
        case turnOnChecks
        /// Puts text, such as commands to run in Terminal, on the clipboard.
        case copy(String)
    }

    let id: String
    /// Whose icon the line carries; nil for the reader's own skills.
    let app: String?
    let title: String
    let detail: String
    let button: String
    let act: Act
    /// Where a click on the line itself goes.
    var page: LibraryPage?
    var busy = false
    var prominent = false
    /// A receipt, not a thing to do: the button is a label saying what was done.
    var done = false
    /// The installer's run for these skills is shown under the line: while it runs, when it
    /// went wrong, and for a moment after it went well.
    var command: [Installation]?
}

@MainActor
enum Assist {
    /// The button on a Claude Code plugin line: Update, or what fits after a run that didn't.
    static func pluginButton(_ runner: PluginUpdateRunner, _ plugins: [PluginRecord]) -> (String, Todo.Act) {
        if runner.isRunning { return ("Updating…", .updatePlugins(plugins)) }
        if Set(runner.ids) == Set(plugins.map(\.id)) {
            switch runner.phase {
            case .needsReview(let commands): return ("Copy commands", .copy(commands))
            case .failed: return ("▶ Try again", .updatePlugins(plugins))
            default: break
            }
        }
        return ("▶ Update", .updatePlugins(plugins))
    }

    /// What needs the reader now, most pressing first. Things that are merely unknown, such as
    /// a skill with no source, are not on it: they are fine as they are.
    static func todos(_ store: InventoryStore) -> [Todo] {
        guard store.inventory != nil else { return [] }
        var list: [Todo] = []
        if !store.checksEnabled {
            list.append(Todo(id: "checks", app: nil, title: "Turn on update checks",
                             detail: "Skillori asks each source whether a skill has changed. It sends the source’s name and nothing about you.",
                             button: "Turn on", act: .turnOnChecks, prominent: true))
        }
        // Skills of yours the installer can update, one line per source. A skill linked by hand
        // can have a copy in several folders; it is still one skill.
        let bySource = Dictionary(grouping: store.updatable) { store.upstreamSource(for: $0)?.name ?? "" }
        let firstUpdate = list.count
        let receipt = store.receipt
        let received = Set(receipt?.installations.map(\.directoryName) ?? [])
        var receiptShown = false
        let runner = store.updater
        let ran = Set(runner.names)
        for source in bySource.keys.sorted() {
            let skills = bySource[source]!.sorted { $0.displayName < $1.displayName }
            let folders = Set(skills.map(\.directoryName))
            // The skills that were just updated: the receipt takes the line's place, and its name,
            // so the line turns into the receipt instead of one going and another coming.
            if let receipt, receipt.source == source, folders.isSubset(of: received) {
                list.append(receiptTodo(receipt, id: "skills:" + source, store: store))
                receiptShown = true
                continue
            }
            var titles: [String] = []
            for skill in skills where !titles.contains(skill.displayName) { titles.append(skill.displayName) }
            let mine = !ran.isEmpty && ran.isSubset(of: folders)
            let running = runner.isRunning && mine
            let failure: String? = if case .failed(let why) = runner.phase, mine, let ended = runner.endedAt,
                                      Date().timeIntervalSince(ended) < 30 * 60 { why } else { nil }
            let what = titles.count == 1 ? titles[0] : "\(titles.count) skills from \(source)"
            list.append(Todo(id: "skills:" + source, app: nil,
                             title: failure != nil ? "Could not update \(what)" : "Update \(what)",
                             detail: failure.map { _ in "The installer didn’t finish. What it printed is below." }
                                 ?? (titles.count == 1 ? "A newer version is at \(source). " : names(titles) + ". ")
                                 + (titles.count == 1 ? "Updating replaces it with the source’s version." : "Updating replaces them with the source’s version."),
                             button: running ? "Updating…" : failure != nil ? "▶ Try again" : "▶ Update", act: .updateSkills(skills),
                             page: titles.count == 1 ? .skill(skills[0].id) : nil, busy: runner.isRunning, prominent: true,
                             command: running || failure != nil ? skills : nil))
        }
        // The source's line is already gone, or still has other skills to update.
        if let receipt, !receiptShown {
            let id = bySource[receipt.source] == nil ? "skills:" + receipt.source : "receipt:" + receipt.source
            list.insert(receiptTodo(receipt, id: id, store: store), at: firstUpdate)
        }
        // Skills linked to an install script whose files have changed. Skillori reads the script
        // but never runs it, so getting the new files is the reader's step, in Terminal.
        var scripted: [String] = []
        for installation in store.updates {
            guard case .differs = store.status(for: installation),
                  case .installer(let script)? = store.upstreamSource(for: installation),
                  !scripted.contains(installation.displayName) else { continue }
            scripted.append(installation.displayName)
            list.append(Todo(id: "script:" + installation.displayName, app: nil,
                             title: "\(installation.displayName) has changed at \(script.name)",
                             detail: "Skillori doesn’t run install scripts. Copy the author’s command and run it in Terminal to get the new version.",
                             button: "Copy command", act: .copy(script.installCommand), page: .skill(installation.id)))
        }
        // Claude Code plugins, which Skillori can update by running Claude Code's own update.
        // Cursor and Codex bring new versions of their plugins themselves, so a newer version at
        // a source is not something for the reader to do; it waits on the app's page.
        let plugins = store.pluginUpdates.sorted { $0.title < $1.title }
        if !plugins.isEmpty {
            let runner = store.pluginUpdater
            let (button, act) = pluginButton(runner, plugins)
            list.append(Todo(id: "plugins:Claude Code", app: "Claude Code",
                             title: "Update \(plugins.count == 1 ? "1 plugin" : "\(plugins.count) plugins") in Claude Code",
                             detail: names(plugins.map(\.title)) + ". " + (runner.note(for: plugins) ?? "Start a new Claude Code session afterwards to load them."),
                             button: button, act: act,
                             page: .app("Claude Code"), busy: runner.isRunning, prominent: true))
        }
        // Codex plugins Codex stopped reading when it moved them to a new catalog. Skillori can
        // add them again from there by running Codex's own `codex plugin add`.
        let moved = store.codexMoved
        if !moved.isEmpty {
            list.append(codexTodo(store, moved))
        }
        // Changes made on this Mac, which an update would replace.
        let changed = (store.inventory?.installations ?? []).filter { store.status(for: $0) == .changedHere }
        if !changed.isEmpty {
            list.append(Todo(id: "changed", app: nil,
                             title: changed.count == 1 ? "You changed \(changed[0].displayName) on this Mac" : "You changed \(changed.count) skills on this Mac",
                             detail: "An update would replace those changes. Have a look before you update.",
                             button: "Show", act: .open(.skill(changed[0].id)), page: .skill(changed[0].id)))
        }
        // Two different copies under one name: an agent may load either.
        let twice = store.differingCopyNames
        if !twice.isEmpty {
            let first = mine(store).first { $0.name.lowercased() == twice[0].lowercased() }?.primary
            list.append(Todo(id: "twice", app: nil,
                             title: twice.count == 1 ? "\(twice[0]) exists twice" : "\(spelled(twice.count)) of your skills exist twice",
                             detail: (twice.count == 1 ? "The two copies differ" : names(twice) + " differ between copies")
                                 + ", so agents may load different ones. Keeping the newer one is usually right.",
                             button: "Keep newer", act: .keepNewer(twice), page: first.map { .skill($0.id) }))
        }
        // Sources that gave no answer, when trying again can help. A source that said how
        // long to wait is a notice instead: there is nothing to press until then.
        if store.isStale, let reason = store.lastProblem, !store.isWaiting {
            let title = switch reason {
            case .rateLimited: "\(store.unansweredBy ?? "A source") asked Skillori to wait"
            case .failed: "Skillori could not read the sources’ answers"
            default: "No contact with the sources"
            }
            list.append(Todo(id: "stale", app: nil, title: title, detail: staleDetail(store),
                             button: "Try again", act: .refresh, page: .mine))
        }
        return list
    }

    /// The line for an update that just went well: what was updated, from where and when, and
    /// what the reader may want to do about it. A click leads to the skill.
    private static func receiptTodo(_ receipt: InventoryStore.Receipt, id: String, store: InventoryStore) -> Todo {
        var titles: [String] = []
        for skill in receipt.installations where !titles.contains(skill.displayName) { titles.append(skill.displayName) }
        let one = titles.count == 1
        return Todo(id: id, app: nil,
                    title: one ? "Updated \(titles[0])" : "Updated \(titles.count) skills",
                    detail: "From \(receipt.source) at \(InventoryStore.stamp(receipt.at)). Start a new agent session to load \(one ? "it" : "them").",
                    button: "✓ Updated", act: .open(.mine),
                    page: one ? receipt.installations.first.map { .skill($0.id) } : .mine,
                    done: true, command: receipt.showsOutput ? receipt.installations : nil)
    }

    /// What the reader should know but has nothing to do about, under the things to do.
    static func notices(_ store: InventoryStore) -> [Todo] {
        guard store.isStale, store.isWaiting, let until = store.waitUntil else { return [] }
        let again = InventoryStore.stamp(until)
        let detail = store.updateWentThrough
            ? "Your update of \(updatedName(store)) went through. Skillori checks it against its source at \(again)."
            : staleDetail(store) + " Skillori asks again at \(again)."
        return [Todo(id: "wait", app: nil, title: "\(store.unansweredBy ?? "A source") asked Skillori to wait",
                     detail: detail, button: "", act: .refresh, page: .mine)]
    }

    /// Which statuses are older than they look, and from when.
    private static func staleDetail(_ store: InventoryStore) -> String {
        let lead = store.updateWentThrough ? "Your update of \(updatedName(store)) went through. " : ""
        let count = store.unansweredCount
        guard let last = store.lastCheck else { return lead + "There is no answer from the sources yet." }
        let when = InventoryStore.stamp(last)
        if count == 0 { return lead + "What you see is from the answer at \(when)." }
        return lead + (count == 1 ? "One skill shows the answer from \(when)." : "\(spelled(count)) skills show the answer from \(when).")
    }

    /// The skill the latest run updated, or how many.
    private static func updatedName(_ store: InventoryStore) -> String {
        let names = store.updater.names
        guard names.count == 1 else { return "\(names.count) skills" }
        return store.inventory?.installations.first { $0.directoryName == names[0] }?.displayName ?? names[0]
    }

    /// The line for Codex plugins Codex no longer reads: what happened, and the button that adds
    /// them again. Also used on the Codex page and, for one plugin, on its skills' pages.
    static func codexTodo(_ store: InventoryStore, _ moved: [(plugin: PluginRecord, replacement: String)]) -> Todo {
        let runner = store.codexRunner
        let ids = moved.map(\.replacement)
        let titles = moved.map(\.plugin.title)
        let failed: Bool = { if case .failed = runner.phase, Set(runner.ids) == Set(ids) { true } else { false } }()
        let running = runner.isRunning && Set(runner.ids) == Set(ids)
        let why = moved.count == 1 ? "Codex moved it to a new catalog and no longer reads this copy. "
            : names(titles) + ". Codex moved them to a new catalog and no longer reads these copies. "
        return Todo(id: "plugins:Codex", app: "Codex",
                    title: moved.count == 1 ? "Codex no longer reads \(titles[0])" : "Codex no longer reads \(moved.count) plugins",
                    detail: runner.note(for: ids) ?? why + "Codex may ask you to sign in to the service the first time you use \(moved.count == 1 ? "it" : "them").",
                    button: running ? "Adding…" : failed ? "▶ Try again" : "▶ Add again",
                    act: .addCodexPlugins(ids), page: .app("Codex"), busy: runner.isRunning, prominent: true)
    }

    // MARK: The reader's own skills

    /// One of the reader's skills, however many folders hold it.
    struct MySkill: Identifiable {
        let name: String
        let installations: [Installation]
        /// The copy the page opens on: the newest when they differ.
        let primary: Installation
        var id: String { name.lowercased() }
    }

    static func mine(_ store: InventoryStore) -> [MySkill] {
        let own = (store.inventory?.installations ?? []).filter { !isManaged($0) }
        return Dictionary(grouping: own) { $0.displayName.lowercased() }.values.map { copies in
            // Only copies that differ need their dates read; the rest are the same skill.
            let newest = copies.count == 1 ? copies[0] : copies.max { modified($0) < modified($1) } ?? copies[0]
            return MySkill(name: newest.displayName, installations: copies, primary: newest)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The one word a skill of yours shows in a list, and only when something is off.
    static func note(for skill: MySkill, store: InventoryStore) -> (text: String, kind: StatusChip.Kind)? {
        if case .different = store.copies(of: skill.primary) { return ("Exists twice", .attention) }
        switch store.status(for: skill.primary) {
        case .updateAvailable: return ("Update", .new)
        // An install script's new version is the reader's to fetch, with a command to copy. A
        // linked folder the installer can't take over can only be compared, not updated.
        case .differs:
            if case .installer? = store.upstreamSource(for: skill.primary) { return ("Update", .new) }
            return ("Differs", .neutral)
        case .changedHere: return ("Changed here", .attention)
        case .heldBack: return ("Kept as is", .neutral)
        case .noSource: return ("No source", .outline)
        case .keptLocal: return ("Local copy", .outline)
        case .cantCheck(.notFound) where store.lostSource(of: skill.primary) != nil: return ("Source gone", .outline)
        case .cantCheck(.folderGone) where store.lostSource(of: skill.primary) != nil: return ("Gone from source", .outline)
        case .cantCheck: return ("Can’t check", .outline)
        default: return nil
        }
    }

    // MARK: The apps

    /// An app that brings skills of its own, such as Cursor with its plugins.
    struct AppSummary: Identifiable {
        let name: String
        let installations: [Installation]
        let plugins: [PluginRecord]
        let updates: [PluginRecord]
        var id: String { name }
    }

    static func apps(_ store: InventoryStore) -> [AppSummary] {
        let managed = (store.inventory?.installations ?? []).filter(isManaged)
        // The plugins that ask something of the reader.
        let updating = Set(store.pluginUpdates.map(\.id) + store.codexMoved.map(\.plugin.id))
        return Dictionary(grouping: managed) { app(of: $0) }.map { name, items in
            var seen = Set<String>()
            let plugins = items.compactMap(\.plugin).filter { seen.insert($0.id).inserted }
            return AppSummary(name: name, installations: items, plugins: plugins,
                              updates: plugins.filter { updating.contains($0.id) }.sorted { $0.title < $1.title })
        }
        .sorted { a, b in
            if a.updates.count != b.updates.count { return a.updates.count > b.updates.count }
            return a.installations.count > b.installations.count
        }
    }

    /// "100 skills in 5 plugins"
    static func contents(_ app: AppSummary) -> String {
        let skills = app.installations.count == 1 ? "1 skill" : "\(app.installations.count) skills"
        switch app.plugins.count {
        case 0: return skills
        case 1: return skills + " in " + app.plugins[0].title
        default: return skills + " in \(app.plugins.count) plugins"
        }
    }

    /// The product that owns a skill, by the name people know it by.
    static func app(of installation: Installation) -> String {
        if let app = installation.plugin?.app { return app }
        guard case .managed(let owner) = installation.provenance else { return "You" }
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

    static func agent(forApp app: String) -> Agent? {
        switch app {
        case "Claude Code": .claudeCode
        case "Claude": .claudeDesktop
        case "Cursor": .cursor
        case "Codex": .codex
        default: Agent.all.first { $0.displayName == app }
        }
    }

    /// "0.53.0 → 0.55.1" for an update Skillori can run, or "→ newer" when the source gives a
    /// tree id rather than a version. "4.0.1 · 5.1.0 at source" when the app brings it itself.
    static func versionStep(_ plugin: PluginRecord, status: SkillStatus?) -> String {
        let installed = plugin.version ?? plugin.commit.map { String($0.prefix(7)) } ?? "?"
        switch status {
        case .ownerUpdate(_, let latest)?: return installed + " → " + (isVersion(latest) ? latest : "newer")
        case .sourceAhead(_, let latest)?: return installed + " · " + (isVersion(latest) ? latest + " at source" : "newer at source")
        default: return installed
        }
    }

    static func isVersion(_ text: String) -> Bool {
        text.count < 24 && text.contains(".") && !(text.count == 40 && text.allSatisfy(\.isHexDigit))
    }

    static func isManaged(_ installation: Installation) -> Bool {
        if case .managed = installation.provenance { true } else { false }
    }

    // MARK: Words

    /// "a, b and c"
    static func names(_ list: [String]) -> String {
        switch list.count {
        case 0: return ""
        case 1: return list[0]
        case 2...4: return list.dropLast().joined(separator: ", ") + " and " + list.last!
        default: return list.prefix(3).joined(separator: ", ") + " and \(list.count - 3) more"
        }
    }

    static func spelled(_ n: Int) -> String {
        ["None", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"].indices.contains(n)
            ? ["None", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"][n] : "\(n)"
    }

    static func day(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated)) }

    /// The latest change to any file of a skill: what "newer" means between two copies.
    static func modified(_ installation: Installation) -> Date {
        let root = URL(fileURLWithPath: installation.canonicalPath)
        var latest = Date.distantPast
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles]) else { return latest }
        var seen = 0
        for case let url as URL in walk {
            seen += 1
            if seen > 400 { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            latest = max(latest, date)
        }
        return latest
    }
}

private extension Agent {
    static let all: [Agent] = [.claudeCode, .cursor, .codex, .geminiCLI, .antigravity, .copilot, .openCode, .amp, .kiro,
                               .droid, .devin, .goose, .claudeDesktop]
}

// MARK: Keeping the newer copy

extension InventoryStore {
    /// For each name, the newest copy stays and every copy that differs from it is replaced by
    /// it. The replaced folder goes to the Trash, so nothing is lost.
    func keepNewer(_ names: [String]) async throws {
        for name in names {
            let copies = (inventory?.installations ?? [])
                .filter { !Assist.isManaged($0) && $0.displayName.lowercased() == name.lowercased() }
            guard let newest = copies.max(by: { Assist.modified($0) < Assist.modified($1) }) else { continue }
            let from = URL(fileURLWithPath: newest.canonicalPath)
            for old in copies where old.canonicalPath != newest.canonicalPath && old.contentHash != newest.contentHash {
                let to = URL(fileURLWithPath: old.canonicalPath)
                try FileManager.default.trashItem(at: to, resultingItemURL: nil)
                try FileManager.default.copyItem(at: from, to: to)
            }
        }
        await refresh()
    }

    /// What "Keep newer" will do, in one sentence, for the confirmation.
    func keepNewerSummary(_ names: [String]) -> String {
        names.compactMap { name -> String? in
            let copies = (inventory?.installations ?? [])
                .filter { !Assist.isManaged($0) && $0.displayName.lowercased() == name.lowercased() }
            guard let newest = copies.max(by: { Assist.modified($0) < Assist.modified($1) }) else { return nil }
            let old = copies.filter { $0.canonicalPath != newest.canonicalPath && $0.contentHash != newest.contentHash }
            guard !old.isEmpty else { return nil }
            return "\(name): the copy in \(Assist.folder(of: newest)) from \(Assist.day(Assist.modified(newest))) replaces the one in "
                + old.map(Assist.folder(of:)).joined(separator: " and ") + "."
        }
        .joined(separator: "\n") + "\n\nThe replaced copies go to the Trash."
    }
}

extension Assist {
    /// The folder a skill sits in, shortened: "~/.claude/skills".
    static func folder(of installation: Installation) -> String {
        (URL(fileURLWithPath: installation.canonicalPath).deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: Buttons on light

/// A button on a block of light, in the block's own ink.
struct LitButtonStyle: ButtonStyle {
    var prominent = false
    /// The ink of the block it sits on.
    var ink: Color = Palette.ink
    /// The colour of text on a prominent button.
    var onInk: Color = Palette.onInk

    func makeBody(configuration: Configuration) -> some View {
        LitBody(configuration: configuration, prominent: prominent, ink: ink, onInk: onInk)
    }

    private struct LitBody: View {
        let configuration: Configuration
        let prominent: Bool
        let ink: Color
        let onInk: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.control, style: .circular)
            configuration.label
                .font(TypeRole.mono(10.5, .medium))
                .tracking(0.42)
                .textCase(.uppercase)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(prominent ? onInk : ink)
                .background(prominent ? ink : ink.opacity(hovering ? 0.1 : 0), in: shape)
                .overlay(shape.strokeBorder(ink.opacity(prominent ? 0 : 0.4), lineWidth: 1))
                .opacity(isEnabled ? (prominent && hovering ? 0.86 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .contentShape(shape)
                .onHover { hovering = $0 }
        }
    }
}

extension Tone {
    /// A button style for this tone's block of light.
    func litButton(prominent: Bool = false) -> LitButtonStyle {
        let ink = blockForeground
        let onInk: Color = switch self {
        case .attention: .white
        case .quiet: background
        case .rest, .new: Palette.inkFixed
        }
        return LitButtonStyle(prominent: prominent, ink: ink, onInk: onInk)
    }
}

/// An app's mark: its icon if it is on this Mac, else a small plate. The reader's own skills
/// carry a plain dot.
struct AppMark: View {
    let app: String?
    var size: CGFloat = 22

    var body: some View {
        if let app, let agent = Assist.agent(forApp: app) {
            AgentMark(agent: agent, size: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .circular).fill(Palette.ink)
                Circle().fill(Palette.panel).frame(width: size * 0.32, height: size * 0.32)
            }
            .frame(width: size, height: size)
            .accessibilityLabel("Your skills")
        }
    }
}

// MARK: Lines to do

/// Does what a line asks, and asks first where it changes files.
struct TodoButton: View {
    @Environment(InventoryStore.self) private var store
    let todo: Todo
    var style: LitButtonStyle
    var open: (LibraryPage) -> Void
    @State private var confirming = false
    @State private var problem: String?

    var body: some View {
        if todo.done {
            // Says what was done; there is nothing to press.
            Button {} label: { SwappingText(todo.button) }
                .buttonStyle(style)
                .allowsHitTesting(false)
                .accessibilityRemoveTraits(.isButton)
        } else {
            button
        }
    }

    private var button: some View {
        Button { run() } label: { SwappingText(todo.button) }
            .buttonStyle(style)
            .disabled(todo.busy)
            .alert(confirmTitle, isPresented: $confirming) {
                Button("Keep newer") { keep() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if case .keepNewer(let names) = todo.act { Text(store.keepNewerSummary(names)) }
            }
            .alert("Could not replace the copy", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(problem ?? "") }
    }

    private var confirmTitle: String {
        if case .keepNewer(let names) = todo.act, names.count > 1 { return "Keep the newer copy of \(names.count) skills?" }
        return "Keep the newer copy?"
    }

    private func run() {
        switch todo.act {
        case .updateSkills(let skills): Task { await store.update(skills) }
        case .updatePlugins(let plugins): Task { await store.updatePlugins(plugins) }
        case .addCodexPlugins(let ids): Task { await store.addCodexPlugins(ids) }
        case .keepNewer: confirming = true
        case .open(let page): open(page)
        case .refresh: Task { await store.refresh() }
        case .turnOnChecks: store.checksEnabled = true
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func keep() {
        guard case .keepNewer(let names) = todo.act else { return }
        Task {
            do { try await store.keepNewer(names) } catch { problem = error.localizedDescription }
        }
    }
}

/// One thing to do: a sentence, a line saying why, and one button.
struct TodoLine: View {
    let todo: Todo
    /// The block it sits on; nil for a plain card.
    var tone: Tone?
    /// The page the line is shown on. A button or click that would only lead here is left out:
    /// the page itself has what the line points to.
    var here: LibraryPage?
    var open: (LibraryPage) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                AppMark(app: todo.app)
                VStack(alignment: .leading, spacing: 2) {
                    SwappingText(todo.title, alignment: .leading).font(TypeRole.sans(14, .medium)).lineLimit(1)
                    SwappingText(todo.detail, alignment: .leading).font(TypeRole.sans(12)).foregroundStyle(secondary).lineLimit(2)
                }
                Spacer(minLength: 12)
                // A notice has no button: there is nothing to do but know it.
                if !leadsHere, !todo.button.isEmpty { TodoButton(todo: todo, style: style, open: open) }
            }
            // The run itself, as the command it is, under the line it belongs to.
            if let command = todo.command {
                CommandFrame(installations: command, compact: true, showsRun: false)
                    .padding(.leading, 40)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .animation(Motion.fold, value: todo.command != nil)
        .padding(.vertical, 12)
        .padding(.horizontal, tone == nil ? 12 : 0)
        .background((tone == nil ? Palette.ink : (tone?.blockForeground ?? Palette.ink)).opacity(hovering && page != nil ? 0.05 : 0),
                    in: RoundedRectangle(cornerRadius: Radius.row, style: .circular))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if let page { open(page) } }
        .accessibilityElement(children: .combine)
    }

    private var leadsHere: Bool {
        if case .open(let page) = todo.act, page == here { true } else { false }
    }

    private var page: LibraryPage? { todo.page == here ? nil : todo.page }

    private var secondary: Color { tone?.blockSecondary ?? Palette.ink2 }

    private var style: LitButtonStyle {
        if let tone { return tone.litButton(prominent: todo.prominent) }
        return LitButtonStyle(prominent: todo.prominent)
    }
}

// MARK: Lists

/// The reader's own skills, one line each, a word only where something is off.
struct MySkillsList: View {
    @Environment(InventoryStore.self) private var store
    var open: (LibraryPage) -> Void

    var body: some View {
        let skills = Assist.mine(store)
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(skills) { skill in
                    SkillLine(name: skill.name, description: skill.primary.frontmatter.description,
                              note: Assist.note(for: skill, store: store)) { open(.skill(skill.primary.id)) }
                }
                if skills.isEmpty {
                    Text("No skills of your own yet. Skills you install with the skills installer show up here.")
                        .font(TypeRole.sans(13)).foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
            .padding(6)
        }
        .scrollIndicators(.never)
    }
}

/// A skill in a list: its name, what it is for, and a word if something is off.
struct SkillLine: View {
    let name: String
    let description: String?
    let note: (text: String, kind: StatusChip.Kind)?
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            Text(name).font(TypeRole.sans(13, .medium)).lineLimit(1).frame(width: 240, alignment: .leading)
            Text(Self.short(description)).font(TypeRole.sans(13)).foregroundStyle(Palette.ink2).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let note {
                if note.kind == .outline {
                    LabelText(note.text).foregroundStyle(Palette.ink3)
                } else {
                    StatusChip(note.text, kind: note.kind)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Palette.ink.opacity(hovering ? 0.04 : 0), in: RoundedRectangle(cornerRadius: Radius.row, style: .circular))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// The first sentence of a description, without the "Use when" that follows.
    static func short(_ text: String?) -> String {
        guard var text, !text.isEmpty else { return "" }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        if let end = text.range(of: ". ") { text = String(text[..<end.lowerBound]) }
        for cut in [" — ", " - ", ": "] where text.count > 90 {
            if let range = text.range(of: cut) { text = String(text[..<range.lowerBound]) }
        }
        return text
    }
}

/// The apps that bring skills, one line each.
struct AppsList: View {
    @Environment(InventoryStore.self) private var store
    var open: (LibraryPage) -> Void

    var body: some View {
        let apps = Assist.apps(store)
        VStack(spacing: 0) {
            ForEach(apps) { app in
                AppLine(app: app) { open(.app(app.name)) }
            }
            Text("Each app keeps its own skills current. Skillori tells you when one has a newer version.")
                .font(TypeRole.sans(12)).foregroundStyle(Palette.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 14)
            Spacer(minLength: 0)
        }
        .padding(6)
    }
}

struct AppLine: View {
    let app: Assist.AppSummary
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            AppMark(app: app.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(TypeRole.sans(14, .medium))
                Text(Assist.contents(app)).font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 12)
            if !app.updates.isEmpty {
                StatusChip(app.updates.count == 1 ? "1 update" : "\(app.updates.count) updates", kind: .new)
            }
            DataText("›").foregroundStyle(Palette.ink3)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .background(Palette.ink.opacity(hovering ? 0.04 : 0), in: RoundedRectangle(cornerRadius: Radius.row, style: .circular))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Everything that matches a search, mine and the apps' alike.
struct SearchResults: View {
    @Environment(InventoryStore.self) private var store
    let query: String
    var open: (LibraryPage) -> Void

    var body: some View {
        let hits = (store.inventory?.installations ?? []).filter { installation in
            installation.displayName.localizedCaseInsensitiveContains(query)
                || (installation.frontmatter.description ?? "").localizedCaseInsensitiveContains(query)
                || (installation.plugin?.title ?? "").localizedCaseInsensitiveContains(query)
        }
        var seen = Set<String>()
        let unique = hits.filter { seen.insert(Assist.app(of: $0) + "/" + $0.displayName.lowercased()).inserted }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(unique) { installation in
                    let app = Assist.app(of: installation)
                    SkillLine(name: installation.displayName, description: installation.frontmatter.description,
                              note: (app == "You" ? "Yours" : installation.plugin.map { "\(app) · \($0.title)" } ?? app, .outline)) {
                        open(.skill(installation.id))
                    }
                }
                if unique.isEmpty {
                    Text("No skill matches “\(query)”.").font(TypeRole.sans(13)).foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
            .padding(6)
        }
        .scrollIndicators(.never)
    }
}

/// The way back, at the top of a page.
struct Crumb: View {
    let title: String
    var action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                Text("‹ " + title).font(TypeRole.mono(11.5, .medium)).foregroundStyle(Palette.ink)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)
            Spacer()
        }
        .frame(height: 30)
        .padding(.horizontal, 10)
    }
}

// MARK: The bar at the top

/// The library's top bar: its name, the search, when it last looked, and the two actions.
struct LibraryTopBar: View {
    @Environment(InventoryStore.self) private var store
    @Binding var search: String
    var onFolders: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                SkilloriMark().fill(Palette.ink).frame(width: 18, height: 18)
                Text("Library").font(TypeRole.sans(13, .medium))
            }
            .frame(width: 110, alignment: .leading)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.ink2)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .font(TypeRole.sans(13))
                    .focused($focused)
                    .onExitCommand { search = ""; focused = false }
                LabelText("⌘F").foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .frame(maxWidth: 360)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .circular))
            Spacer(minLength: 8)
            SwappingLabel(stamp, alignment: .trailing).foregroundStyle(Palette.ink2)
            Button("Folders", action: onFolders).buttonStyle(PillButtonStyle())
            Button { Task { await store.refresh() } } label: {
                SwappingText(store.isScanning ? "Reading…" : store.isChecking ? "Checking…" : store.checksEnabled ? "Check now" : "Read again")
            }
            .buttonStyle(PillButtonStyle())
            .keyboardShortcut("r")
            .disabled(store.isScanning || store.isChecking)
        }
        .padding(.leading, 78)
        .padding(.trailing, 8)
        .frame(height: 52)
        .background {
            Button("Search") { focused = true }.keyboardShortcut("f").opacity(0).accessibilityHidden(true)
        }
    }

    private var stamp: String {
        guard let inventory = store.inventory else { return "Reading now" }
        guard store.checksEnabled else { return "Read \(inventory.scannedAt.formatted(date: .omitted, time: .shortened))" }
        return store.checkStamp
    }
}

/// A plain card that holds a list.
struct ListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
            .clipShape(RoundedRectangle(cornerRadius: Radius.block, style: .circular))
    }
}

/// The pages under the home of either layout: a skill, an app, the full record, the folders.
/// `title` names a page for the way back to it.
@MainActor
enum LibraryPaging {
    static func title(_ page: LibraryPage, store: InventoryStore) -> String {
        switch page {
        case .home: "Library"
        case .mine: "Your skills"
        case .apps: "From your apps"
        case .skill(let id), .details(let id): store.installation(id: id)?.displayName ?? "Skill"
        case .app(let name): name
        case .folders: "Folders"
        }
    }
}

/// A page below the library's home: a skill, an app, the full record or the folders.
struct LibraryPageView: View {
    @Environment(InventoryStore.self) private var store
    let page: LibraryPage
    let backTitle: String
    var back: () -> Void
    var open: (LibraryPage) -> Void
    var onLink: (Installation) -> Void
    var onFindSources: (Installation) -> Void = { _ in }

    var body: some View {
        switch page {
        case .skill(let id):
            if let installation = find(id) {
                SkillPage(installation: installation, backTitle: backTitle, back: back, open: open,
                          onLink: { onLink(installation) }, onFindSources: { onFindSources(installation) })
                    .id(id)
            } else {
                gone
            }
        case .details(let id):
            if let installation = find(id) {
                InstallationDetail(installation: installation, readAt: store.inventory?.scannedAt,
                                   agentsOnThisMac: Array(Set((store.inventory?.installations ?? []).flatMap(\.installedAgents))).sorted(),
                                   onBack: back, onLink: { onLink(installation) })
            } else {
                gone
            }
        case .app(let name):
            AppPage(app: name, backTitle: backTitle, back: back, open: open)
        case .folders:
            VStack(spacing: 6) {
                Crumb(title: backTitle, action: back)
                ListCard { CoverageView() }
            }
        case .home, .mine, .apps:
            EmptyView()
        }
    }

    private func find(_ id: Installation.ID) -> Installation? {
        store.installation(id: id)
    }

    /// A skill that was removed or replaced while its page was open.
    private var gone: some View {
        VStack(spacing: 6) {
            Crumb(title: backTitle, action: back)
            ListCard {
                Text("This skill is no longer where it was. It may have been updated or moved.")
                    .font(TypeRole.sans(13)).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
        }
    }
}
