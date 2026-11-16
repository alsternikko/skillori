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
    /// Owned by a product; Skillori can only point at the owner.
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
    /// When the installer first recorded this skill, if it left a record.
    public var installedAt: Date? = nil
    /// When the installer last changed it, if it left a record.
    public var updatedAt: Date? = nil
    /// The branch or tag the installer recorded, if any. Nil means the source's default branch.
    public var sourceRef: String? = nil
    /// The kind of source the installer recorded (`github`, `gitlab`, `local`, …), if any.
    public var sourceType: String? = nil
    /// The Claude Code plugin this skill came with, when Claude Code recorded one.
    public var plugin: PluginRecord? = nil
    /// The git tree id of the files, when another skill of yours has the same name. It tells
    /// an identical copy from a different version without anyone opening the folders.
    public var contentHash: String? = nil

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
    /// The disk root, for places an administrator sets up. Nil leaves those unread, which
    /// keeps tests away from the machine they run on.
    public let system: URL?

    public init(home: URL, projects: [URL] = [], environment: [String: String] = [:], system: URL? = nil) {
        self.home = home
        self.projects = projects
        self.environment = environment
        self.system = system
    }

    public func scan() -> Inventory {
        let start = Date()
        var builder = Builder()

        for rule in AdapterRules.personal {
            scan(rule, under: home, projectName: nil, into: &builder)
            for place in relocated(rule.pattern) {
                scan(rule, pattern: place.pattern, under: place.base, projectName: nil, into: &builder)
            }
        }
        scanRecordedClaudePlugins(into: &builder)
        if let system {
            for rule in AdapterRules.system { scan(rule, under: system, projectName: nil, into: &builder) }
        }
        for project in projects {
            for rule in AdapterRules.project {
                scan(rule, under: project, projectName: project.lastPathComponent, into: &builder)
            }
        }

        let lockURL = applySkillsLock(to: &builder)
        applyPluginRecords(to: &builder)
        hashSameNameCopies(in: &builder)

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
        /// Folders already read, by the path they were reached through, so no folder is read
        /// twice through the same place. A root that links to another root is still read:
        /// skills are deduplicated by file identity in `register`, and the link adds bindings.
        var seen: Set<String> = []
    }

    private func scan(_ rule: RootRule, pattern: String? = nil, under base: URL, projectName: String?,
                      into builder: inout Builder) {
        for location in expand(pattern: pattern ?? rule.pattern, under: base) {
            if let layout = rule.plugin {
                scanPlugin(location, layout: layout, rule: rule, projectName: projectName, into: &builder)
            } else {
                scanRoot(location, rule: rule, markerDirectory: location.deletingLastPathComponent(),
                         projectName: projectName, into: &builder)
            }
        }
    }

    /// The other places a personal pattern can be, from variables that move a settings folder.
    func relocated(_ pattern: String) -> [(base: URL, pattern: String)] {
        AdapterRules.relocations.compactMap { relocation in
            guard let value = environment[relocation.variable], value.hasPrefix("/"),
                  pattern == relocation.prefix || pattern.hasPrefix(relocation.prefix + "/") else { return nil }
            var base = URL(fileURLWithPath: value, isDirectory: true)
            if !relocation.subpath.isEmpty { base.appendPathComponent(relocation.subpath) }
            return (base, String(pattern.dropFirst(relocation.prefix.count)))
        }
    }

    /// Claude Code records where each plugin is installed. Most are in its cache, which the
    /// rules already read; one from a local marketplace is loaded from where it lies.
    private func scanRecordedClaudePlugins(into builder: inout Builder) {
        let rule = AdapterRules.claudeCodePlugins
        guard let layout = rule.plugin else { return }
        let folders = [home.appendingPathComponent(".claude/plugins")] + relocated(".claude/plugins").map {
            $0.base.appendingPathComponent($0.pattern)
        }
        for folder in folders {
            let record = folder.appendingPathComponent("installed_plugins.json")
            guard let data = try? Data(contentsOf: record),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let plugins = json["plugins"] as? [String: Any] else { continue }
            for name in plugins.keys.sorted() {
                for entry in plugins[name] as? [[String: Any]] ?? [] {
                    guard let path = entry["installPath"] as? String, path.hasPrefix("/") else { continue }
                    scanPlugin(URL(fileURLWithPath: path, isDirectory: true), layout: layout, rule: rule,
                               projectName: nil, into: &builder)
                }
            }
        }
    }

    /// Reads one plugin folder: `skills/`, plus or instead the folders its manifest names.
    private func scanPlugin(_ plugin: URL, layout: PluginLayout, rule: RootRule, projectName: String?,
                            into builder: inout Builder) {
        let fm = FileManager.default
        guard isDirectory(plugin) else { return }
        let standard = plugin.appendingPathComponent("skills")
        if let marker = rule.inactiveMarker, fm.fileExists(atPath: plugin.appendingPathComponent(marker).path) {
            builder.roots.append(RootReport(path: standard.path, rule: rule.note, projectName: projectName, state: .inactive, skillCount: 0))
            return
        }
        let named = layout.manifests.lazy.compactMap { manifestSkillPaths(plugin.appendingPathComponent($0)) }.first
        var folders: [URL] = []
        if named == nil || !layout.customPathsReplaceDefault { folders.append(standard) }
        let inside = plugin.standardizedFileURL.path
        for path in named ?? [] {
            let folder = URL(fileURLWithPath: path, relativeTo: plugin).standardizedFileURL
            // A manifest may only point inside its own plugin.
            guard folder.path == inside || folder.path.hasPrefix(inside + "/") else { continue }
            folders.append(folder)
        }
        var found = false
        for folder in folders where isDirectory(folder) {
            found = true
            if fm.fileExists(atPath: folder.appendingPathComponent("SKILL.md").path) {
                scanSingle(folder, rule: rule, projectName: projectName, into: &builder)
            } else {
                scanRoot(folder, rule: rule, markerDirectory: nil, projectName: projectName, into: &builder)
            }
        }
        // A plugin with nothing but a SKILL.md at its top is one skill.
        if !found, named == nil, fm.fileExists(atPath: plugin.appendingPathComponent("SKILL.md").path) {
            scanSingle(plugin, rule: rule, projectName: projectName, into: &builder)
        }
    }

    /// The `skills` entry of a plugin manifest: one path or a list of them. Nil when the file
    /// is missing, unreadable or names none.
    func manifestSkillPaths(_ manifest: URL) -> [String]? {
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let paths: [String]
        switch json["skills"] {
        case let one as String: paths = [one]
        case let many as [Any]: paths = many.compactMap { $0 as? String }
        default: return nil
        }
        let usable = paths.filter { !$0.isEmpty && !$0.hasPrefix("/") }
        return usable.isEmpty ? nil : usable
    }

    /// A folder that is itself one skill.
    private func scanSingle(_ skill: URL, rule: RootRule, projectName: String?, into builder: inout Builder) {
        guard builder.seen.insert(skill.standardizedFileURL.path).inserted else { return }
        let added = register(skill, rule: rule, projectName: projectName, into: &builder)
        builder.roots.append(RootReport(path: skill.path, rule: rule.note, projectName: projectName, state: .found, skillCount: added ? 1 : 0))
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

    private func scanRoot(_ root: URL, rule: RootRule, markerDirectory: URL?, projectName: String?,
                          into builder: inout Builder) {
        let fm = FileManager.default
        guard builder.seen.insert(root.standardizedFileURL.path).inserted else { return }
        guard fm.fileExists(atPath: root.path) else {
            // Only report literal roots as missing; unmatched wildcards simply have no instances.
            if !rule.pattern.contains("*") {
                builder.roots.append(RootReport(path: root.path, rule: rule.note, projectName: projectName, state: .missing, skillCount: 0))
            }
            return
        }
        if let marker = rule.inactiveMarker, let markerDirectory,
           fm.fileExists(atPath: markerDirectory.appendingPathComponent(marker).path) {
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

        let rootIsLink = (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
        var count = 0
        for name in names.sorted() where !name.hasPrefix(".") {
            if register(root.appendingPathComponent(name), rule: rule, projectName: projectName,
                        throughLink: rootIsLink, into: &builder) { count += 1 }
        }
        builder.roots.append(RootReport(path: root.path, rule: rule.note, projectName: projectName, state: .found, skillCount: count))
    }

    /// Records the skill at `entry`, if it is one. Returns whether it was.
    private func register(_ entry: URL, rule: RootRule, projectName: String?, throughLink: Bool = false,
                          into builder: inout Builder) -> Bool {
        let fm = FileManager.default
        let isLink = (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
        let resolved = entry.resolvingSymlinksInPath()
        guard isDirectory(resolved) else {
            if isLink && !fm.fileExists(atPath: resolved.path) {
                builder.diagnostics.append(Diagnostic(path: entry.path, message: "Broken link"))
            }
            return false
        }
        let skillFile = resolved.appendingPathComponent("SKILL.md")
        guard fm.fileExists(atPath: skillFile.path) else { return false }
        guard let key = fileIdentity(resolved) else {
            builder.diagnostics.append(Diagnostic(path: entry.path, message: "Can't read file identity"))
            return false
        }

        let binding = AgentBinding(discoveredPath: entry.path, agents: rule.agents, scope: rule.scope,
                                   projectName: projectName, viaSymlink: isLink || throughLink)
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
        return true
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
            // A key names one folder in the shared root; anything else could point at another skill.
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
                builder.diagnostics.append(Diagnostic(path: url.path, message: "Lock file entry with an unusable name: \(name)"))
                continue
            }
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
            installation.installedAt = entry.installedAt.flatMap(Self.parseDate)
            installation.updatedAt = entry.updatedAt.flatMap(Self.parseDate)
            installation.sourceRef = entry.ref
            installation.sourceType = entry.sourceType
            builder.installations[key] = installation
        }
        return url
    }

    /// Hashes the skills of yours that share a name with another, so copies can be told apart.
    /// Skills managed by apps are left out: plugins often ship the same skill to several agents,
    /// and those copies are the apps' business.
    private func hashSameNameCopies(in builder: inout Builder) {
        let own = builder.order.compactMap { key -> (String, Installation)? in
            guard let installation = builder.installations[key] else { return nil }
            if case .managed = installation.provenance { return nil }
            return (key, installation)
        }
        let byName = Dictionary(grouping: own) { $0.1.displayName.lowercased() }
        for (_, group) in byName where group.count > 1 {
            for (key, installation) in group {
                let url = URL(fileURLWithPath: installation.canonicalPath)
                builder.installations[key]?.contentHash = try? GitTreeHash.hashDirectory(at: url).treeID
            }
        }
    }

    /// Ties each skill inside a recorded Claude Code plugin to that plugin's record.
    private func applyPluginRecords(to builder: inout Builder) {
        let folders = [home.appendingPathComponent(".claude/plugins")] + relocated(".claude/plugins").map {
            $0.base.appendingPathComponent($0.pattern)
        }
        let records = folders.flatMap { ClaudePlugins.records(in: $0) }
        guard !records.isEmpty else { return }
        let byPath = records.map { (URL(fileURLWithPath: $0.installPath).resolvingSymlinksInPath().path + "/", $0) }
        for key in builder.order {
            guard var installation = builder.installations[key],
                  let match = byPath.first(where: { installation.canonicalPath.hasPrefix($0.0) }) else { continue }
            installation.plugin = match.1
            builder.installations[key] = installation
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
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
