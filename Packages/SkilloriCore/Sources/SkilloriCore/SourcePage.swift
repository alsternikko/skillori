import Foundation

/// One way to install skills that a web page names: a command shown on it, or a repository it
/// links to. Followed, it is read like anything the reader pastes.
public struct PageLead: Sendable, Hashable, Identifiable {
    public let source: SkillSource
    /// The folder the command or address names in the repository, if it names one.
    public let subpath: String?
    /// The skill a command picks by name (`--skill animate`), if it picks one.
    public let skill: String?
    /// What the page shows, as a person would read it. An installer's key, or anything after
    /// the package, is never part of it.
    public let line: String

    public var id: String { source.name + "#" + (subpath ?? "") + "#" + (skill ?? "") }

    /// What Link source reads to follow this lead.
    public var text: String {
        switch source {
        case .github(let repository):
            repository.name + (subpath.map { "/" + $0 } ?? "")
        case .installer(let script): script.url.absoluteString
        case .package(let installer): installer.command
        }
    }
}

/// Reads a web page as text for the ways it names to install skills: `npx skills add …`,
/// `curl … | bash`, an installer package (`npx @site/install`), and links to GitHub
/// repositories. Nothing on the page is run, and nothing is sent but the request for it.
public enum SourcePage {
    /// The largest page read.
    public static let maxBytes = 4 * 1024 * 1024

    /// Commands first, as they say how the skills are installed. Repository links only when the
    /// page shows no command, since every page links to repositories that are not the skill's.
    public static func leads(in html: String) -> [PageLead] {
        let text = flatten(html)
        var found: [PageLead] = []
        func add(_ lead: PageLead) { if !found.contains(where: { $0.id == lead.id }) { found.append(lead) } }
        for lead in commands(in: text) { add(lead) }
        if found.isEmpty {
            // Links live in the tags' attributes, so they are read before the tags go.
            for lead in repositoryLinks(in: flatten(html, keepingTags: true)).prefix(6) { add(lead) }
        }
        return Array(found.prefix(8))
    }

    /// The page as plain text: tags out, entities and the escapes of embedded data undone, so
    /// commands inside highlighted code or in a script's data read as one line.
    static func flatten(_ html: String, keepingTags: Bool = false) -> String {
        var text = keepingTags ? html : html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        for (escaped, plain) in [("\\u002F", "/"), ("\\u002f", "/"), ("\\/", "/"), ("\\u0026", "&"), ("\\u003c", "<"),
                                 ("\\u003e", ">"), ("\\\"", "\""), ("\\n", " "),
                                 ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&#x2F;", "/"), ("&#47;", "/"),
                                 ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&#160;", " "), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: escaped, with: plain)
        }
        return text
    }

    /// Characters a command's word may end with in running text, which are not part of it.
    private static let trailing = CharacterSet(charactersIn: ".,;:!?)]}\"'`")

    private static func word(_ token: Substring) -> String {
        String(token).trimmingCharacters(in: trailing)
    }

