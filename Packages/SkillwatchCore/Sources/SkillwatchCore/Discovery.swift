import Foundation

/// A place a skill was found through, and which agents that place makes it visible to.
public struct AgentBinding: Sendable, Hashable {
    public let discoveredPath: String
    public let agents: [Agent]
    public let scope: RootScope
    public let projectName: String?
    public let viaSymlink: Bool
}

/// What is known about where an installation came from. One claim per evidence source.
public enum Provenance: Sendable, Equatable {
    public enum LocalState: Sendable, Equatable {
        case matchesBaseline
        case modified(localHash: String)
        case hashFailed(String)
    }

    /// Recorded by `npx skills` in its lock file, with a baseline content hash.
    case skillsLock(source: String, sourceURL: String?, subpath: String?, baselineHash: String?, local: LocalState)
    /// Owned by a product; Skillwatch can only point at the owner.
    case managed(by: String)
    case unknown
}

/// One concrete skill directory on disk, identified by file system identity.
public struct Installation: Sendable, Identifiable {
    public let id: String
    public let canonicalPath: String
    public let directoryName: String
    public let frontmatter: SkillFrontmatter
    public var bindings: [AgentBinding]
    public var provenance: Provenance

    public var displayName: String { frontmatter.name ?? directoryName }
    public var agents: [Agent] { Array(Set(bindings.flatMap(\.agents))).sorted() }
}

public struct RootReport: Sendable, Identifiable {
    public enum State: Sendable, Equatable { case found, missing, unreadable(String), inactive }
    public var id: String { path }
    public let path: String
    public let rule: String
    public let projectName: String?
    public let state: State
    public let skillCount: Int
}

public struct Diagnostic: Sendable, Identifiable {
    public let id = UUID()
    public let path: String
    public let message: String
}

public struct Inventory: Sendable {
    public var installations: [Installation]
    public var roots: [RootReport]
    public var diagnostics: [Diagnostic]
    public var lockFile: String?
    public var scannedAt: Date
    public var duration: TimeInterval

    public var bindingCount: Int { installations.reduce(0) { $0 + $1.bindings.count } }
}

/// Reads skills from the roots in `AdapterRules`. Read-only: it lists directories, reads
/// `SKILL.md` front matter and hashes files. It never executes anything it finds.
public struct DiscoveryEngine: Sendable {
    public let home: URL
    public let projects: [URL]
    public let environment: [String: String]

    public init(home: URL, projects: [URL] = [], environment: [String: String] = [:]) {
        self.home = home
        self.projects = projects
        self.environment = environment
    }

    public func scan() -> Inventory {
        let start = Date()
        var builder = Builder()

        for rule in AdapterRules.personal {
            for root in expand(pattern: rule.pattern, under: home) {
                scanRoot(root, rule: rule, projectName: nil, into: &builder)
            }
        }
        for project in projects {
            for rule in AdapterRules.project {
                for root in expand(pattern: rule.pattern, under: project) {
                    scanRoot(root, rule: rule, projectName: project.lastPathComponent, into: &builder)
                }
            }
        }

        let lockURL = applySkillsLock(to: &builder)

        let installations = builder.order.compactMap { builder.installations[$0] }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return Inventory(installations: installations, roots: builder.roots, diagnostics: builder.diagnostics,
                         lockFile: lockURL?.path, scannedAt: start, duration: Date().timeIntervalSince(start))
    }

    // MARK: - Internals

    private struct Builder {
        var installations: [String: Installation] = [:]
        var order: [String] = []
        var roots: [RootReport] = []
        var diagnostics: [Diagnostic] = []
    }

    /// Expands `*` components. Literal components are not required to exist; the root report
    /// says "missing" so Coverage can show it.
    func expand(pattern: String, under base: URL) -> [URL] {
        var current = [base]
        for component in pattern.split(separator: "/").map(String.init) {
            if component == "*" {
                current = current.flatMap { dir -> [URL] in
                    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
                    return names.filter { !$0.hasPrefix(".") }.sorted().map { dir.appendingPathComponent($0) }
                        .filter { isDirectory($0) }
                }
            } else {
                current = current.map { $0.appendingPathComponent(component) }
            }
        }
        return current
    }

