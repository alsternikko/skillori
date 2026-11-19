import Foundation
import Testing
@testable import SkilloriCore

@Suite struct SourceFinderTests {
    private static func blob(_ text: String) -> String { GitTreeHash.objectID(type: "blob", body: Data(text.utf8)).hex }

    private static func skill(_ name: String, _ text: String) -> LocalSkill {
        let id = blob(text)
        let tree = GitTreeHash.treeID(of: [(mode: "100644", name: "SKILL.md", id: id)])!
        return LocalSkill(name: name, treeID: tree,
                          entries: [GitTreeHash.Entry(path: "SKILL.md", kind: .file, size: text.utf8.count, objectID: id)],
                          skillFile: Data(text.utf8))
    }

    /// A GitHub listing with one folder holding the given files.
    private static func listing(_ folder: String, _ files: [String: String]) -> String {
        let blobs = files.map { #"{"path":"\#(folder)/\#($0.key)","type":"blob","sha":"\#(blob($0.value))","mode":"100644"}"# }
        let entries = files.map { (mode: "100644", name: $0.key, id: blob($0.value)) }
        let tree = GitTreeHash.treeID(of: entries)!
        let items = [#"{"path":"\#(folder)","type":"tree","sha":"\#(tree)"}"#] + blobs
        return #"{"sha":"root","truncated":false,"tree":[\#(items.joined(separator: ","))]}"#
    }

    private static func trees(_ bodies: [String: String]) -> GitHubTrees {
        GitHubTrees { request in
            let url = request.url!
            for (repository, body) in bodies where url.path.contains("/repos/\(repository)/") {
                return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
    }

    private static let noRegistry = SkillRegistry { request in
        (Data(#"{"error":"Skill not found"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
    }

    @Test func readsWhereTheRegistrySaysASkillLives() {
        let folder = #"{"skill":{"owner":"nextlevelbuilder","repo":"ui-ux-pro-max-skill","skill_path":".claude/skills/ui-ux-pro-max","github_url":"https://github.com/nextlevelbuilder/ui-ux-pro-max-skill"}}"#
        #expect(SkillRegistry.read(Data(folder.utf8)) == RegistryHit(registry: "mdskills.ai",
            source: UpstreamSource(owner: "nextlevelbuilder", repository: "ui-ux-pro-max-skill"), subpath: ".claude/skills/ui-ux-pro-max"))
        let file = #"{"skill":{"owner":"pbakaus","repo":"impeccable","skill_path":"README.md"}}"#
        #expect(SkillRegistry.read(Data(file.utf8))?.subpath == "")
        let address = #"{"skill":{"github_url":"https://github.com/sickn33/collection/tree/main/skills/pptx-official"}}"#
        #expect(SkillRegistry.read(Data(address.utf8))?.subpath == "skills/pptx-official")
        #expect(SkillRegistry.read(Data(#"{"error":"Skill not found"}"#.utf8)) == nil)
        #expect(SkillRegistry.request(for: "../x") == nil)
        #expect(SkillRegistry.request(for: "a/b") == nil)
    }

    @Test func aWholeFolderTheSameIsIdentical() async {
        let text = "---\nname: demo\n---\n"
        let finder = SourceFinder(trees: Self.trees(["o/r": Self.listing("skills/demo", ["SKILL.md": text])]),
                                  registry: Self.noRegistry, fetchFile: { _, _, _ in nil }, history: { _, _ in .success([]) })
        let found = await finder.proposals(for: Self.skill("demo", text), yourSources: [UpstreamSource(owner: "o", repository: "r")])
        #expect(found.first?.evidence == .identical)
        #expect(found.first?.via == "your sources")
    }

    @Test func aCopyOfOnlyTheSkillFileCountsTheMissingFiles() async {
        let text = "---\nname: demo\n---\n"
        let finder = SourceFinder(trees: Self.trees(["o/r": Self.listing("skills/demo", ["SKILL.md": text, "scripts/run.py": "print(1)\n"])]),
                                  registry: Self.noRegistry, fetchFile: { _, _, _ in nil }, history: { _, _ in .success([]) })
        let found = await finder.proposals(for: Self.skill("demo", text), yourSources: [UpstreamSource(owner: "o", repository: "r")])
        #expect(found.first?.evidence == .sameSkillFile(missing: 1))
    }

    @Test func findsAnOlderVersionWithCodexsRewriteUndone() async {
        let old = "Remember: Claude can do it.\n"
        let mine = "Remember: Codex can do it.\n"
        let finder = SourceFinder(
            trees: Self.trees(["o/r": Self.listing("skills/demo", ["SKILL.md": "Newer text\n"])]),
            registry: Self.noRegistry,
            fetchFile: { _, ref, _ in ref == "bbbb" ? Data(old.utf8) : Data("other\n".utf8) },
            history: { _, path in
                #expect(path == "skills/demo/SKILL.md")
                return .success([(sha: "aaaa", date: nil), (sha: "bbbb", date: Date(timeIntervalSince1970: 0))])
            })
        let found = await finder.proposals(for: Self.skill("demo", mine), yourSources: [UpstreamSource(owner: "o", repository: "r")])
        #expect(found.first?.evidence == .olderVersion(date: Date(timeIntervalSince1970: 0), commit: "bbbb", missing: 0))
        #expect(found.first?.rewritten == true)
    }

    @Test func aNameAloneIsOnlyANameAndNothingElseIsNothing() async {
        let finder = SourceFinder(trees: Self.trees(["o/r": Self.listing("skills/demo", ["SKILL.md": "theirs\n"])]),
                                  registry: Self.noRegistry, fetchFile: { _, _, _ in nil }, history: { _, _ in .success([]) })
        let named = await finder.proposals(for: Self.skill("demo-official", "mine\n"), yourSources: [UpstreamSource(owner: "o", repository: "r")])
        #expect(named.map(\.evidence) == [.sameName])
        #expect(!named[0].evidence.isConfirmed)
        let other = await finder.proposals(for: Self.skill("unrelated", "mine\n"), yourSources: [UpstreamSource(owner: "o", repository: "r")])
        #expect(other.isEmpty)
    }

    @Test func aFolderGoneFromItsSourceComesAfterOneThatIsStillThere() async {
        let text = "the text\n"
        let registry = SkillRegistry { request in
            (Data(#"{"skill":{"owner":"gone","repo":"r","skill_path":"skills/demo"}}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let finder = SourceFinder(
            trees: Self.trees(["gone/r": #"{"sha":"root","truncated":false,"tree":[]}"#,
                               "o/r": Self.listing("skills/demo", ["SKILL.md": text, "x.md": "x\n"])]),
            registry: registry,
            fetchFile: { _, _, _ in Data(text.utf8) },
            history: { _, _ in .success([(sha: "cccc", date: nil)]) })
        let found = await finder.proposals(for: Self.skill("demo", text), yourSources: [UpstreamSource(owner: "o", repository: "r")])
        #expect(found.map(\.source.name) == ["o/r", "gone/r"])
        #expect(found[0].evidence == .sameSkillFile(missing: 1))
        #expect(found[1].folderGone)
    }

    @Test func sourcesThatCouldNotBeAskedAreNotCalledEmpty() async {
        let busy = GitHubTrees { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: ["x-ratelimit-remaining": "0"])!)
        }
        let finder = SourceFinder(trees: busy, registry: Self.noRegistry, fetchFile: { _, _, _ in nil }, history: { _, _ in .success([]) })
        let search = await finder.search(for: Self.skill("demo", "x\n"), yourSources: [UpstreamSource(owner: "o", repository: "r")])
        #expect(search.proposals.isEmpty)
        #expect(search.problem == .rateLimited)

        let text = "same\n"
        let fine = SourceFinder(trees: Self.trees(["o/r": Self.listing("skills/demo", ["SKILL.md": text])]),
                                registry: Self.noRegistry, fetchFile: { _, _, _ in nil }, history: { _, _ in .success([]) })
        #expect(await fine.search(for: Self.skill("demo", text), yourSources: [UpstreamSource(owner: "o", repository: "r")]).problem == nil)
    }

    @Test func readsCommitHistory() throws {
        let body = #"[{"sha":"abc","commit":{"committer":{"date":"2026-01-19T13:19:38Z"}}},{"sha":"def","commit":{}}]"#
        let commits = try SourceFinder.readCommits(Data(body.utf8)).get()
        #expect(commits.map(\.sha) == ["abc", "def"])
        #expect(commits[0].date == ISO8601DateFormatter().date(from: "2026-01-19T13:19:38Z"))
        #expect(commits[1].date == nil)
    }
}
