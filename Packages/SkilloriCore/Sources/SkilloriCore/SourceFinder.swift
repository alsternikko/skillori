import Foundation

/// Finds where a skill with no installer record came from, and says how sure that is.
///
/// Candidates come from three places: a skill registry that records where its skills live
/// (mdskills.ai), the repositories the reader already installs from, and a few large public
/// collections. Each candidate is then compared with the files on this Mac: the folder as it
/// is now, the skill file alone (some installers copy only SKILL.md), the skill file as Codex's
/// import from Claude rewrites it, and earlier versions of the skill file in the source's
/// history. Nothing is guessed: a name match is reported as only a name match.
///
/// Every request carries a skill's name or a repository's name and nothing else.

/// One place a skill registry says a skill lives.
public struct RegistryHit: Sendable, Equatable {
    public let registry: String
    public let source: UpstreamSource
    public let subpath: String
}

/// Asks the mdskills.ai registry where a skill lives. Its records name the GitHub repository
/// and the folder, which is what its own installer leaves out.
public struct SkillRegistry: Sendable {
    public typealias Transport = GitHubTrees.Transport
    private let transport: Transport

    public init(transport: @escaping Transport = GitHubTrees.network) {
        self.transport = transport
    }

    public static func request(for name: String) -> URLRequest? {
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }),
              name != ".", name != "..",
              let url = URL(string: "https://www.mdskills.ai/api/skills/\(name)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Skillori", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    public func lookup(_ name: String) async -> RegistryHit? {
        if case .success(let hit) = await find(name) { return hit }
        return nil
    }

    /// Nil when the registry does not know the skill; a failure when it could not be asked.
    public func find(_ name: String) async -> Result<RegistryHit?, UpstreamState.Reason> {
        guard let request = Self.request(for: name) else { return .success(nil) }
        let data: Data
        do {
            let (body, response) = try await transport(request)
            switch response.statusCode {
            case 200: data = body
            case 404: return .success(nil)
            case 429: return .failure(.rateLimited)
            default: return .failure(.failed)
            }
        } catch {
            return .failure(.offline)
        }
        return .success(Self.read(data))
    }

    static func read(_ data: Data) -> RegistryHit? {
        struct Answer: Decodable {
            struct Skill: Decodable {
                let owner: String?
                let repo: String?
                let skill_path: String?
                let github_url: String?
            }
            let skill: Skill?
        }
        guard let skill = (try? JSONDecoder().decode(Answer.self, from: data))?.skill else { return nil }
        var source: UpstreamSource?
        var subpath = ""
        if let owner = skill.owner, let repo = skill.repo {
            source = UpstreamSource(source: "\(owner)/\(repo)", sourceURL: nil)
        }
        if let path = skill.skill_path?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            // Sometimes a file (SKILL.md, README.md); the skill is the folder that holds it.
            subpath = path.lowercased().hasSuffix(".md") ? (path as NSString).deletingLastPathComponent : path
        }
        if source == nil, let url = skill.github_url, let (parsed, folder) = UpstreamSource.parse(url) {
            source = UpstreamSource(owner: parsed.owner, repository: parsed.repository)
            if subpath.isEmpty { subpath = folder ?? "" }
        }
        guard let source, !subpath.contains("..") else { return nil }
        return RegistryHit(registry: "mdskills.ai", source: source, subpath: subpath)
    }
}

/// How a skill on this Mac relates to a folder in a source.
public enum SourceEvidence: Sendable, Equatable {
    /// The whole folder has the same content as the source has now.
    case identical
    /// The skill file is the source's current one; files the source has besides it are missing here.
    case sameSkillFile(missing: Int)
    /// The skill file is one the source had earlier.
    case olderVersion(date: Date?, commit: String, missing: Int)
    /// Only the folder name is the same.
    case sameName

    /// Lower is stronger.
    var rank: Int {
        switch self {
        case .identical: 0
        case .sameSkillFile: 1
        case .olderVersion: 2
        case .sameName: 3
        }
    }

    /// The evidence proves where the skill came from, rather than suggesting it.
    public var isConfirmed: Bool { self != .sameName }
}