    private func scanRoot(_ root: URL, rule: RootRule, projectName: String?, into builder: inout Builder) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else {
            // Only report literal roots as missing; unmatched wildcards simply have no instances.
            if !rule.pattern.contains("*") {
                builder.roots.append(RootReport(path: root.path, rule: rule.note, projectName: projectName, state: .missing, skillCount: 0))
            }
            return
        }
        if let marker = rule.inactiveMarker, hasMarker(marker, near: root) {
            builder.roots.append(RootReport(path: root.path, rule: rule.note, projectName: projectName, state: .inactive, skillCount: 0))
            return
        }
        let names: [String]
        do {
            names = try fm.contentsOfDirectory(atPath: root.path)
        } catch {
            builder.roots.append(RootReport(path: root.path, rule: rule.note, projectName: projectName,
                                            state: .unreadable(error.localizedDescription), skillCount: 0))
            return
        }

        var count = 0
        for name in names.sorted() where !name.hasPrefix(".") {
            let entry = root.appendingPathComponent(name)
            let isLink = (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
            let resolved = entry.resolvingSymlinksInPath()
            guard isDirectory(resolved) else {
                if isLink && !fm.fileExists(atPath: resolved.path) {
                    builder.diagnostics.append(Diagnostic(path: entry.path, message: "Broken link"))
                }
                continue
            }
            let skillFile = resolved.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else { continue }
            guard let key = fileIdentity(resolved) else {
                builder.diagnostics.append(Diagnostic(path: entry.path, message: "Can't read file identity"))
                continue
            }
            count += 1

            let binding = AgentBinding(discoveredPath: entry.path, agents: rule.agents, scope: rule.scope,
                                       projectName: projectName, viaSymlink: isLink)
            if var existing = builder.installations[key] {
                existing.bindings.append(binding)
                if case .managed = rule.ownership, existing.provenance == .unknown {
                    existing.provenance = provenance(for: rule.ownership)
                }
                builder.installations[key] = existing
            } else {
                let frontmatter = SkillFrontmatter.parse(fileAt: skillFile)
                builder.installations[key] = Installation(
                    id: key, canonicalPath: resolved.path, directoryName: resolved.lastPathComponent,
                    frontmatter: frontmatter, bindings: [binding], provenance: provenance(for: rule.ownership))
                builder.order.append(key)
            }
        }
        builder.roots.append(RootReport(path: root.path, rule: rule.note, projectName: projectName, state: .found, skillCount: count))
    }

    private func provenance(for ownership: Ownership) -> Provenance {
        switch ownership {
        case .user: return .unknown
        case .managed(let owner): return .managed(by: owner)
        }
    }

    /// Attaches `npx skills` lock entries to the installation at `~/.agents/skills/<name>`.
    private func applySkillsLock(to builder: inout Builder) -> URL? {
        let locations = SkillsLockFile.defaultLocations(home: home, environment: environment)
        guard let url = locations.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        let lock: SkillsLockFile
        do {
            lock = try SkillsLockFile.load(from: url)
        } catch {
            builder.diagnostics.append(Diagnostic(path: url.path, message: "Unreadable lock file: \(error.localizedDescription)"))
            return url
        }
        let canonicalRoot = home.appendingPathComponent(".agents/skills")
        for (name, entry) in lock.skills {
            let dir = canonicalRoot.appendingPathComponent(name).resolvingSymlinksInPath()
            guard let key = fileIdentity(dir), var installation = builder.installations[key] else { continue }
            let local: Provenance.LocalState
            do {
                let hash = try GitTreeHash.hashDirectory(at: dir).treeID
                local = hash == entry.skillFolderHash ? .matchesBaseline : .modified(localHash: hash)
            } catch {
                local = .hashFailed(String(describing: error))
            }
            installation.provenance = .skillsLock(source: entry.source ?? name, sourceURL: entry.sourceUrl,
                                                  subpath: entry.repositorySubpath,
                                                  baselineHash: entry.skillFolderHash, local: local)
            builder.installations[key] = installation
        }
        return url
    }

    private func hasMarker(_ marker: String, near root: URL) -> Bool {
        // The marker sits in the version directory, which is the parent of `skills`.
        let parent = root.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: parent.appendingPathComponent(marker).path)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Device + inode of the resolved directory: one physical skill, however many links point at it.
    func fileIdentity(_ url: URL) -> String? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return "\(st.st_dev):\(st.st_ino)"
    }
}
