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
            if url.path.contains("/busy/") { return (Data(), Self.response(url, 403, ["x-ratelimit-remaining": "0"])) }
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

    @Test func readingsSurviveBeingSaved() throws {
        let reading = UpstreamReading(state: .updateAvailable(upstreamHash: "abc"), checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try JSONEncoder().encode(["k": reading])
        #expect(try JSONDecoder().decode([String: UpstreamReading].self, from: data) == ["k": reading])
    }

    private static func response(_ url: URL, _ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: headers)!
    }
}

private actor Counter {
    var requests: [URLRequest] = []
    func add(_ request: URLRequest) { requests.append(request) }
}
