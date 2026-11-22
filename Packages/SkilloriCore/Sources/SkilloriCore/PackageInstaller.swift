import Foundation

/// A skill its author hands out through an installer published as an npm package, run with the
/// reader's own key: `npx @interfacecraft/install@latest --token=…`. The installer fetches the
/// files from the author's site with that key, so nobody without it can read them. Skillori
/// keeps only the package's name. Everything after it on the pasted line, the key included, is
/// dropped as it is read and never kept or sent anywhere.
public struct PackageInstaller: Hashable, Sendable {
    /// The package, without a version: `@interfacecraft/install`.
    public let package: String
    /// The author's site, as the package names it, when it names one.
    public let site: URL?

    public init(package: String, site: URL? = nil) {
        self.package = package
        self.site = site
    }

    /// Reads a pasted install command (`npx`, `bunx`, `pnpm dlx` or `yarn dlx`, then the package
    /// and whatever follows), or a bare scoped package name. Nil for anything else, and for the
    /// `skills` CLI, whose sources are repositories and read as such.
    public init?(_ text: String) {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return nil }
        let spec: String
        if first.hasPrefix("@"), words.count == 1 {
            spec = first
        } else {
            var rest = words[...]
            switch rest.popFirst() {
            case "npx", "bunx": break
            case "pnpm", "yarn":
                guard rest.popFirst() == "dlx" else { return nil }
            default: return nil
            }
            // Flags before the package, such as `-y`. A flag that takes a value is not expected here.
            while let next = rest.first, next.hasPrefix("-") { rest.removeFirst() }
            guard let word = rest.first else { return nil }
            spec = word
        }
        guard let name = Self.packageName(from: spec), !Self.notInstallers.contains(name) else { return nil }
        self.init(package: name)
    }

    /// Packages that install from repositories, which Skillori reads as repositories instead.
    private static let notInstallers: Set<String> = ["skills", "add-skill"]

    /// `@scope/name@1.2.3` → `@scope/name`, after checking it is a valid npm name.
    static func packageName(from spec: String) -> String? {
        var text = spec.lowercased()
        if text.hasPrefix("@") {
            let body = text.dropFirst()
            if let at = body.firstIndex(of: "@") { text = "@" + body[..<at] }
            let parts = text.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, parts.allSatisfy(isPart) else { return nil }
        } else {
            if let at = text.firstIndex(of: "@") { text = String(text[..<at]) }
            guard isPart(Substring(text)) else { return nil }
        }
        return text.count <= 214 ? text : nil
    }

    private static func isPart(_ part: Substring) -> Bool {
        guard let first = part.first, first != ".", first != "_" else { return false }
        return part.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || "-._~".contains($0)) }
    }

    /// The author's site without its scheme when the package names one, else the package.
    public var name: String {
        guard let host = site?.host else { return package }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The package's page on npm.
    public var packageURL: URL {
        URL(string: "https://www.npmjs.com/package/\(package)")!
    }

    /// The command without its key, for saying which installer it is. It needs the reader's own
    /// key to run, which only the author's site gives them.
    public var command: String { "npx \(package)@latest" }
}

/// What npm says about an installer's package: that it exists, and the site it names.
public struct PackageInfo: Sendable, Equatable {
    public let package: String
    public let version: String?
    public let summary: String?
    public let site: URL?

    public init(package: String, version: String?, summary: String?, site: URL?) {
        self.package = package
        self.version = version
        self.summary = summary
        self.site = site
    }

    public var installer: PackageInstaller { PackageInstaller(package: package, site: site) }
}

/// Asks the public npm registry about a package. Only the package's name is sent.
public struct NpmRegistry: Sendable {
    public typealias Transport = GitHubTrees.Transport
    private let transport: Transport

    public init(transport: @escaping Transport = InstallerScripts.network) {
        self.transport = transport
    }

    public static func request(for package: String) -> URLRequest {
        // A scoped name keeps its `@` and has its `/` encoded, as the registry wants it.
        let path = package.replacingOccurrences(of: "/", with: "%2F")
        var request = URLRequest(url: URL(string: "https://registry.npmjs.org/\(path)/latest")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Skillori", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    public func info(for package: String) async -> Result<PackageInfo, UpstreamState.Reason> {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(Self.request(for: package))
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
        case 429: return .failure(.rateLimited)
        default: return .failure(.failed)
        }
        struct Latest: Decodable {
            let name: String
            let version: String?
            let description: String?
            let homepage: String?
        }
        guard let latest = try? JSONDecoder().decode(Latest.self, from: data), latest.name == package else {
            return .failure(.failed)
        }
        // Only an https page is offered to open; anything else is left out rather than mended.
        let site = latest.homepage.flatMap(URL.init(string:)).flatMap { url -> URL? in
            guard url.scheme?.lowercased() == "https", url.host?.contains(".") == true, url.user == nil else { return nil }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            return components?.url
        }
        return .success(PackageInfo(package: latest.name, version: latest.version, summary: latest.description, site: site))
    }
}
