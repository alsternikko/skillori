import Foundation

/// Reads the global lock file that `npx skills` (vercel-labs/skills) writes.
///
/// Observed at `~/.agents/.skill-lock.json` with `version: 3`; newer releases may honour
/// `$XDG_STATE_HOME/skills/.skill-lock.json`. Unknown fields are ignored and every field is
/// optional so that schema drift degrades to "Source unknown" instead of failing.
public struct SkillsLockFile: Sendable {
    public struct Entry: Sendable, Decodable, Equatable {
        public var source: String?
        public var sourceType: String?
        public var sourceUrl: String?
        public var ref: String?
        public var skillPath: String?
        public var skillFolderHash: String?
        public var installedAt: String?
        public var updatedAt: String?

        /// Directory of the skill inside the source repository, e.g. `skills/animate`.
        public var repositorySubpath: String? {
            guard let skillPath else { return nil }
            let dir = (skillPath as NSString).deletingLastPathComponent
            return dir.isEmpty ? nil : dir
        }
    }

    private struct Raw: Decodable {
        var version: Int?
        var skills: [String: Entry]?
    }

    public let url: URL
    public let version: Int?
    public let skills: [String: Entry]

    public static func load(from url: URL) throws -> SkillsLockFile {
        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        return SkillsLockFile(url: url, version: raw.version, skills: raw.skills ?? [:])
    }

    public static func defaultLocations(home: URL, environment: [String: String]) -> [URL] {
        var urls: [URL] = []
        if let state = environment["XDG_STATE_HOME"], !state.isEmpty {
            urls.append(URL(fileURLWithPath: state).appendingPathComponent("skills/.skill-lock.json"))
        }
        urls.append(home.appendingPathComponent(".agents/.skill-lock.json"))
        return urls
    }
}