    static func commands(in text: String) -> [PageLead] {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        var leads: [PageLead] = []
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            let first = word(tokens[index])
            var next = index + 1
            if first == "curl" {
                if let lead = script(after: next, in: tokens) { leads.append(lead) }
                continue
            }
            let runner: String
            switch first {
            case "npx", "bunx": runner = first
            case "pnpm", "yarn":
                guard next < tokens.count, word(tokens[next]) == "dlx" else { continue }
                runner = first + " dlx"
                next += 1
            default: continue
            }
            while next < tokens.count, tokens[next].hasPrefix("-") { next += 1 }
            guard next < tokens.count, let package = PackageInstaller.packageName(from: word(tokens[next])) else { continue }
            next += 1
            if package == "skills" || package == "add-skill" {
                // `npx skills add <source> [--skill name]`; `npx add-skill <source>`.
                if package == "skills" {
                    guard next < tokens.count, word(tokens[next]) == "add" else { continue }
                    next += 1
                }
                guard next < tokens.count else { continue }
                let argument = word(tokens[next])
                // Pages show the form as `owner/repo` too; that is not a repository.
                guard let (repository, subpath) = UpstreamSource.parse(argument),
                      repository.owner.lowercased() != "owner" else { continue }
                var skill: String?
                for look in (next + 1)..<min(next + 4, tokens.count) where ["--skill", "-s"].contains(word(tokens[look])) {
                    if look + 1 < tokens.count { skill = word(tokens[look + 1]) }
                    break
                }
                let line = "\(runner) \(package) \(package == "skills" ? "add " : "")\(argument)" + (skill.map { " --skill \($0)" } ?? "")
                leads.append(PageLead(source: .github(repository), subpath: subpath, skill: skill, line: line))
            } else if package.contains("install"), let installer = PackageInstaller("npx " + package) {
                // An installer of the site's own; whatever follows it, such as a key, is left out.
                leads.append(PageLead(source: .package(installer), subpath: nil, skill: nil, line: "\(runner) \(package)"))
            }
        }
        return leads
    }

    /// `curl … https://site/install | bash`: an install script, never run.
    private static func script(after start: Int, in tokens: [Substring]) -> PageLead? {
        var index = start
        while index < min(start + 6, tokens.count) {
            let token = word(tokens[index])
            if token.lowercased().hasPrefix("https://"), let source = InstallerSource(token) {
                let rest = tokens[(index + 1)..<min(index + 4, tokens.count)].map(word)
                guard let pipe = rest.firstIndex(of: "|"), pipe + 1 < rest.count,
                      ["bash", "sh", "zsh"].contains(rest[pipe + 1]) else { return nil }
                return PageLead(source: .installer(source), subpath: nil, skill: nil, line: source.installCommand)
            }
            index += 1
        }
        return nil
    }

    /// GitHub's own pages, which share the shape of a repository's address.
    private static let notOwners: Set<String> = ["about", "apps", "collections", "enterprise", "features", "login", "marketplace",
                                                 "orgs", "pricing", "settings", "site", "sponsors", "topics", "join", "signup"]

    static func repositoryLinks(in text: String) -> [PageLead] {
        let pattern = #"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/(?:tree|blob)/[^\s"'<>()]+)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var leads: [PageLead] = []
        for match in expression.matches(in: text, range: range) {
            guard let found = Range(match.range, in: text) else { continue }
            var address = String(text[found]).trimmingCharacters(in: trailing)
            if address.hasSuffix(".git") { address.removeLast(4) }
            guard let (repository, subpath) = UpstreamSource.parse(address),
                  !notOwners.contains(repository.owner.lowercased()) else { continue }
            let lead = PageLead(source: .github(repository), subpath: subpath, skill: nil,
                                line: "github.com/" + repository.name + (subpath.map { "/" + $0 } ?? ""))
            if !leads.contains(where: { $0.id == lead.id }) { leads.append(lead) }
        }
        // A repository named for skills first; the order on the page otherwise.
        let named = leads.filter { $0.source.name.lowercased().contains("skill") }
        return named + leads.filter { !$0.source.name.lowercased().contains("skill") }
    }
}

/// Fetches a page the reader named, as text. No cookies are sent or kept, so a page that needs
/// the reader signed in shows what anyone sees.
public struct PageReader: Sendable {
    public typealias Transport = GitHubTrees.Transport
    private let transport: Transport

    public init(transport: @escaping Transport = InstallerScripts.network) {
        self.transport = transport
    }

    public static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("text/html, text/plain;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("Skillori", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    public func leads(at url: URL) async -> Result<[PageLead], UpstreamState.Reason> {
        guard url.scheme?.lowercased() == "https" else { return .failure(.failed) }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(Self.request(for: url))
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch let error as URLError where error.code == .cancelled {
            return .failure(.cancelled)
        } catch {
            return .failure(.offline)
        }
        if let final = response.url, final.scheme?.lowercased() != "https" { return .failure(.failed) }
        switch response.statusCode {
        case 200: break
        case 404, 410: return .failure(.notFound)
        case 429: return .failure(.rateLimited)
        default: return .failure(.failed)
        }
        guard data.count <= SourcePage.maxBytes,
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return .failure(.failed) }
        return .success(SourcePage.leads(in: html))
    }
}
