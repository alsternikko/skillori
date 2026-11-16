import Foundation
import Testing
@testable import SkilloriCore

@Suite struct UpstreamCheckTests {
    @Test func readsGitHubSourceFromCloneURL() {
        let source = UpstreamSource(source: "emilkowalski/skills", sourceURL: "https://github.com/emilkowalski/skills.git")
        #expect(source == UpstreamSource(owner: "emilkowalski", repository: "skills"))
        #expect(source?.historyURL(subpath: "skills/animate")?.absoluteString
            == "https://github.com/emilkowalski/skills/commits/HEAD/skills/animate")
    }

    @Test func readsOwnerAndRepositoryWhenThereIsNoURL() {
        #expect(UpstreamSource(source: "vercel-labs/skills", sourceURL: nil, ref: "main")
            == UpstreamSource(owner: "vercel-labs", repository: "skills", ref: "main"))
    }

    @Test func refusesWhatIsNotPlainlyGitHub() {
        #expect(UpstreamSource(source: "x/y", sourceURL: "https://gitlab.com/x/y.git") == nil)
        #expect(UpstreamSource(source: "x/y", sourceURL: "http://github.com/x/y.git") == nil)
        #expect(UpstreamSource(source: "x/y", sourceURL: "https://github.com/x/y/z") == nil)
        #expect(UpstreamSource(source: "just-a-name", sourceURL: nil) == nil)
        #expect(UpstreamSource(source: "../y", sourceURL: nil) == nil)
        #expect(UpstreamSource(source: "x/y?ref=1", sourceURL: nil) == nil)
    }

    @Test func comparesBaselineWithTheSourceFolder() {
        let tree = SourceTree(rootHash: "root", folders: ["skills/a": "aaa", "skills/b": "bbb"])
        #expect(UpstreamComparer.state(baseline: "aaa", subpath: "skills/a", in: tree) == .upToDate)
        #expect(UpstreamComparer.state(baseline: "old", subpath: "skills/b", in: tree) == .updateAvailable(upstreamHash: "bbb"))
        #expect(UpstreamComparer.state(baseline: "root", subpath: nil, in: tree) == .upToDate)
        #expect(UpstreamComparer.state(baseline: "x", subpath: "skills/gone", in: tree) == .cannotCheck(.folderGone))
        #expect(UpstreamComparer.state(baseline: nil, subpath: "skills/a", in: tree) == .cannotCheck(.noBaseline))
    }

    @Test func aTruncatedListingDoesNotProveAFolderIsGone() {
        let tree = SourceTree(rootHash: "root", folders: [:], truncated: true)
        #expect(UpstreamComparer.state(baseline: "x", subpath: "skills/a", in: tree) == .cannotCheck(.failed))
    }

    @Test func asksEachSourceOnceAndSendsNothingButItsName() async {
        let asked = Counter()
        let trees = GitHubTrees { request in
            await asked.add(request)
            let url = request.url!
            if url.path.contains("/gone/") { return (Data(), Self.response(url, 404)) }
            if url.path.contains("/busy/") {
                // Answers last, so the wait it asks for cannot stop the others, which were already sent.
                try? await Task.sleep(for: .milliseconds(100))
                return (Data(), Self.response(url, 403, ["x-ratelimit-remaining": "0"]))
            }
            if url.path.contains("/down/") { throw URLError(.notConnectedToInternet) }
            let body = #"{"sha":"root","truncated":false,"tree":[{"path":"skills/a","type":"tree","sha":"aaa"},{"path":"skills/a/SKILL.md","type":"blob","sha":"f"},{"path":"skills/b","type":"tree","sha":"new"}]}"#
            return (Data(body.utf8), Self.response(url, 200))
        }
        let here = UpstreamSource(owner: "o", repository: "here")
        let answers = await UpstreamChecker.check([
            UpstreamQuestion(key: "a", source: here, subpath: "skills/a", baseline: "aaa"),
            UpstreamQuestion(key: "b", source: here, subpath: "skills/b", baseline: "old"),
            UpstreamQuestion(key: "c", source: UpstreamSource(owner: "o", repository: "gone"), subpath: "s", baseline: "x"),
            UpstreamQuestion(key: "d", source: UpstreamSource(owner: "o", repository: "busy"), subpath: "s", baseline: "x"),
            UpstreamQuestion(key: "e", source: UpstreamSource(owner: "o", repository: "down"), subpath: "s", baseline: "x"),
            UpstreamQuestion(key: "f", source: nil, subpath: "s", baseline: "x"),
        ], using: trees)
        #expect(answers["a"] == .upToDate)
        #expect(answers["b"] == .updateAvailable(upstreamHash: "new"))
        #expect(answers["c"] == .cannotCheck(.notFound))
        #expect(answers["d"] == .cannotCheck(.rateLimited))
        #expect(answers["e"] == .cannotCheck(.offline))
        #expect(answers["f"] == .cannotCheck(.unsupported))

        let requests = await asked.requests
        #expect(requests.count == 4)
        for request in requests {
            #expect(request.url?.host == "api.github.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.httpBody == nil)
        }
    }

    @Test func readsWhatAPersonTypesOrPastes() {
        #expect(UpstreamSource.parse(" emilkowalski/skills ")?.source == UpstreamSource(owner: "emilkowalski", repository: "skills"))
        #expect(UpstreamSource.parse("https://github.com/anthropics/skills")?.source.name == "anthropics/skills")
        #expect(UpstreamSource.parse("github.com/anthropics/skills.git/")?.source.name == "anthropics/skills")
        let folder = UpstreamSource.parse("https://github.com/anthropics/skills/tree/main/skills/pptx")
        #expect(folder?.source == UpstreamSource(owner: "anthropics", repository: "skills", ref: "main"))
        #expect(folder?.subpath == "skills/pptx")
        #expect(UpstreamSource.parse("https://github.com/o/r/blob/main/a/SKILL.md")?.subpath == "a")
        #expect(UpstreamSource.parse("https://gitlab.com/o/r") == nil)
        #expect(UpstreamSource.parse("https://github.com/o/r/issues/4") == nil)
        #expect(UpstreamSource.parse("not a source") == nil)
        #expect(UpstreamSource.parse("") == nil)
    }

    @Test func ranksTheFoldersASkillMightComeFrom() {
        let tree = SourceTree(rootHash: "root",
                              folders: ["skills": "s", "skills/pptx": "p1", "skills/docx": "d1", "other/pptx": "p2"],
                              skillFolders: ["other/pptx", "skills/docx", "skills/pptx"])
        let found = SourceMatcher.candidates(localHash: "d1", names: ["PPTX"], in: tree)
        #expect(found.map(\.subpath) == ["skills/docx", "other/pptx", "skills/pptx"])
        #expect(found.map(\.match) == [.identical, .sameName, .sameName])
        #expect(SourceMatcher.candidates(localHash: nil, names: [], in: tree).allSatisfy { $0.match == .other })
    }

    @Test func aSkillAtTheTopOfItsSourceIsFound() async {
        let trees = GitHubTrees { request in
            let body = #"{"sha":"root","tree":[{"path":"SKILL.md","type":"blob","sha":"f"},{"path":"docs","type":"tree","sha":"d"}]}"#
            return (Data(body.utf8), Self.response(request.url!, 200))
        }
        let tree = try? await trees.tree(of: UpstreamSource(owner: "o", repository: "r")).get()
        #expect(tree?.skillFolders == [""])
        #expect(SourceMatcher.candidates(localHash: "root", names: [], in: tree!).first
            == SourceCandidate(subpath: "", hash: "root", match: .identical))
    }

    @Test func readingsSurviveBeingSaved() throws {
        let reading = UpstreamReading(state: .updateAvailable(upstreamHash: "abc"), checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try JSONEncoder().encode(["k": reading])
        #expect(try JSONDecoder().decode([String: UpstreamReading].self, from: data) == ["k": reading])
    }

    private static func response(_ url: URL, _ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: headers)!
    }

    @Test func neverSendsALocalOrOtherHostSourceToGitHubByName() {
        #expect(UpstreamSource(source: "my/folder", sourceURL: nil, sourceType: "local") == nil)
        #expect(UpstreamSource(source: "x/y", sourceURL: nil, sourceType: "gitlab") == nil)
        #expect(UpstreamSource(source: "x/y", sourceURL: nil, sourceType: "github") != nil)
        #expect(UpstreamSource(source: "x/y", sourceURL: nil, sourceType: nil) != nil)
    }

    @Test func aRefCannotLeaveTheTreesEndpoint() {
        #expect(GitHubTrees.request(for: UpstreamSource(owner: "o", repository: "r", ref: "../../users/x")) == nil)
        #expect(GitHubTrees.request(for: UpstreamSource(owner: "o", repository: "r", ref: "release/1.0")) != nil)
    }

    @Test func tellsALimitFromAMissingSourceAndACancelFromNoContact() async {
        let source = UpstreamSource(owner: "o", repository: "r")
        let secondary = GitHubTrees { request in
            (Data(), Self.response(request.url!, 403, ["x-ratelimit-remaining": "41", "retry-after": "60"]))
        }
        #expect(await secondary.tree(of: source).failureReason == .rateLimited)
        let forbidden = GitHubTrees { request in (Data(), Self.response(request.url!, 403, ["x-ratelimit-remaining": "41"])) }
        #expect(await forbidden.tree(of: source).failureReason == .notFound)
        let cancelled = GitHubTrees { _ in throw URLError(.cancelled) }
        #expect(await cancelled.tree(of: source).failureReason == .cancelled)
        let stopped = GitHubTrees { _ in throw CancellationError() }
        #expect(await stopped.tree(of: source).failureReason == .cancelled)
    }

}

