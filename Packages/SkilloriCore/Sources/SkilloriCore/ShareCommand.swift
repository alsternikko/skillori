import Foundation

/// A skill to pass on to someone else: the name the installer knows it by, and where it lives.
public struct SharedSkill: Hashable, Sendable {
    /// The name in the skill's `SKILL.md`, or its folder's name when it has none.
    public let name: String
    public let source: UpstreamSource
    /// The skill's folder in the repository. Nil when the repository itself is the skill.
    public let subpath: String?

    public init(name: String, source: UpstreamSource, subpath: String?) {
        self.name = name
        self.source = source
        self.subpath = subpath?.isEmpty == false ? subpath : nil
    }
}

/// What adds a set of skills from their sources on someone else's computer, with the skills
/// installer (`npx skills`): as one line for a terminal, as a request to a coding agent, and as a
/// script file. Whoever gets it needs Node.js and nothing else.
///
/// The text is pasted into shells and chats by people who did not write it, so it is built only
/// from repository names, folder names and skill names made of letters, digits, `.`, `_` and `-`.
/// A skill that would need anything else is left out, and nothing a skill says about itself,
/// such as its description, is ever put in.
public struct ShareCommand: Equatable, Sendable {
    /// One run of the installer: a repository or a folder in it, and the skills taken from it.
    public struct Step: Equatable, Sendable {
        /// What the installer is pointed at: `owner/repo`, `owner/repo/folder`, or the address of
        /// a folder on a branch when the source names one.
        public let address: String
        /// The skills picked by name with `-s`. Empty when the address is the skill's own folder.
        public let picked: [String]
        /// The skills this step adds, for a person to read.
        public let labels: [String]
        /// `owner/repo`
        public let sourceName: String
    }

    public let steps: [Step]
    /// The one agent the skills are installed for. Nil leaves it to the installer, which takes
    /// the agents it finds on the computer.
    public let agent: Agent?

    public var skillCount: Int { steps.reduce(0) { $0 + $1.labels.count } }
    public var sourceCount: Int { Set(steps.map { $0.sourceName.lowercased() }).count }
    public var isEmpty: Bool { steps.isEmpty }

    /// Skills that can't be written safely are dropped: ask `canCarry` first to tell the reader.
    /// An agent the installer has no name for is dropped too, which leaves the choice to it.
    public init(_ skills: [SharedSkill], agent: Agent? = nil) {
        self.agent = agent.flatMap { Self.installerID(for: $0) == nil ? nil : $0 }
        var seen: Set<String> = []
        var groups: [String: [SharedSkill]] = [:]
        var order: [String] = []
        for skill in skills where Self.canCarry(skill) {
            let place = Self.address(skill.source, folder: skill.subpath).lowercased()
            guard seen.insert(place).inserted else { continue }
            let key = Self.address(skill.source, folder: Self.parent(of: skill.subpath)).lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(skill)
        }
        var steps: [Step] = []
        for key in order {
            let group = groups[key] ?? []
            // Picking by name is only safe among the folders of one folder: the installer takes
            // the first skill it finds with a name, and a repository can hold the name twice.
            var pickable: [(skill: SharedSkill, token: String)] = []
            if group.count > 1, let folder = Self.parent(of: group[0].subpath), !folder.isEmpty {
                let tokens = group.map { Self.token(for: $0.name) }
                let counts = Dictionary(tokens.compactMap { $0?.lowercased() }.map { ($0, 1) }, uniquingKeysWith: +)
                for (skill, token) in zip(group, tokens) {
                    if let token, counts[token.lowercased()] == 1 { pickable.append((skill, token)) }
                }
                if pickable.count < 2 { pickable = [] }
            }
            if !pickable.isEmpty {
                let names = pickable.map(\.token).sorted { $0.lowercased() < $1.lowercased() }
                steps.append(Step(address: Self.address(group[0].source, folder: Self.parent(of: group[0].subpath)),
                                  picked: names, labels: names, sourceName: group[0].source.name))
            }
            for skill in group where !pickable.contains(where: { $0.skill == skill }) {
                let label = skill.subpath.map { ($0 as NSString).lastPathComponent } ?? skill.source.repository
                steps.append(Step(address: Self.address(skill.source, folder: skill.subpath), picked: [],
                                  labels: [label], sourceName: skill.source.name))
            }
        }
        self.steps = steps.sorted {
            ($0.sourceName.lowercased(), $0.address.lowercased()) < ($1.sourceName.lowercased(), $1.address.lowercased())
        }
    }

    /// Whether the skill's source and folder can be written in a command as they are.
    public static func canCarry(_ skill: SharedSkill) -> Bool {
        guard isWord(skill.source.owner), isWord(skill.source.repository) else { return false }
        // A branch with a slash in its name can't be told from a folder in an address.
        if let ref = skill.source.ref, !isWord(ref) { return false }
        guard let subpath = skill.subpath else { return true }
        let parts = subpath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return parts.allSatisfy(isWord)
    }

