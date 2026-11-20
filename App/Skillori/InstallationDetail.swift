import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// One skill, as a page: what it is, what is known about its source, who can see it and
/// where it lives. Everything shown is read from disk or from the installer's record.
struct InstallationDetail: View {
    @Environment(InventoryStore.self) private var store
    let installation: Installation
    var number = 1
    var total = 1
    var readAt: Date?
    var agentsOnThisMac: [Agent] = []
    var onBack: () -> Void = {}
    /// Opens the sheet where the reader points out this skill's source.
    var onLink: () -> Void = {}
    var onStep: (Int) -> Void = { _ in }
    @FocusState private var focused: Bool
    /// The files the update would touch, once the source has been asked.
    @State private var changes: Result<[FileChange], UpstreamState.Reason>?

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                header
                HStack(alignment: .top, spacing: 6) {
                    typePlate
                    visibility
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 6) {
                    record
                    locations
                }
                .fixedSize(horizontal: false, vertical: true)
                if !installation.frontmatter.problems.isEmpty { problems }
            }
        }
        .scrollIndicators(.never)
        .clipShape(RoundedRectangle(cornerRadius: Radius.block, style: .circular))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .task(id: "\(installation.id)·\(status.word)") {
            changes = nil
            guard showsChanges else { return }
            changes = await store.fileChanges(for: installation)
        }
        .onKeyPress(.escape) { onBack(); return .handled }
        .onKeyPress(.leftArrow) { onStep(-1); return .handled }
        .onKeyPress(.rightArrow) { onStep(1); return .handled }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            // Where this is, and the way back.
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Text("← LIBRARY").font(TypeRole.mono(11.5, .medium)).foregroundStyle(Palette.ink)
                }
                .buttonStyle(.plain)
                DataText("/").foregroundStyle(Palette.ink3)
                DataText(installation.displayName).foregroundStyle(Palette.ink2).lineLimit(1)
                Spacer(minLength: 8)
            }
            .frame(height: 30)
            .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    LabelText("Skill · \(scope) · \(status.word)")
                        .accessibilityLabel("Skill, \(scope), \(status.word)")
                    Spacer(minLength: 8)
                    LabelText(String(format: "No %03d of %03d", number, total))
                }
                .foregroundStyle(tone.secondary)
                Text(installation.displayName)
                    .font(TypeRole.sans(30, .medium))
                    .tracking(-0.6)
                    .lineLimit(1)
                    .padding(.top, 14)
                    .textSelection(.enabled)
                if let description = installation.frontmatter.description {
                    Text(description)
                        .font(TypeRole.sans(13))
                        .lineSpacing(3)
                        .lineLimit(4)
                        .foregroundStyle(tone.foreground.opacity(0.76))
                        .frame(maxWidth: 560, alignment: .leading)
                        .padding(.top, 8)
                }
                // What the status means for this skill, in one sentence.
                Text(status.sentence)
                    .font(TypeRole.sans(13, .medium))
                    .padding(.top, 14)
                // The update is a command; it is shown as one, with a button that runs it.
                if case .updateAvailable = status {
                    CommandFrame(installations: [installation]).padding(.top, 12)
                }
                if showsChanges {
                    ChangedFiles(changes: changes, tone: tone).padding(.top, 10)
                }
                // The actions sit in the block they act on, under a hairline.
                tone.foreground.opacity(0.18).frame(height: 1).padding(.top, 14)
                HStack(spacing: 6) {
                    let history = store.upstreamSource(for: installation)?.historyURL(subpath: subpath)
                    switch status {
                    case .updateAvailable:
                        if let history {
                            Button("See what changed") { NSWorkspace.shared.open(history) }
                                .buttonStyle(PillButtonStyle(prominent: true, on: tone))
                        }
                        Button("Hold back") { store.hold(installation) }.buttonStyle(PillButtonStyle(on: tone))
                    case .heldBack(let moved):
                        Button("Release") { store.release(installation) }
                            .buttonStyle(PillButtonStyle(prominent: true, on: tone))
                        if moved, let history {
                            Button("See what changed") { NSWorkspace.shared.open(history) }
                                .buttonStyle(PillButtonStyle(on: tone))
                        }
                    case .differs:
                        if case .installer(let script)? = store.upstreamSource(for: installation) {
                            CopyInstallCommandButton(script: script, prominent: true, tone: tone)
                        }
                        if let link = sourceLink {
                            Button("Open source") { NSWorkspace.shared.open(link) }
                                .buttonStyle(PillButtonStyle(prominent: !isInstallerSource, on: tone))
                        }
                        Button("Hold back") { store.hold(installation) }.buttonStyle(PillButtonStyle(on: tone))
                    case .noSource:
                        Button("Link source…", action: onLink).buttonStyle(PillButtonStyle(prominent: true, on: tone))
                    default:
                        if store.canLink(installation) {
                            // The installer's recorded source is gone, or one Skillori can't ask.
                            Button("Link source…", action: onLink).buttonStyle(PillButtonStyle(prominent: true, on: tone))
                        } else if let link = sourceLink {
                            Button("Open source") { NSWorkspace.shared.open(link) }
                                .buttonStyle(PillButtonStyle(prominent: true, on: tone))
                        }
                    }
                    if store.link(for: installation) != nil {
                        Button("Unlink") { store.unlink(installation) }.buttonStyle(PillButtonStyle(on: tone))
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installation.canonicalPath)])
                    }
                    .buttonStyle(PillButtonStyle(prominent: sourceLink == nil && status != .noSource, on: tone))
                    Button("Open SKILL.md") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: installation.canonicalPath).appendingPathComponent("SKILL.md"))
                    }
                    .buttonStyle(PillButtonStyle(on: tone))
                    Spacer(minLength: 8)
                    if let reading = store.reading(for: installation) {
                        LabelText("Checked \(InventoryStore.stamp(reading.checkedAt))").foregroundStyle(tone.secondary)
                    }
                }
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 14, trailing: 20))
            .foregroundStyle(tone.foreground)
            .background(tone.background, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
        }
    }

    private var scope: String {
        let projects = Set(installation.bindings.compactMap(\.projectName))
        return projects.isEmpty ? "Personal" : projects.sorted().joined(separator: ", ")
    }

    private var status: SkillStatus { store.status(for: installation) }

    /// The source has other files than this Mac: say which, before anything is run.
    private var showsChanges: Bool {
        switch status {
        case .updateAvailable, .differs, .heldBack(sourceMoved: true): true
        default: false
        }
    }

    private var tone: Tone { status.tone }

    private var subpath: String? { store.sourceSubpath(for: installation) }

    private var isInstallerSource: Bool {
        if case .installer? = store.upstreamSource(for: installation) { true } else { false }
    }

    private var sourceLink: URL? {
        store.upstreamSource(for: installation)?.webURL(subpath: subpath)
    }

    // MARK: Type plate

    private var typePlate: some View {
        DetailCard(label: "Type plate", note: plateNote) {
            switch installation.provenance {
            case .skillsLock(let source, _, let subpath, let baseline, let local):
                PlateRow("ID") { value(baseline.map { String($0.prefix(8)) } ?? "not recorded", faint: "tree hash") }
                PlateRow("Source") {
                    if let link = sourceLink {
                        Button(source) { NSWorkspace.shared.open(link) }.buttonStyle(ValueLinkStyle())
                    } else {
                        value(source)
                    }
                }
                PlateRow("Path in source") { value(subpath ?? "top level") }
                PlateRow("Installed by") { value("npx skills") }
                PlateRow("Local copy") {
                    switch local {
                    case .matchesBaseline: value("matches baseline")
                    case .modified(let hash): value("changed", faint: String(hash.prefix(8)))
                    case .hashFailed: value("could not be checked")
                    }
                }
                PlateRow("Source now") {
                    switch store.reading(for: installation)?.state {
                    case .upToDate: value("same as installed")
                    case .updateAvailable(let upstream): value(String(upstream.prefix(8)), faint: "changed")
                    case .cannotCheck(let reason): value(reason.short, muted: true)
                    case nil: value(store.checksEnabled ? "not asked yet" : "checks are off", muted: true)
                    }
                }
                PlateRow("Checked", isLast: true) {
                    if let reading = store.reading(for: installation) {
                        value(InventoryStore.stamp(reading.checkedAt))
                    } else {
                        value("never", muted: true)
                    }
                }
            case .managed(let owner):
                if let plugin = installation.plugin {
                    PlateRow("Plugin") { value(plugin.name, faint: plugin.marketplace) }
                    PlateRow("Installed") {
                        value(plugin.version ?? plugin.commit.map { String($0.prefix(8)) } ?? "no version recorded",
                              muted: plugin.version == nil && plugin.commit == nil)
                    }
                    if let from = plugin.repository ?? plugin.marketplaceRepository {
                        PlateRow("Source") { value(from) }
                    }
                    if plugin.enabled == false {
                        PlateRow("In \(plugin.app)") { value("turned off") }
                    }
                    PlateRow("Source now", isLast: true) {
                        switch store.pluginReadings[plugin.id]?.state {
                        case .upToDate: value("same as installed")
                        case .updateAvailable(let latest): value(String(latest.prefix(12)), faint: "update in \(plugin.app)")
                        case .cannotCheck(.unsupported): value("updated with \(plugin.app)", muted: true)
                        case .cannotCheck(let reason): value(reason.short, muted: true)
                        case nil: value(store.checksEnabled ? "not asked yet" : "checks are off", muted: true)
                        }
                    }
                } else {
                    PlateRow("Managed by") { value(owner) }
                    PlateRow("Updates", isLast: true) { value("handled by the app") }
                }
            case .unknown:
                if let link = store.link(for: installation) {
                    PlateRow("Source") {
                        Button(link.source.name) { if let url = sourceLink { NSWorkspace.shared.open(url) } }
                            .buttonStyle(ValueLinkStyle())
                    }
                    PlateRow("Path in source") { value(link.subpath.isEmpty ? "top level" : link.subpath) }
                    PlateRow("Linked") { value(InventoryStore.stamp(link.linkedAt), faint: "by you") }
                    if let note = link.note {
                        PlateRow("Found by") {
                            Text(note).font(TypeRole.sans(12)).foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    PlateRow("Local copy") {
                        value(link.localHash.map { String($0.prefix(8)) } ?? "could not be read", faint: "tree hash")
                    }
                    PlateRow("Source now") {
                        switch store.reading(for: installation)?.state {
                        case .upToDate: value("same content")
                        case .updateAvailable(let upstream): value(String(upstream.prefix(8)), faint: "differs")
                        case .cannotCheck(let reason): value(reason.short, muted: true)
                        case nil: value("not asked yet", muted: true)
                        }
                    }
                    PlateRow("Checked", isLast: true) {
                        if let reading = store.reading(for: installation) {
                            value(InventoryStore.stamp(reading.checkedAt))
                        } else {
                            value("never", muted: true)
                        }
                    }
                } else {
                PlateRow("Source") { value("not linked", muted: true) }
                PlateRow("Installed by") { value("no record", muted: true) }
                PlateRow("Local copy", isLast: true) { value("no baseline", muted: true) }
                }
            }
        }
    }

    private var plateNote: String {
        switch installation.provenance {
        case .skillsLock(_, _, _, _, .hashFailed): "Not verified"
        case .skillsLock: "Verified by content hash"
        case .managed: "Read-only here"
        case .unknown: store.link(for: installation) == nil ? "No installer record" : "Linked by you"
        }
    }

    private func value(_ text: String, faint: String? = nil, muted: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(text).foregroundStyle(muted ? Palette.ink3 : Palette.ink)
            if let faint { Text(faint).foregroundStyle(Palette.ink3) }
        }
        .font(TypeRole.mono(11.5))
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
    }

    // MARK: Visible to

    private var visibility: some View {
        let mine = Set(installation.installedAgents)
        let all = agentsOnThisMac.isEmpty ? installation.installedAgents : agentsOnThisMac
        let absent = installation.absentAgents
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                LabelText("Visible to")
                Spacer(minLength: 8)
                LabelText("By documented folders")
            }
            .foregroundStyle(Tone.rest.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                DotNumber(String(format: "%02d", mine.count), size: 52)
                Text("of \(all.count) agents on this Mac")
                    .font(TypeRole.sans(13))
                    .foregroundStyle(Tone.rest.secondary)
            }
            .padding(.top, 18)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(all, id: \.id) { agent in
                    Rectangle()
                        .frame(width: mine.contains(agent) ? 2 : 1, height: mine.contains(agent) ? 18 : 8)
                        .opacity(mine.contains(agent) ? 1 : 0.4)
                        .frame(maxWidth: .infinity)
                        .help(agent.displayName)
                }
            }
            .padding(.top, 22)
            Rectangle().frame(height: 1).opacity(0.5)

            Text(mine.isEmpty ? "No agent on this Mac reads this folder." : installation.installedAgents.map(\.displayName).joined(separator: " · "))
                .font(TypeRole.mono(10.5))
                .lineSpacing(3)
                .foregroundStyle(Tone.rest.foreground.opacity(0.8))
                .padding(.top, 12)
                .textSelection(.enabled)
            if !absent.isEmpty {
                // The folder is documented for these too; they would read it if installed.
                Text("Also read by \(absent.map(\.displayName).joined(separator: ", ")), if installed")
                    .font(TypeRole.sans(11))
                    .foregroundStyle(Tone.rest.secondary)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            LabelText("Whether an agent loads it depends on its version and settings")
                .foregroundStyle(Tone.rest.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 18, trailing: 20))
        .foregroundStyle(Tone.rest.foreground)
        .background(Tone.rest.background, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
    }

    // MARK: Record

    /// What can be shown with a date, in order. Anything not recorded is a gap, not a guess.
    private var record: some View {
        let steps = recordSteps
        return DetailCard(label: "Record", note: nil) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Rectangle().fill(Palette.ink).frame(width: 9, height: 1).offset(y: -4)
                            .opacity(step.known ? 1 : 0)
                        DataText(step.when).frame(width: 104, alignment: .leading)
                            .foregroundStyle(step.known ? Palette.ink2 : Palette.ink3)
                        Text(step.what).font(TypeRole.sans(13))
                            .foregroundStyle(step.known ? Palette.ink : Palette.ink3)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 30)
                    .overlay(alignment: .leading) {
                        // The line is solid for a proven step and broken for a gap.
                        Rectangle().fill(Palette.ink).frame(width: 1)
                            .opacity(step.known ? 1 : 0)
                    }
                }
            }
            .padding(.top, 6)
            Text("A step that cannot be proven is drawn as a gap in the line, never as a guess.")
                .font(TypeRole.sans(12))
                .foregroundStyle(Palette.ink2)
                .padding(.top, 12)
                .padding(.bottom, 6)
        }
    }

    private var recordSteps: [(when: String, what: String, known: Bool)] {
        func stamp(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        }
        var steps: [(String, String, Bool)] = []
        switch installation.provenance {
        case .skillsLock(_, _, _, _, let local):
            if let installed = installation.installedAt {
                steps.append((stamp(installed), "Installed with npx skills", true))
            } else {
                steps.append(("no date", "Installed with npx skills", false))
            }
            if let move = store.move(of: installation) {
                steps.append((stamp(move.at), "Moved from \(move.from) by you", true))
            }
            if let updated = installation.updatedAt, updated != installation.installedAt {
                steps.append((stamp(updated), "Updated by npx skills", true))
            }
            if let readAt {
                switch local {
                case .matchesBaseline: steps.append((stamp(readAt), "Read, matches baseline", true))
                case .modified: steps.append((stamp(readAt), "Read, changed since install", true))
                case .hashFailed: steps.append((stamp(readAt), "Read, could not be checked", true))
                }
            }
            if let reading = store.reading(for: installation) {
                let what = switch reading.state {
                case .upToDate: "Source asked, no changes"
                case .updateAvailable: "Source asked, it has changed"
                case .cannotCheck(let reason): "Source asked, \(reason.short)"
                }
                steps.append((stamp(reading.checkedAt), what, true))
            } else {
                steps.append(("not yet", "Source asked for changes", false))
            }
            if let key = store.sourceKey(for: installation), let since = store.held[key] {
                steps.append((stamp(since), "Held back by you", true))
            }
        case .managed(let owner):
            steps.append(("no date", "Installed by \(owner)", false))
            if let readAt { steps.append((stamp(readAt), "Read on this Mac", true)) }
        case .unknown:
            steps.append(("no record", "Installed", false))
            if let readAt { steps.append((stamp(readAt), "Read on this Mac", true)) }
            if let link = store.link(for: installation) {
                steps.append((stamp(link.linkedAt), "Linked to \(link.source.name) by you", true))
                if let reading = store.reading(for: installation) {
                    let what = switch reading.state {
                    case .upToDate: "Source asked, same content"
                    case .updateAvailable: "Source asked, content differs"
                    case .cannotCheck(let reason): "Source asked, \(reason.short)"
                    }
                    steps.append((stamp(reading.checkedAt), what, true))
                }
                if let key = store.sourceKey(for: installation), let since = store.held[key] {
                    steps.append((stamp(since), "Held back by you", true))
                }
            }
        }
        return steps
    }

    // MARK: Locations

    private var locations: some View {
        let links = installation.bindings.filter { $0.discoveredPath != installation.canonicalPath }
        return DetailCard(label: "Locations",
                          note: "1 copy · \(links.count) link\(links.count == 1 ? "" : "s")") {
            HStack(spacing: 8) {
                Text(installation.canonicalPath.abbreviatedHome)
                    .font(TypeRole.mono(11.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(installation.canonicalPath)
                Spacer(minLength: 8)
                StatusChip("Copy")
            }
            .frame(height: 38)
            .overlay(alignment: .bottom) { if !links.isEmpty { Palette.line.frame(height: 1) } }

            ForEach(Array(links.enumerated()), id: \.element.discoveredPath) { index, binding in
                HStack(spacing: 10) {
                    DataText(index == links.count - 1 ? "└─" : "├─").foregroundStyle(Palette.ink3)
                    Text(binding.agents.isEmpty ? "No agent" : binding.agents.map(\.displayName).joined(separator: ", "))
                        .font(TypeRole.sans(13))
                        .lineLimit(1)
                        .help(binding.agents.map(\.displayName).joined(separator: ", "))
                    Spacer(minLength: 8)
                    DataText(((binding.discoveredPath as NSString).deletingLastPathComponent).abbreviatedHome)
                        .truncationMode(.middle)
                        .foregroundStyle(Palette.ink2)
                        .layoutPriority(1)
                        .help(binding.discoveredPath)
                    if !binding.viaSymlink { StatusChip("Also here", kind: .outline) }
                }
                .frame(height: 38)
                .overlay(alignment: .bottom) { if index < links.count - 1 { Palette.line.frame(height: 1) } }
            }
        }
    }

    // MARK: Problems

    private var problems: some View {
        DetailCard(label: "Problems in SKILL.md", note: "\(installation.frontmatter.problems.count) found") {
            ForEach(Array(installation.frontmatter.problems.enumerated()), id: \.offset) { index, problem in
                HStack(spacing: 10) {
                    StatusChip("Check", kind: .attention)
                    Text(problem).font(TypeRole.sans(13)).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 38)
                .overlay(alignment: .bottom) {
                    if index < installation.frontmatter.problems.count - 1 { Palette.line.frame(height: 1) }
                }
            }
        }
    }
}

/// A card with a mono label row on top.
private struct DetailCard<Content: View>: View {
    let label: String
    let note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LabelText(label)
                Spacer(minLength: 8)
                if let note { LabelText(note) }
            }
            .foregroundStyle(Palette.ink2)
            .padding(.bottom, 6)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 10, trailing: 20))
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
    }
}

