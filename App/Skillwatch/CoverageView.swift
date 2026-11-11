import SkillwatchCore
import SwiftUI

struct CoverageView: View {
    @Environment(InventoryStore.self) private var store
    @State private var showMissing = false

    var body: some View {
        List {
            Section {
                Text("Skillwatch reads these locations and nothing else. Add project folders to include their skills.")
                    .font(.callout).foregroundStyle(.secondary)
                if let lock = store.inventory?.lockFile {
                    LabeledContent("npx skills lock file") { PathText(lock) }
                }
                LabeledContent("Rules", value: AdapterRules.rulesVersion)
            }

            Section("Project Folders") {
                if store.projects.isEmpty {
                    Text("None yet").foregroundStyle(.secondary)
                }
                ForEach(store.projects, id: \.self) { url in
                    HStack {
                        PathText(url.path)
                        Spacer()
                        Button("Remove", role: .destructive) { store.removeProject(url) }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add Project Folder…") { store.addProject() }
            }

            Section("Locations Read") {
                ForEach(found) { root in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            PathText(root.path)
                            Text(root.rule).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(root.skillCount)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }

            Section("Problems") {
                let problems = (store.inventory?.roots ?? []).filter {
                    if case .unreadable = $0.state { true } else { false }
                }
                let diagnostics = store.inventory?.diagnostics ?? []
                if problems.isEmpty && diagnostics.isEmpty {
                    Text("No problems").foregroundStyle(.secondary)
                }
                ForEach(problems) { root in
                    Label { PathText(root.path) } icon: { Image(systemName: "lock") }
                }
                ForEach(diagnostics) { d in
                    Label { VStack(alignment: .leading) { Text(d.message); PathText(d.path) } } icon: {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
            }

            Section {
                DisclosureGroup("Checked but not present (\(missing.count))", isExpanded: $showMissing) {
                    ForEach(missing) { root in PathText(root.path).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private var found: [RootReport] { (store.inventory?.roots ?? []).filter { $0.state == .found && $0.skillCount > 0 } }
    private var missing: [RootReport] { (store.inventory?.roots ?? []).filter { $0.state == .missing } }
}
