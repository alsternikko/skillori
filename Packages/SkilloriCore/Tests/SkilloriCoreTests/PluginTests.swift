import Foundation
import Testing
@testable import SkilloriCore

@Suite struct PluginTests {
    /// A `.claude/plugins` folder like the one Claude Code writes, in miniature.
    private func makePlugins() throws -> TempTree {
        let home = try TempTree()
        try home.file(".claude/plugins/installed_plugins.json", """
        {"version":2,"plugins":{
          "inrepo@market":[{"scope":"user","installPath":"\(home.root.path)/.claude/plugins/cache/market/inrepo/1.0.0","version":"1.0.0","gitCommitSha":"old"}],
          "pinned@market":[{"scope":"project","projectPath":"/p","installPath":"\(home.root.path)/.claude/plugins/cache/market/pinned/2.0.0","version":"2.0.0","gitCommitSha":"aaa"}],
          "versioned@market":[{"scope":"user","installPath":"\(home.root.path)/.claude/plugins/cache/market/versioned/1.0","version":"1.0"}]
        }}
        """)
        try home.file(".claude/plugins/known_marketplaces.json", """
        {"market":{"source":{"source":"github","repo":"acme/market"},"installLocation":"\(home.root.path)/.claude/plugins/marketplaces/market"}}
        """)
        try home.file(".claude/plugins/marketplaces/market/.claude-plugin/marketplace.json", Self.manifest(pinned: "aaa", version: "1.0"))
        try home.skill(".claude/plugins/cache/market/inrepo/1.0.0/skills/one", name: "one")
        try home.skill(".claude/plugins/cache/market/pinned/2.0.0/skills/two", name: "two")
        return home
    }

    static func manifest(pinned: String, version: String) -> String {
        """
        {"name":"market","plugins":[
          {"name":"inrepo","source":"./plugins/inrepo"},
          {"name":"pinned","source":{"source":"git-subdir","url":"https://github.com/acme/other.git","path":"plugins/p","sha":"\(pinned)"}},
          {"name":"versioned","source":{"source":"url","url":"https://example.com/x.git"},"version":"\(version)"}
        ]}
        """
    }

    @Test func readsWhatClaudeCodeRecords() throws {
        let home = try makePlugins()
        defer { home.remove() }
        let records = ClaudePlugins.records(in: home.root.appendingPathComponent(".claude/plugins"))
        #expect(records.count == 3)
        let inrepo = records.first { $0.id == "inrepo@market" }
        #expect(inrepo?.marketplaceRepository == "acme/market")
        #expect(inrepo?.origin == .inMarketplace(path: "plugins/inrepo"))
        #expect(inrepo?.commit == "old")
        let pinned = records.first { $0.id == "pinned@market" }
        #expect(pinned?.origin == .repository(owner: "acme", repository: "other", path: "plugins/p", pinned: "aaa"))
        #expect(pinned?.scope == "project")
        #expect(pinned?.projectPath == "/p")
    }

    @Test func discoveryTiesSkillsToTheirPlugin() throws {
        let home = try makePlugins()
        defer { home.remove() }
        let inventory = DiscoveryEngine(home: home.root).scan()
        #expect(inventory.installations.first { $0.displayName == "one" }?.plugin?.id == "inrepo@market")
        #expect(inventory.installations.first { $0.displayName == "two" }?.plugin?.id == "pinned@market")
    }

    @Test func pathsThatLeaveTheRepositoryAreRefused() {
        #expect(PluginOrigin.normalizedPath("./") == "")
        #expect(PluginOrigin.normalizedPath("./plugins/x/") == "plugins/x")
        #expect(PluginOrigin.normalizedPath("../elsewhere") == nil)
        #expect(PluginOrigin.parse("../x") == .other)
    }

