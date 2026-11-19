import Foundation

/// Hands a skill the reader linked by hand over to the installer: `npx skills add` from its
/// source, for the agents whose folders hold the copies. The installer then puts the source's
/// version in their place and records it, so the next update is an ordinary `npx skills update`.
///
/// Only folders the installer itself writes take part. A copy anywhere else, or a folder that
/// another skill already has under the name the installer would use, means no plan: the
/// installer would leave that copy behind or write over the other skill.
public struct Adoption: Sendable, Equatable {
    public let source: UpstreamSource
    /// The skill's name, as the installer looks it up in the source.
    public let skill: String
    /// The folder name the installer gives the skill.
    public let folderName: String
    /// The installer's agents, one for each folder that holds a copy.
    public let agents: [String]
    /// Folders under another name than the installer's, which it does not write over. They go to
    /// the Trash once the installer has put the skill in place beside them.
    public let leftovers: [String]

    /// The installer's agent for each personal skills folder it writes, relative to home. From
    /// the `npx skills` agent table (`globalSkillsDir`), checked in version 1.7.6.
    public static let agentForFolder: [String: String] = [
        ".agents/skills": "codex",
        ".claude/skills": "claude-code",
        ".cursor/skills": "cursor",
        ".gemini/skills": "gemini-cli",
        ".gemini/antigravity/skills": "antigravity",
        ".gemini/antigravity-cli/skills": "antigravity-cli",
        ".copilot/skills": "github-copilot",
        ".config/opencode/skills": "opencode",
        ".config/agents/skills": "amp",
        ".config/goose/skills": "goose",
        ".config/devin/skills": "devin",
        ".config/crush/skills": "crush",
        ".factory/skills": "droid",
        ".kiro/skills": "kiro-cli",
        ".roo/skills": "roo",
        ".kilo/skills": "kilo",
        ".junie/skills": "junie",
        ".augment/skills": "augment",
    ]

    /// - Parameters:
    ///   - skill: the skill's name in its SKILL.md, which is the one the installer looks up.
    ///   - folders: every folder that holds a copy, as found in a skills folder and as resolved.
    ///   - home: the home folder the skills folders are under.
    ///   - taken: folders that belong to other skills.
    public static func plan(skill: String, source: UpstreamSource, folders: [String], home: String,
                            taken: Set<String>) -> Adoption? {
        guard source.ref == nil, isPlain(source.owner), isPlain(source.repository), isPlain(skill),
              !folders.isEmpty else { return nil }
        let folderName = installName(skill)
        // Paths are compared with their folders' symlinks resolved, the skill folder itself left
        // as it is: a copy that is a link into another skills folder still belongs to its own.
        let base = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        let taken = Set(taken.map(settled))
        // With more than one agent the installer keeps its own copy in `.agents/skills`.
        if taken.contains(base + "/.agents/skills/" + folderName) { return nil }
        var agents: [String] = []
        var leftovers: [String] = []
        for folder in Set(folders.map(settled)).sorted() {
            let url = URL(fileURLWithPath: folder)
            let parent = url.deletingLastPathComponent().path
            guard parent.hasPrefix(base + "/"),
                  let agent = agentForFolder[String(parent.dropFirst(base.count + 1))] else { return nil }
            // The installer writes this name in every folder it serves; another skill must not have it.
            if taken.contains(parent + "/" + folderName) { return nil }
            if !agents.contains(agent) { agents.append(agent) }
            if url.lastPathComponent != folderName { leftovers.append(folder) }
        }
        return Adoption(source: source, skill: skill, folderName: folderName, agents: agents.sorted(), leftovers: leftovers)
    }

    /// One `add` per source and set of agents: the installer takes several skills at once.
    public static func commands(for adoptions: [Adoption], package: String) -> [(arguments: [String], adoptions: [Adoption])] {
        var order: [String] = []
        var groups: [String: [Adoption]] = [:]
        for adoption in adoptions {
            let key = adoption.source.name + " " + adoption.agents.joined(separator: ",")
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(adoption)
        }
        return order.map { key in
            let group = groups[key]!
            var skills: [String] = []
            for adoption in group where !skills.contains(adoption.skill) { skills.append(adoption.skill) }
            let arguments = ["--yes", package, "add", group[0].source.name, "-s"] + skills
                + ["-a"] + group[0].agents + ["-g", "-y"]
            return (arguments, group)
        }
    }

    /// The folder name `npx skills` gives a skill: its name in lower case, with anything but
    /// letters, digits, dots and underscores turned into dashes (its `sanitizeName`).
    public static func installName(_ name: String) -> String {
        var out = ""
        var dash = false
        for character in name.lowercased() {
            if character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "_") {
                if dash { out.append("-"); dash = false }
                out.append(character)
            } else {
                dash = true
            }
        }
        if dash { out.append("-") }
        while let first = out.first, first == "." || first == "-" { out.removeFirst() }
        while let last = out.last, last == "." || last == "-" { out.removeLast() }
        return out.isEmpty ? "unnamed-skill" : String(out.prefix(255))
    }

    /// The path with the folders above it resolved (`/private/tmp` and `/tmp` are one place),
    /// and its last part kept as it is.
    static func settled(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
    }

    /// A name that can be handed to the installer as an argument of its own.
    static func isPlain(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("-") && name != "." && name != ".."
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }
}
