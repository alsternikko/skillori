import Foundation

/// Where a tracked skill came from, in a form that can be asked about its current content.
/// Only public GitHub repositories are supported so far.
public struct UpstreamSource: Hashable, Sendable {
    public let owner: String
    public let repository: String
    /// Branch, tag or commit. Nil means the repository's default branch.
    public let ref: String?

    public init(owner: String, repository: String, ref: String? = nil) {
        self.owner = owner
        self.repository = repository
        self.ref = ref
    }

    /// Reads what `npx skills` records: a clone URL when there is one, otherwise `owner/repo`.
    /// Anything that is not plainly a GitHub repository gives nil, never a guess. A bare
    /// `owner/repo` is only read as GitHub when the recorded source type allows it, so a local
    /// folder or another host is never sent to GitHub by name.
    public init?(source: String, sourceURL: String?, ref: String? = nil, sourceType: String? = nil) {
        let parts: [Substring]
        if let sourceURL, !sourceURL.isEmpty {
            guard let url = URL(string: sourceURL), url.scheme == "https",
                  url.host?.lowercased() == "github.com" else { return nil }
            parts = url.path.split(separator: "/")
        } else {
            if let sourceType, !sourceType.isEmpty, sourceType.lowercased() != "github" { return nil }
            parts = source.split(separator: "/", omittingEmptySubsequences: false)
        }
        guard parts.count == 2 else { return nil }
        let owner = String(parts[0])
        var repository = String(parts[1])
        if repository.hasSuffix(".git") { repository.removeLast(4) }
        guard Self.isName(owner), Self.isName(repository) else { return nil }
        self.init(owner: owner, repository: repository, ref: ref?.isEmpty == false ? ref : nil)
    }

    public var name: String { "\(owner)/\(repository)" }

    /// Reads what a person types or pastes when pointing at a source: `owner/repo`, a GitHub
    /// address, or the address of a folder inside a repository (`…/tree/<branch>/<folder>`).
    /// A branch name with a slash in it cannot be told from a folder, so it is not supported here.
    public static func parse(_ text: String) -> (source: UpstreamSource, subpath: String?)? {
        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.hasSuffix("/") { input.removeLast() }
        guard !input.isEmpty else { return nil }
        if !input.contains("://"), !input.lowercased().hasPrefix("github.com/") {
            return UpstreamSource(source: input, sourceURL: nil).map { ($0, nil) }
        }
        if !input.contains("://") { input = "https://" + input }
        guard let url = URL(string: input), url.scheme == "https", url.host?.lowercased() == "github.com" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        var ref: String?
        var subpath: String?
        if parts.count >= 4, parts[2] == "tree" || parts[2] == "blob" {
            ref = parts[3]
            var rest = Array(parts.dropFirst(4))
            if rest.last == "SKILL.md" { rest.removeLast() }
            subpath = rest.isEmpty ? nil : rest.joined(separator: "/")
        } else if parts.count > 2 {
            return nil
        }
        guard let source = UpstreamSource(source: "\(parts[0])/\(parts[1])", sourceURL: nil, ref: ref) else { return nil }
        return (source, subpath)
    }

    /// The page a person can open to look at the source themselves.
    public func webURL(subpath: String? = nil) -> URL? {
        var text = "https://github.com/\(owner)/\(repository)"
        if let subpath, !subpath.isEmpty { text += "/tree/\(ref ?? "HEAD")/\(subpath)" }
        return URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? text)
    }

    /// The source's history for one folder, newest first.
    public func historyURL(subpath: String?) -> URL? {
        var text = "https://github.com/\(owner)/\(repository)/commits/\(ref ?? "HEAD")"
        if let subpath, !subpath.isEmpty { text += "/\(subpath)" }
        return URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? text)
    }

    private static func isName(_ text: String) -> Bool {
        !text.isEmpty && text != "." && text != ".."
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }
}

