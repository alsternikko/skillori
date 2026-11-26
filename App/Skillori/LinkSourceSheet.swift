import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// Lets the reader say where a skill with no installer record came from. Skillori asks the
/// named repository for its skill folders, or reads which files a named install script writes,
/// compares them with the files on this Mac, and remembers the folder the reader picks. Given
/// the page the skill was installed from, it reads the page for the commands and repositories it
/// names and follows the one the reader picks. Nothing on disk is changed, and nothing is run.
struct LinkSourceSheet: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let installation: Installation

    init(installation: Installation, preview: InventoryStore.LinkSearch? = nil, package: PackageInfo? = nil, text: String = "",
         page: (host: String, leads: [PageLead])? = nil, via: String? = nil) {
        self.installation = installation
        _text = State(initialValue: text)
        _via = State(initialValue: via)
        _phase = State(initialValue: page.map { Phase.page(host: $0.host, leads: $0.leads) }
            ?? package.map(Phase.package) ?? preview.map(Phase.found) ?? .idle)
        _chosen = State(initialValue: preview?.candidates.first.flatMap { $0.match == .other ? nil : $0.subpath })
    }

    private enum Phase {
        case idle
        case searching
        case found(InventoryStore.LinkSearch)
        /// An installer run with the reader's own key, as npm describes it.
        case package(PackageInfo)
        /// Why the search gave nothing, and the word on the chip before it.
        case failed(String, chip: String)
        /// A page the reader named, and the ways to install it names, to choose from.
        case page(host: String, leads: [PageLead])
    }

    @State private var text: String
    @State private var phase: Phase
    @State private var chosen: String?
    /// The page and line a search followed, said above its result.
    @State private var via: String?
    /// Keep the key on a pasted installer command in the Keychain, for checks.
    @State private var keepKey = true
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LabelText("Link source")
                Spacer(minLength: 8)
                LabelText(installation.displayName)
            }
            .foregroundStyle(Palette.ink2)
            // A skill whose recorded source is gone is asked about where it lives now.
            Text(store.lostSource(of: installation) != nil ? "Where does this skill live now?" : "Where did this skill come from?")
                .font(TypeRole.sans(20, .medium))
                .tracking(-0.4)
                .padding(.top, 14)
            Text("Paste the GitHub repository or the address of the skill's folder in it. If the author shares the skill as an install script on their own site, paste the script's address or the whole curl command. If it comes with an npx command and your own key, paste that; you choose whether Skillori keeps the key, to check for new versions. Or paste the address of the page you installed it from, and Skillori reads the page for how it says to install. Skillori compares the source with the files on this Mac. It reads a script without running it, and nothing is changed.")
                .font(TypeRole.sans(12))
                .lineSpacing(2)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            HStack(spacing: 6) {
                TextField("owner/repository, a GitHub or page address, a curl or npx command", text: $text)
                    .textFieldStyle(.plain)
                    .font(TypeRole.mono(11.5))
                    .focused($fieldFocused)
                    .onSubmit(find)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .circular))
                Button(isSearching ? "Asking…" : "Find", action: find)
                    .buttonStyle(PillButtonStyle(prominent: !hasResult))
                    .disabled(isSearching || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 16)

            result.padding(.top, 14)

            HStack(spacing: 6) {
                Button("Link") {
                    let installation = installation, store = store
                    if case .found(let search) = phase, let candidate = search.candidates.first(where: { $0.subpath == chosen }) {
                        dismiss()
                        AfterSheet.run { store.link(installation, to: candidate, in: search) }
                    } else if case .package(let info) = phase {
                        let arguments = keepKey ? PackageInstaller.arguments(in: text) : nil
                        dismiss()
                        AfterSheet.run {
                            store.link(installation, toPackage: info)
                            if let arguments { store.keepKey(arguments, for: installation) }
                        }
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: hasResult))
                .disabled(!canLink)
                .keyboardShortcut(.defaultAction)
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 520)
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .font(TypeRole.sans(13))
        .onAppear { fieldFocused = true }
    }

    /// The host being asked, for the line shown while waiting.
    private var askedHost: String {
        switch SkillSource.parse(text)?.source {
        case .installer(let script)?: return script.url.host ?? "the site"
        case .package?: return "npm"
        default: return "github.com"
        }
    }

    private var isSearching: Bool { if case .searching = phase { true } else { false } }
    private var hasResult: Bool {
        switch phase {
        case .found, .package: true
        default: false
        }
    }
    private var canLink: Bool {
        switch phase {
        case .found: chosen != nil
        case .package: true
        default: false
        }
    }

    @ViewBuilder private var result: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .searching:
            Text("Asking \(askedHost)…").font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
        case .failed(let sentence, let chip):
            VStack(alignment: .leading, spacing: 6) {
                viaLine
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    StatusChip(chip, kind: .attention, mark: "✕")
                    Text(sentence).font(TypeRole.sans(12)).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .page(let host, let leads):
            VStack(alignment: .leading, spacing: 8) {
                Text("\(host) names \(leads.count == 1 ? "one way" : "\(leads.count) ways") to install skills. Choose the one you used, and Skillori compares it with this skill.")
                    .font(TypeRole.sans(13, .medium))
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(leads) { lead in
                            leadRow(lead, host: host, isLast: lead.id == leads.last?.id)
                        }
                    }
                }
                .frame(maxHeight: 216)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
                .clipShape(RoundedRectangle(cornerRadius: Radius.block, style: .circular))
            }
        case .package(let info):
            VStack(alignment: .leading, spacing: 6) {
                viaLine
                Text(info.site.map { "\(info.package) installs skills from \($0.host.map(Self.bare) ?? $0.absoluteString) with your own key." }
                     ?? "\(info.package) installs skills with your own key.")
                    .font(TypeRole.sans(13, .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let summary = info.summary, !summary.isEmpty {
                    Text("npm: “\(summary)”")
                        .font(TypeRole.sans(12))
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if PackageInstaller.arguments(in: text) != nil {
                    Toggle("Keep my key in the Keychain, so Skillori can check for new versions", isOn: $keepKey)
                        .toggleStyle(.checkbox)
                        .font(TypeRole.sans(12.5))
                        .padding(.top, 4)
                }
                Text(PackageInstaller.arguments(in: text) != nil && keepKey
                     ? "To check, Skillori runs the installer now and then into a folder of its own, compares what it gets with this copy, and removes the folder. Your key stays in your Keychain and goes only where the installer sends it."
                     : "Skillori keeps only the installer’s name. Without your key it can’t see new versions; you can add it later from the skill’s page.")
                    .font(TypeRole.sans(12))
                    .lineSpacing(2)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .found(let search):
            VStack(alignment: .leading, spacing: 8) {
                viaLine
                Text(summary(of: search))
                    .font(TypeRole.sans(13, .medium))
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(search.candidates) { candidate in
                            row(candidate, isLast: candidate.id == search.candidates.last?.id)
                        }
                    }
                }
                .frame(maxHeight: 216)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
                .clipShape(RoundedRectangle(cornerRadius: Radius.block, style: .circular))
            }
        }
    }

    /// Where the result came from, when it was followed from a page.
    @ViewBuilder private var viaLine: some View {
        if let via {
            Text("From \(via)")
                .font(TypeRole.mono(10.5))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// One way to install that a page names. Choosing it follows it.
    private func leadRow(_ lead: PageLead, host: String, isLast: Bool) -> some View {
        HStack(spacing: 10) {
            Text("→").font(TypeRole.mono(11.5)).foregroundStyle(Palette.ink2)
            Text(lead.line)
                .font(TypeRole.mono(11.5))
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch lead.source {
            case .github: StatusChip("Repository", kind: .outline)
            case .installer: StatusChip("Script", kind: .outline)
            case .package: StatusChip("Installer", kind: .outline)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { if !isLast { Palette.line.frame(height: 1) } }
        .contentShape(Rectangle())
        .onTapGesture { follow(lead, from: host) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func row(_ candidate: SourceCandidate, isLast: Bool) -> some View {
        let isChosen = candidate.subpath == chosen
        return HStack(spacing: 10) {
            Text(isChosen ? "●" : "○").font(TypeRole.mono(11.5))
            Text(candidate.subpath.isEmpty ? "top of the source" : candidate.subpath)
                .font(TypeRole.mono(11.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch candidate.match {
            case .identical: StatusChip("Same content", mark: "●")
            case .sameName: StatusChip("Same name", kind: .outline)
            case .other: EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Palette.ink.opacity(isChosen ? 0.06 : 0))
        .overlay(alignment: .bottom) { if !isLast { Palette.line.frame(height: 1) } }
        .contentShape(Rectangle())
        .onTapGesture { chosen = candidate.subpath }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    private func summary(of search: InventoryStore.LinkSearch) -> String {
        let best = search.candidates.first?.match
        let name = search.source.name
        if case .installer = search.source {
            switch best {
            case .identical: return "The script writes the same content as this copy."
            case .sameName: return "The script writes a skill with the same name but other files. It may be a newer version."
            default: return "The script writes no skill with the same content or name. Choose one only if you know it is the right one."
            }
        }
        switch best {
        case .identical: return "Found the same content in \(name)."
        case .sameName: return "No folder in \(name) has the same content. One has the same name; it may be a newer version."
        default: return "No folder in \(name) has the same content or name. Choose one only if you know it is the right one."
        }
    }

    private static func bare(_ host: String) -> String { host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }

    private func find() {
        via = nil
        search(followingPage: false)
    }

    /// Puts what the page names in the field and looks there, saying where it came from.
    private func follow(_ lead: PageLead, from host: String) {
        text = lead.text
        via = host + ": " + lead.line
        search(followingPage: true)
    }

    /// The page behind an address that turned out not to be a script, read for what it names.
    /// One way to install is followed at once; several are offered.
    /// `moved` is what a script said when it answered "gone" and pointed here: said again when
    /// the page shows nothing to follow, since it may need the reader to sign in.
    private func readPage(_ url: URL, moved: SourceNotice? = nil) async {
        let host = url.host.map(Self.bare) ?? url.absoluteString
        if let moved {
            switch await store.readPage(url) {
            case .success(let leads) where leads.count == 1: follow(leads[0], from: host)
            case .success(let leads) where !leads.isEmpty: phase = .page(host: host, leads: leads)
            default:
                phase = .failed("The script says: “\(moved.message)” Skillori can’t see an install command at \(url.absoluteString). "
                                + "If you have to sign in there, copy the new install command and paste it here.", chip: "Moved")
            }
            return
        }
        switch await store.readPage(url) {
        case .success(let leads) where leads.count == 1:
            follow(leads[0], from: host)
        case .success(let leads) where !leads.isEmpty:
            phase = .page(host: host, leads: leads)
        case .success:
            phase = .failed("\(host) shows no install command or GitHub repository that anyone can see. If you have to sign in to see it, copy the install command from the page and paste it here.", chip: "Nothing found")
        case .failure(.notFound):
            phase = .failed("\(host) has no page at that address.", chip: "Not found")
        case .failure(.offline):
            phase = .failed("No contact with \(host). Check the connection and try again.", chip: "No contact")
        case .failure:
            phase = .failed("\(host) gave an answer Skillori couldn’t read. Try again in a while.", chip: "No answer")
        }
    }

    private func search(followingPage: Bool) {
        guard !isSearching else { return }
        phase = .searching
        chosen = nil
        if case .package(let installer)? = SkillSource.parse(text)?.source {
            Task {
                switch await store.lookUpPackage(installer) {
                case .success(let info): phase = .package(info)
                case .failure(.notFound):
                    phase = .failed("npm has no package called \(installer.package). Check the command and try again.", chip: "Not found")
                case .failure(.offline):
                    phase = .failed("No contact with npm. Check the connection and try again.", chip: "No contact")
                case .failure(.rateLimited):
                    phase = .failed("npm asked Skillori to wait. Try again in a while.", chip: "Wait")
                case .failure:
                    phase = .failed("npm gave an answer Skillori couldn’t read. Try again in a while.", chip: "No answer")
                }
            }
            return
        }
        Task {
            switch await store.searchSource(text, for: installation) {
            case .failure(.source(.rateLimited, _)):
                // Nothing asks again from here, so say when the reader can.
                let at = await GitHubBudget.shared.retryAt
                phase = .failed("GitHub asked Skillori to wait. "
                                + (at.map { "Try again after \(InventoryStore.stamp($0))." } ?? "Try again in a while."), chip: "Wait")
            case .failure(.source(.offline, _)):
                phase = .failed("No contact with the source. Check the connection and try again.", chip: "No contact")
            case .failure(.source(.failed, installer: true)) where !followingPage:
                // Not a script: most likely the page the skill was installed from.
                if case .installer(let address)? = SkillSource.parse(text)?.source {
                    await readPage(address.url)
                } else {
                    phase = .failed(InventoryStore.LinkProblem.source(.failed, installer: true).sentence, chip: "Not found")
                }
            case .failure(.moved(let notice)) where !followingPage:
                if let url = notice.url {
                    await readPage(url, moved: notice)
                } else {
                    phase = .failed("The script says: “\(notice.message)” "
                                    + InventoryStore.LinkProblem.moved(notice).sentence, chip: "Moved")
                }
            case .failure(let problem):
                phase = .failed(problem.sentence, chip: "Not found")
            case .success(let search):
                // Pre-select only what the evidence supports: the folder the address named, or a real match.
                if let suggested = search.suggested, search.candidates.contains(where: { $0.subpath == suggested }) {
                    chosen = suggested
                } else if let first = search.candidates.first, first.match != .other {
                    chosen = first.subpath
                }
                phase = .found(search)
            }
        }
    }
}
