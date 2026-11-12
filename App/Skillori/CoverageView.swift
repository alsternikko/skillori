import SkilloriCore
import SkilloriUI
import SwiftUI

/// Which folders Skillori read, what each one is, and what went wrong if anything did.
struct CoverageView: View {
    @Environment(InventoryStore.self) private var store
    @State private var showMissing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                LabelText("No").frame(width: Column.number, alignment: .leading)
                LabelText("Folder").frame(maxWidth: .infinity, alignment: .leading)
                LabelText("What it is").frame(width: Column.what, alignment: .leading)
                LabelText("Skills").frame(width: Column.skills, alignment: .leading)
                LabelText("State").frame(width: Column.state, alignment: .leading)
            }
            .foregroundStyle(Palette.ink2)
            .frame(height: 36)
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
            .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(problems.enumerated()), id: \.element.id) { index, root in
                        row(number: index + 1, path: root.path, what: reason(root), skills: nil,
                            chip: StatusChip("No access", kind: .attention))
                    }
                    ForEach(Array(read.enumerated()), id: \.element.id) { index, root in
                        row(number: problems.count + index + 1, path: root.path, what: root.rule,
                            skills: root.skillCount,
                            chip: isAdded(root) ? StatusChip("Added by you") : StatusChip("Found"),
                            remove: addedURL(root))
                    }
                    ForEach(store.inventory?.diagnostics ?? []) { diagnostic in
                        row(number: nil, path: diagnostic.path, what: diagnostic.message, skills: nil,
                            chip: StatusChip("Check", kind: .attention))
                    }

                    section("Looked for, not on this Mac · \(missing.count)",
                            note: showMissing ? "Hide" : "Show") { showMissing.toggle() }
                    if showMissing {
                        ForEach(missing) { root in
                            row(number: nil, path: root.path, what: root.rule, skills: nil,
                                chip: StatusChip("Not here", kind: .outline), muted: true)
                        }
                    }

                    HStack(spacing: 12) {
                        Text("Skillori reads these folders and nothing else. Add a project folder to include its skills.")
                            .font(TypeRole.sans(12))
                            .foregroundStyle(Palette.ink2)
                        Spacer(minLength: 8)
                        if let lock = store.inventory?.lockFile {
                            DataText("LOCK FILE \((lock as NSString).abbreviatingWithTildeInPath)")
                                .foregroundStyle(Palette.ink2)
                                .help(lock)
                        }
                        Button("Add folder") { store.addProject() }.buttonStyle(PillButtonStyle(prominent: true))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 14)
                }
                .padding(.horizontal, 6)
            }
        }
    }

    private enum Column {
        static let number: CGFloat = 44
        static let what: CGFloat = 300
        static let skills: CGFloat = 64
        static let state: CGFloat = 200
    }

    private func row(number: Int?, path: String, what: String, skills: Int?, chip: StatusChip,
                     remove: URL? = nil, muted: Bool = false) -> some View {
        HStack(spacing: 0) {
            DataText(number.map { String(format: "%03d", $0) } ?? "—")
                .foregroundStyle(Palette.ink3)
                .frame(width: Column.number, alignment: .leading)
            Text((path as NSString).abbreviatingWithTildeInPath)
                .font(TypeRole.mono(11.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(muted ? Palette.ink3 : Palette.ink)
                .textSelection(.enabled)
                .help(path)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
            Text(what)
                .font(TypeRole.sans(12))
                .lineLimit(1)
                .foregroundStyle(muted ? Palette.ink3 : Palette.ink2)
                .help(what)
                .frame(width: Column.what - 12, alignment: .leading)
                .padding(.trailing, 12)
            DataText(skills.map(String.init) ?? "")
                .foregroundStyle(Palette.ink)
                .frame(width: Column.skills, alignment: .leading)
            HStack(spacing: 8) {
                chip
                if let remove {
                    Button("Remove") { store.removeProject(remove) }.buttonStyle(HintButtonStyle(underlined: true))
                }
            }
            .frame(width: Column.state, alignment: .leading)
        }
        .frame(height: 40)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
        .padding(.horizontal, 10)
    }

    private func section(_ title: String, note: String, action: @escaping () -> Void) -> some View {
        HStack {
            LabelText(title).foregroundStyle(Palette.ink)
            Spacer()
            Button(note, action: action).buttonStyle(HintButtonStyle(underlined: true))
        }
        .frame(height: 40)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private var read: [RootReport] {
        (store.inventory?.roots ?? []).filter { $0.state == .found }.sorted { $0.skillCount > $1.skillCount }
    }

    private var missing: [RootReport] { (store.inventory?.roots ?? []).filter { $0.state == .missing } }

    private var problems: [RootReport] {
        (store.inventory?.roots ?? []).filter { if case .unreadable = $0.state { true } else { false } }
    }

    private func reason(_ root: RootReport) -> String {
        if case .unreadable(let message) = root.state { return message }
        return root.rule
    }

    private func addedURL(_ root: RootReport) -> URL? {
        store.projects.first { root.path.hasPrefix($0.path) }
    }

    private func isAdded(_ root: RootReport) -> Bool { addedURL(root) != nil }
}
