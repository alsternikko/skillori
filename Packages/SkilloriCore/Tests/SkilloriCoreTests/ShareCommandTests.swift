import Foundation
import Testing
@testable import SkilloriCore

@Suite struct ShareCommandTests {
    private let emil = UpstreamSource(owner: "emilkowalski", repository: "skills")
    private let materic = UpstreamSource(owner: "materic-inc", repository: "plugins")

    private func skill(_ name: String, _ source: UpstreamSource, _ subpath: String?) -> SharedSkill {
        SharedSkill(name: name, source: source, subpath: subpath)
    }

    @Test func oneSkillIsAddedByItsFolder() {
        let command = ShareCommand([skill("twombly", materic, "twombly/skills/twombly")])
        #expect(command.line == "npx -y skills add materic-inc/plugins/twombly/skills/twombly -g -y")
        #expect(command.skillCount == 1)
        #expect(command.sourceCount == 1)
    }

    @Test func skillsInOneFolderArePickedByNameFromThatFolder() {
        let command = ShareCommand([skill("gestures", emil, "skills/gestures"), skill("animate", emil, "skills/animate"),
                                    skill("animate-expo", emil, "skills/animate-expo")])
        #expect(command.line == "npx -y skills add emilkowalski/skills/skills -s animate animate-expo gestures -g -y")
        #expect(command.skillCount == 3)
    }

