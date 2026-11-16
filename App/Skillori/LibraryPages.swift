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
}

/// One skill, as a page.
struct SkillPage: View {
    @Environment(InventoryStore.self) private var store
    let installation: Installation
    let backTitle: String
    var back: () -> Void
    var open: (LibraryPage) -> Void
    var onLink: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Crumb(title: backTitle, action: back)
            ScrollView {
                VStack(spacing: 6) {
                    header
                    if let advice { adviceBlock(advice) }
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
            }
            .scrollIndicators(.never)
        }
        .onKeyPress(.escape) { back(); return .handled }
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
        case .noSource: return "Nothing to do. Skillori doesn’t know where it came from, which is fine."
        case .cantCheck(let reason): return "Nothing to do. " + reason.sentence
        case .notChecked: return "Its source hasn’t been asked yet."
        default: return status.sentence
        }
    }

    // MARK: Advice

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
        let history = store.upstreamSource(for: installation)?.historyURL(subpath: store.sourceSubpath(for: installation))
        let web = store.upstreamSource(for: installation)?.webURL(subpath: store.sourceSubpath(for: installation))
        switch status {
        case .updateAvailable:
            let running = store.updater.isRunning
            var extra: [(String, Bool, () -> Void)] = []
            if let history { extra.append(("See what changed", false, { NSWorkspace.shared.open(history) })) }
            extra.append(("Keep this version", false, { store.hold(installation) }))
            return Advice(tone: .new, title: "A newer version is at \(store.upstreamSource(for: installation)?.name ?? "its source")",
                          text: "Updating replaces this copy with the source’s.",
                          todo: Todo(id: "update", app: nil, title: "", detail: "", button: running ? "Updating…" : "▶ Update",
                                     act: .updateSkills([installation]), busy: running, prominent: true),
                          extra: extra)
        case .differs:
            var extra: [(String, Bool, () -> Void)] = []
            if let web { extra.append(("Open source", true, { NSWorkspace.shared.open(web) })) }
            extra.append(("Keep this version", false, { store.hold(installation) }))
            return Advice(tone: .new, title: "The source has other files than this copy",
                          text: "Open the source to see what changed, or keep this version as it is.", extra: extra)
        case .ownerUpdate(let owner, _):
            guard let plugin = installation.plugin else { return nil }
            if owner == "Claude Code" {
                let running = store.pluginUpdater.isRunning
                return Advice(tone: .new, title: "\(plugin.title) has a newer version",
                              text: "Skillori can run Claude Code’s update. Start a new Claude Code session afterwards.",
                              todo: Todo(id: "plugin", app: nil, title: "", detail: "", button: running ? "Updating…" : "▶ Update",
                                         act: .updatePlugins([plugin]), busy: running, prominent: true))
            }
            let has = Assist.appURL(owner) != nil
            return Advice(tone: .new, title: "\(plugin.title) has a newer version",
                          text: "\(owner) installs its own plugins" + (has ? ": open it and choose Update." : "."),
                          todo: has ? Todo(id: "open", app: nil, title: "", detail: "", button: "Open \(owner)", act: .openApp(owner), prominent: true) : nil)
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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(advice.title).font(TypeRole.sans(16, .medium))
                Text(advice.text).font(TypeRole.sans(12.5)).foregroundStyle(advice.tone.blockSecondary).lineLimit(3)
            }
            Spacer(minLength: 12)
            if let todo = advice.todo {
                TodoButton(todo: todo, style: advice.tone.litButton(prominent: true), open: open)
            }
            ForEach(Array(advice.extra.enumerated()), id: \.offset) { _, button in
                Button(button.label, action: button.run).buttonStyle(advice.tone.litButton(prominent: button.prominent && advice.todo == nil))
            }
        }
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
        let readers = Array(Set(copies.flatMap(\.installedAgents))).sorted()
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
                FactRow { Text("Kept current by \(app)") } value: { EmptyView() }
                FactRow { Text(plugin.title) } value: {
                    Text(Assist.versionStep(plugin, latest: store.checksEnabled ? store.pluginReadings[plugin.id]?.state : nil))
                        .font(TypeRole.mono(11.5))
                }
                if let repo = plugin.repository ?? plugin.marketplaceRepository,
                   let url = URL(string: "https://github.com/\(repo)") {
                    Button(repo) { NSWorkspace.shared.open(url) }.buttonStyle(PillButtonStyle()).padding(.top, 8)
                }
            } else if !isMine {
                FactRow { Text("Kept current by \(app)") } value: { EmptyView() }
            } else if let source = store.upstreamSource(for: installation) {
                FactRow { Text(source.name) } value: {
                    if let reading = store.reading(for: installation) { Text("checked " + InventoryStore.stamp(reading.checkedAt)) }
                }
                if case .cantCheck(let reason) = status {
                    Text(reason.sentence).font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).padding(.top, 8)
                }
                HStack(spacing: 6) {
                    if let url = source.webURL(subpath: store.sourceSubpath(for: installation)) {
                        Button("Open source") { NSWorkspace.shared.open(url) }.buttonStyle(PillButtonStyle())
                    }
                    if store.link(for: installation) != nil {
                        Button("Unlink") { store.unlink(installation) }.buttonStyle(PillButtonStyle())
                    }
                }
                .padding(.top, 8)
            } else {
                FactRow { Text("Not known") } value: {
                    Button("Link…", action: onLink).buttonStyle(PillButtonStyle())
                }
                Text("Linking it to a repository lets Skillori tell you when it changes. Optional.")
                    .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).padding(.top, 8)
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
                        TodoLine(todo: todo, tone: .new, open: open)
                            .padding(.horizontal, 20).padding(.vertical, 6)
                            .foregroundStyle(Tone.new.blockForeground)
                            .background { Tone.new.blockBackground(phase: 3) }
                    }
                    VStack(spacing: 0) {
                        ForEach(branches(summary)) { branch in
                            branchRow(branch)
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
        let n = summary.installations.count
        var text = "\(app) keeps \(n == 1 ? "this skill" : "these \(n) skills") current."
        if summary.plugins.count == 1 { text += " They come with \(summary.plugins[0].title)." }
        if summary.plugins.count > 1 { text += " They come in \(summary.plugins.count) plugins." }
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

    /// Plugins with an update first, then the others, then those nobody can ask about folded
    /// into one line, then what the app ships itself.
    private func branches(_ summary: Assist.AppSummary?) -> [Branch] {
        guard let summary else { return [] }
        let updating = Set(summary.updates.map(\.id))
        let byPlugin = Dictionary(grouping: summary.installations) { $0.plugin?.id ?? "" }
        var plugins = summary.plugins.map { plugin in
            Branch(id: plugin.id, title: plugin.title, items: byPlugin[plugin.id] ?? [], plugin: plugin)
        }
        .sorted { a, b in
            let x = updating.contains(a.id), y = updating.contains(b.id)
            if x != y { return x }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        let quiet = plugins.filter { !Self.isCheckable($0.plugin!) }
        if quiet.count > 1 {
            plugins.removeAll { !Self.isCheckable($0.plugin!) }
            plugins.append(Branch(id: "quiet", title: "\(quiet.count) plugins \(app) keeps current", items: quiet.flatMap(\.items)))
        }
        if let own = byPlugin[""], !own.isEmpty {
            plugins.append(Branch(id: "own", title: app == "Claude" ? "From your Claude account" : "Built in", items: own))
        }
        return plugins
    }

    private func branchRow(_ branch: Branch) -> some View {
        let state = branch.plugin.flatMap { store.checksEnabled ? store.pluginReadings[$0.id]?.state : nil }
        let update: Bool = { if case .updateAvailable = state { true } else { false } }()
        return Button {
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
                DataText(branch.plugin.map { Assist.versionStep($0, latest: state) } ?? "").foregroundStyle(Palette.ink2)
                    .frame(width: 170, alignment: .leading)
                Group {
                    if update { StatusChip("Update", kind: .new) } else { Color.clear }
                }
                .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