private actor Counter {
    var requests: [URLRequest] = []
    func add(_ request: URLRequest) { requests.append(request) }
}

private extension Result where Failure == UpstreamState.Reason {
    var failureReason: UpstreamState.Reason? {
        if case .failure(let reason) = self { reason } else { nil }
    }
}

@Suite struct FileChangeTests {
    @Test func listsWhatAnUpdateWouldChangeWithRunnableFilesFirst() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file("SKILL.md", "---\nname: x\n---\n")
        try tree.file("notes.md", "old\n")
        try tree.file("gone.txt", "bye\n")
        try tree.file("run.sh", "echo\n")
        let local = try GitTreeHash.hashDirectory(at: tree.root).entries
        let ids = Dictionary(uniqueKeysWithValues: local.map { ($0.path, $0.objectID) })
        let upstream = SourceTree(rootHash: "r", folders: [:], files: [
            "skills/x/SKILL.md": SourceFile(id: ids["SKILL.md"]!, mode: "100644"),
            "skills/x/notes.md": SourceFile(id: "different", mode: "100644"),
            "skills/x/run.sh": SourceFile(id: ids["run.sh"]!, mode: "100755"),
            "skills/x/scripts/new.py": SourceFile(id: "n", mode: "100644"),
            "skills/other/SKILL.md": SourceFile(id: "o", mode: "100644"),
        ])
        let changes = FileChanges.compare(local: local, upstream: upstream, subpath: "skills/x")
        #expect(changes.map(\.path) == ["run.sh", "scripts/new.py", "gone.txt", "notes.md"])
        #expect(changes.first { $0.path == "run.sh" }?.modeOnly == true)
        #expect(changes.first { $0.path == "scripts/new.py" }?.kind == .added)
        #expect(changes.first { $0.path == "gone.txt" }?.kind == .removed)
        #expect(changes.first { $0.path == "notes.md" }?.runnable == false)
    }
}