    @Test func comparesEachKindOfPluginWithWhatItsMarketplaceSaysNow() async throws {
        let home = try makePlugins()
        defer { home.remove() }
        let records = ClaudePlugins.records(in: home.root.appendingPathComponent(".claude/plugins"))
        let asked = Asked()
        let trees = GitHubTrees { request in
            await asked.add(request.url!.path)
            let url = request.url!
            // The folder was "f-old" at the installed commit and is "f-new" now.
            let folder = url.path.hasSuffix("/trees/old") ? "f-old" : "f-new"
            let body = #"{"sha":"root","truncated":false,"tree":[{"path":"plugins/inrepo","type":"tree","sha":"\#(folder)"}]}"#
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!)
        }
        let checker = PluginChecker(trees: trees) { repository, _ in
            #expect(repository == "acme/market")
            return .success(Data(Self.manifest(pinned: "bbb", version: "1.1").utf8))
        }
        var baselines: [String: String] = [:]
        let answers = await checker.check(records, baselines: &baselines)
        #expect(answers["inrepo@market"] == .updateAvailable(upstreamHash: "f-new"))
        #expect(answers["pinned@market"] == .updateAvailable(upstreamHash: "bbb"))
        #expect(answers["versioned@market"] == .updateAvailable(upstreamHash: "1.1"))
        #expect(baselines["acme/market@old#plugins/inrepo"] == "f-old")

        // The installed commit's folder never changes, so a second check does not ask for it again.
        var again = baselines
        _ = await checker.check(records, baselines: &again)
        #expect(await asked.paths.filter { $0.hasSuffix("/trees/old") }.count == 1)
    }

    @Test func aPluginTheMarketplaceDroppedIsNotCalledCurrent() async throws {
        let home = try makePlugins()
        defer { home.remove() }
        let records = ClaudePlugins.records(in: home.root.appendingPathComponent(".claude/plugins"))
        let checker = PluginChecker(trees: GitHubTrees { _ in throw URLError(.notConnectedToInternet) }) { _, _ in
            .success(Data(#"{"plugins":[]}"#.utf8))
        }
        var baselines: [String: String] = [:]
        let answers = await checker.check(records, baselines: &baselines)
        #expect(answers["pinned@market"] == .cannotCheck(.folderGone))
    }
}

@Suite struct GitHubBudgetTests {
    @Test func asksConditionallyAndUsesTheCachedAnswerWhenUnchanged() async throws {
        let seen = Asked()
        let trees = GitHubTrees { request in
            let url = request.url!
            await seen.add(request.value(forHTTPHeaderField: "If-None-Match") ?? "-")
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" {
                return (Data(), HTTPURLResponse(url: url, statusCode: 304, httpVersion: nil, headerFields: [:])!)
            }
            let body = #"{"sha":"root","tree":[]}"#
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"v1\""])!)
        }
        let source = UpstreamSource(owner: "o", repository: "r")
        #expect(try await trees.tree(of: source).get().rootHash == "root")
        #expect(try await trees.tree(of: source).get().rootHash == "root")
        #expect(await seen.paths == ["-", "\"v1\""])
    }

    @Test func stopsAskingOnceGitHubSaysToWait() async {
        let count = Asked()
        let trees = GitHubTrees { request in
            await count.add(request.url!.path)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil,
                                            headerFields: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "\(Int(Date().timeIntervalSince1970) + 600)"])!)
        }
        let questions = (0..<10).map {
            UpstreamQuestion(key: "\($0)", source: UpstreamSource(owner: "o", repository: "r\($0)"), subpath: nil, baseline: "x")
        }
        let answers = await UpstreamChecker.check(questions, using: trees)
        #expect(answers.values.allSatisfy { $0 == .cannotCheck(.rateLimited) })
        // At most the first batch was sent before the answer to wait arrived.
        #expect(await count.paths.count <= UpstreamChecker.maxConcurrent)
    }

    @Test func asksAFewSourcesAtATime() async {
        let gauge = Gauge()
        let trees = GitHubTrees { request in
            await gauge.enter()
            try? await Task.sleep(for: .milliseconds(20))
            await gauge.leave()
            return (Data(#"{"sha":"root","tree":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
        }
        let questions = (0..<12).map {
            UpstreamQuestion(key: "\($0)", source: UpstreamSource(owner: "o", repository: "r\($0)"), subpath: nil, baseline: "root")
        }
        let answers = await UpstreamChecker.check(questions, using: trees)
        #expect(answers.count == 12)
        #expect(await gauge.peak <= UpstreamChecker.maxConcurrent)
    }
}

private actor Asked {
    var paths: [String] = []
    func add(_ path: String) { paths.append(path) }
}

private actor Gauge {
    var now = 0
    var peak = 0
    func enter() { now += 1; peak = max(peak, now) }
    func leave() { now -= 1 }
}