/// A source for one skill, with what speaks for it.
public struct SourceProposal: Sendable, Equatable, Identifiable {
    public let source: UpstreamSource
    public let subpath: String
    public let evidence: SourceEvidence
    /// Matched only after undoing Codex's import rewriting "Claude" as "Codex".
    public let rewritten: Bool
    /// The folder is no longer in the source; the match is with its history.
    public let folderGone: Bool
    /// Where the candidate came from: a registry, "your sources", or a known collection.
    public let via: String
    /// The folder's content id in the source now, when it is still there.
    public let upstreamHash: String?
    public var id: String { source.name + "#" + subpath }

    public init(source: UpstreamSource, subpath: String, evidence: SourceEvidence, rewritten: Bool = false,
                folderGone: Bool = false, via: String, upstreamHash: String?) {
        self.source = source
        self.subpath = subpath
        self.evidence = evidence
        self.rewritten = rewritten
        self.folderGone = folderGone
        self.via = via
        self.upstreamHash = upstreamHash
    }
}

/// What a skill on this Mac looks like, for the comparison.
public struct LocalSkill: Sendable {
    public let name: String
    public let treeID: String
    public let entries: [GitTreeHash.Entry]
    public let skillFile: Data?

    public init(name: String, treeID: String, entries: [GitTreeHash.Entry], skillFile: Data?) {
        self.name = name
        self.treeID = treeID
        self.entries = entries
        self.skillFile = skillFile
    }

    public init(name: String, folder: URL) throws {
        let hashed = try GitTreeHash.hashDirectory(at: folder)
        self.init(name: name, treeID: hashed.treeID, entries: hashed.entries,
                  skillFile: FileManager.default.contents(atPath: folder.appendingPathComponent("SKILL.md").path))
    }

    /// Blob ids the skill file may have had in its source: as it is, and with Codex's rewrite undone.
    var skillFileIDs: [(id: String, rewritten: Bool)] {
        guard let skillFile else { return [] }
        var ids = [(id: GitTreeHash.objectID(type: "blob", body: skillFile).hex, rewritten: false)]
        if let text = String(data: skillFile, encoding: .utf8), text.contains("Codex") {
            let undone = Data(text.replacingOccurrences(of: "Codex", with: "Claude").utf8)
            ids.append((id: GitTreeHash.objectID(type: "blob", body: undone).hex, rewritten: true))
        }
        return ids
    }
}

/// Large public collections worth asking by name when nothing better is known.
public enum KnownCollections {
    public static let repositories: [UpstreamSource] = [
        UpstreamSource(owner: "anthropics", repository: "skills"),
        UpstreamSource(owner: "openai", repository: "skills"),
        UpstreamSource(owner: "vercel-labs", repository: "agent-skills"),
    ]
}

/// The repositories one search has read, so each is asked once however many skills it is
/// compared with. GitHub counts every request against its hourly limit, unchanged answers too.
actor TreeMemory {
    private var trees: [UpstreamSource: Result<SourceTree, UpstreamState.Reason>] = [:]

    func tree(of source: UpstreamSource, asking ask: GitHubTrees) async -> Result<SourceTree, UpstreamState.Reason> {
        if let known = trees[source] { return known }
        let answer = await ask.tree(of: source)
        // A withdrawn question says nothing; ask again next time.
        if answer != .failure(.cancelled) { trees[source] = answer }
        return answer
    }
}

/// Keep one finder for a whole search: it remembers each repository it has read.
public struct SourceFinder: Sendable {
    public typealias FileFetcher = @Sendable (_ source: UpstreamSource, _ ref: String, _ path: String) async -> Data?
    public typealias HistoryFetcher = @Sendable (_ source: UpstreamSource, _ path: String) async -> Result<[(sha: String, date: Date?)], UpstreamState.Reason>

    private let trees: GitHubTrees
    private let registry: SkillRegistry
    private let fetchFile: FileFetcher
    private let history: HistoryFetcher
    private let memory = TreeMemory()
    /// How many earlier versions of one skill file are read at most.
    public static let maxVersions = 30

