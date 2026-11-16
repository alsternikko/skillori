import Foundation

/// What Claude Code recorded about one installed plugin, together with what its marketplace
/// says about where the plugin comes from. Read from three files Claude Code writes:
/// `installed_plugins.json`, `known_marketplaces.json` and the marketplace's own
/// `.claude-plugin/marketplace.json` in its local clone.
public struct PluginRecord: Sendable, Hashable, Codable {
    /// `name@marketplace`, as Claude Code writes it.
    public let id: String
    public let name: String
    public let marketplace: String
    public let version: String?
    /// The commit Claude Code installed, of the repository the plugin comes from.
    public let commit: String?
    public let installPath: String
    /// `user`, `project` or `local`.
    public let scope: String?
    public let projectPath: String?
    /// The marketplace's repository on GitHub, `owner/repo`, when it is one.
    public let marketplaceRepository: String?
    /// Where the marketplace says the plugin is, as of the local clone.
    public let origin: PluginOrigin?
    /// The app that installed it and updates it: Claude Code, Cursor or Codex.
    public var app: String = "Claude Code"
    /// For Cursor and Codex: the plugin's own repository on GitHub, `owner/repo`, from its git
    /// checkout or, failing that, from the `repository` its manifest names.
    public var repository: String? = nil
    /// For Cursor and Codex: the manifest inside the plugin folder, such as `.cursor-plugin/plugin.json`.
    public var manifestPath: String? = nil
    /// The plugin folder is a git checkout of `repository`, so the manifest sits at its top.
    public var isCheckout = false
    /// Whether the app has the plugin turned on, when the app records it.
    public var enabled: Bool? = nil
    /// A name for people, when the manifest gives one apart from `name`.
    public var displayName: String? = nil
    /// The name to show: the manifest's name for people, or the plugin's own.
    public var title: String { displayName ?? name }

    public init(id: String, name: String, marketplace: String, version: String?, commit: String?,
                installPath: String, scope: String?, projectPath: String?,
                marketplaceRepository: String?, origin: PluginOrigin?) {
        self.id = id
        self.name = name
        self.marketplace = marketplace
        self.version = version
        self.commit = commit
        self.installPath = installPath
        self.scope = scope
        self.projectPath = projectPath
        self.marketplaceRepository = marketplaceRepository
        self.origin = origin
    }
}

/// Where a marketplace entry says a plugin's files are.
public enum PluginOrigin: Sendable, Hashable, Codable {
    /// A folder in the marketplace's own repository (`"./plugins/x"`). Empty for the top.
    case inMarketplace(path: String)
    /// Another repository, at a revision the marketplace pins when it gives `sha`.
    case repository(owner: String, repository: String, path: String?, pinned: String?)
    /// A kind of source Skillori cannot ask.
    case other