/// What asking the source said about one skill.
public enum UpstreamState: Sendable, Equatable, Codable {
    /// Why a skill could not be compared with its source.
    public enum Reason: String, Sendable, Codable, Error {
        /// The source answered "not found": private, renamed or removed. They look the same from outside.
        case notFound
        /// The source exists but no longer has this skill's folder.
        case folderGone
        /// Too many questions for now; the source says when to ask again.
        case rateLimited
        /// No answer: offline, timed out, or the connection failed.
        case offline
        /// The question was withdrawn before an answer came. Says nothing about the source.
        case cancelled
        /// Not a kind of source Skillori can ask yet.
        case unsupported
        /// The installer left no baseline to compare with.
        case noBaseline
        /// The source answered with something unexpected.
        case failed
    }

    /// The folder in the source has the same content as the installed baseline.
    case upToDate
    /// The folder in the source has other content than the installed baseline.
    case updateAvailable(upstreamHash: String)
    case cannotCheck(Reason)
}

/// One answer, and when it was given.
public struct UpstreamReading: Sendable, Equatable, Codable {
    public var state: UpstreamState
    public var checkedAt: Date

    public init(state: UpstreamState, checkedAt: Date) {
        self.state = state
        self.checkedAt = checkedAt
    }
}

/// The folders of a source and the git tree id of each, as the source has them now.
public struct SourceTree: Sendable, Equatable {
    public let rootHash: String
    public let folders: [String: String]
    /// Folders that hold a `SKILL.md`, sorted. The empty string stands for the top of the source.
    public let skillFolders: [String]
    /// The source cut the listing short, so a missing folder proves nothing.
    public let truncated: Bool

    public init(rootHash: String, folders: [String: String], skillFolders: [String] = [], truncated: Bool = false) {
        self.rootHash = rootHash
        self.folders = folders
        self.skillFolders = skillFolders
        self.truncated = truncated
    }

    /// The tree id of a folder; the empty string or nil is the top of the source.
    public func hash(of subpath: String?) -> String? {
        let path = (subpath ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? rootHash : folders[path]
    }
}

public enum UpstreamComparer {
    /// Compares the baseline the installer recorded with the same folder in the source.
    /// The ids are git tree ids, so equal ids mean identical content.
    public static func state(baseline: String?, subpath: String?, in tree: SourceTree) -> UpstreamState {
        guard let baseline, !baseline.isEmpty else { return .cannotCheck(.noBaseline) }
        guard let current = tree.hash(of: subpath) else {
            return .cannotCheck(tree.truncated ? .failed : .folderGone)
        }
        return current == baseline ? .upToDate : .updateAvailable(upstreamHash: current)
    }
}

/// Asks GitHub for a repository's folders. One question per repository answers for every skill in it.
///
/// The request carries the repository's name and nothing else: no account, no token, nothing
/// about the reader or the files on this Mac.
public struct GitHubTrees: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport

    public init(transport: @escaping Transport = GitHubTrees.network) {
        self.transport = transport
    }

