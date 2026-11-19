import Foundation

/// A skill its author shares as an install script on their own site (`curl … | bash`) rather
/// than as a folder in a repository. Skillori downloads the script as text and reads which files
/// it would write. The script is never run.
public struct InstallerSource: Hashable, Sendable {
    public let url: URL

    /// Reads a script address, or a whole `curl -fsSL https://… | bash` line pasted as it was
    /// copied from the author's page. Only https. GitHub repositories are not read here: they
    /// have their own kind of source.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: Substring
        if let start = trimmed.range(of: "https://", options: .caseInsensitive) {
            let rest = trimmed[start.lowerBound...]
            let end = rest.firstIndex(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "|" || $0 == ")" }) ?? rest.endIndex
            candidate = rest[..<end]
        } else {
            return nil
        }
        guard let url = URL(string: String(candidate)), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), host.contains("."),
              host != "github.com", host != "www.github.com",
              url.user == nil, url.password == nil else { return nil }
        self.url = url
    }

    /// The address without its scheme, as a person would say it: `interfacecraft.dev/api/install-skills`.
    public var name: String {
        var host = url.host ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path == "/" ? "" : url.path
        return host + path
    }

    /// The author's site, for a person to look at. The script itself is mostly encoded files.
    public var siteURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = url.host
        components.path = "/"
        return components.url
    }

    /// The command the author gives for installing. Running it is the reader's own choice.
    public var installCommand: String { "curl -fsSL \(url.absoluteString) | bash" }
}

/// Where a skill comes from, in a form that can be asked about its current content.
public enum SkillSource: Hashable, Sendable {
    case github(UpstreamSource)
    case installer(InstallerSource)

    public var name: String {
        switch self {
        case .github(let source): source.name
        case .installer(let source): source.name
        }
    }

    /// The page a person can open to look at the source themselves.
    public func webURL(subpath: String? = nil) -> URL? {
        switch self {
        case .github(let source): source.webURL(subpath: subpath)
        case .installer(let source): source.siteURL
        }
    }

    /// The source's history for one folder. An install script keeps none.
    public func historyURL(subpath: String?) -> URL? {
        switch self {
        case .github(let source): source.historyURL(subpath: subpath)
        case .installer: nil
        }
    }

    /// Reads what a person types or pastes: a GitHub repository first, then a script address.
    public static func parse(_ text: String) -> (source: SkillSource, subpath: String?)? {
        if let (source, subpath) = UpstreamSource.parse(text) { return (.github(source), subpath) }
        if let source = InstallerSource(text) { return (.installer(source), nil) }
        return nil
    }
}

/// Reads an install script as text and works out the files it writes. Nothing is executed: the
/// script is matched against the few plain patterns such installers use, files embedded as
/// base64 and quoted here-documents, and anything else is left unread.
public enum InstallerScript {
    /// One file the script writes, by the path it writes it to (variables filled in where the
    /// script sets them as plain text).
    public struct Written: Sendable, Equatable {
        public let path: String
        public let content: Data
        public let executable: Bool
    }

    public enum ReadError: Error, Equatable {
        /// A file's content depends on something only running the script would tell.
        case notPlainText(String)
    }

    /// The largest script read. Embedded files make these large, but not this large.
    public static let maxBytes = 8 * 1024 * 1024

