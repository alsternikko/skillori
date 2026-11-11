import AppKit
import SkilloriCore
import SwiftUI

struct InstallationDetail: View {
    let installation: Installation

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(installation.displayName).font(.title2.weight(.semibold))
                        StatusBadge(provenance: installation.provenance)
                    }
                    if let description = installation.frontmatter.description {
                        Text(description).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Source") {
                sourceRows
            }

            Section("Available to") {
                Text(installation.agents.map(\.displayName).joined(separator: ", "))
                Text("Based on documented skill locations. Whether an agent actually loads it depends on the agent's version and settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Locations") {
                LabeledContent("Folder") { PathText(installation.canonicalPath) }
                ForEach(installation.bindings, id: \.discoveredPath) { binding in
                    if binding.discoveredPath != installation.canonicalPath {
                        LabeledContent(binding.viaSymlink ? "Linked from" : "Also at") {
                            PathText(binding.discoveredPath)
                        }
                    }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installation.canonicalPath)])
                }
            }

            if !installation.frontmatter.problems.isEmpty {
                Section("Problems") {
                    ForEach(installation.frontmatter.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var sourceRows: some View {
        switch installation.provenance {
        case .skillsLock(let source, let url, let subpath, let baseline, let local):
            LabeledContent("Installed with", value: "npx skills")
            LabeledContent("Repository", value: source)
            if let subpath { LabeledContent("Folder in repository", value: subpath) }
            if let baseline { LabeledContent("Installed content") { Text(baseline.prefix(12)).monospaced() } }
            switch local {
            case .matchesBaseline:
                Label("Matches the installed version", systemImage: "checkmark.circle").foregroundStyle(.green)
            case .modified(let hash):
                Label("Changed locally since install", systemImage: "pencil.circle").foregroundStyle(.orange)
                LabeledContent("Current content") { Text(hash.prefix(12)).monospaced() }
            case .hashFailed(let error):
                Label("Couldn't check local content: \(error)", systemImage: "xmark.octagon").foregroundStyle(.red)
            }
            if let url, let link = URL(string: url.replacingOccurrences(of: ".git", with: "")) {
                Link("Open Source", destination: link)
            }
            Text("Checking for upstream updates comes in a later version.")
                .font(.caption).foregroundStyle(.secondary)
        case .managed(let owner):
            LabeledContent("Managed by", value: owner)
            Text("\(owner) installs and updates this skill. Skillori only reads it.")
                .font(.caption).foregroundStyle(.secondary)
        case .unknown:
            Label("Source unknown", systemImage: "questionmark.circle")
            Text("No installer left a record of where this came from. Linking a source comes in a later version.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PathText: View {
    let path: String
    init(_ path: String) { self.path = path }

    var body: some View {
        Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            .font(.callout.monospaced())
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.middle)
            .help(path)
    }
}