    public init(trees: GitHubTrees = GitHubTrees(budget: .shared), registry: SkillRegistry = SkillRegistry(),
                fetchFile: @escaping FileFetcher = SourceFinder.rawFile, history: @escaping HistoryFetcher = SourceFinder.commits) {
        self.trees = trees
        self.registry = registry
        self.fetchFile = fetchFile
        self.history = history
    }

    /// What a search for one skill found, and why it may have found less than it could.
    public struct Search: Sendable, Equatable {
        public let proposals: [SourceProposal]
        /// A source that could not be asked (offline, asked to wait). Set only when nothing
        /// confirmed was found, since only then could the missing answer have changed the result.
        public let problem: UpstreamState.Reason?

        public init(proposals: [SourceProposal], problem: UpstreamState.Reason?) {
            self.proposals = proposals
            self.problem = problem
        }
    }

    /// Sources for one skill, strongest first.
    public func proposals(for skill: LocalSkill, yourSources: [UpstreamSource] = []) async -> [SourceProposal] {
        await search(for: skill, yourSources: yourSources).proposals
    }

    /// Sources for one skill, strongest first. `yourSources` are repositories other skills on
    /// this Mac come from. Asking stops at the first confirmed match, to keep requests few.
    public func search(for skill: LocalSkill, yourSources: [UpstreamSource] = []) async -> Search {
        var problem: UpstreamState.Reason?
        func note(_ reason: UpstreamState.Reason) {
            if reason == .rateLimited || reason == .offline || reason == .failed { problem = problem ?? reason }
        }
        var candidates: [(source: UpstreamSource, subpath: String, via: String)] = []
        switch await registry.find(skill.name) {
        case .success(let hit?): candidates.append((hit.source, hit.subpath, hit.registry))
        case .success(nil): break
        case .failure(let reason): note(reason)
        }
        let wanted = Self.nameVariants(skill.name)
        var seenRepositories = Set(candidates.map(\.source.name))
        for (repositories, via) in [(yourSources, "your sources"), (KnownCollections.repositories, "known collection")] {
            for repository in repositories where !seenRepositories.contains(repository.name) {
                seenRepositories.insert(repository.name)
                let tree: SourceTree
                switch await memory.tree(of: repository, asking: trees) {
                case .success(let answer): tree = answer
                case .failure(let reason): note(reason); continue
                }
                for folder in tree.skillFolders where wanted.contains((folder as NSString).lastPathComponent.lowercased()) {
                    candidates.append((repository, folder, via))
                }
            }
        }

        var found: [SourceProposal] = []
        var seen: Set<String> = []
        for candidate in candidates where seen.insert(candidate.source.name + "#" + candidate.subpath).inserted {
            let proposal: SourceProposal
            switch await check(skill, in: candidate.source, subpath: candidate.subpath, via: candidate.via) {
            case .success(let answer?): proposal = answer
            case .success(nil): continue
            case .failure(let reason): note(reason); continue
            }
            found.append(proposal)
            if proposal.evidence.isConfirmed, !proposal.folderGone { break }
        }
        // A folder still in its source comes first: one that is gone can explain, but not be followed.
        let sorted = found.sorted { ($0.folderGone ? 1 : 0, $0.evidence.rank) < ($1.folderGone ? 1 : 0, $1.evidence.rank) }
        let confirmed = sorted.contains { $0.evidence.isConfirmed && !$0.folderGone }
        return Search(proposals: sorted, problem: confirmed ? nil : problem)
    }

    /// The name, and the name without a suffix collections add when they copy a skill.
    static func nameVariants(_ name: String) -> Set<String> {
        let lower = name.lowercased()
        var names: Set<String> = [lower]
        for suffix in ["-official", "-skill"] where lower.hasSuffix(suffix) && lower.count > suffix.count {
            names.insert(String(lower.dropLast(suffix.count)))
        }
        return names
    }

    /// Compares a skill with one folder of a source.
    public func verify(_ skill: LocalSkill, in source: UpstreamSource, subpath: String, via: String) async -> SourceProposal? {
        if case .success(let answer) = await check(skill, in: source, subpath: subpath, via: via) { return answer }
        return nil
    }