@Suite struct RootTreeTests {
    /// GitHub answers a trees question by branch with the commit id as `sha`. The root tree id
    /// must come from the entries, or a skill at the top of a repository never matches.
    @Test func rootHashIsTheTreeNotTheCommit() async throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file("SKILL.md", "---\nname: top\n---\n")
        try tree.file("scripts/run.sh", "echo\n", executable: true)
        let local = try GitTreeHash.hashDirectory(at: tree.root)
        let ids = Dictionary(uniqueKeysWithValues: local.entries.map { ($0.path, $0.objectID) })
        let scripts = try GitTreeHash.hashDirectory(at: tree.root.appendingPathComponent("scripts")).treeID
        let body = """
        {"sha":"ed201f195ccb8b26bea450ee6a9fefa7614a0318","truncated":false,"tree":[
          {"path":"SKILL.md","mode":"100644","type":"blob","sha":"\(ids["SKILL.md"]!)"},
          {"path":"scripts","mode":"040000","type":"tree","sha":"\(scripts)"},
          {"path":"scripts/run.sh","mode":"100755","type":"blob","sha":"\(ids["scripts/run.sh"]!)"}]}
        """
        let trees = GitHubTrees { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
        }
        let listing = try await trees.tree(of: UpstreamSource(owner: "o", repository: "r")).get()
        #expect(listing.rootHash == local.treeID)
        #expect(UpstreamComparer.state(baseline: local.treeID, subpath: nil, in: listing) == .upToDate)
    }
}