    public static let network: Transport = { request in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    public static func request(for source: UpstreamSource) -> URLRequest? {
        // A ref goes into the path, so it may not climb out of the trees endpoint.
        if let ref = source.ref, ref.split(separator: "/", omittingEmptySubsequences: false)
            .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(source.owner)/\(source.repository)/git/trees/\(source.ref ?? "HEAD")"
        components.queryItems = [URLQueryItem(name: "recursive", value: "1")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Skillori", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// GitHub answers both its hourly limit and its secondary limits with 403 or 429. The
    /// secondary ones carry `retry-after` and usually still have requests left in the hour.
    static func isRateLimit(_ response: HTTPURLResponse) -> Bool {
        if response.statusCode == 429 { return true }
        if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" { return true }
        return response.value(forHTTPHeaderField: "retry-after") != nil
    }

    public func tree(of source: UpstreamSource) async -> Result<SourceTree, UpstreamState.Reason> {
        guard let request = Self.request(for: source) else { return .failure(.unsupported) }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch let error as URLError where error.code == .cancelled {
            return .failure(.cancelled)
        } catch {
            return .failure(.offline)
        }
        switch response.statusCode {
        case 200: break
        case 404: return .failure(.notFound)
        case 403, 429:
            return .failure(Self.isRateLimit(response) ? .rateLimited : .notFound)
        default: return .failure(.failed)
        }
        struct Listing: Decodable {
            struct Item: Decodable { let path: String; let type: String; let sha: String }
            let sha: String
            let tree: [Item]
            let truncated: Bool?
        }
        guard let listing = try? JSONDecoder().decode(Listing.self, from: data) else { return .failure(.failed) }
        let folders = Dictionary(listing.tree.filter { $0.type == "tree" }.map { ($0.path, $0.sha) },
                                 uniquingKeysWith: { first, _ in first })
        let skillFolders = listing.tree
            .filter { $0.type == "blob" && ($0.path == "SKILL.md" || $0.path.hasSuffix("/SKILL.md")) }
            .map { ($0.path as NSString).deletingLastPathComponent }
            .sorted()
        return .success(SourceTree(rootHash: listing.sha, folders: folders, skillFolders: skillFolders,
                                   truncated: listing.truncated ?? false))
    }
}

/// One tracked skill to ask about.
public struct UpstreamQuestion: Sendable {
    public let key: String
    public let source: UpstreamSource?
    public let subpath: String?
    public let baseline: String?

    public init(key: String, source: UpstreamSource?, subpath: String?, baseline: String?) {
        self.key = key
        self.source = source
        self.subpath = subpath
        self.baseline = baseline
    }
}

public enum UpstreamChecker {
    /// Answers every question, asking each source once.
    public static func check(_ questions: [UpstreamQuestion], using trees: GitHubTrees = GitHubTrees()) async -> [String: UpstreamState] {
        var answers: [String: UpstreamState] = [:]
        var bySource: [UpstreamSource: [UpstreamQuestion]] = [:]
        for question in questions {
            if let source = question.source {
                bySource[source, default: []].append(question)
            } else {
                answers[question.key] = .cannotCheck(.unsupported)
            }
        }
        await withTaskGroup(of: (UpstreamSource, Result<SourceTree, UpstreamState.Reason>).self) { group in
            for source in bySource.keys {
                group.addTask { (source, await trees.tree(of: source)) }
            }
            for await (source, result) in group {
                for question in bySource[source] ?? [] {
                    switch result {
                    case .success(let tree):
                        answers[question.key] = UpstreamComparer.state(baseline: question.baseline, subpath: question.subpath, in: tree)
                    case .failure(let reason):
                        answers[question.key] = .cannotCheck(reason)
                    }
                }
            }
        }
        return answers
    }
}

/// A folder in a source that a skill on this Mac might have come from.
public struct SourceCandidate: Sendable, Equatable, Identifiable {
    public enum Match: Int, Sendable, Comparable {
        /// Byte for byte the same content as the skill on this Mac.
        case identical
        /// A skill folder with the same name; the content differs.
        case sameName
        /// Some other skill in the source.
        case other

        public static func < (a: Match, b: Match) -> Bool { a.rawValue < b.rawValue }
    }

    /// The folder inside the source; empty for the top of it.
    public let subpath: String
    public let hash: String
    public let match: Match
    public var id: String { subpath }

    public init(subpath: String, hash: String, match: Match) {
        self.subpath = subpath
        self.hash = hash
        self.match = match
    }
}

public enum SourceMatcher {
    /// The skill folders of a source, best match first: identical content, then the same
    /// name, then the rest in order. Nothing is guessed: a name match is only a name match.
    public static func candidates(localHash: String?, names: [String], in tree: SourceTree) -> [SourceCandidate] {
        let wanted = Set(names.map { $0.lowercased() })
        return tree.skillFolders.compactMap { folder -> SourceCandidate? in
            guard let hash = tree.hash(of: folder) else { return nil }
            let last = (folder as NSString).lastPathComponent.lowercased()
            let match: SourceCandidate.Match = hash == localHash ? .identical : wanted.contains(last) ? .sameName : .other
            return SourceCandidate(subpath: folder, hash: hash, match: match)
        }
        .sorted { a, b in a.match != b.match ? a.match < b.match : a.subpath < b.subpath }
    }
}
