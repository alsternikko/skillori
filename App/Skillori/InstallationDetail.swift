import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// One skill, as a page: what it is, what is known about its source, who can see it and
/// where it lives. Everything shown is read from disk or from the installer's record.
struct InstallationDetail: View {
    let installation: Installation
    var number = 1
    var total = 1
    var readAt: Date?
    var agentsOnThisMac: [Agent] = []
    var onBack: () -> Void = {}
    var onStep: (Int) -> Void = { _ in }
    @FocusState private var focused: Bool

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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) { onBack(); return .handled }
        .onKeyPress(.leftArrow) { onStep(-1); return .handled }
        .onKeyPress(.rightArrow) { onStep(1); return .handled }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LabelText("Skill · \(scope) · \(status.word)")
                    Spacer(minLength: 8)
                    LabelText(String(format: "No %03d of %03d", number, total))
                }
                .foregroundStyle(tone.secondary)
                Text(installation.displayName)
                    .font(TypeRole.sans(30, .medium))
                    .tracking(-0.6)
                    .lineLimit(1)
                    .padding(.top, 8)
                    .textSelection(.enabled)
                if let description = installation.frontmatter.description {
                    Text(description)
                        .font(TypeRole.sans(13))
                        .lineSpacing(3)
                        .lineLimit(4)
                        .foregroundStyle(tone.foreground.opacity(0.76))
                        .frame(maxWidth: 560, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 46, trailing: 20))
            .foregroundStyle(tone.foreground)
            .background(tone.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack(spacing: 6) {
                Button("← Library", action: onBack).buttonStyle(PillButtonStyle())
                if let link = sourceLink {
                    Button("Open source") { NSWorkspace.shared.open(link) }.buttonStyle(PillButtonStyle(prominent: true))
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installation.canonicalPath)])
                }
                .buttonStyle(PillButtonStyle(prominent: sourceLink == nil))
                Button("Open SKILL.md") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: installation.canonicalPath).appendingPathComponent("SKILL.md"))
                }
                .buttonStyle(PillButtonStyle())
                Spacer(minLength: 8)
                if let readAt {
                    LabelText("Read \(readAt.formatted(date: .omitted, time: .shortened))").foregroundStyle(Palette.ink2)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 12))
            .background(FrostedSheet(behind: tone.background, cornerRadius: 18))
            .padding(.horizontal, 14)
            .padding(.top, -28)
        }
    }

    private var scope: String {
        let projects = Set(installation.bindings.compactMap(\.projectName))
        return projects.isEmpty ? "Personal" : projects.sorted().joined(separator: ", ")
    }

    private var status: (word: String, tone: Tone) {
        switch installation.provenance {
        case .skillsLock(_, _, _, _, .matchesBaseline): ("Tracked", .rest)
        case .skillsLock(_, _, _, _, .modified): ("Changed here", .new)
        case .skillsLock(_, _, _, _, .hashFailed): ("Check failed", .attention)
        case .managed: ("Managed", .quiet)
        case .unknown: ("Source unknown", .quiet)
        }
    }

    private var tone: Tone { status.tone }

    private var sourceLink: URL? {
        guard case .skillsLock(_, let url?, _, _, _) = installation.provenance else { return nil }
        return URL(string: url.replacingOccurrences(of: ".git", with: ""))
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
                PlateRow("Local copy", isLast: true) {
                    switch local {
                    case .matchesBaseline: value("matches baseline")
                    case .modified(let hash): value("changed", faint: String(hash.prefix(8)))
                    case .hashFailed: value("could not be checked")
                    }
                }
            case .managed(let owner):
                PlateRow("Managed by") { value(owner) }
                PlateRow("Updates", isLast: true) { value("handled by the app") }
            case .unknown:
                PlateRow("Source") { value("not linked", muted: true) }
                PlateRow("Installed by") { value("no record", muted: true) }
                PlateRow("Local copy", isLast: true) { value("no baseline", muted: true) }
            }
        }
    }

    private var plateNote: String {
        switch installation.provenance {
        case .skillsLock(_, _, _, _, .hashFailed): "Not verified"
        case .skillsLock: "Verified by content hash"
        case .managed: "Read-only here"
        case .unknown: "No installer record"
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
        let mine = Set(installation.agents)
        let all = agentsOnThisMac.isEmpty ? installation.agents : agentsOnThisMac
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                LabelText("Visible to")
                Spacer(minLength: 8)
                LabelText("By documented folders")
            }
            .foregroundStyle(Tone.rest.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                DotNumber(String(format: "%02d", mine.count), size: 52)
                Text("of \(all.count) agents Skillori knows")
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

            Text(mine.isEmpty ? "No agent reads this folder." : installation.agents.map(\.displayName).joined(separator: " · "))
                .font(TypeRole.mono(10.5))
                .lineSpacing(3)
                .foregroundStyle(Tone.rest.foreground.opacity(0.8))
                .padding(.top, 12)
                .textSelection(.enabled)
            Spacer(minLength: 16)
            LabelText("Whether an agent loads it depends on its version and settings")
                .foregroundStyle(Tone.rest.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 18, trailing: 20))
        .foregroundStyle(Tone.rest.foreground)
        .background(Tone.rest.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            steps.append(("not yet", "Source asked for changes", false))
        case .managed(let owner):
            steps.append(("no date", "Installed by \(owner)", false))
            if let readAt { steps.append((stamp(readAt), "Read on this Mac", true)) }
        case .unknown:
            steps.append(("no record", "Installed", false))
            if let readAt { steps.append((stamp(readAt), "Read on this Mac", true)) }
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
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
