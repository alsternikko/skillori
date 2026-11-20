import Foundation
import Testing
@testable import SkilloriCore

@Suite struct AdoptionTests {
    private let home = "/Users/someone"
    private let anthropic = UpstreamSource(owner: "anthropics", repository: "skills")

    @Test func copiesInClaudeAndSharedFoldersGoToBothAgents() throws {
        let plan = try #require(Adoption.plan(skill: "frontend-design", source: anthropic,
                                              folders: ["\(home)/.claude/skills/frontend-design", "\(home)/.agents/skills/frontend-design"],
                                              home: home, taken: []))
        #expect(plan.agents == ["claude-code", "codex"])
        #expect(plan.folderName == "frontend-design")
        #expect(plan.leftovers.isEmpty)
    }

    @Test func aFolderUnderAnotherNameIsLeftOverForTheTrash() throws {
        let plan = try #require(Adoption.plan(skill: "pptx", source: anthropic,
                                              folders: ["\(home)/.claude/skills/pptx-official", "\(home)/.agents/skills/pptx-official"],
                                              home: home, taken: []))
        #expect(plan.folderName == "pptx")
        #expect(plan.leftovers == ["\(home)/.agents/skills/pptx-official", "\(home)/.claude/skills/pptx-official"])
    }

    @Test func aFolderTheInstallerDoesNotWriteMeansNoPlan() {
        #expect(Adoption.plan(skill: "x", source: anthropic, folders: ["\(home)/.codex/skills/x"], home: home, taken: []) == nil)
        #expect(Adoption.plan(skill: "x", source: anthropic, folders: ["\(home)/dev/skills/x"], home: home, taken: []) == nil)
    }

    @Test func anotherSkillWithTheNameMeansNoPlan() {
        // The installer would write over the pptx that is already there.
        #expect(Adoption.plan(skill: "pptx", source: anthropic, folders: ["\(home)/.claude/skills/pptx-official"],
                              home: home, taken: ["\(home)/.claude/skills/pptx"]) == nil)
        // And over its own copy in the shared folder.
        #expect(Adoption.plan(skill: "pptx", source: anthropic, folders: ["\(home)/.claude/skills/pptx-official"],
                              home: home, taken: ["\(home)/.agents/skills/pptx"]) == nil)
    }

    @Test func namesThatCannotBeArgumentsAndPinnedSourcesMeanNoPlan() {
        let folders = ["\(home)/.claude/skills/x"]
        #expect(Adoption.plan(skill: "-rf", source: anthropic, folders: folders, home: home, taken: []) == nil)
        #expect(Adoption.plan(skill: "two words", source: anthropic, folders: folders, home: home, taken: []) == nil)
        #expect(Adoption.plan(skill: "x", source: UpstreamSource(owner: "a", repository: "b", ref: "main"),
                              folders: folders, home: home, taken: []) == nil)
    }

    @Test func oneAddPerSourceAndAgents() throws {
        let a = try #require(Adoption.plan(skill: "pptx", source: anthropic, folders: ["\(home)/.claude/skills/pptx-official", "\(home)/.agents/skills/pptx-official"], home: home, taken: []))
        let b = try #require(Adoption.plan(skill: "frontend-design", source: anthropic, folders: ["\(home)/.claude/skills/frontend-design", "\(home)/.agents/skills/frontend-design"], home: home, taken: []))
        let c = try #require(Adoption.plan(skill: "refactor", source: UpstreamSource(owner: "someone", repository: "awesome"), folders: ["\(home)/.claude/skills/refactor"], home: home, taken: []))
        let commands = Adoption.commands(for: [a, b, c], package: "skills@1.7.6")
        #expect(commands.count == 2)
        #expect(commands[0].arguments == ["--yes", "skills@1.7.6", "add", "anthropics/skills", "-s", "pptx", "frontend-design",
                                          "-a", "claude-code", "codex", "-g", "-y"])
        #expect(commands[1].arguments == ["--yes", "skills@1.7.6", "add", "someone/awesome", "-s", "refactor", "-a", "claude-code", "-g", "-y"])
    }

    @Test func aKnownFolderIsNamedInsteadOfTheSkill() throws {
        // materic-inc/plugins has two skills called twombly; `-s twombly` installed the wrong one.
        let plugins = UpstreamSource(owner: "materic-inc", repository: "plugins")
        let folders = ["\(home)/.agents/skills/twombly", "\(home)/.claude/skills/twombly"]
        let plan = try #require(Adoption.plan(skill: "twombly", source: plugins, folders: folders, home: home, taken: [],
                                              subpath: "twombly/skills/twombly"))
        let other = try #require(Adoption.plan(skill: "pptx", source: anthropic, folders: ["\(home)/.claude/skills/pptx"], home: home, taken: []))
        let commands = Adoption.commands(for: [plan, other], package: "skills@1.7.6")
        #expect(commands.count == 2)
        #expect(commands[0].arguments == ["--yes", "skills@1.7.6", "add", "materic-inc/plugins/twombly/skills/twombly",
                                          "-a", "claude-code", "codex", "-g", "-y"])
        #expect(commands[1].arguments == ["--yes", "skills@1.7.6", "add", "anthropics/skills", "-s", "pptx", "-a", "claude-code", "-g", "-y"])
        // A branch goes with the folder, as a tree address.
        let main = UpstreamSource(owner: "materic-inc", repository: "plugins", ref: "main")
        let pinned = try #require(Adoption.plan(skill: "twombly", source: main, folders: folders, home: home, taken: [],
                                                subpath: "twombly/skills/twombly"))
        #expect(Adoption.commands(for: [pinned], package: "skills@1.7.6")[0].arguments
                == ["--yes", "skills@1.7.6", "add", "https://github.com/materic-inc/plugins/tree/main/twombly/skills/twombly",
                    "-a", "claude-code", "codex", "-g", "-y"])
        // A link elsewhere into the skill's own folder is left to follow it; one in a folder the
        // installer writes adds its agent.
        let linked = try #require(Adoption.plan(skill: "twombly", source: plugins, folders: ["\(home)/.agents/skills/twombly"],
                                                home: home, taken: [], subpath: "twombly/skills/twombly",
                                                links: ["\(home)/.gemini/config/skills/twombly", "\(home)/.claude/skills/twombly"]))
        #expect(linked.agents == ["claude-code", "codex"])
        // A folder that could not be an argument falls back to the name.
        let odd = try #require(Adoption.plan(skill: "twombly", source: plugins, folders: folders, home: home, taken: [],
                                             subpath: "a b/-rf"))
        #expect(odd.subpath == nil)
    }

    @Test func aHomeBehindASymlinkStillMatches() throws {
        // `/tmp` is a link to `/private/tmp`; Foundation hands out either spelling.
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("adoption-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent(".claude/skills"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let resolved = base.resolvingSymlinksInPath().path
        let other = resolved.hasPrefix("/private/") ? String(resolved.dropFirst("/private".count)) : "/private" + resolved
        let plan = Adoption.plan(skill: "x", source: anthropic, folders: [resolved + "/.claude/skills/x"], home: other, taken: [])
        #expect(plan?.agents == ["claude-code"])
    }

    @Test func folderNamesFollowTheInstaller() {
        #expect(Adoption.installName("Frontend-Design") == "frontend-design")
        #expect(Adoption.installName("my skill!") == "my-skill")
        #expect(Adoption.installName("--x--") == "x")
        #expect(Adoption.installName("") == "unnamed-skill")
    }
}
