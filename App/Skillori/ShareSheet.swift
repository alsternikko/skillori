import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: What can be passed on

/// The reader's skills as they look to someone who is to get them: the ones a command can add
/// from their source, by source, and the ones it can't, each with why.
struct ShareList {
    struct Row: Identifiable {
        /// The skill's name in lower case: copies in several folders are one row.
        let id: String
        let name: String
        let description: String?
        let skill: SharedSkill
        /// The files on this Mac differ from the source's, and the command adds the source's.
        let changedHere: Bool
    }

    struct Group: Identifiable {
        /// `owner/repo`
        let source: String
        let rows: [Row]
        var id: String { source.lowercased() }
    }

    enum Reason: Error, CaseIterable {
        case noSource, sourceGone, script, key, notGitHub, unwritable

        @MainActor func sentence(_ names: [String]) -> String {
            let one = names.count == 1
            let list = Assist.names(names)
            return switch self {
            case .noSource: "\(list) \(one ? "has" : "have") no known source"
            case .sourceGone: "\(list) \(one ? "has lost its source" : "have lost their source")"
            case .script: "\(list) \(one ? "comes" : "come") from an install script"
            case .key: "\(list) \(one ? "is" : "are") fetched with your own key"
            case .notGitHub: "\(list) \(one ? "isn’t" : "aren’t") from a GitHub repository"
            case .unwritable: "\(list) \(one ? "has a folder name" : "have folder names") that can’t go in a command"
            }
        }
    }

    var groups: [Group] = []
    var leftOut: [(name: String, reason: Reason)] = []

    var rows: [Row] { groups.flatMap(\.rows) }

    /// Why some skills are not offered, in a sentence per reason.
    @MainActor var leftOutSentence: String? {
        guard !leftOut.isEmpty else { return nil }
        let parts = Reason.allCases.compactMap { reason -> String? in
            let names = leftOut.filter { $0.reason == reason }.map(\.name)
            return names.isEmpty ? nil : reason.sentence(names)
        }
        return "Not offered: " + parts.joined(separator: ". ") + "."
    }
}

extension InventoryStore {
    /// How one copy of a skill can be passed on, or why it can't.
    private func shared(_ installation: Installation) -> Result<SharedSkill, ShareList.Reason> {
        if Assist.isManaged(installation) { return .failure(.noSource) }
        if isKeptLocal(installation) { return .failure(.sourceGone) }
        guard let source = upstreamSource(for: installation) else {
            // The installer recorded a source, but not one on GitHub: another host, or a folder.
            if case .skillsLock = installation.provenance { return .failure(.notGitHub) }
            return .failure(.noSource)
        }
        switch source {
        case .installer: return .failure(.script)
        case .package: return .failure(.key)
        case .github(let repository):
            if lostSource(of: installation) != nil { return .failure(.sourceGone) }
            let skill = SharedSkill(name: installation.displayName, source: repository, subpath: sourceSubpath(for: installation))
            return ShareCommand.canCarry(skill) ? .success(skill) : .failure(.unwritable)
        }
    }

    /// Whether a command can add this skill from its source on someone else's computer.
    func canShare(_ installation: Installation) -> Bool {
        if case .success = shared(installation) { true } else { false }
    }

    func shareList() -> ShareList {
        var rows: [ShareList.Row] = []
        var list = ShareList()
        for mine in Assist.mine(self) {
            // The copy the library opens on first; any other copy with a source will do.
            let copies = [mine.primary] + mine.installations.filter { $0.id != mine.primary.id }
            var why: ShareList.Reason?
            var row: ShareList.Row?
            for copy in copies {
                switch shared(copy) {
                case .success(let skill):
                    row = ShareList.Row(id: mine.id, name: mine.name, description: copy.frontmatter.description,
                                        skill: skill, changedHere: status(for: copy) == .changedHere)
                case .failure(let reason):
                    why = why ?? reason
                }
                if row != nil { break }
            }
            if let row { rows.append(row) } else if let why { list.leftOut.append((mine.name, why)) }
        }
        list.groups = Dictionary(grouping: rows) { $0.skill.source.name.lowercased() }.values
            .map { ShareList.Group(source: $0[0].skill.source.name, rows: $0) }
            .sorted { $0.source.lowercased() < $1.source.lowercased() }
        return list
    }

    /// The agents on this Mac that the skills installer can be told to install for, the ones
    /// that read most of the reader's skills first. A few, as they are offered side by side.
    var shareAgents: [Agent] {
        var counts: [Agent: Int] = [:]
        for installation in inventory?.installations ?? [] where !Assist.isManaged(installation) {
            for agent in installation.installedAgents where ShareCommand.installerID(for: agent) != nil {
                counts[agent, default: 0] += 1
            }
        }
        return counts.sorted { ($1.value, $0.key.displayName) < ($0.value, $1.key.displayName) }.prefix(3).map(\.key)
    }
}

