import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// Lets the reader say where a skill with no installer record came from. Skillori asks the
/// named repository for its skill folders, or reads which files a named install script writes,
/// compares them with the files on this Mac, and remembers the folder the reader picks.
/// Nothing on disk is changed, and a script is never run.
struct LinkSourceSheet: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let installation: Installation

    init(installation: Installation, preview: InventoryStore.LinkSearch? = nil, text: String = "") {
        self.installation = installation
        _text = State(initialValue: text)
        _phase = State(initialValue: preview.map(Phase.found) ?? .idle)
        _chosen = State(initialValue: preview?.candidates.first.flatMap { $0.match == .other ? nil : $0.subpath })
    }

    private enum Phase {
        case idle
        case searching
        case found(InventoryStore.LinkSearch)
        /// Why the search gave nothing, and the word on the chip before it.
        case failed(String, chip: String)
    }

    @State private var text: String
    @State private var phase: Phase
    @State private var chosen: String?
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
            Text("Paste the GitHub repository or the address of the skill's folder in it. If the author shares the skill as an install script on their own site, paste the script's address or the whole curl command. Skillori compares the source with the files on this Mac. It reads a script without running it, and nothing is changed.")
                .font(TypeRole.sans(12))
                .lineSpacing(2)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            HStack(spacing: 6) {
                TextField("owner/repository, https://github.com/… or a script address", text: $text)
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
                    if case .found(let search) = phase, let candidate = search.candidates.first(where: { $0.subpath == chosen }) {
                        store.link(installation, to: candidate, in: search)
                        dismiss()
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: hasResult))
                .disabled(chosen == nil || !hasResult)
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
        if case .installer(let script)? = SkillSource.parse(text)?.source { return script.url.host ?? "the site" }
        return "github.com"
    }

    private var isSearching: Bool { if case .searching = phase { true } else { false } }
    private var hasResult: Bool { if case .found = phase { true } else { false } }

    @ViewBuilder private var result: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .searching:
            Text("Asking \(askedHost)…").font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
        case .failed(let sentence, let chip):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StatusChip(chip, kind: .attention, mark: "✕")
                Text(sentence).font(TypeRole.sans(12)).fixedSize(horizontal: false, vertical: true)
            }
        case .found(let search):
            VStack(alignment: .leading, spacing: 8) {
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

    private func find() {
        guard !isSearching else { return }
        phase = .searching
        chosen = nil
        Task {
            switch await store.searchSource(text, for: installation) {
            case .failure(.source(.rateLimited, _)):
                // Nothing asks again from here, so say when the reader can.
                let at = await GitHubBudget.shared.retryAt
                phase = .failed("GitHub asked Skillori to wait. "
                                + (at.map { "Try again after \(InventoryStore.stamp($0))." } ?? "Try again in a while."), chip: "Wait")
            case .failure(.source(.offline, _)):
                phase = .failed("No contact with the source. Check the connection and try again.", chip: "No contact")
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
