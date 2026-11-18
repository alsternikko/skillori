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
        #expect(baselines["tree:acme/market@old#plugins/inrepo"] == "f-old")

        // The installed commit's folder never changes, so a second check does not ask for it again.
        var again = baselines
        _ = await checker.check(records, baselines: &again)
        #expect(await asked.paths.filter { $0.hasSuffix("/trees/old") }.count == 1)
    }

    /// A plugin at the top of its marketplace's repository with a version, like FLORA's: new
    /// commits under the same version are "already at the latest version" to Claude Code.
    @Test func aVersionedPluginInItsMarketplaceGoesByVersion() async throws {
        let home = try TempTree()
        defer { home.remove() }
        try home.file(".claude/plugins/installed_plugins.json", """
        {"version":2,"plugins":{
          "kit@kit":[{"scope":"user","installPath":"\(home.root.path)/.claude/plugins/cache/kit/kit/0.11.5","version":"0.11.5","gitCommitSha":"ed201f195ccb8b26bea450ee6a9fefa7614a0318"}],
          "bare@kit":[{"scope":"user","installPath":"\(home.root.path)/.claude/plugins/cache/kit/bare/ed201f195ccb","version":"ed201f195ccb","gitCommitSha":"ed201f195ccb8b26bea450ee6a9fefa7614a0318"}]
        }}
        """)
        try home.file(".claude/plugins/known_marketplaces.json", """
        {"kit":{"source":{"source":"github","repo":"acme/kit"},"installLocation":"\(home.root.path)/.claude/plugins/marketplaces/kit"}}
        """)
        let manifest = #"{"name":"kit","plugins":[{"name":"kit","source":"./","version":"0.11.5"},{"name":"bare","source":"./bare"}]}"#
        try home.file(".claude/plugins/marketplaces/kit/.claude-plugin/marketplace.json", manifest)
        let records = ClaudePlugins.records(in: home.root.appendingPathComponent(".claude/plugins"))
        let trees = GitHubTrees { request in
            let url = request.url!
            let old = url.path.hasSuffix("/trees/ed201f195ccb8b26bea450ee6a9fefa7614a0318")
            let body = #"{"sha":"\#(old ? "r-old" : "r-new")","truncated":false,"tree":[{"path":"bare","type":"tree","sha":"\#(old ? "b-old" : "b-new")"}]}"#
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!)
        }
        func check(pluginJSON: String) async -> [String: UpstreamState] {
            let checker = PluginChecker(trees: trees) { _, path in
                path == ".claude-plugin/plugin.json" ? .success(Data(pluginJSON.utf8)) : .success(Data(manifest.utf8))
            }
            var baselines: [String: String] = [:]
            return await checker.check(records, baselines: &baselines)
        }
        let same = await check(pluginJSON: #"{"name":"kit","version":"0.11.5"}"#)
        #expect(same["kit@kit"] == .upToDate)
        // Without a version Claude Code records the commit, so the files decide.
        #expect(same["bare@kit"] == .updateAvailable(upstreamHash: "b-new"))
        let newer = await check(pluginJSON: #"{"name":"kit","version":"0.11.6"}"#)
        #expect(newer["kit@kit"] == .updateAvailable(upstreamHash: "0.11.6"))
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
        let first = try await trees.tree(of: source).get()
        let second = try await trees.tree(of: source).get()
        #expect(first == second)
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

@Suite struct AppPluginTests {
    private func makeHome() throws -> TempTree {
        let home = try TempTree()
        // Cursor: one plugin as a git checkout, one plain folder with a manifest.
        let checkout = ".cursor/plugins/cache/cursor-public/vercel/3b472643cbb1a42479d99b0c9a1d27b8bc84aaa7"
        try home.file("\(checkout)/.cursor-plugin/plugin.json", #"{"name":"vercel","version":"0.53.0","repository":"https://github.com/someone/else"}"#)
        try home.file("\(checkout)/.git/config", "[core]\n\tbare = false\n[remote \"origin\"]\n\turl = https://github.com/vercel/vercel-plugin.git\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n")
        try home.file("\(checkout)/.git/HEAD", "3b472643cbb1a42479d99b0c9a1d27b8bc84aaa7\n")
        try home.skill("\(checkout)/skills/deploy", name: "deploy")
        try home.file(".cursor/plugins/cache/cursor-public/gmail/0dda7b576f7bc64af8285d29e6367c33b88c887b/.cursor-plugin/plugin.json",
                      #"{"name":"gmail","version":"1.0.0","repository":"https://github.com/cursor/plugins"}"#)
        // Codex: one from a remote marketplace, one from a local one, and the config.
        try home.file(".codex/plugins/cache/openai-curated/slack/11c74d6b/.codex-plugin/plugin.json",
                      #"{"name":"slack","version":"0.1.2","repository":"https://github.com/openai/plugins"}"#)
        try home.file(".codex/plugins/cache/claude-cowork/finance/1.1.0/.codex-plugin/plugin.json",
                      #"{"name":"finance","version":"1.1.0","repository":"https://github.com/anthropics/x"}"#)
        try home.file(".codex/config.toml", """
        model = "secret-is-not-read"
        [marketplaces.claude-cowork]
        source_type = "local"
        [plugins."slack@openai-curated"]
        enabled = false
        [plugins."finance@claude-cowork"]
        enabled = true
        """)
        return home
    }

    @Test func readsCursorCheckoutsAndManifests() throws {
        let home = try makeHome()
        defer { home.remove() }
        let records = AppPlugins.records(of: AppPlugins.cursor, in: home.root.appendingPathComponent(".cursor"))
        let vercel = records.first { $0.name == "vercel" }
        // The checkout's remote wins over what the manifest claims.
        #expect(vercel?.repository == "vercel/vercel-plugin")
        #expect(vercel?.isCheckout == true)
        #expect(vercel?.commit == "3b472643cbb1a42479d99b0c9a1d27b8bc84aaa7")
        #expect(vercel?.version == "0.53.0")
        #expect(vercel?.app == "Cursor")
        let gmail = records.first { $0.name == "gmail" }
        #expect(gmail?.repository == "cursor/plugins")
        #expect(gmail?.isCheckout == false)
    }

    @Test func readsWhichCodexPluginsAreOnAndWhichMarketplacesAreLocal() throws {
        let home = try makeHome()
        defer { home.remove() }
        let records = AppPlugins.records(of: AppPlugins.codex, in: home.root.appendingPathComponent(".codex"))
        let slack = records.first { $0.name == "slack" }
        #expect(slack?.enabled == false)
        #expect(slack?.repository == "openai/plugins")
        let finance = records.first { $0.name == "finance" }
        #expect(finance?.enabled == true)
        // A local marketplace ships with Codex: nothing to ask, whatever the manifest says.
        #expect(finance?.repository == nil)
    }

    @Test func skillsInsideAPluginGetItsRecord() throws {
        let home = try makeHome()
        defer { home.remove() }
        let skill = DiscoveryEngine(home: home.root).scan().installations.first { $0.displayName == "deploy" }
        #expect(skill?.plugin?.id == "cursor:vercel@cursor-public")
    }

    @Test func comparesVersionsAsNumbers() {
        #expect(PluginChecker.isNewer("0.10.0", than: "0.9.1"))
        #expect(!PluginChecker.isNewer("0.1.15", than: "0.1.23"))
        #expect(!PluginChecker.isNewer("1.0", than: "1.0.0"))
        #expect(PluginChecker.isNewer("v2.0.0", than: "1.9.9"))
        #expect(PluginChecker.isNewer("nightly", than: "beta"))
    }

    @Test func findsTheManifestInTheRepositoryAndComparesItsVersion() async throws {
        let home = try makeHome()
        defer { home.remove() }
        let records = AppPlugins.records(of: AppPlugins.cursor, in: home.root.appendingPathComponent(".cursor"))
            + AppPlugins.records(of: AppPlugins.codex, in: home.root.appendingPathComponent(".codex"))
        let trees = GitHubTrees { request in
            let url = request.url!
            let files: [String] = url.path.contains("/vercel/vercel-plugin/")
                ? [".cursor-plugin/plugin.json"]
                : url.path.contains("/cursor/plugins/") ? ["plugins/gmail/.cursor-plugin/plugin.json", "plugins/drive/.cursor-plugin/plugin.json"]
                : ["plugins/slack/.codex-plugin/plugin.json", "plugins/notion/.codex-plugin/plugin.json"]
            let items = files.map { #"{"path":"\#($0)","type":"blob","sha":"x","mode":"100644"}"# }.joined(separator: ",")
            let body = #"{"sha":"root","truncated":false,"tree":[\#(items)]}"#
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!)
        }
        let fetched = Asked()
        let checker = PluginChecker(trees: trees) { repository, path in
            await fetched.add("\(repository)/\(path)")
            let version = repository == "vercel/vercel-plugin" ? "0.55.1" : repository == "cursor/plugins" ? "1.0.0" : "0.1.7"
            return .success(Data(#"{"version":"\#(version)"}"#.utf8))
        }
        var baselines: [String: String] = [:]
        let answers = await checker.check(records, baselines: &baselines)
        #expect(answers["cursor:vercel@cursor-public"] == .updateAvailable(upstreamHash: "0.55.1"))
        #expect(answers["cursor:gmail@cursor-public"] == .upToDate)
        #expect(answers["codex:slack@openai-curated"] == .updateAvailable(upstreamHash: "0.1.7"))
        #expect(answers["codex:finance@claude-cowork"] == .cannotCheck(.unsupported))
        let paths = await fetched.paths
        #expect(paths.contains("cursor/plugins/plugins/gmail/.cursor-plugin/plugin.json"))
        #expect(paths.contains("vercel/vercel-plugin/.cursor-plugin/plugin.json"))
    }
}