    /// The name the skills installer has for an agent Skillori knows, for its `-a`. Nil when it
    /// has none, or when the two have not been matched against the installer's own list.
    public static func installerID(for agent: Agent) -> String? {
        switch agent {
        case .claudeCode, .cursor, .codex, .geminiCLI, .antigravity, .copilot, .openCode, .amp, .droid, .goose: agent.id
        case .kiro: "kiro-cli"
        default: nil
        }
    }

    // MARK: The three forms

    /// The whole thing on one line, for a terminal. A shell reads a line to its end before it
    /// runs any of it, so nothing the installer reads can swallow what follows, which is what
    /// happens to commands pasted as several lines. `;` and not `&&`: one source that fails
    /// should not stop the rest, and older PowerShell has no `&&`.
    public var line: String {
        steps.map { "npx -y skills add " + arguments(for: $0).joined(separator: " ") + " -g -y" + agentFlag }
            .joined(separator: "; ")
    }

    /// The same line with a request around it, for a coding agent that has a terminal. It asks
    /// for a report, which the bare line can't give, and for nothing to be fetched from elsewhere.
    public var prompt: String {
        """
        Please add these agent skills for me. Run this in the terminal, exactly as written:

        \(line)

        It adds \(counts) with the skills installer (npx skills)\(agent.map { ", for \($0.displayName)" } ?? ""). \
        When it is done, tell me which skills were added and which were not. \
        If one fails, leave it and tell me. Do not fetch it from anywhere else.
        """
    }

    /// A script that adds one source at a time, goes on when one fails, and says at the end which
    /// did. Each run of the installer has its input closed, so the script also works when it is
    /// fed to a shell line by line.
    public var script: String {
        var lines = [
            "#!/bin/sh",
            "# \(counts). Made with Skillori, https://skillori.app",
            "#",
            "# Run it:   sh skills.sh",
            "# Or give this file to a coding agent and ask it to run it.",
            "#",
            "# Each line at the end adds skills from their source on GitHub with the skills",
            "# installer (npx skills), for \(agent?.displayName ?? "the agents it finds on this computer").",
            "# It needs Node.js.",
            "",
            "if ! command -v npx >/dev/null 2>&1; then",
            "  echo \"This needs Node.js, which brings npx: https://nodejs.org\"",
            "  exit 1",
            "fi",
            "",
            "failed=\"\"",
            "add() {",
            "  echo \"Adding from $1\"",
            "  npx -y skills add \"$@\" -g -y\(agentFlag) </dev/null || failed=\"$failed",
            "  $1\"",
            "}",
            "",
        ]
        for step in steps {
            lines.append("add " + arguments(for: step).joined(separator: " "))
        }
        lines += [
            "",
            "if [ -n \"$failed\" ]; then",
            "  echo",
            "  echo \"Could not add from:$failed\"",
            "  exit 1",
            "fi",
            "echo",
            "echo \"Added everything.\"",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    /// "25 skills from 7 GitHub repositories"
    public var counts: String {
        "\(skillCount) skill\(skillCount == 1 ? "" : "s") from \(sourceCount) GitHub repositor\(sourceCount == 1 ? "y" : "ies")"
    }

    private func arguments(for step: Step) -> [String] {
        [step.address] + (step.picked.isEmpty ? [] : ["-s"] + step.picked)
    }

    private var agentFlag: String {
        agent.flatMap(Self.installerID(for:)).map { " -a " + $0 } ?? ""
    }

    // MARK: Words

    /// Letters, digits, `.`, `_` and `-`, not led by a dash: nothing a shell or a chat app reads
    /// as anything but itself, and nothing the installer could take for an option.
    private static func isWord(_ text: String) -> Bool {
        !text.isEmpty && text != "." && text != ".." && !text.hasPrefix("-")
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }

    /// The word to pick a skill by. The installer matches names without regard to case, and
    /// reads spaces and underscores as dashes, so "My Skill" is picked as `my-skill`.
    private static func token(for name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        if isWord(name) { return name }
        let dashed = name.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "_" }).joined(separator: "-")
        return isWord(dashed) ? dashed : nil
    }

    private static func parent(of subpath: String?) -> String? {
        guard let subpath else { return nil }
        let folder = (subpath as NSString).deletingLastPathComponent
        return folder.isEmpty ? "" : folder
    }

    private static func address(_ source: UpstreamSource, folder: String?) -> String {
        let folder = folder?.isEmpty == false ? "/" + folder! : ""
        if let ref = source.ref { return "https://github.com/\(source.name)/tree/\(ref)\(folder)" }
        return source.name + folder
    }
}
