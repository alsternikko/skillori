import SkillwatchCore
import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All Skills"
    case tracked = "Tracked Source"
    case localChanges = "Local Changes"
    case unknown = "Source Unknown"
    case managed = "Managed by an App"
    case coverage = "Coverage"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .tracked: "checkmark.seal"
        case .localChanges: "pencil.circle"
        case .unknown: "questionmark.circle"
        case .managed: "shippingbox"
        case .coverage: "scope"
        }
    }

    func includes(_ installation: Installation) -> Bool {
        switch (self, installation.provenance) {
        case (.all, _): true
        case (.tracked, .skillsLock): true
        case (.localChanges, .skillsLock(_, _, _, _, .modified)): true
        case (.unknown, .unknown): true
        case (.managed, .managed): true
        default: false
        }
    }
}

struct LibraryView: View {
    @Environment(InventoryStore.self) private var store
    @State private var filter: LibraryFilter?
    @State private var selection: Installation.ID?
    @State private var search = ""

    init(initialFilter: LibraryFilter = .all, initialSelection: Installation.ID? = nil) {
        _filter = State(initialValue: initialFilter)
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationSplitView {
            List(LibraryFilter.allCases, selection: $filter) { item in
                Label(item.rawValue, systemImage: item.systemImage)
                    .badge(badge(for: item))
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } content: {
            if filter == .coverage {
                CoverageView()
            } else {
                List(visible, selection: $selection) { installation in
                    InstallationRow(installation: installation)
                }
                .searchable(text: $search, placement: .sidebar, prompt: "Search skills")
                .overlay {
                    if store.inventory != nil && visible.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
            }
        } detail: {
            if let installation = selected {
                InstallationDetail(installation: installation)
            } else {
                ContentUnavailableView("No Skill Selected", systemImage: "sparkles.rectangle.stack",
                                       description: Text("Select a skill to see where it lives and where it came from."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button { Task { await store.rescan() } } label: {
                    Label("Scan Now", systemImage: "arrow.clockwise")
                }
                .disabled(store.isScanning)
            }
        }
    }

    private var visible: [Installation] {
        let all = store.inventory?.installations ?? []
        let filtered = all.filter { (filter ?? .all).includes($0) }
        guard !search.isEmpty else { return filtered }
        return filtered.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
                || ($0.frontmatter.description ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    private var selected: Installation? {
        store.inventory?.installations.first { $0.id == selection }
    }

    private func badge(for item: LibraryFilter) -> Int {
        guard item != .coverage, let all = store.inventory?.installations else { return 0 }
        return all.filter(item.includes).count
    }
}

private struct InstallationRow: View {
    let installation: Installation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(installation.displayName).fontWeight(.medium)
                if !installation.frontmatter.problems.isEmpty {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Has validation problems")
                }
                Spacer()
                StatusBadge(provenance: installation.provenance)
            }
            Text(scopeLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var scopeLine: String {
        let projects = Set(installation.bindings.compactMap(\.projectName))
        let scope = projects.isEmpty ? "Personal" : projects.sorted().joined(separator: ", ")
        let n = installation.bindings.count
        return "\(scope) · \(n) location\(n == 1 ? "" : "s")"
    }
}

struct StatusBadge: View {
    let provenance: Provenance

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }

    private var text: String {
        switch provenance {
        case .skillsLock(_, _, _, _, .matchesBaseline): "Tracked"
        case .skillsLock(_, _, _, _, .modified): "Local changes"
        case .skillsLock(_, _, _, _, .hashFailed): "Check failed"
        case .managed: "Managed"
        case .unknown: "Source unknown"
        }
    }

    private var color: Color {
        switch provenance {
        case .skillsLock(_, _, _, _, .matchesBaseline): .green
        case .skillsLock(_, _, _, _, .modified): .orange
        case .skillsLock(_, _, _, _, .hashFailed): .red
        case .managed: .blue
        case .unknown: .secondary
        }
    }
}
