import Foundation
import Testing
@testable import SkilloriCore

@Suite struct DiscoveryTests {
    /// A home directory shaped like the one observed on 2026-11-11, in miniature.
    private func makeHome() throws -> TempTree {
        let home = try TempTree()
        // `npx skills` style: canonical copy + relative symlinks into agent roots.
        try home.skill(".agents/skills/animate", name: "animate", extra: ["scripts/x.sh": "echo\n"])
        try home.link(".claude/skills/animate", to: "../../.agents/skills/animate")
        try home.link(".cursor/skills/animate", to: home.root.appendingPathComponent(".agents/skills/animate").path)
        // A separate copy with identical content is still a separate installation.
        try home.skill(".claude/skills/copied", name: "copied")
        try home.skill(".cursor/skills/copied", name: "copied")
        // Plugin caches: one active version, one orphaned version.
        try home.skill(".claude/plugins/cache/mkt/plug/1.0.0/skills/plugged", name: "plugged")
        try home.skill(".claude/plugins/cache/mkt/plug/0.9.0/skills/old", name: "old")
        try home.file(".claude/plugins/cache/mkt/plug/0.9.0/.orphaned_at", "1")
        // Marketplace clone: lots of SKILL.md that are NOT installed.
        try home.skill(".claude/plugins/marketplaces/mkt/plugins/plug/skills/catalog-only", name: "catalog-only")
        // Broken link and invalid skill.
        try home.link(".claude/skills/gone", to: "../../nowhere")
        try home.file(".claude/skills/broken/SKILL.md", "no front matter")
        return home
    }

    private func writeLock(_ home: TempTree, hash: String) throws {
        try home.file(".agents/.skill-lock.json", """
        {"version":3,"skills":{"animate":{"source":"emilkowalski/skills","sourceType":"github",
        "sourceUrl":"https://github.com/emilkowalski/skills.git","skillPath":"skills/animate/SKILL.md",
        "skillFolderHash":"\(hash)","installedAt":"2026-10-16T06:22:43.511Z","updatedAt":"2026-11-11T10:05:12.461Z",
        "futureField":{"nested":true}}},"lastSelectedAgents":["claude-code"]}
        """)
    }

    @Test func deduplicatesPhysicalSkillsButKeepsCopies() throws {
        let home = try makeHome()
        defer { home.remove() }
        let inventory = DiscoveryEngine(home: home.root).scan()

        let animate = inventory.installations.filter { $0.displayName == "animate" }
        #expect(animate.count == 1)
        #expect(animate.first?.bindings.count == 3) // .agents, .claude (relative link), .cursor (absolute link)
        #expect(animate.first?.agents.contains(.claudeCode) == true)

        #expect(inventory.installations.filter { $0.displayName == "copied" }.count == 2)
    }

    @Test func excludesOrphanedVersionsAndMarketplaceClones() throws {
        let home = try makeHome()
        defer { home.remove() }
        let names = Set(DiscoveryEngine(home: home.root).scan().installations.map(\.displayName))
        #expect(names.contains("plugged"))
        #expect(!names.contains("old"))
        #expect(!names.contains("catalog-only"))
    }

    @Test func pluginSkillsAreManaged() throws {
        let home = try makeHome()
        defer { home.remove() }
        let plugged = DiscoveryEngine(home: home.root).scan().installations.first { $0.displayName == "plugged" }
        #expect(plugged?.provenance == .managed(by: "Claude Code plugin"))
    }

    @Test func reportsBrokenLinksAndInvalidSkillsWithoutFailing() throws {
        let home = try makeHome()
        defer { home.remove() }
        let inventory = DiscoveryEngine(home: home.root).scan()
        #expect(inventory.diagnostics.contains { $0.path.hasSuffix("/gone") && $0.message == "Broken link" })
        let broken = inventory.installations.first { $0.directoryName == "broken" }
        #expect(broken?.frontmatter.problems.isEmpty == false)
        #expect(broken?.provenance == .unknown)
    }

