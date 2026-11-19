import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// Looks for the source of every skill of yours that has none, and links the ones the reader
/// ticks. Proven matches are ticked from the start; a name alone never is. Identical copies in
/// several folders are one row and are linked together. Nothing on disk is changed.
struct FindSourcesSheet: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Finding {
        case asking
        case found(SourceFinder.Search)
    }

    @State private var groups: [InventoryStore.UnlinkedGroup] = []
    @State private var findings: [String: Finding] = [:]
    /// Group id → the proposal to link.
    @State private var chosen: [String: String] = [:]
    @State private var started = false

    init() {}

    /// Already answered, for pictures: no questions are asked.
    init(preview: [(InventoryStore.UnlinkedGroup, SourceFinder.Search)]) {
        _groups = State(initialValue: preview.map(\.0))
        _findings = State(initialValue: Dictionary(uniqueKeysWithValues: preview.map { ($0.0.id, Finding.found($0.1)) }))
        _chosen = State(initialValue: Dictionary(uniqueKeysWithValues: preview.compactMap { group, list in
            list.proposals.first.flatMap { $0.evidence.isConfirmed && !$0.folderGone ? (group.id, $0.id) : nil }
        }))
        _started = State(initialValue: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LabelText("Find sources")
                Spacer(minLength: 8)
                LabelText(groups.isEmpty ? "" : groups.count == 1 ? "1 skill" : "\(groups.count) skills")
            }
            .foregroundStyle(Palette.ink2)
            Text("Where did these skills come from?")
                .font(TypeRole.sans(20, .medium))
                .tracking(-0.4)
                .padding(.top, 14)
            Text("Skillori asks the mdskills.ai registry where each skill lives, and looks in the repositories your other skills come from and a few large collections on GitHub. It compares what it finds with the files on this Mac, earlier versions included. Only skill and repository names are sent. Nothing is changed.")
                .font(TypeRole.sans(12))
                .lineSpacing(2)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(groups) { group in
                        row(group, isLast: group.id == groups.last?.id)
                    }
                    if started && groups.isEmpty {
                        Text("Every skill of yours has a source.")
                            .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            }
            .frame(maxHeight: 380)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.block, style: .circular))
            .clipShape(RoundedRectangle(cornerRadius: Radius.block, style: .circular))
            .padding(.top, 16)

            HStack(spacing: 6) {
                Button(linkTitle) {
                    for group in groups {
                        if let id = chosen[group.id], let proposal = proposals(for: group).first(where: { $0.id == id }) {
                            store.link(group, to: proposal)
                        }
                    }
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(prominent: !chosen.isEmpty))
                .disabled(chosen.isEmpty)
                .keyboardShortcut(.defaultAction)
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 8)
                if isAsking {
                    Text("Asking…").font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
                }
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 600)
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .font(TypeRole.sans(13))
        .task { await find() }
    }

    private var isAsking: Bool {
        findings.values.contains { if case .asking = $0 { true } else { false } }
    }

    private var linkTitle: String {
        let copies = groups.filter { chosen[$0.id] != nil }.reduce(0) { $0 + $1.installations.count }
        return chosen.isEmpty ? "Link" : chosen.count == 1 && copies == 1 ? "Link 1 skill"
            : "Link \(chosen.count) skill\(chosen.count == 1 ? "" : "s")" + (copies > chosen.count ? " (\(copies) copies)" : "")
    }

    private func proposals(for group: InventoryStore.UnlinkedGroup) -> [SourceProposal] {
        if case .found(let search)? = findings[group.id] { search.proposals } else { [] }
    }

    private func row(_ group: InventoryStore.UnlinkedGroup, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.name).font(TypeRole.sans(13, .medium))
                if group.installations.count > 1 {
                    Text("\(group.installations.count) copies").font(TypeRole.mono(10.5)).foregroundStyle(Palette.ink3)
                }
                Spacer(minLength: 8)
            }
            switch findings[group.id] {
            case .asking, nil:
                Text("Asking…").font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
            case .found(let search):
                ForEach(search.proposals) { proposal in
                    choice(proposal, in: group)
                }
                if let problem = search.problem {
                    // Not "nothing found": some places could not be asked, so the search is unfinished.
                    Text((problem == .rateLimited
                          ? "GitHub asked Skillori to wait, so not every place was asked. Try again in an hour."
                          : problem == .offline ? "Some places could not be reached, so not every place was asked. Try again later."
                          : "Some places gave answers Skillori could not read, so not every place was asked."))
                        .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
                } else if search.proposals.isEmpty {
                    Text(group.local == nil ? "The files on this Mac could not be read."
                         : "Nothing found. Link it by hand from its page if you know where it came from.")
                        .font(TypeRole.sans(12)).foregroundStyle(Palette.ink2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { if !isLast { Palette.line.frame(height: 1) } }
    }

    private func choice(_ proposal: SourceProposal, in group: InventoryStore.UnlinkedGroup) -> some View {
        let isChosen = chosen[group.id] == proposal.id
        let chip = proposal.chip
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(isChosen ? "●" : "○").font(TypeRole.mono(11.5))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(proposal.source.name + (proposal.subpath.isEmpty ? "" : " › " + proposal.subpath))
                        .font(TypeRole.mono(11.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    StatusChip(chip.text, kind: chip.kind, mark: chip.mark)
                }
                Text(proposal.sentence + " Found via \(proposal.via).")
                    .font(TypeRole.sans(12))
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(Palette.ink.opacity(isChosen ? 0.06 : 0), in: RoundedRectangle(cornerRadius: Radius.control, style: .circular))
        .contentShape(Rectangle())
        .onTapGesture {
            chosen[group.id] = isChosen ? nil : proposal.id
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    private func find() async {
        guard !started else { return }
        let found = await store.unlinkedGroups()
        groups = found
        started = true
        for group in found { findings[group.id] = .asking }
        let finder = SourceFinder()
        // One skill at a time: each asks a few sources, and GitHub counts requests per hour.
        for group in found {
            let search = await store.proposals(for: group, using: finder)
            findings[group.id] = .found(search)
            // Tick only what is proven and can be followed: not a name alone, not a folder that is gone.
            if let best = search.proposals.first, best.evidence.isConfirmed, !best.folderGone {
                chosen[group.id] = best.id
            }
        }
    }
}
