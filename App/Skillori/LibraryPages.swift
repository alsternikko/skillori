import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

// The pages a reader clicks through to: one skill, one app. Both layouts of the library use
// them. Each page says first what, if anything, the reader should do, with one button, and
// keeps the rest below it.

/// The app's advice for one skill: what is going on and the one thing to do.
private struct Advice {
    let tone: Tone
    let title: String
    let text: String
    var todo: Todo?
    var extra: [(label: String, prominent: Bool, run: () -> Void)] = []
    /// The installer's run for this skill, shown under the advice.
    var command: [Installation]?
}

/// One skill, as a page.
struct SkillPage: View {
    @Environment(InventoryStore.self) private var store
    let installation: Installation
    let backTitle: String
    var back: () -> Void
    var open: (LibraryPage) -> Void
    var onLink: () -> Void
    /// Looks for this skill's source, with the copies that share its name.
    var onFindSources: () -> Void = {}
    /// The last update of this skill, kept while the page is open. The store's receipt folds
    /// away after a few seconds, as its line in the library's list does; here the reader came
    /// for this skill, so the result stays until they leave.
    @State private var heldReceipt: InventoryStore.Receipt?

    var body: some View {
        VStack(spacing: 6) {
            Crumb(title: backTitle, action: back)
            ScrollView {
                VStack(spacing: 6) {
                    header
                    if let advice { adviceBlock(advice).transition(.opacity) }
                    HStack(alignment: .top, spacing: 6) {
                        whereCard
                        readByCard
                        sourceCard
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("All details") { open(.details(installation.id)) }.buttonStyle(PillButtonStyle())
                        Button("Open SKILL.md") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: installation.canonicalPath).appendingPathComponent("SKILL.md"))
                        }
                        .buttonStyle(PillButtonStyle())
                        Spacer()
                    }
                    .padding(.top, 6)
                }
                // The advice changing, or a run unfolding under it, moves the cards below with it.
                .animation(Motion.fold, value: [advice?.title ?? "", advice?.command == nil ? "" : "+",
                                                 String(store.updater.lastLines(3).count)])
            }
            .scrollIndicators(.never)
        }
        .onKeyPress(.escape) { back(); return .handled }
        .onChange(of: store.receipt?.at, initial: true) {
            if let receipt = store.receipt, receipt.contains(installation) { heldReceipt = receipt }
        }
        .onChange(of: store.updater.isRunning) { if store.updater.isRunning { heldReceipt = nil } }
    }

    /// The update to tell about: the store's while it shows one, then the one this page kept.
    private var receipt: InventoryStore.Receipt? {
        if let receipt = store.receipt, receipt.contains(installation) { return receipt }
        guard !store.updater.isRunning, var held = heldReceipt else { return nil }
        held.showsOutput = false
        return held
    }

    // MARK: Facts

    private var status: SkillStatus { store.status(for: installation) }
    private var isMine: Bool { !Assist.isManaged(installation) }
    private var app: String { Assist.app(of: installation) }

    /// Every folder of the reader's that holds a skill with this name.
    private var copies: [Installation] {
        guard isMine else { return [installation] }
        let name = installation.displayName.lowercased()
        return (store.inventory?.installations ?? []).filter { !Assist.isManaged($0) && $0.displayName.lowercased() == name }
    }

    private var differing: Bool { Set(copies.map { $0.contentHash ?? $0.id }).count > 1 }

    private var newest: Installation {
        copies.count == 1 ? installation : copies.max { Assist.modified($0) < Assist.modified($1) } ?? installation
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabelText(origin).foregroundStyle(Palette.ink2)
            Text(installation.displayName)
                .font(TypeRole.sans(28, .medium)).tracking(-0.5).lineLimit(1)
                .padding(.top, 12)
                .textSelection(.enabled)
            if let description = installation.frontmatter.description {
                Text(description)
                    .font(TypeRole.sans(13)).lineSpacing(3).lineLimit(5)
                    .foregroundStyle(Palette.ink2)
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.top, 8)
            }
            if advice == nil {
                Text(calmSentence).font(TypeRole.sans(13, .medium)).padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 18, trailing: 20))
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
    }

    private var origin: String {
        if let plugin = installation.plugin { return "\(app) · \(plugin.title) plugin" }
        if !isMine { return app }
        if let source = store.upstreamSource(for: installation) { return "Yours · from \(source.name)" }
        return "Yours"
    }

    /// What there is to say when there is nothing to do.
    private var calmSentence: String {
        switch status {
        case .upToDate:
            if let reading = store.reading(for: installation) { return "Same as its source. Checked \(InventoryStore.stamp(reading.checkedAt))." }
            return "Same as its source."
        case .managed: return "\(app) keeps it current. Nothing for you to do."
        case .noSource:
            if store.pastSource(of: installation) != nil {
                return "Nothing to do. Its old source stopped answering, so Skillori doesn’t know where it lives now."
            }
            return "Nothing to do. Skillori doesn’t know where it came from, which is fine."
        case .keptLocal: return "Nothing to do. You keep it as a local copy, so Skillori doesn’t check it against a source."
        case .cantCheck(let reason): return "Nothing to do. " + reason.sentence
        case .notChecked: return "Its source hasn’t been asked yet."
        default: return status.sentence
        }
    }

    // MARK: Advice

    /// What the gone source said, quoted as it said it, for the advice.
    private var noteSentence: String? {
        guard let message = store.notice(for: installation)?.message, !message.isEmpty else { return nil }
        return "It says: “\(message)” "
    }

    /// The address the gone source pointed to, opened in the browser.
    private var noteButton: [(label: String, prominent: Bool, run: () -> Void)] {
        guard let url = store.notice(for: installation)?.url else { return [] }
        return [(Self.openLabel(for: url), false, { NSWorkspace.shared.open(url) })]
    }

    /// What became of a source the reader unlinked after it stopped answering, in a sentence or two.
    static func pastSentence(_ past: InventoryStore.PastSource) -> String {
        let said = past.notice.map(\.message).flatMap { $0.isEmpty ? nil : $0 }
        return "It stopped answering and you unlinked it." + (said.map { " It said: “\($0)”" } ?? "")
    }

    static func openLabel(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return "Open " + (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
    }

    private var advice: Advice? {
        if isMine, differing, copies.count > 1 {
            let new = newest
            let readers = Set(copies.flatMap(\.installedAgents))
            let newOnly = readers.filter { a in new.installedAgents.contains(a) && !copies.contains { $0.id != new.id && $0.installedAgents.contains(a) } }
            let oldOnly = readers.filter { a in !new.installedAgents.contains(a) }
            var text = ""
            if !oldOnly.isEmpty {
                let names = Assist.names(oldOnly.sorted().map(\.displayName))
                text += "\(names) read\(oldOnly.count == 1 ? "s" : "") the older copy"
                text += newOnly.isEmpty ? ". " : ", \(Assist.names(newOnly.sorted().map(\.displayName))) the newer. "
            }
            text += "Keep the copy from \(Assist.day(Assist.modified(new))) and every agent reads the same."
            let todo = Todo(id: "keep:" + installation.displayName, app: nil, title: "", detail: "", button: "Keep newer",
                            act: .keepNewer([installation.displayName]), prominent: true)
            let urls = copies.map { URL(fileURLWithPath: $0.canonicalPath) }
            return Advice(tone: .attention, title: copies.count == 2 ? "Two different copies on this Mac" : "\(copies.count) different copies on this Mac",
                          text: text, todo: todo,
                          extra: [("Show in Finder", false, { NSWorkspace.shared.activateFileViewerSelecting(urls) })])
        }
        // Just updated: say so for a moment, with where it came from, before the page settles.
        if let receipt {
            let at = InventoryStore.stamp(receipt.at)
            // A move happens in the same run as the update; its record is a moment older than the receipt.
            if let move = store.move(of: installation), abs(move.at.timeIntervalSince(receipt.at)) < 120 {
                return Advice(tone: .new, title: "Moved to \(move.to)",
                              text: "Moved from \(move.from) and updated at \(at). Start a new agent session to load it.",
                              command: receipt.showsOutput ? receipt.installations : nil)
            }
            return Advice(tone: .new, title: "Updated from \(receipt.source)",
                          text: "At \(at). Start a new agent session to load it.",
                          command: receipt.showsOutput ? receipt.installations : nil)
        }
        // The source the installer recorded is gone: say what probably happened, and the ways on.
        if isMine, let reason = store.lostSource(of: installation) {
            let recorded = store.recordedSource(of: installation) ?? "Its source"
            let (title, text): (String, String) = switch reason {
            case .notFound:
                ("The source is gone", "\(recorded) no longer answers. "
                    + (noteSentence ?? "It may be private or removed, or have moved. ") + "Your copy works as it is.")
            case .folderGone:
                ("The skill is gone from its source", "\(recorded) no longer has this skill’s folder. It may have moved. Your copy works as it is.")
            case .unsupported:
                ("Skillori can’t ask this source", "The installer recorded \(recorded), which isn’t a GitHub repository. Link the skill to one to hear when it changes.")
            default:
                ("Nothing to compare with", "The installer left no record of what it installed. Link the skill to its source to compare with it.")
            }
            return Advice(tone: .quiet, title: title, text: text,
                          extra: [("Find sources", true, onFindSources), ("Link…", false, onLink)] + noteButton
                              + [("Keep as local", false, { store.keepLocal(installation) })])
        }
        // The source the reader linked is gone in turn: unlinking leaves the way on open again.
        if isMine, store.link(for: installation) != nil, case .cantCheck(let reason) = status,
           InventoryStore.lostReasons.contains(reason), let source = store.upstreamSource(for: installation) {
            let back = store.recordedSource(of: installation).map { " Unlinking goes back to \($0), the source the installer recorded." }
                ?? " Unlink it to link it again or look for where it went."
            return Advice(tone: .quiet, title: "The linked source is gone",
                          text: "\(source.name) no longer answers. " + (noteSentence ?? "") + "Your copy works as it is." + back,
                          extra: [("Unlink", true, { store.unlink(installation) })] + noteButton)
        }
        let history = store.upstreamSource(for: installation)?.historyURL(subpath: store.sourceSubpath(for: installation))
        let web = store.upstreamSource(for: installation)?.webURL(subpath: store.sourceSubpath(for: installation))
        switch status {
        case .updateAvailable:
            let runner = store.updater
            let running = runner.isRunning
            let mine = runner.names.contains(installation.directoryName)
            let failure: String? = if case .failed(let why) = runner.phase, mine, let ended = runner.endedAt,
                                      Date().timeIntervalSince(ended) < 30 * 60 { why } else { nil }
            var extra: [(String, Bool, () -> Void)] = []
            if let history { extra.append(("See what changed", false, { NSWorkspace.shared.open(history) })) }
            extra.append(("Keep this version", false, { store.hold(installation) }))
            return Advice(tone: .new,
                          title: failure != nil ? "Could not update" : "A newer version is at \(store.upstreamSource(for: installation)?.name ?? "its source")",
                          text: failure.map { _ in "The installer didn’t finish. What it printed is below." } ?? "Updating replaces this copy with the source’s.",
                          todo: Todo(id: "update", app: nil, title: "", detail: "",
                                     button: running && mine ? "Updating…" : failure != nil ? "▶ Try again" : "▶ Update",
                                     act: .updateSkills([installation]), busy: running, prominent: true),
                          extra: extra,
                          command: (running && mine) || failure != nil ? [installation] : nil)
        case .differs:
            var extra: [(String, Bool, () -> Void)] = []
            if case .installer(let script)? = store.upstreamSource(for: installation) {
                // Skillori reads the script but never runs it; installing again is the reader's step.
                extra.append(("Copy install command", true, {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(script.installCommand, forType: .string)
                }))
                if let web { extra.append(("Open site", false, { NSWorkspace.shared.open(web) })) }
                extra.append(("Keep this version", false, { store.hold(installation) }))
                return Advice(tone: .new, title: "The install script has other files than this copy",
                              text: "Run the author’s install command in Terminal to get its version, or keep this one as it is.", extra: extra)
            }
            if let web { extra.append(("Open source", true, { NSWorkspace.shared.open(web) })) }
            extra.append(("Keep this version", false, { store.hold(installation) }))
            return Advice(tone: .new, title: "The source has other files than this copy",
                          text: "Open the source to see what changed, or keep this version as it is.", extra: extra)
        case .ownerUpdate:
            guard let plugin = installation.plugin else { return nil }
            let runner = store.pluginUpdater
            let (button, act) = Assist.pluginButton(runner, [plugin])
            return Advice(tone: .new, title: "\(plugin.title) has a newer version",
                          text: runner.note(for: [plugin]) ?? "Skillori can run Claude Code’s update. Start a new Claude Code session afterwards.",
                          todo: Todo(id: "plugin", app: nil, title: "", detail: "", button: button,
                                     act: act, busy: runner.isRunning, prominent: true))
        case .sourceAhead(let owner, let upstream):
            guard let plugin = installation.plugin else { return nil }
            let version = Assist.isVersion(upstream) ? "Version \(upstream) is" : "A newer version is"
            return Advice(tone: .rest, title: "\(version) at \(plugin.title)’s source",
                          text: "\(owner) brings new versions of its plugins itself, once its own catalog has them. There is nothing to do here.")
        case .leftBehind(let owner, let replacement):
            guard let plugin = installation.plugin else { return nil }
            if let replacement {
                let todo = Assist.codexTodo(store, [(plugin, replacement)])
                return Advice(tone: .attention, title: todo.title, text: todo.detail, todo: todo)
            }
            if store.codexReplacement(of: plugin) != nil {
                return Advice(tone: .rest, title: "\(owner) has \(plugin.title) from its new catalog",
                              text: "This copy is left over from the old catalog, and \(owner) does not load it. Nothing needs doing.")
            }
            return Advice(tone: .rest, title: "\(owner) no longer reads this copy",
                          text: "It is from a catalog \(owner) no longer uses, so its skills are not loaded. \(owner) reads its plugins from where it installs them now.")
        case .changedHere:
            let url = URL(fileURLWithPath: installation.canonicalPath)
            return Advice(tone: .attention, title: "You changed this skill on this Mac",
                          text: "An update from the source would replace your changes. Keep them somewhere else first if you want them.",
                          extra: [("Show in Finder", true, { NSWorkspace.shared.activateFileViewerSelecting([url]) })])
        case .heldBack(let moved):
            return Advice(tone: .rest, title: "You’re keeping this version",
                          text: moved ? "The source has moved on since. Let go to hear about updates again." : "The source hasn’t changed since.",
                          extra: [("Let go", true, { store.release(installation) })])
        default:
            return nil
        }
    }

    private func adviceBlock(_ advice: Advice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    SwappingText(advice.title, alignment: .leading).font(TypeRole.sans(16, .medium))
                    SwappingText(advice.text, alignment: .leading).font(TypeRole.sans(12.5)).foregroundStyle(advice.tone.blockSecondary).lineLimit(3)
                }
                Spacer(minLength: 12)
                if let todo = advice.todo {
                    TodoButton(todo: todo, style: advice.tone.litButton(prominent: true), open: open)
                }
                ForEach(Array(advice.extra.enumerated()), id: \.offset) { _, button in
                    Button(button.label, action: button.run).buttonStyle(advice.tone.litButton(prominent: button.prominent && advice.todo == nil))
                }
            }
            if let command = advice.command {
                CommandFrame(installations: command, compact: true, showsRun: false).transition(.opacity)
            }
        }
        .animation(Motion.fold, value: advice.command != nil)
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 18))
        .foregroundStyle(advice.tone.blockForeground)
        .background { advice.tone.blockBackground(phase: 41) }
    }

    // MARK: Cards

    private var whereCard: some View {
        PageCard(label: copies.count > 1 ? "Where it lives · \(copies.count) copies" : "Where it lives") {
            let new = newest
            ForEach(copies) { copy in
                FactRow {
                    PathText(Assist.folder(of: copy))
                } value: {
                    Text(Assist.day(Assist.modified(copy)) + (copies.count > 1 && differing && copy.id == new.id ? " · newer" : ""))
                }
                let links = copy.bindings.filter { $0.discoveredPath != copy.canonicalPath }
                ForEach(links, id: \.discoveredPath) { binding in
                    FactRow {
                        PathText((URL(fileURLWithPath: binding.discoveredPath).deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    } value: { Text("linked") }
                }
            }
        }
    }

    private var readByCard: some View {
        var readers = Array(Set(copies.flatMap(\.installedAgents))).sorted()
        // The app that left this plugin behind does not read it, whatever its folder suggests.
        if case .leftBehind(let owner, _) = status, let agent = Assist.agent(forApp: owner) { readers.removeAll { $0 == agent } }
        let new = newest
        return PageCard(label: "Read by") {
            ForEach(readers.prefix(6), id: \.self) { agent in
                FactRow {
                    HStack(spacing: 8) {
                        AgentMark(agent: agent, size: 18)
                        Text(agent.displayName)
                    }
                } value: {
                    if copies.count > 1, differing {
                        let reads = copies.filter { $0.installedAgents.contains(agent) }
                        Text(reads.count > 1 ? "both copies" : reads.first?.id == new.id ? "newer copy" : "older copy")
                    }
                }
            }
            if readers.count > 6 {
                Text("and \(readers.count - 6) more").font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).padding(.top, 8)
            }
            if readers.isEmpty {
                Text("No agent on this Mac reads this folder.").font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
            }
        }
    }

    @ViewBuilder private var sourceCard: some View {
        PageCard(label: "Source") {
            if let plugin = installation.plugin {
                if case .leftBehind = status {
                    FactRow { Text("Left behind by \(app)") } value: { EmptyView() }
                } else {
                    FactRow { Text("Kept current by \(app)") } value: { EmptyView() }
                }
                FactRow { Text(plugin.title) } value: {
                    Text(Assist.versionStep(plugin, status: status)).font(TypeRole.mono(11.5))
                }
                if let repo = plugin.repository ?? plugin.marketplaceRepository,
                   let url = URL(string: "https://github.com/\(repo)") {
                    Button(repo) { NSWorkspace.shared.open(url) }.buttonStyle(PillButtonStyle()).padding(.top, 8)
                }
            } else if !isMine {
                FactRow { Text("Kept current by \(app)") } value: { EmptyView() }
            } else if store.isKeptLocal(installation) {
                FactRow { Text("Local copy") } value: { Text("kept by you") }
                Text(store.recordedSource(of: installation).map { "Skillori no longer checks it against \($0)." }
                     ?? "Skillori no longer checks it against a source.")
                    .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).padding(.top, 8)
                Button("Check again") { store.stopKeepingLocal(installation); Task { await store.refresh() } }
                    .buttonStyle(PillButtonStyle()).padding(.top, 8)
            } else if let reason = store.lostSource(of: installation), let recorded = store.recordedSource(of: installation) {
                // The installer's record names a source that is no use: show it struck out, and the way on.
                FactRow { Text(recorded).strikethrough(reason == .notFound) } value: {
                    Text(reason == .notFound ? "gone" : reason == .folderGone ? "folder gone" : reason == .unsupported ? "can’t ask" : "no record")
                }
                HStack(spacing: 6) {
                    Button("Link…", action: onLink).buttonStyle(PillButtonStyle())
                    // A source that answers no longer has nothing to show; the repository may, when only the folder went.
                    if reason == .folderGone, let url = store.upstreamSource(for: installation)?.webURL(subpath: nil) {
                        Button("Open repository") { NSWorkspace.shared.open(url) }.buttonStyle(PillButtonStyle())
                    }
                }
                .padding(.top, 8)
            } else if let source = store.upstreamSource(for: installation) {
                FactRow { Text(source.name) } value: {
                    if let reading = store.reading(for: installation) { Text("checked " + InventoryStore.stamp(reading.checkedAt)) }
                }
                if case .cantCheck(let reason) = status {
                    let note = store.notice(for: installation)
                    Text(note == nil ? reason.sentence
                         : note?.url == nil ? "The source no longer answers. It left a note."
                         : "The source no longer answers. It left a note and a new address.")
                        .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).padding(.top, 8)
                }
                if let move = store.move(of: installation) {
                    Text("Moved here from \(move.from) on \(Assist.day(move.at)).")
                        .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).padding(.top, 8)
                }
                if store.link(for: installation) != nil, let recorded = store.recordedSource(of: installation) {
                    // Linked to a new home because the installer's recorded one was gone.
                    Text("Linked in place of \(recorded). Unlink to go back to it.")
                        .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).padding(.top, 8)
                }
                HStack(spacing: 6) {
                    // A gone source that names its new address: that is the one worth opening.
                    if let moved = store.notice(for: installation)?.url {
                        Button(Self.openLabel(for: moved)) { NSWorkspace.shared.open(moved) }.buttonStyle(PillButtonStyle())
                    } else if let url = source.webURL(subpath: store.sourceSubpath(for: installation)) {
                        Button("Open source") { NSWorkspace.shared.open(url) }.buttonStyle(PillButtonStyle())
                    }
                    if store.link(for: installation) != nil {
                        Button("Unlink") { store.unlink(installation) }.buttonStyle(PillButtonStyle())
                    }
                }
                .padding(.top, 8)
            } else {
                let past = store.pastSource(of: installation)
                FactRow { Text("Not known") } value: { EmptyView() }
                if let past {
                    // The source it was linked to before, struck out, and what it said on the way out.
                    FactRow { Text(past.name).strikethrough() } value: { Text("until " + Assist.day(past.until)) }
                    Text(Self.pastSentence(past))
                        .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).padding(.top, 8)
                }
                Text(past == nil ? "Find or link where it came from, and Skillori tells you when it changes. Optional."
                     : "Find or link where it lives now, and Skillori tells you when it changes. Optional.")
                    .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).padding(.top, 8)
                HStack(spacing: 6) {
                    Button("Find sources", action: onFindSources).buttonStyle(PillButtonStyle())
                    Button("Link…", action: onLink).buttonStyle(PillButtonStyle())
                    if let url = past?.notice?.url {
                        Button(Self.openLabel(for: url)) { NSWorkspace.shared.open(url) }.buttonStyle(PillButtonStyle())
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

/// A card on a page: a small label and rows of facts.
struct PageCard<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabelText(label).foregroundStyle(Palette.ink2).padding(.bottom, 6)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
    }
}