    @Test func lockFileGivesBaselineAndDetectsLocalChanges() throws {
        let home = try makeHome()
        defer { home.remove() }
        let skillDir = home.root.appendingPathComponent(".agents/skills/animate")
        try writeLock(home, hash: try referenceTreeHash(of: skillDir))

        var animate = DiscoveryEngine(home: home.root).scan().installations.first { $0.displayName == "animate" }
        guard case .skillsLock(let source, _, let subpath, _, let local)? = animate?.provenance else {
            Issue.record("Expected skills lock provenance, got \(String(describing: animate?.provenance))")
            return
        }
        #expect(source == "emilkowalski/skills")
        #expect(subpath == "skills/animate")
        #expect(local == .matchesBaseline)

        try home.file(".agents/skills/animate/SKILL.md", "---\nname: animate\ndescription: edited\n---\n")
        animate = DiscoveryEngine(home: home.root).scan().installations.first { $0.displayName == "animate" }
        guard case .skillsLock(_, _, _, _, .modified)? = animate?.provenance else {
            Issue.record("Expected modified after local edit")
            return
        }
    }

    @Test func unregisteredProjectsAreNotScanned() throws {
        let home = try makeHome()
        defer { home.remove() }
        let project = try TempTree()
        defer { project.remove() }
        try project.skill(".claude/skills/project-skill", name: "project-skill")
        try project.skill(".github/skills/copilot-only", name: "copilot-only")

        let without = DiscoveryEngine(home: home.root).scan()
        #expect(!without.installations.contains { $0.displayName == "project-skill" })

        let with = DiscoveryEngine(home: home.root, projects: [project.root]).scan()
        let projectSkill = with.installations.first { $0.displayName == "project-skill" }
        #expect(projectSkill?.bindings.first?.scope == .project)
        #expect(with.installations.first { $0.displayName == "copilot-only" }?.agents == [.copilot])
    }

    @Test func missingRootsAreReportedNotFatal() throws {
        let home = try TempTree()
        defer { home.remove() }
        let inventory = DiscoveryEngine(home: home.root).scan()
        #expect(inventory.installations.isEmpty)
        #expect(inventory.roots.contains { $0.path.hasSuffix(".claude/skills") && $0.state == .missing })
    }
}

@Suite struct DiscoveryCoverageTests {
    private func names(_ inventory: Inventory) -> Set<String> { Set(inventory.installations.map(\.displayName)) }

    @Test func readsWhatTheClaudeAppDownloads() throws {
        let home = try TempTree()
        defer { home.remove() }
        let app = "Library/Application Support/Claude/local-agent-mode-sessions"
        try home.skill("\(app)/skills-plugin/aaa/bbb/skills/docx", name: "docx")
        try home.skill("\(app)/bbb/aaa/rpm/plugin_1/skills/figma-use", name: "figma-use")
        // The catalogue of plugins that could be installed is not an installation.
        try home.skill("\(app)/bbb/aaa/cowork_plugins/marketplaces/mkt/sales/skills/pitch", name: "pitch")

        let inventory = DiscoveryEngine(home: home.root).scan()
        #expect(names(inventory) == ["docx", "figma-use"])
        let docx = inventory.installations.first { $0.displayName == "docx" }
        #expect(docx?.provenance == .managed(by: "Claude app"))
        #expect(docx?.agents == [.claudeDesktop])
    }

    @Test func readsAgentsAddedInRulesTwo() throws {
        let home = try TempTree()
        defer { home.remove() }
        try home.skill(".cline/skills/a", name: "a")
        try home.skill(".config/goose/skills/b", name: "b")
        try home.skill(".codeium/windsurf/skills/c", name: "c")
        try home.skill(".continue/skills/d", name: "d")
        let inventory = DiscoveryEngine(home: home.root).scan()
        #expect(names(inventory) == ["a", "b", "c", "d"])
        #expect(inventory.installations.first { $0.displayName == "d" }?.agents.map(\.id) == ["continue"])
    }

