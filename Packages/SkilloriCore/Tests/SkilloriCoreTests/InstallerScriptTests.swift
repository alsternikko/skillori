import Foundation
import Testing
@testable import SkilloriCore

@Suite struct InstallerScriptTests {
    private static func b64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

    /// The shape interfacecraft.dev uses: files embedded as base64, written under a variable path,
    /// then linked into each agent's folder.
    private static let embedded = """
    #!/bin/bash
    set -e
    SKILL_NAME="demo"
    # Embedded skill files (base64)
    SKILL_md="\(b64("---\nname: demo\n---\n# Demo\n"))"
    notes_md="\(b64("notes\n"))"
    run_sh="\(b64("echo hi\n"))"
    CANONICAL="$HOME/.agents/skills/$SKILL_NAME"
    mkdir -p "$CANONICAL/references"
    echo "$SKILL_md" | base64 -d > "$CANONICAL/SKILL.md"
    echo "$notes_md" | base64 -d > "$CANONICAL/references/notes.md"
    echo "$run_sh" | base64 --decode > "$CANONICAL/run.sh"
    chmod +x "$CANONICAL/run.sh"
    echo "$SKILL_md" | base64 -d >> "$HOME/.codeium/windsurf/memories/global_rules.md"
    if [ -d "$HOME/.claude" ]; then
      ln -s "$CANONICAL" "$HOME/.claude/skills/$SKILL_NAME"
    fi
    """