struct FactRow<Key: View, Value: View>: View {
    @ViewBuilder var key: Key
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 12) {
            key.lineLimit(1)
            Spacer(minLength: 8)
            value.font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).lineLimit(1)
        }
        .font(TypeRole.sans(13))
        .frame(minHeight: 34)
        .overlay(alignment: .top) { Palette.line.frame(height: 1) }
    }
}

// MARK: An app

/// One app's skills: its plugins, what it ships itself, and what to do about updates.
struct AppPage: View {
    @Environment(InventoryStore.self) private var store
    let app: String
    let backTitle: String
    var back: () -> Void
    var open: (LibraryPage) -> Void
    @State private var expanded: Set<String> = []

    var body: some View {
        let summary = Assist.apps(store).first { $0.name == app }
        VStack(spacing: 6) {
            Crumb(title: backTitle, action: back)
            ScrollView {
                VStack(spacing: 6) {
                    header(summary)
                    if let todo = Assist.todos(store).first(where: { $0.id == "plugins:" + app }) {
                        TodoLine(todo: todo, tone: .new, here: .app(app), open: open)
                            .padding(.horizontal, 20).padding(.vertical, 6)
                            .foregroundStyle(Tone.new.blockForeground)
                            .background { Tone.new.blockBackground(phase: 3) }
                    }
                    VStack(spacing: 0) {
                        ForEach(branches(summary)) { branch in
                            branchRow(branch, status: branch.items.first.map { store.status(for: $0) })
                            if expanded.contains(branch.id) {
                                ForEach(branch.items) { installation in
                                    SkillLine(name: installation.displayName, description: installation.frontmatter.description, note: nil) {
                                        open(.skill(installation.id))
                                    }
                                    .padding(.leading, 28)
                                }
                            }
                        }
                    }
                    .padding(6)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
                }
            }
            .scrollIndicators(.never)
        }
        .onKeyPress(.escape) { back(); return .handled }
    }