/// A mono label on the left and a value on the right, with a hairline under it.
private struct PlateRow<Value: View>: View {
    let label: String
    let isLast: Bool
    let value: Value

    init(_ label: String, isLast: Bool = false, @ViewBuilder value: () -> Value) {
        self.label = label
        self.isLast = isLast
        self.value = value()
    }

    var body: some View {
        HStack(spacing: 0) {
            LabelText(label).foregroundStyle(Palette.ink2).frame(width: 118, alignment: .leading)
            value
            Spacer(minLength: 0)
        }
        .frame(height: 35)
        .overlay(alignment: .bottom) { if !isLast { Palette.line.frame(height: 1) } }
    }
}

private struct ValueLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeRole.mono(11.5))
            .underline()
            .lineLimit(1)
            .foregroundStyle(Palette.ink)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

struct PathText: View {
    let path: String
    init(_ path: String) { self.path = path }

    var body: some View {
        Text(path.abbreviatedHome)
            .font(TypeRole.mono(11.5))
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.middle)
            .help(path)
    }
}

private extension String {
    var abbreviatedHome: String { (self as NSString).abbreviatingWithTildeInPath }
}

/// The files an update would add, change or remove, runnable ones first. Told from file ids,
/// so nothing from the source is downloaded or opened to show it.
private struct ChangedFiles: View {
    let changes: Result<[FileChange], UpstreamState.Reason>?
    let tone: Tone
    private static let shown = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch changes {
            case nil:
                LabelText("Asking the source which files differ…").foregroundStyle(tone.secondary)
            case .failure(let reason)?:
                LabelText("Files: \(reason.short)").foregroundStyle(tone.secondary)
            case .success(let list)?:
                let runnable = list.filter(\.runnable).count
                HStack(spacing: 8) {
                    LabelText(list.count == 1 ? "1 file differs" : "\(list.count) files differ")
                    if runnable > 0 {
                        LabelText("· \(runnable) can run").foregroundStyle(tone.foreground)
                    }
                }
                .foregroundStyle(tone.secondary)
                if runnable > 0 {
                    Text("Read the files that can run before you update. An agent may run them with your rights.")
                        .font(TypeRole.sans(12))
                        .padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(list.prefix(Self.shown)) { change in
                        HStack(spacing: 8) {
                            Text(mark(change.kind)).frame(width: 10)
                            Text(change.path).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            if change.modeOnly { Text("MODE").foregroundStyle(tone.secondary) }
                            if change.runnable { Text("RUNS") }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(change.kind.rawValue): \(change.path)\(change.runnable ? ", can run" : "")")
                    }
                    if list.count > Self.shown {
                        Text("and \(list.count - Self.shown) more").foregroundStyle(tone.secondary)
                    }
                }
                .font(TypeRole.mono(11))
                .padding(.top, 8)
                .textSelection(.enabled)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func mark(_ kind: FileChange.Kind) -> String {
        switch kind {
        case .added: "+"
        case .changed: "~"
        case .removed: "−"
        }
    }
}