    @Test func readsFilesEmbeddedAsBase64WithoutRunningAnything() throws {
        let files = try InstallerScript.files(in: Self.embedded)
        #expect(files.map(\.path) == ["$HOME/.agents/skills/demo/SKILL.md", "$HOME/.agents/skills/demo/references/notes.md",
                                      "$HOME/.agents/skills/demo/run.sh"])
        #expect(files[1].content == Data("notes\n".utf8))
        #expect(files[2].executable)
        #expect(!files[0].executable)
    }

    @Test func theTreeHasTheSameIdsAsTheFolderOnDisk() throws {
        let tree = InstallerScript.tree(from: try InstallerScript.files(in: Self.embedded))
        #expect(tree.skillFolders == ["demo"])
        #expect(tree.files["demo/run.sh"]?.mode == "100755")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("installer-\(UUID().uuidString)/demo")
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("references"), withIntermediateDirectories: true)
        try Data("---\nname: demo\n---\n# Demo\n".utf8).write(to: folder.appendingPathComponent("SKILL.md"))
        try Data("notes\n".utf8).write(to: folder.appendingPathComponent("references/notes.md"))
        try Data("echo hi\n".utf8).write(to: folder.appendingPathComponent("run.sh"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appendingPathComponent("run.sh").path)

        let local = try GitTreeHash.hashDirectory(at: folder)
        #expect(tree.hash(of: "demo") == local.treeID)
        #expect(FileChanges.compare(local: local.entries, upstream: tree, subpath: "demo").isEmpty)
    }

    @Test func readsQuotedHereDocuments() throws {
        let script = """
        DIR=~/.claude/skills/notes
        mkdir -p "$DIR"
        cat > "$DIR/SKILL.md" <<'EOF'
        ---
        name: notes
        ---
        Costs $5 and uses `code`.
        EOF
        cat <<-EOF > $DIR/extra.md
        \tPlain text in $DIR
        \tEOF
        """
        let files = try InstallerScript.files(in: script)
        #expect(files.map(\.path) == ["$HOME/.claude/skills/notes/SKILL.md", "$HOME/.claude/skills/notes/extra.md"])
        #expect(String(decoding: files[0].content, as: UTF8.self) == "---\nname: notes\n---\nCosts $5 and uses `code`.\n")
        #expect(String(decoding: files[1].content, as: UTF8.self) == "Plain text in ~/.claude/skills/notes\n")
        #expect(InstallerScript.tree(from: files).skillFolders == ["notes"])
    }

    @Test func refusesContentOnlyRunningTheScriptCouldTell() {
        let script = """
        cat > "$HOME/.claude/skills/x/SKILL.md" <<EOF
        Installed on $(date)
        EOF
        """
        #expect(throws: InstallerScript.ReadError.self) { try InstallerScript.files(in: script) }
        let fetched = """
        BODY=$(curl -fsSL https://example.com/skill.b64)
        echo "$BODY" | base64 -d > "$HOME/.claude/skills/x/SKILL.md"
        """
        #expect(throws: InstallerScript.ReadError.self) { try InstallerScript.files(in: fetched) }
    }

    @Test func countsTheSameSkillWrittenToSeveralPlacesOnce() throws {
        let body = Self.b64("---\nname: twin\n---\n")
        let script = """
        S="\(body)"
        echo "$S" | base64 -d > "$HOME/.claude/skills/twin/SKILL.md"
        echo "$S" | base64 -d > "$HOME/.cursor/skills/twin/SKILL.md"
        """
        let tree = InstallerScript.tree(from: try InstallerScript.files(in: script))
        #expect(tree.skillFolders == [".claude/skills/twin"])
    }

    @Test func readsAddressesAndPastedCommands() {
        #expect(InstallerSource("https://www.interfacecraft.dev/api/install-skills")?.name == "interfacecraft.dev/api/install-skills")
        let pasted = InstallerSource("curl -fsSL https://www.interfacecraft.dev/api/install-skills | bash")
        #expect(pasted?.url.absoluteString == "https://www.interfacecraft.dev/api/install-skills")
        #expect(pasted?.siteURL?.absoluteString == "https://www.interfacecraft.dev/")
        #expect(InstallerSource("http://example.com/install.sh") == nil)
        #expect(InstallerSource("https://github.com/owner/repo") == nil)
        #expect(InstallerSource("https://localhost/install") == nil)
        #expect(InstallerSource("owner/repo") == nil)

        if case .github(let source)? = SkillSource.parse("owner/repo")?.source {
            #expect(source.name == "owner/repo")
        } else {
            Issue.record("owner/repo should be read as GitHub")
        }
        if case .installer? = SkillSource.parse("https://example.com/install.sh")?.source {} else {
            Issue.record("a script address should be read as an installer")
        }
        #expect(SkillSource.installer(InstallerSource("https://example.com/i")!).historyURL(subpath: nil) == nil)
    }

    @Test func asksTheScriptOnceAndSendsNothingButItsAddress() async {
        let asked = Requests()
        let script = Self.embedded
        let installers = InstallerScripts { request in
            await asked.add(request)
            let url = request.url!
            if url.path == "/gone" { return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!) }
            if url.path == "/page" {
                return (Data("<!DOCTYPE html><html></html>".utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return (Data(script.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let tree = InstallerScript.tree(from: try! InstallerScript.files(in: script))
        let here = SkillSource.installer(InstallerSource("https://example.com/install")!)
        let answers = await UpstreamChecker.check([
            UpstreamQuestion(key: "a", source: here, subpath: "demo", baseline: tree.hash(of: "demo")),
            UpstreamQuestion(key: "b", source: here, subpath: "demo", baseline: "old"),
            UpstreamQuestion(key: "c", source: .installer(InstallerSource("https://example.com/gone")!), subpath: "demo", baseline: "x"),
            UpstreamQuestion(key: "d", source: .installer(InstallerSource("https://example.com/page")!), subpath: "demo", baseline: "x"),
        ], using: GitHubTrees { _ in throw URLError(.badURL) }, installers: installers)
        #expect(answers["a"] == .upToDate)
        #expect(answers["b"] == .updateAvailable(upstreamHash: tree.hash(of: "demo")!))
        #expect(answers["c"] == .cannotCheck(.notFound))
        #expect(answers["d"] == .cannotCheck(.failed))

        let requests = await asked.requests
        #expect(requests.count == 3)
        for request in requests {
            #expect(request.httpMethod == nil || request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.httpBody == nil)
        }
    }
}

@Suite struct SourceNoticeTests {
    /// What interfacecraft.dev answered with its 410 once the installer moved behind its library.
    static let moved = """
    #!/bin/sh
    printf '%s\\n' "This installer has moved."
    printf '%s\\n' "Members can copy their new install command from the Library:"
    printf '%s\\n' "https://www.interfacecraft.dev/library/interface-craft-skills"
    exit 1
    """

    @Test func readsWhatAMovedInstallerPrints() {
        let notice = SourceNotice(body: Self.moved)
        #expect(notice?.message == "This installer has moved. Members can copy their new install command from the Library:")
        #expect(notice?.url?.absoluteString == "https://www.interfacecraft.dev/library/interface-craft-skills")
    }

    @Test func readsEchoLinesAndPlainText() {
        let echoed = SourceNotice(body: "#!/bin/bash\necho \"Moved to https://example.com/new.\" >&2\nexit 1\n")
        #expect(echoed?.message == "Moved to https://example.com/new.")
        #expect(echoed?.url?.absoluteString == "https://example.com/new")
        let plain = SourceNotice(body: "Gone for good.\n")
        #expect(plain == SourceNotice(message: "Gone for good.", url: nil))
    }

    @Test func aWebPageOrAScriptAtWorkSaysNothing() {
        #expect(SourceNotice(body: "<!DOCTYPE html><html><body>Not found</body></html>") == nil)
        #expect(SourceNotice(body: "") == nil)
        #expect(SourceNotice(body: "#!/bin/sh\necho \"$SKILL_md\" | base64 -d > \"$DIR/SKILL.md\"\n") == nil)
    }

    @Test func onlyHttpsAddressesAndShortMessages() {
        let notice = SourceNotice(body: "See http://example.com/new\n" + String(repeating: "word ", count: 200))
        #expect(notice?.url == nil)
        #expect((notice?.message.count ?? 0) <= SourceNotice.maxCharacters)
    }

    @Test func aGoneInstallerKeepsWhatItSaid() async {
        let scripts = InstallerScripts { request in
            let url = request.url!
            return (Data(Self.moved.utf8), HTTPURLResponse(url: url, statusCode: 410, httpVersion: nil, headerFields: nil)!)
        }
        let read = await scripts.read(InstallerSource("https://www.interfacecraft.dev/api/install-skills")!)
        #expect(read.tree == .failure(.notFound))
        #expect(read.notice?.url?.host == "www.interfacecraft.dev")

        let answers = await UpstreamChecker.answers(
            to: [UpstreamQuestion(key: "k", source: .installer(InstallerSource("https://www.interfacecraft.dev/api/install-skills")!),
                                  subpath: "interface-craft", baseline: "abc")],
            installers: scripts)
        #expect(answers["k"]?.state == .cannotCheck(.notFound))
        #expect(answers["k"]?.notice?.message.hasPrefix("This installer has moved.") == true)
    }

    @Test func readingsSavedBeforeNoticesStillLoad() throws {
        let old = #"{"checkedAt": 816885109.36, "state": {"cannotCheck": {"_0": "notFound"}}}"#
        let reading = try JSONDecoder().decode(UpstreamReading.self, from: Data(old.utf8))
        #expect(reading.state == .cannotCheck(.notFound))
        #expect(reading.notice == nil)
    }
}

private actor Requests {
    var requests: [URLRequest] = []
    func add(_ request: URLRequest) { requests.append(request) }
}