    public static func files(in script: String) throws(ReadError) -> [Written] {
        let lines = script.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var variables: [String: String] = [:]
        var written: [String: Written] = [:]
        var order: [String] = []
        var executable: Set<String> = []

        func write(_ path: String, _ content: Data) {
            if written[path] == nil { order.append(path) }
            written[path] = Written(path: path, content: content, executable: false)
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            let code = line.trimmingCharacters(in: .whitespaces)
            if code.isEmpty || code.hasPrefix("#") { continue }

            if let heredoc = Self.heredoc(in: code) {
                var body: [String] = []
                var closed = false
                while index < lines.count {
                    let next = lines[index]
                    index += 1
                    let compared = heredoc.stripTabs ? String(next.drop(while: { $0 == "\t" })) : next
                    if compared == heredoc.delimiter { closed = true; break }
                    body.append(heredoc.stripTabs ? compared : next)
                }
                guard closed, let target = heredoc.target else { continue }
                var text = body.map { $0 + "\n" }.joined()
                if !heredoc.quoted {
                    if text.contains("\\$") || text.contains("\\`") || text.contains("\\\\") || text.contains("\\\n") {
                        throw .notPlainText(Self.expand(target, with: variables))
                    }
                    // An unquoted here-document expands variables and commands. Plain variables the
                    // script set are filled in; anything else could only be known by running it.
                    text = Self.expand(text, with: variables)
                    if text.contains("$") || text.contains("`") {
                        throw .notPlainText(Self.expand(target, with: variables))
                    }
                }
                write(Self.path(target, variables), Data(text.utf8))
                continue
            }

            if let (name, value) = Self.assignment(in: code) {
                variables[name] = value
                continue
            }

            if code.contains("base64"), code.range(of: #"base64\s+(-d|--decode|-D)\b"#, options: .regularExpression) != nil,
               let target = Self.redirectTarget(in: code) {
                let before = code.components(separatedBy: "base64").first ?? ""
                var encoded: String?
                if let name = Self.firstVariable(in: before) {
                    encoded = variables[name]
                } else if let literal = Self.firstQuoted(in: before) {
                    encoded = literal
                }
                guard let encoded, let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else {
                    throw .notPlainText(Self.expand(target, with: variables))
                }
                write(Self.path(target, variables), data)
                continue
            }

            if code.hasPrefix("chmod "), code.range(of: #"^chmod\s+(\+x|u\+x|a\+x|0?7[0-7][0-7])\s"#, options: .regularExpression) != nil {
                let parts = Self.words(code)
                for part in parts.dropFirst(2) { executable.insert(Self.path(part, variables)) }
            }
        }

        return order.compactMap { path in
            guard let file = written[path] else { return nil }
            return Written(path: path, content: file.content, executable: executable.contains(path))
        }
    }

    /// The skills among the written files: every folder holding a `SKILL.md`, with what is
    /// under it, as a source tree. Paths are relative to the folder above the skill folders,
    /// so a script that installs one skill gives one folder named after it. A script that
    /// writes the same skill to several places counts it once.
    public static func tree(from files: [Written]) -> SourceTree {
        let skillFolders = files
            .filter { ($0.path as NSString).lastPathComponent == "SKILL.md" }
            .map { ($0.path as NSString).deletingLastPathComponent }
        guard !skillFolders.isEmpty else { return SourceTree(rootHash: GitTreeHash.emptyTreeID.hex, folders: [:]) }
        // The deepest folder above all skill folders.
        var root = (skillFolders[0] as NSString).deletingLastPathComponent
        for folder in skillFolders.dropFirst() {
            while !(folder == root || folder.hasPrefix(root + "/")) && !root.isEmpty && root != "/" {
                root = (root as NSString).deletingLastPathComponent
            }
        }
        func relative(_ path: String) -> String {
            if root.isEmpty { return path }
            if root == "/" { return path.hasPrefix("/") ? String(path.dropFirst()) : path }
            return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
        }

        var sourceFiles: [String: SourceFile] = [:]
        for file in files {
            let path = relative(file.path)
            guard skillFolders.contains(where: { $0.isEmpty || file.path.hasPrefix($0 + "/") }) else { continue }
            let id = GitTreeHash.objectID(type: "blob", body: file.content).hex
            sourceFiles[path] = SourceFile(id: id, mode: file.executable ? "100755" : "100644")
        }

        // Tree ids bottom up, the way git builds them, so they compare with a folder on disk.
        var children: [String: [(mode: String, name: String, id: String)]] = [:]
        var folders: Set<String> = []
        for (path, file) in sourceFiles {
            let parent = (path as NSString).deletingLastPathComponent
            children[parent, default: []].append((mode: file.mode, name: (path as NSString).lastPathComponent, id: file.id))
            var folder = parent
            while !folder.isEmpty {
                folders.insert(folder)
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        var hashes: [String: String] = [:]
        for folder in folders.sorted(by: { $0.split(separator: "/").count > $1.split(separator: "/").count }) {
            if let id = GitTreeHash.treeID(of: children[folder] ?? []) {
                hashes[folder] = id
                let parent = (folder as NSString).deletingLastPathComponent
                children[parent, default: []].append((mode: "40000", name: (folder as NSString).lastPathComponent, id: id))
            }
        }
        let rootHash = GitTreeHash.treeID(of: children[""] ?? []) ?? GitTreeHash.emptyTreeID.hex

        // The same skill written to several places is offered once, at its first place.
        var seen: Set<String> = []
        let skills = skillFolders.map(relative).filter { folder in
            guard let hash = folder.isEmpty ? rootHash : hashes[folder] else { return false }
            return seen.insert(hash).inserted
        }
        return SourceTree(rootHash: rootHash, folders: hashes, skillFolders: Array(Set(skills)).sorted(), files: sourceFiles)
    }

    // MARK: Reading lines

    /// `NAME=value`, `NAME="value"`, `NAME='value'`, optionally after `export`, `local` or `readonly`.
    /// A value that runs a command is not taken: its result is not known.
    static func assignment(in line: String) -> (String, String)? {
        var text = Substring(line)
        for keyword in ["export ", "local ", "readonly ", "declare "] where text.hasPrefix(keyword) {
            text = text.dropFirst(keyword.count).drop(while: { $0 == " " })
        }
        guard let equals = text.firstIndex(of: "="), equals != text.startIndex else { return nil }
        let name = String(text[..<equals])
        guard name.first.map({ $0.isLetter || $0 == "_" }) == true,
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
        var value = String(text[text.index(after: equals)...])
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        } else if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            return (name, String(value.dropFirst().dropLast()))
        } else if value.contains(" ") {
            return nil
        }
        if value.contains("$(") || value.contains("`") { return nil }
        return (name, value)
    }

    struct Heredoc {
        let delimiter: String
        let quoted: Bool
        let stripTabs: Bool
        /// The file it is written to; nil when it goes elsewhere (a pipe, an append, the screen).
        let target: String?
    }

    /// `cat > path <<'EOF'`, `cat <<EOF > path`, `cat <<-"EOF" >"path"`.
    static func heredoc(in line: String) -> Heredoc? {
        guard let range = line.range(of: #"<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1"#, options: .regularExpression),
              !line[..<range.lowerBound].hasSuffix("<") else { return nil }
        let marker = String(line[range])
        let stripTabs = marker.hasPrefix("<<-")
        let quoted = marker.contains("'") || marker.contains("\"")
        let delimiter = marker.trimmingCharacters(in: CharacterSet(charactersIn: "<-'\" \t"))
        var rest = line
        rest.removeSubrange(range)
        let target = rest.contains(">>") || rest.contains("|") || !rest.hasPrefix("cat") ? nil : redirectTarget(in: rest)
        return Heredoc(delimiter: delimiter, quoted: quoted, stripTabs: stripTabs, target: target)
    }

    /// The file after a plain `>` (not `>>`, not `2>`, not `>&`).
    static func redirectTarget(in line: String) -> String? {
        let pattern = #"(?<![>0-9&])>(?![>&])\s*("[^"]*"|'[^']*'|[^\s;&|]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let match = regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        let target = ns.substring(with: match.range(at: 1))
        if target == "/dev/null" { return nil }
        return target
    }

    static func firstVariable(in text: String) -> String? {
        guard let range = text.range(of: #"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#, options: .regularExpression) else { return nil }
        return String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "${}"))
    }

    static func firstQuoted(in text: String) -> String? {
        guard let range = text.range(of: #"(["'])[A-Za-z0-9+/=\s]{8,}\1"#, options: .regularExpression) else { return nil }
        return String(text[range].dropFirst().dropLast())
    }

    static func words(_ line: String) -> [String] {
        line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    /// Fills in `$NAME` and `${NAME}` for the plain variables the script set. Others stay as written.
    static func expand(_ text: String, with variables: [String: String]) -> String {
        guard text.contains("$"), let regex = try? NSRegularExpression(pattern: #"\$(\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))"#) else {
            return text
        }
        var result = text
        // A few rounds, for variables made of other variables; never more, so a loop cannot hang.
        for _ in 0..<6 {
            let ns = result as NSString
            var changed = false
            var output = ""
            var last = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
                let nameRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
                let name = ns.substring(with: nameRange)
                output += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                if let value = variables[name] {
                    output += value
                    changed = true
                } else {
                    output += ns.substring(with: match.range)
                }
                last = match.range.location + match.range.length
            }
            output += ns.substring(from: last)
            result = output
            if !changed { break }
        }
        return result
    }

    /// A target as written, unquoted, with plain variables filled in and `~` read as `$HOME`.
    static func path(_ target: String, _ variables: [String: String]) -> String {
        var text = target
        if text.count >= 2, (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("'") && text.hasSuffix("'")) {
            text = String(text.dropFirst().dropLast())
        }
        text = expand(text, with: variables)
        if text.hasPrefix("~/") { text = "$HOME" + text.dropFirst() }
        // `a//b` and `a/./b` name the same file as `a/b`.
        let parts = text.split(separator: "/", omittingEmptySubsequences: true).filter { $0 != "." }
        return (text.hasPrefix("/") ? "/" : "") + parts.joined(separator: "/")
    }
}

/// Downloads install scripts. The request carries the address and nothing else: no account,
/// no cookies, nothing about the reader or the files on this Mac.
public struct InstallerScripts: Sendable {
    public typealias Transport = GitHubTrees.Transport
    private let transport: Transport

    public init(transport: @escaping Transport = InstallerScripts.network) {
        self.transport = transport
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    public static let network: Transport = { request in
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    public static func request(for source: InstallerSource) -> URLRequest {
        var request = URLRequest(url: source.url)
        request.setValue("text/plain, text/x-shellscript, */*", forHTTPHeaderField: "Accept")
        request.setValue("Skillori", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    public func tree(of source: InstallerSource) async -> Result<SourceTree, UpstreamState.Reason> {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(Self.request(for: source))
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch let error as URLError where error.code == .cancelled {
            return .failure(.cancelled)
        } catch {
            return .failure(.offline)
        }
        // A redirect may only end on https; the session follows it, so look where it ended.
        if let final = response.url, final.scheme?.lowercased() != "https" { return .failure(.failed) }
        switch response.statusCode {
        case 200: break
        case 404, 410: return .failure(.notFound)
        case 429: return .failure(.rateLimited)
        default: return .failure(.failed)
        }
        guard data.count <= InstallerScript.maxBytes, let text = String(data: data, encoding: .utf8) else { return .failure(.failed) }
        // A web page is not a script, whatever its address.
        if text.prefix(512).lowercased().contains("<!doctype html") || text.prefix(512).lowercased().contains("<html") {
            return .failure(.failed)
        }
        guard let files = try? InstallerScript.files(in: text) else { return .failure(.failed) }
        return .success(InstallerScript.tree(from: files))
    }
}