// MARK: The sheet

/// Asks the library for the share sheet: for every skill, or opened on one.
struct ShareRequest: Identifiable {
    let id = UUID()
    var only: Installation?
}

/// Passes skills on to someone else. The reader ticks skills and gets one command that adds them
/// from their sources with the skills installer, for a terminal or for a coding agent, on the
/// clipboard or as a script file. Whoever gets it needs no Skillori. Nothing is sent anywhere:
/// the command is the reader's to paste where they like.
struct ShareSheet: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Where the command is meant to be pasted.
    enum Target: String {
        case terminal, agent
    }

    /// What was made, shown in place of the list until the reader is done or goes back.
    enum Outcome: Equatable {
        case copied
        case saved(URL)
    }

    static let targetKey = "share.target"
    static let agentKey = "share.agent"
    /// Where Copy puts the text. A test run points it at a pasteboard of its own, so it never
    /// takes over the clipboard of whoever is working at the Mac.
    @MainActor static var board = NSPasteboard.general

    @State private var list = ShareList()
    @State private var ticked: Set<String> = []
    @State private var started = false
    @State private var target: Target
    /// The id of the one agent to install for. Empty leaves it to the installer.
    @State private var agentID: String
    @State private var outcome: Outcome?
    @State private var problem: String?

    /// Set when the sheet is opened from one skill's page: only that one is ticked.
    private let only: Installation?
    /// Rows left unticked from the start, for pictures.
    private var previewUnticked: Set<String>?

    init(only: Installation? = nil) {
        self.only = only
        let defaults = UserDefaults.standard
        _target = State(initialValue: defaults.string(forKey: Self.targetKey).flatMap(Target.init(rawValue:)) ?? .terminal)
        _agentID = State(initialValue: defaults.string(forKey: Self.agentKey) ?? "")
    }

    /// A fixed state, for pictures: nothing is copied or saved, and no choice is remembered.
    init(preview outcome: Outcome?, target: Target = .terminal, agent: Agent? = nil, unticked: Set<String> = []) {
        only = nil
        previewUnticked = unticked
        _target = State(initialValue: target)
        _agentID = State(initialValue: agent?.id ?? "")
        _outcome = State(initialValue: outcome)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LabelText("Share skills")
                Spacer(minLength: 8)
                LabelText(countLabel)
            }
            .foregroundStyle(Palette.ink2)
            if let outcome {
                receipt(outcome).transition(.opacity)
            } else {
                choosing.transition(.opacity)
            }
        }
        .padding(20)
        .frame(width: 600)
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .font(TypeRole.sans(13))
        .animation(Motion.swap, value: outcome)
        .onAppear(perform: start)
        .onChange(of: target) { if previewUnticked == nil { UserDefaults.standard.set(target.rawValue, forKey: Self.targetKey) } }
        .onChange(of: agentID) { if previewUnticked == nil { UserDefaults.standard.set(agentID, forKey: Self.agentKey) } }
        #if DEBUG
        .onChange(of: ticked, initial: true) { DebugShareProbe.ticked = ticked }
        .onChange(of: outcome, initial: true) { DebugShareProbe.showsReceipt = outcome != nil }
        #endif
    }

    // MARK: Choosing

    private var choosing: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(only.map { "Pass \($0.displayName) on" } ?? "Pass your skills on")
                .font(TypeRole.sans(20, .medium))
                .tracking(-0.4)
                .padding(.top, 14)
            Text("Skillori writes one command that adds the skills you tick from their sources on GitHub, with the skills installer (npx skills). Whoever gets it needs Node.js, not Skillori, and gets each skill as its source has it that day. Only the names of repositories, folders and skills are in it. A private repository works for those who can read it.")
                .font(TypeRole.sans(12))
                .lineSpacing(2)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            HStack(spacing: 6) {
                Spacer(minLength: 8)
                Button("All") { ticked = Set(list.rows.map(\.id)) }
                    .buttonStyle(PillButtonStyle(compact: true))
                    .disabled(ticked.count == list.rows.count)
                Button("None") { ticked = [] }
                    .buttonStyle(PillButtonStyle(compact: true))
                    .disabled(ticked.isEmpty)
            }
            .padding(.top, 14)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(list.groups) { group in
                            header(group)
                            ForEach(group.rows) { row in
                                line(row).id(row.id)
                            }
                        }
                        if started && list.rows.isEmpty {
                            Text("None of your skills has a source on GitHub that a command could add it from.")
                                .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: listHeight)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
                .clipShape(RoundedRectangle(cornerRadius: Radius.block, style: .circular))
                .padding(.top, 8)
                .onChange(of: started) {
                    // Opened from one skill's page: that skill is the one in view.
                    if let name = only?.displayName.lowercased() { proxy.scrollTo(name, anchor: .center) }
                }
            }

            if only == nil, let sentence = list.leftOutSentence {
                Text(sentence)
                    .font(TypeRole.sans(12))
                    .lineSpacing(2)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            VStack(alignment: .leading, spacing: 8) {
                choice("Paste into") {
                    SegmentedChoice(Self.targetOptions, selection: $target, label: "Paste into")
                }
                choice("Install for") {
                    SegmentedChoice(agentOptions, selection: $agentID, label: "Install for")
                }
                Text(choiceNote)
                    .font(TypeRole.sans(12))
                    .lineSpacing(2)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)

            HStack(spacing: 6) {
                Button(target == .agent ? "Copy request" : "Copy command", action: copy)
                    .buttonStyle(PillButtonStyle(prominent: !ticked.isEmpty))
                    .disabled(ticked.isEmpty)
                    .keyboardShortcut(.defaultAction)
                Button("Save as file…", action: save)
                    .buttonStyle(PillButtonStyle())
                    .disabled(ticked.isEmpty)
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                if let problem {
                    Text(problem).font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).padding(.leading, 6)
                }
            }
            .padding(.top, 16)
        }
    }

    /// As tall as its rows up to a point, then it scrolls: a short list leaves no empty card.
    private var listHeight: CGFloat {
        guard !list.rows.isEmpty else { return 56 }
        return min(300, CGFloat(list.rows.count) * 28 + CGFloat(list.groups.count) * 32 + 8)
    }

    private func choice(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 12) {
            LabelText(label).foregroundStyle(Palette.ink2).frame(width: 84, alignment: .leading)
            control()
        }
    }

    /// A source and how many of its skills are ticked. A click ticks them all, or none when all are.
    private func header(_ group: ShareList.Group) -> some View {
        let count = group.rows.filter { ticked.contains($0.id) }.count
        let all = count == group.rows.count
        return Button {
            let ids = group.rows.map(\.id)
            if all { ticked.subtract(ids) } else { ticked.formUnion(ids) }
        } label: {
            HStack(spacing: 10) {
                TickBox(state: all ? .on : count == 0 ? .off : .some)
                Text(group.source).font(TypeRole.mono(11.5, .medium)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                LabelText("\(count) of \(group.rows.count)").foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(all ? "All ticked" : count == 0 ? "None ticked" : "\(count) of \(group.rows.count) ticked")
    }

    private func line(_ row: ShareList.Row) -> some View {
        let isTicked = ticked.contains(row.id)
        return Button {
            if isTicked { ticked.remove(row.id) } else { ticked.insert(row.id) }
        } label: {
            HStack(spacing: 10) {
                TickBox(state: isTicked ? .on : .off)
                Text(row.name).font(TypeRole.sans(13)).lineLimit(1).frame(width: 190, alignment: .leading)
                Text(SkillLine.short(row.description)).font(TypeRole.sans(12)).foregroundStyle(Palette.ink2).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if row.changedHere {
                    LabelText("Changed here").foregroundStyle(Palette.ink3)
                        .help("You changed this skill on this Mac. The command adds it as its source has it, without your changes.")
                }
            }
            .padding(.leading, 30)
            .padding(.trailing, 12)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isTicked ? .isSelected : [])
    }

    // MARK: The receipt

    private func receipt(_ outcome: Outcome) -> some View {
        let made = command
        return VStack(alignment: .leading, spacing: 0) {
            Text(receiptTitle(outcome, made))
                .font(TypeRole.sans(20, .medium))
                .tracking(-0.4)
                .padding(.top, 14)
            Text(receiptNote(outcome, made))
                .font(TypeRole.sans(12))
                .lineSpacing(2)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            switch outcome {
            case .copied:
                ScrollView {
                    Text(text(of: made))
                        .font(TypeRole.mono(11.5))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
                .padding(.top, 16)
            case .saved(let url):
                fileChip(url).padding(.top, 16)
            }

            HStack(spacing: 6) {
                Button("Done") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                switch outcome {
                case .copied:
                    Button("Copy again", action: copy).buttonStyle(PillButtonStyle())
                case .saved(let url):
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(PillButtonStyle())
                }
                Button("Back") { self.outcome = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 16)
        }
    }

    /// The saved file, to drag straight into a chat, a mail or a folder.
    private func fileChip(_ url: URL) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent).font(TypeRole.sans(13, .medium)).lineLimit(1).truncationMode(.middle)
                Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(TypeRole.mono(10.5)).foregroundStyle(Palette.ink2).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            LabelText("Drag to pass it on").foregroundStyle(Palette.ink3)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
        .contentShape(RoundedRectangle(cornerRadius: Radius.block, style: .circular))
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(url.lastPathComponent), saved. Drag it to pass it on.")
    }

    private func receiptTitle(_ outcome: Outcome, _ made: ShareCommand) -> String {
        let skills = made.skillCount == 1 ? (list.rows.first { ticked.contains($0.id) }?.name ?? "one skill")
            : "\(Assist.spelled(made.skillCount).lowercased()) skills"
        switch outcome {
        case .copied: return target == .agent ? "Copied a request for \(skills)" : "Copied a command for \(skills)"
        case .saved(let url): return "Saved \(url.lastPathComponent) for \(skills)"
        }
    }

    private func receiptNote(_ outcome: Outcome, _ made: ShareCommand) -> String {
        let adds = "It adds \(made.counts)" + (made.agent.map { ", for \($0.displayName)" } ?? "") + ", and needs Node.js but not Skillori."
        switch outcome {
        case .copied where target == .agent:
            return "Paste it where you want to pass it on. Whoever gets it pastes it into a coding agent that has a terminal, and the agent runs it and says how it went. " + adds
        case .copied:
            return "Paste it where you want to pass it on. Whoever gets it pastes it into a terminal and presses Return. " + adds
        case .saved(let url):
            return "Pass the file on. Whoever gets it runs sh \(url.lastPathComponent) in a terminal, or gives the file to a coding agent. " + adds
        }
    }

    // MARK: What is made

    private var agents: [Agent] { store.shareAgents }

    private static let targetOptions: [(value: Target, label: String)] = [(.terminal, "Terminal"), (.agent, "Agent")]

    private var agentOptions: [(value: String, label: String)] {
        [(value: "", label: "Any agent")] + agents.map { (value: $0.id, label: $0.displayName) }
    }

    /// The agent to install for, when the remembered one is still offered.
    private var agent: Agent? { agents.first { $0.id == agentID } }

    private var command: ShareCommand {
        ShareCommand(list.rows.filter { ticked.contains($0.id) }.map(\.skill), agent: agent)
    }

    private func text(of command: ShareCommand) -> String {
        target == .agent ? command.prompt : command.line
    }

    private var countLabel: String {
        guard started, !list.rows.isEmpty else { return "" }
        return "\(ticked.count) of \(list.rows.count) skills"
    }

    /// What the two choices mean together, said before anything is made.
    private var choiceNote: String {
        let paste = target == .agent
            ? "The command with a request around it, for a coding agent that has a terminal. The agent says how it went."
            : "One line for a terminal. It also works pasted into a coding agent."
        let install = agent.map { " The skills are installed for \($0.displayName) only." }
            ?? " The installer takes the agents it finds on their computer, and every agent it knows when it finds none."
        return paste + install
    }

    private func start() {
        guard !started else { return }
        list = store.shareList()
        let all = Set(list.rows.map(\.id))
        if let only {
            ticked = all.intersection([only.displayName.lowercased()])
        } else {
            ticked = all.subtracting(previewUnticked ?? [])
        }
        // An agent that is no longer on this Mac is not offered, so it is not chosen either.
        if agent == nil { agentID = "" }
        started = true
    }

    private func copy() {
        let made = command
        guard !made.isEmpty else { return }
        let board = Self.board
        board.clearContents()
        board.setString(text(of: made), forType: .string)
        problem = nil
        outcome = .copied
    }

    private func save() {
        let made = command
        guard !made.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "skills.sh"
        panel.allowedContentTypes = [.shellScript]
        panel.canCreateDirectories = true
        panel.message = "A script that adds \(made.counts)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try made.script.write(to: url, atomically: true, encoding: .utf8)
            problem = nil
            outcome = .saved(url)
        } catch {
            problem = "The file could not be saved there."
        }
    }
}

/// A small box that is ticked, empty, or half: some of what it stands for is ticked.
private struct TickBox: View {
    enum Mark { case on, off, some }
    let state: Mark

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3.5, style: .circular)
        ZStack {
            shape.fill(state == .off ? Color.clear : Palette.ink)
            shape.strokeBorder(Palette.ink.opacity(state == .off ? 0.4 : 0), lineWidth: 1)
            switch state {
            case .on:
                Path { path in
                    path.move(to: CGPoint(x: 3.4, y: 7.2))
                    path.addLine(to: CGPoint(x: 5.9, y: 9.6))
                    path.addLine(to: CGPoint(x: 10.6, y: 4.4))
                }
                .stroke(Palette.onInk, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            case .some:
                Path { path in
                    path.move(to: CGPoint(x: 4, y: 7))
                    path.addLine(to: CGPoint(x: 10, y: 7))
                }
                .stroke(Palette.onInk, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            case .off:
                EmptyView()
            }
        }
        .frame(width: 14, height: 14)
        .animation(Motion.hover, value: state)
        .accessibilityHidden(true)
    }
}