    /// Reads a marketplace entry's `source`: a string path or an object.
    static func parse(_ source: Any?) -> PluginOrigin? {
        if let text = source as? String {
            guard let path = normalizedPath(text) else { return .other }
            return .inMarketplace(path: path)
        }
        guard let object = source as? [String: Any] else { return nil }
        let pinned = (object["sha"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let path = (object["path"] as? String).flatMap(normalizedPath)
        if let repo = object["repo"] as? String, let source = UpstreamSource(source: repo, sourceURL: nil) {
            return .repository(owner: source.owner, repository: source.repository, path: path, pinned: pinned)
        }
        if let url = object["url"] as? String, let source = UpstreamSource(source: "", sourceURL: url) {
            return .repository(owner: source.owner, repository: source.repository, path: path, pinned: pinned)
        }
        return .other
    }

    /// `./plugins/x/` → `plugins/x`; `./` → empty. Nil for anything that leaves the repository.
    static func normalizedPath(_ text: String) -> String? {
        let parts = text.split(separator: "/").filter { $0 != "." }
        guard !parts.contains("..") else { return nil }
        return parts.joined(separator: "/")
    }
}

public enum ClaudePlugins {
    /// The plugins Claude Code recorded under one `.claude/plugins` folder. Unreadable files
    /// give an empty list: the skills are still found by their folders, just without this.
    public static func records(in pluginsFolder: URL) -> [PluginRecord] {
        guard let installed = json(pluginsFolder.appendingPathComponent("installed_plugins.json")),
              let plugins = installed["plugins"] as? [String: Any] else { return [] }
        let marketplaces = json(pluginsFolder.appendingPathComponent("known_marketplaces.json")) ?? [:]

        var records: [PluginRecord] = []
        for id in plugins.keys.sorted() {
            let pieces = id.split(separator: "@", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            let (name, marketplace) = (pieces[0], pieces[1])
            let known = marketplaces[marketplace] as? [String: Any]
            let repository = marketplaceRepository(known)
            let origin = entry(named: name, in: known, pluginsFolder: pluginsFolder, marketplace: marketplace)
            for case let install as [String: Any] in plugins[id] as? [Any] ?? [] {
                guard let path = install["installPath"] as? String, path.hasPrefix("/") else { continue }
                records.append(PluginRecord(
                    id: id, name: name, marketplace: marketplace,
                    version: install["version"] as? String,
                    commit: (install["gitCommitSha"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    installPath: path, scope: install["scope"] as? String,
                    projectPath: install["projectPath"] as? String,
                    marketplaceRepository: repository, origin: origin))
            }
        }
        return records
    }

    private static func marketplaceRepository(_ known: [String: Any]?) -> String? {
        guard let source = known?["source"] as? [String: Any] else { return nil }
        if source["source"] as? String == "github", let repo = source["repo"] as? String,
           let parsed = UpstreamSource(source: repo, sourceURL: nil) {
            return parsed.name
        }
        if let url = source["url"] as? String, let parsed = UpstreamSource(source: "", sourceURL: url) {
            return parsed.name
        }
        return nil
    }

    /// The marketplace's entry for a plugin, from the clone Claude Code keeps of it.
    private static func entry(named name: String, in known: [String: Any]?, pluginsFolder: URL,
                              marketplace: String) -> PluginOrigin? {
        var clone = pluginsFolder.appendingPathComponent("marketplaces").appendingPathComponent(marketplace)
        if let location = known?["installLocation"] as? String, location.hasPrefix("/") {
            clone = URL(fileURLWithPath: location, isDirectory: true)
        }
        guard let manifest = json(clone.appendingPathComponent(".claude-plugin/marketplace.json")) else { return nil }
        return origin(of: name, inMarketplace: manifest)
    }

    /// The origin of one plugin in a parsed `marketplace.json`.
    static func origin(of name: String, inMarketplace manifest: [String: Any]) -> PluginOrigin? {
        let entries = manifest["plugins"] as? [[String: Any]] ?? []
        guard let entry = entries.first(where: { $0["name"] as? String == name }) else { return nil }
        return PluginOrigin.parse(entry["source"])
    }

    /// The version a parsed `marketplace.json` gives one plugin, if it gives one.
    static func version(of name: String, inMarketplace manifest: [String: Any]) -> String? {
        let entries = manifest["plugins"] as? [[String: Any]] ?? []
        return entries.first(where: { $0["name"] as? String == name })?["version"] as? String
    }

    private static func json(_ url: URL) -> [String: Any]? {
        // These files are small; a huge one is not what Claude Code writes, so it is not read.
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? 0) < 8_000_000,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// Asks whether an installed Claude Code plugin has a newer version than the one installed.
///
/// - A plugin in its marketplace's own repository is compared folder by folder: the folder at
///   the installed commit against the same folder now. Equal tree ids mean identical content.
/// - A plugin the marketplace pins to a commit of another repository is compared by that pin,
///   read from the marketplace's current `marketplace.json`.
/// - Anything else is "can't check": a newer commit somewhere is not proof of a newer plugin.
///
/// Each request carries a repository's name and nothing else.
public struct PluginChecker: Sendable {
    public typealias FileFetcher = @Sendable (_ repository: String, _ path: String) async -> Result<Data, UpstreamState.Reason>
    private let trees: GitHubTrees
    private let fetchFile: FileFetcher

    public init(trees: GitHubTrees = GitHubTrees(budget: .shared), fetchFile: @escaping FileFetcher = PluginChecker.rawFile) {
        self.trees = trees
        self.fetchFile = fetchFile
    }

    /// Reads one file from a repository's default branch, from GitHub's raw file host.
    public static let rawFile: FileFetcher = { repository, path in
        guard let url = URL(string: "https://raw.githubusercontent.com/\(repository)/HEAD/\(path)") else {
            return .failure(.unsupported)
        }
        var request = URLRequest(url: url)
        request.setValue("Skillori", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await GitHubTrees.network(request)
            switch response.statusCode {
            case 200: return .success(data)
            case 404: return .failure(.notFound)
            case 403, 429: return .failure(.rateLimited)
            default: return .failure(.failed)
            }
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.offline)
        }
    }

    /// A Cursor or Codex plugin: the version in its manifest now, at the top of its repository's
    /// default branch, against the version installed. A newer version there is what the app
    /// would install next; a commit without a new version is not counted as an update.
    private func checkManifest(of record: PluginRecord,
                               tree: (UpstreamSource) async -> Result<SourceTree, UpstreamState.Reason>) async -> UpstreamState {
        guard let manifestPath = record.manifestPath, let repository = record.repository,
              let source = UpstreamSource(source: repository, sourceURL: nil) else { return .cannotCheck(.unsupported) }
        guard let installed = record.version, !installed.isEmpty else { return .cannotCheck(.noBaseline) }
        let listing: SourceTree
        switch await tree(source) {
        case .failure(let reason): return .cannotCheck(reason)
        case .success(let value): listing = value
        }
        guard let path = Self.manifestLocation(of: record, manifestPath: manifestPath, in: listing) else {
            return .cannotCheck(listing.truncated ? .failed : .folderGone)
        }
        switch await fetchFile(source.name, path) {
        case .failure(let reason): return .cannotCheck(reason)
        case .success(let data):
            guard let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let latest = manifest["version"] as? String, !latest.isEmpty else { return .cannotCheck(.failed) }
            return Self.isNewer(latest, than: installed) ? .updateAvailable(upstreamHash: latest) : .upToDate
        }
    }

    /// Whether version `a` comes after `b`. Dotted numbers are compared as numbers
    /// (`0.10.0` after `0.9.1`); anything else counts as newer only when it differs.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ text: String) -> [Int]? {
            let core = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? text
            let numbers = core.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").map { Int($0) }
            return numbers.contains(nil) || numbers.isEmpty ? nil : numbers.compactMap { $0 }
        }
        guard let x = parts(a), let y = parts(b) else { return a != b }
        for index in 0..<max(x.count, y.count) {
            let left = index < x.count ? x[index] : 0
            let right = index < y.count ? y[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// Where a plugin's manifest is in its repository: at the top for a checkout of the plugin
    /// itself, otherwise in the folder named like the plugin. Nil when that is not clear.
    static func manifestLocation(of record: PluginRecord, manifestPath: String, in tree: SourceTree) -> String? {
        if record.isCheckout { return tree.files[manifestPath] != nil ? manifestPath : nil }
        let all = tree.files.keys.filter { $0 == manifestPath || $0.hasSuffix("/" + manifestPath) }
        let named = all.filter { path in
            let folder = String(path.dropLast(manifestPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return (folder as NSString).lastPathComponent == record.name
        }
        if named.count == 1 { return named[0] }
        if named.isEmpty, all.count == 1 { return all[0] }
        return nil
    }

    /// One answer per plugin id. `baselines` holds folder hashes at installed commits that
    /// earlier checks already fetched (they never change), and gains the new ones.
    public func check(_ records: [PluginRecord], baselines: inout [String: String]) async -> [String: UpstreamState] {
        var answers: [String: UpstreamState] = [:]
        // Each marketplace manifest is read once, however many of its plugins are installed.
        var manifests: [String: Result<[String: Any], UpstreamState.Reason>] = [:]
        // Each tree is asked for once, however many plugins share it.
        var treeAnswers: [String: Result<SourceTree, UpstreamState.Reason>] = [:]
        func tree(_ source: UpstreamSource) async -> Result<SourceTree, UpstreamState.Reason> {
            let key = "\(source.name)@\(source.ref ?? "HEAD")"
            if let known = treeAnswers[key] { return known }
            let answer = await trees.tree(of: source)
            treeAnswers[key] = answer
            return answer
        }

        for record in Set(records.map(\.id)).sorted().compactMap({ id in records.first { $0.id == id } }) {
            if record.manifestPath != nil {
                answers[record.id] = await checkManifest(of: record, tree: tree)
                continue
            }
            guard let repository = record.marketplaceRepository else {
                answers[record.id] = .cannotCheck(.unsupported)
                continue
            }
            if manifests[repository] == nil {
                let fetched = await fetchFile(repository, ".claude-plugin/marketplace.json")
                manifests[repository] = fetched.flatMap { data in
                    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                        return .failure(.failed)
                    }
                    return .success(object)
                }
            }
            let manifest: [String: Any]
            switch manifests[repository]! {
            case .failure(let reason):
                answers[record.id] = .cannotCheck(reason)
                continue
            case .success(let value): manifest = value
            }
            guard let origin = ClaudePlugins.origin(of: record.name, inMarketplace: manifest) else {
                // The marketplace no longer lists it.
                answers[record.id] = .cannotCheck(.folderGone)
                continue
            }
            switch origin {
            case .repository(_, _, _, let pinned?):
                guard let commit = record.commit else {
                    answers[record.id] = .cannotCheck(.noBaseline)
                    continue
                }
                answers[record.id] = commit == pinned ? .upToDate : .updateAvailable(upstreamHash: pinned)
            case .inMarketplace(let path):
                guard let commit = record.commit, let parts = UpstreamSource(source: repository, sourceURL: nil) else {
                    answers[record.id] = .cannotCheck(.noBaseline)
                    continue
                }
                // "tree:" marks hashes of the real root tree; older keys held a commit id there.
                let baselineKey = "tree:\(repository)@\(commit)#\(path)"
                if baselines[baselineKey] == nil {
                    let then = UpstreamSource(owner: parts.owner, repository: parts.repository, ref: commit)
                    switch await tree(then) {
                    case .success(let old):
                        if let hash = old.hash(of: path) { baselines[baselineKey] = hash }
                    case .failure(let reason):
                        answers[record.id] = .cannotCheck(reason)
                        continue
                    }
                }
                switch await tree(parts) {
                case .success(let now):
                    answers[record.id] = UpstreamComparer.state(baseline: baselines[baselineKey], subpath: path, in: now)
                case .failure(let reason):
                    answers[record.id] = .cannotCheck(reason)
                }
            case .repository(_, _, _, nil), .other:
                // Not pinned: compare versions when both sides give one, otherwise say so.
                if let installed = record.version, let latest = ClaudePlugins.version(of: record.name, inMarketplace: manifest) {
                    answers[record.id] = Self.isNewer(latest, than: installed) ? .updateAvailable(upstreamHash: latest) : .upToDate
                } else {
                    answers[record.id] = .cannotCheck(.unsupported)
                }
            }
        }
        return answers
    }
}