    /// Compares a skill with one folder of a source; a failure means the source could not be asked.
    func check(_ skill: LocalSkill, in source: UpstreamSource, subpath: String, via: String) async -> Result<SourceProposal?, UpstreamState.Reason> {
        let tree: SourceTree
        switch await memory.tree(of: source, asking: trees) {
        case .success(let answer): tree = answer
        case .failure(let reason): return .failure(reason)
        }
        let folderHash = tree.hash(of: subpath)
        let prefix = subpath.isEmpty ? "" : subpath + "/"
        let upstreamFiles = tree.files.filter { $0.key.hasPrefix(prefix) }
        let localPaths = Set(skill.entries.filter { $0.kind != .directory }.map(\.path))
        let missing = upstreamFiles.keys.filter { !localPaths.contains(String($0.dropFirst(prefix.count))) }.count

        func proposal(_ evidence: SourceEvidence, rewritten: Bool = false) -> SourceProposal {
            SourceProposal(source: source, subpath: subpath, evidence: evidence, rewritten: rewritten,
                           folderGone: folderHash == nil, via: via, upstreamHash: folderHash)
        }

        if folderHash == skill.treeID { return .success(proposal(.identical)) }
        let ids = skill.skillFileIDs
        if let current = upstreamFiles[prefix + "SKILL.md"]?.id, let match = ids.first(where: { $0.id == current }) {
            return .success(proposal(.sameSkillFile(missing: missing), rewritten: match.rewritten))
        }
        let sameName = folderHash != nil && Self.nameVariants(skill.name).contains((subpath as NSString).lastPathComponent.lowercased())
        if !ids.isEmpty {
            switch await history(source, prefix + "SKILL.md") {
            case .success(let versions):
                for version in versions.prefix(Self.maxVersions) {
                    guard let data = await fetchFile(source, version.sha, prefix + "SKILL.md") else { continue }
                    let id = GitTreeHash.objectID(type: "blob", body: data).hex
                    if let match = ids.first(where: { $0.id == id }) {
                        return .success(proposal(.olderVersion(date: version.date, commit: version.sha, missing: missing), rewritten: match.rewritten))
                    }
                }
            case .failure(let reason) where reason == .rateLimited || reason == .offline:
                // The history could not be read, so "only the name" may be selling it short.
                if !sameName { return .failure(reason) }
                return .success(proposal(.sameName))
            case .failure:
                break
            }
        }
        return .success(sameName ? proposal(.sameName) : nil)
    }

    // MARK: Network

    /// One file at one commit, from GitHub's raw file host, which does not count against the API limit.
    public static let rawFile: FileFetcher = { source, ref, path in
        guard ref.allSatisfy({ $0.isHexDigit }), !path.split(separator: "/").contains(".."),
              let url = URL(string: "https://raw.githubusercontent.com/\(source.owner)/\(source.repository)/\(ref)/"
                            + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Skillori", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await GitHubTrees.network(request), response.statusCode == 200 else { return nil }
        return data
    }

    /// The commits that changed one file, newest first: one API request.
    public static let commits: HistoryFetcher = { source, path in
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(source.owner)/\(source.repository)/commits"
        components.queryItems = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "per_page", value: "\(maxVersions)")]
        guard let url = components.url else { return .failure(.unsupported) }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Skillori", forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            let (body, response) = try await GitHubTrees.network(request)
            switch response.statusCode {
            case 200: data = body
            case 404: return .failure(.notFound)
            case 403, 429: return .failure(.rateLimited)
            default: return .failure(.failed)
            }
        } catch {
            return .failure(.offline)
        }
        return readCommits(data)
    }

    static func readCommits(_ data: Data) -> Result<[(sha: String, date: Date?)], UpstreamState.Reason> {
        struct Item: Decodable {
            struct Commit: Decodable {
                struct Person: Decodable { let date: String? }
                let committer: Person?
            }
            let sha: String
            let commit: Commit?
        }
        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { return .failure(.failed) }
        let dates = ISO8601DateFormatter()
        return .success(items.map { ($0.sha, $0.commit?.committer?.date.flatMap(dates.date(from:))) })
    }
}