    @Test func manifestPathsReplaceTheStandardFolderInCursorAndAddToItInClaudeCode() throws {
        let home = try TempTree()
        defer { home.remove() }
        let cursor = ".cursor/plugins/cache/mkt/figma/abc"
        try home.skill("\(cursor)/skills/standard", name: "cursor-standard")
        try home.skill("\(cursor)/skills-other/named", name: "cursor-named")
        try home.file("\(cursor)/.cursor-plugin/plugin.json", #"{"name":"figma","skills":"./skills-other/"}"#)
        let claude = ".claude/plugins/cache/mkt/figma/1.0.0"
        try home.skill("\(claude)/skills/standard", name: "claude-standard")
        try home.skill("\(claude)/more/named", name: "claude-named")
        try home.skill("\(claude)/single", name: "claude-single")
        try home.skill("outside/escaped", name: "escaped")
        try home.file("\(claude)/.claude-plugin/plugin.json",
                      #"{"name":"figma","skills":["./more","./single","../../../../../../outside","/etc"]}"#)

        let found = names(DiscoveryEngine(home: home.root).scan())
        #expect(found == ["cursor-named", "claude-standard", "claude-named", "claude-single"])
    }

    @Test func pluginThatIsOneSkillIsRead() throws {
        let home = try TempTree()
        defer { home.remove() }
        try home.skill(".claude/plugins/cache/mkt/solo/1.0.0", name: "solo")
        #expect(names(DiscoveryEngine(home: home.root).scan()) == ["solo"])
    }

    @Test func readsPluginsTheInstallRecordPlacesOutsideTheCache() throws {
        let home = try TempTree()
        defer { home.remove() }
        try home.skill("dev/my-plugin/skills/local", name: "local")
        try home.skill(".claude/plugins/cache/mkt/plug/1.0.0/skills/cached", name: "cached")
        let cached = home.root.appendingPathComponent(".claude/plugins/cache/mkt/plug/1.0.0").path
        let local = home.root.appendingPathComponent("dev/my-plugin").path
        try home.file(".claude/plugins/installed_plugins.json", """
        {"version":2,"plugins":{"plug@mkt":[{"scope":"user","installPath":"\(cached)"}],
        "my-plugin@local":[{"scope":"user","installPath":"\(local)"}]}}
        """)
        let inventory = DiscoveryEngine(home: home.root).scan()
        #expect(names(inventory) == ["cached", "local"])
        // The cached plugin is named by both the rule and the record, and counted once.
        #expect(inventory.installations.first { $0.displayName == "cached" }?.bindings.count == 1)
    }

    @Test func followsVariablesThatMoveASettingsFolder() throws {
        let home = try TempTree()
        defer { home.remove() }
        let elsewhere = try TempTree()
        defer { elsewhere.remove() }
        try home.skill(".claude/skills/usual", name: "usual")
        try elsewhere.skill("claude/skills/moved", name: "moved")
        try elsewhere.skill("claude/plugins/cache/mkt/plug/1.0.0/skills/moved-plugin", name: "moved-plugin")
        try elsewhere.skill("xdg/opencode/skills/moved-xdg", name: "moved-xdg")
        try elsewhere.skill("gemini-home/.gemini/skills/moved-gemini", name: "moved-gemini")
        let environment = [
            "CLAUDE_CONFIG_DIR": elsewhere.root.appendingPathComponent("claude").path,
            "XDG_CONFIG_HOME": elsewhere.root.appendingPathComponent("xdg").path,
            "GEMINI_CLI_HOME": elsewhere.root.appendingPathComponent("gemini-home").path,
            "CODEX_HOME": "relative/is/ignored",
        ]
        #expect(names(DiscoveryEngine(home: home.root).scan()) == ["usual"])
        let found = names(DiscoveryEngine(home: home.root, environment: environment).scan())
        #expect(found == ["usual", "moved", "moved-plugin", "moved-xdg", "moved-gemini"])
    }

    @Test func readsAdministratorFoldersOnlyWhenGivenTheDiskRoot() throws {
        let home = try TempTree()
        defer { home.remove() }
        let disk = try TempTree()
        defer { disk.remove() }
        try disk.skill("etc/codex/skills/company", name: "company")
        #expect(names(DiscoveryEngine(home: home.root).scan()).isEmpty)
        let inventory = DiscoveryEngine(home: home.root, system: disk.root).scan()
        #expect(inventory.installations.first?.provenance == .managed(by: "your organization"))
    }
}