    @Test func theSameNameInTwoFoldersIsNeverPickedByName() {
        // materic-inc/plugins holds two skills called twombly; a name alone would take the first.
        let command = ShareCommand([skill("twombly", materic, "twombly/skills/twombly"),
                                    skill("twombly", materic, "twombly-hosted/skills/twombly")])
        #expect(command.steps.map(\.address) == ["materic-inc/plugins/twombly-hosted/skills/twombly",
                                                 "materic-inc/plugins/twombly/skills/twombly"])
        #expect(command.steps.allSatisfy { $0.picked.isEmpty })
        #expect(command.sourceCount == 1)
    }

    @Test func foldersAtTheTopOfARepositoryAreNotPickedByName() {
        // Picking from the whole repository could take a skill of the same name further down.
        let command = ShareCommand([skill("a", emil, "a"), skill("b", emil, "b")])
        #expect(command.line == "npx -y skills add emilkowalski/skills/a -g -y; npx -y skills add emilkowalski/skills/b -g -y")
    }

    @Test func aRepositoryThatIsTheSkillIsAddedWhole() {
        let source = UpstreamSource(owner: "nextlevelbuilder", repository: "one-skill")
        #expect(ShareCommand([skill("one", source, nil)]).line == "npx -y skills add nextlevelbuilder/one-skill -g -y")
        #expect(ShareCommand([skill("one", source, "")]).line == "npx -y skills add nextlevelbuilder/one-skill -g -y")
    }

    @Test func aBranchIsKeptAsAFolderAddress() {
        let source = UpstreamSource(owner: "acme", repository: "skills", ref: "next")
        #expect(ShareCommand([skill("review", source, "skills/review")]).line
            == "npx -y skills add https://github.com/acme/skills/tree/next/skills/review -g -y")
        let slashed = UpstreamSource(owner: "acme", repository: "skills", ref: "feature/x")
        #expect(!ShareCommand.canCarry(skill("review", slashed, "skills/review")))
    }

    @Test func aNameWithSpacesIsPickedTheWayTheInstallerReadsIt() {
        let command = ShareCommand([skill("My Skill", emil, "skills/my-skill"), skill("animate", emil, "skills/animate")])
        #expect(command.line == "npx -y skills add emilkowalski/skills/skills -s animate my-skill -g -y")
    }

    @Test func aNameThatCannotBeWrittenFallsBackToItsFolder() {
        let command = ShareCommand([skill("it's; rm -rf ~", emil, "skills/odd"), skill("animate", emil, "skills/animate"),
                                    skill("gestures", emil, "skills/gestures")])
        #expect(command.line == "npx -y skills add emilkowalski/skills/skills -s animate gestures -g -y; "
            + "npx -y skills add emilkowalski/skills/skills/odd -g -y")
        #expect(command.skillCount == 3)
    }

    @Test func aFolderThatCannotBeWrittenIsLeftOut() {
        let hostile = [skill("x", emil, "skills/$(rm -rf ~)"), skill("y", emil, "skills/a b"), skill("z", emil, "skills/../.."),
                       skill("w", emil, "skills/-g"), skill("v", emil, "skills//x"), skill("u", emil, "skills/a\nrm")]
        #expect(hostile.allSatisfy { !ShareCommand.canCarry($0) })
        #expect(ShareCommand(hostile).isEmpty)
        #expect(ShareCommand(hostile + [skill("animate", emil, "skills/animate")]).line
            == "npx -y skills add emilkowalski/skills/skills/animate -g -y")
    }

    @Test func nothingButPlainWordsReachesTheText() {
        let odd = [skill("-rf", emil, "skills/dash"), skill("a`b", emil, "skills/tick"), skill("ok", emil, "skills/ok"),
                   skill("also ok", emil, "skills/also"), skill("$HOME", emil, "skills/home")]
        let command = ShareCommand(odd, agent: .claudeCode)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/; ")
        #expect(command.line.unicodeScalars.allSatisfy(allowed.contains))
        #expect(command.skillCount == 5)
        // A name led by a dash would be read as an option, so that skill goes by its folder.
        #expect(!command.steps.flatMap(\.picked).contains("-rf"))
    }

    @Test func oneAgentIsNamedTheWayTheInstallerNamesIt() {
        let one = [skill("twombly", materic, "twombly/skills/twombly")]
        #expect(ShareCommand(one, agent: .claudeCode).line == "npx -y skills add materic-inc/plugins/twombly/skills/twombly -g -y -a claude-code")
        #expect(ShareCommand(one, agent: .kiro).line.hasSuffix(" -a kiro-cli"))
        // No name for it at the installer: the choice is left to the installer.
        #expect(ShareCommand(one, agent: .claudeDesktop).line.hasSuffix(" -g -y"))
        #expect(ShareCommand(one, agent: .claudeDesktop).agent == nil)
    }

    @Test func sourcesAreOrderedAndASkillIsAddedOnce() {
        let command = ShareCommand([skill("twombly", materic, "twombly/skills/twombly"), skill("animate", emil, "skills/animate"),
                                    skill("animate", emil, "skills/animate")])
        #expect(command.steps.map(\.sourceName) == ["emilkowalski/skills", "materic-inc/plugins"])
        #expect(command.skillCount == 2)
        #expect(command.counts == "2 skills from 2 GitHub repositories")
    }

    @Test func theRequestToAnAgentCarriesTheSameLine() {
        let command = ShareCommand([skill("animate", emil, "skills/animate")], agent: .cursor)
        #expect(command.prompt.contains("\n\n" + command.line + "\n\n"))
        #expect(command.prompt.contains("1 skill from 1 GitHub repository"))
        #expect(command.prompt.contains("for Cursor"))
    }

    @Test func theScriptAddsEachSourceWithItsInputClosed() {
        let command = ShareCommand([skill("animate", emil, "skills/animate"), skill("gestures", emil, "skills/gestures"),
                                    skill("twombly", materic, "twombly/skills/twombly")], agent: .claudeCode)
        let script = command.script
        #expect(script.hasPrefix("#!/bin/sh\n"))
        #expect(script.contains("\nadd emilkowalski/skills/skills -s animate gestures\nadd materic-inc/plugins/twombly/skills/twombly\n"))
        #expect(script.contains("npx -y skills add \"$@\" -g -y -a claude-code </dev/null"))
        #expect(script.contains("for Claude Code."))
        #expect(script.hasSuffix("echo \"Added everything.\"\n"))
    }
}