    private func header(_ summary: Assist.AppSummary?) -> some View {
        HStack(spacing: 16) {
            AppMark(app: app, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(app).font(TypeRole.sans(28, .medium)).tracking(-0.5)
                Text(summary.map(sentence) ?? "")
                    .font(TypeRole.sans(13)).foregroundStyle(Palette.ink2)
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
    }

    private func sentence(_ summary: Assist.AppSummary) -> String {
        let statuses = Dictionary(summary.installations.map { ($0.plugin?.id ?? "", store.status(for: $0)) }) { a, _ in a }
        func status(_ plugin: PluginRecord) -> SkillStatus? { statuses[plugin.id] }
        let behind = summary.plugins.filter { if case .leftBehind = status($0) { true } else { false } }
        let ahead = summary.plugins.filter { if case .sourceAhead = status($0) { true } else { false } }
        let behindIDs = Set(behind.map(\.id))
        // Skills of plugins the app no longer reads are not ones it keeps current.
        let n = summary.installations.filter { !behindIDs.contains($0.plugin?.id ?? "") }.count
        let plugins = summary.plugins.filter { !behindIDs.contains($0.id) }
        var text = "\(app) keeps \(n == 1 ? "this skill" : "these \(n) skills") current."
        if plugins.count == 1 { text += " They come with \(plugins[0].title)." }
        if plugins.count > 1 { text += " They come in \(plugins.count) plugins." }
        if ahead.count == 1 { text += " One has a newer version at its source; \(app) brings it once its catalog has it." }
        if ahead.count > 1 { text += " \(ahead.count) have newer versions at their source; \(app) brings them once its catalog has them." }
        if behind.count == 1 { text += " It no longer reads \(behind[0].title)." }
        if behind.count > 1 { text += " It no longer reads \(behind.count) other plugins." }
        return text
    }

    private struct Branch: Identifiable {
        let id: String
        let title: String
        let items: [Installation]
        var plugin: PluginRecord?
        var note: String = ""
    }

    private static func isCheckable(_ plugin: PluginRecord) -> Bool {
        plugin.manifestPath == nil ? plugin.marketplaceRepository != nil : plugin.repository != nil
    }

    /// Plugins that ask something of the reader first, then the others, then those nobody can
    /// ask about folded into one line, then what the app ships itself.
    private func branches(_ summary: Assist.AppSummary?) -> [Branch] {
        guard let summary else { return [] }
        let updating = Set(summary.updates.map(\.id))
        let byPlugin = Dictionary(grouping: summary.installations) { $0.plugin?.id ?? "" }
        // A plugin the app no longer reads comes before the others even when there is nothing
        // to add: it is not one the app keeps current.
        func isBehind(_ branch: Branch) -> Bool {
            guard let item = branch.items.first, case .leftBehind = store.status(for: item) else { return false }
            return true
        }
        var plugins = summary.plugins.map { plugin in
            Branch(id: plugin.id, title: plugin.title, items: byPlugin[plugin.id] ?? [], plugin: plugin)
        }
        .sorted { a, b in
            let x = updating.contains(a.id) || isBehind(a), y = updating.contains(b.id) || isBehind(b)
            if x != y { return x }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        let quiet = plugins.filter { !Self.isCheckable($0.plugin!) && !isBehind($0) }
        if quiet.count > 1 {
            let ids = Set(quiet.map(\.id))
            plugins.removeAll { ids.contains($0.id) }
            plugins.append(Branch(id: "quiet", title: "\(quiet.count) plugins \(app) keeps current", items: quiet.flatMap(\.items)))
        }
        if let own = byPlugin[""], !own.isEmpty {
            plugins.append(Branch(id: "own", title: app == "Claude" ? "From your Claude account" : "Built in", items: own))
        }
        return plugins
    }

    /// One plugin: its skills fold out on a click. What it asks of the reader sits at the end,
    /// apart from the click that folds it out.
    private func branchRow(_ branch: Branch, status: SkillStatus?) -> some View {
        let status = branch.plugin == nil ? nil : status
        return HStack(spacing: 12) {
            Button {
                withAnimation(Motion.swap) {
                    if expanded.contains(branch.id) { expanded.remove(branch.id) } else { expanded.insert(branch.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    DataText(expanded.contains(branch.id) ? "−" : "+").foregroundStyle(Palette.ink2).frame(width: 14)
                    Text(branch.title).font(TypeRole.sans(13, .medium)).lineLimit(1)
                    Spacer(minLength: 12)
                    DataText(branch.items.count == 1 ? "1 skill" : "\(branch.items.count) skills").foregroundStyle(Palette.ink2)
                        .frame(width: 90, alignment: .leading)
                    DataText(branch.plugin.map { Assist.versionStep($0, status: status) } ?? "").foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                        .frame(width: 200, alignment: .leading)
                }
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Group {
                switch status {
                case .ownerUpdate?: StatusChip("Update", kind: .new)
                // The line above the list adds them again; each row says what is wrong.
                case .leftBehind?:
                    if let plugin = branch.plugin, store.codexReplacement(of: plugin) != nil {
                        StatusChip("Left over", kind: .neutral)
                    } else {
                        StatusChip("Not read", kind: .attention)
                    }
                default: Color.clear.frame(height: 1)
                }
            }
            // The same width on every row, so the columns line up whatever the row asks.
            .frame(width: 124, alignment: .trailing)
        }
        .padding(.horizontal, 10)
    }
}
