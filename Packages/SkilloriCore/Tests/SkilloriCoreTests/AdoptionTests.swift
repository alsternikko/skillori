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

    @Test func folderNamesFollowTheInstaller() {
        #expect(Adoption.installName("Frontend-Design") == "frontend-design")
        #expect(Adoption.installName("my skill!") == "my-skill")
        #expect(Adoption.installName("--x--") == "x")
        #expect(Adoption.installName("") == "unnamed-skill")
    }
}
