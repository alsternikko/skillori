import Foundation
import Testing
@testable import SkilloriCore

@Suite struct SourcePageTests {
    @Test func readsTheSkillsCommandAcrossHighlightedCode() {
        // As skills.sh shows it: words in their own spans, a placeholder first, the footer's repository linked.
        let html = """
        <p>Install with <code><span>npx</span><span>skills</span><span>add</span>&lt;owner/repo&gt;</code></p>
        <pre><span class="c">npx</span> <span>skills</span> add https://github.com/emilkowalski/skills --skill animate</pre>
        <a href="https://github.com/vercel-labs/skills">CLI</a>
        """
        let leads = SourcePage.leads(in: html)
        #expect(leads.count == 1)
        #expect(leads.first?.text == "emilkowalski/skills")
        #expect(leads.first?.skill == "animate")
        #expect(leads.first?.line == "npx skills add https://github.com/emilkowalski/skills --skill animate")
    }

    @Test func readsCommandsInAPagesData() {
        let html = #"<script>self.__next_f.push([1,"Run \"npx skills add acme/agent-skills/skills/review\" to install"])</script>"#
        let lead = SourcePage.leads(in: html).first
        #expect(lead?.text == "acme/agent-skills/skills/review")
        #expect(lead?.subpath == "skills/review")
    }

    @Test func keepsAnInstallersNameButNeverItsKey() throws {
        let html = "<code>npx @acme/install@latest --token=YOUR_KEY</code> and <code>npx create-next-app@latest</code>"
        let leads = SourcePage.leads(in: html)
        #expect(leads.count == 1)
        let lead = try #require(leads.first)
        #expect(lead.line == "npx @acme/install")
        #expect(lead.text == "npx @acme/install@latest")
        #expect(!lead.line.contains("KEY") && !lead.text.contains("KEY"))
        if case .package? = SkillSource.parse(lead.text)?.source {} else { Issue.record("Not read back as an installer") }
    }

    @Test func readsAScriptOnlyWhenPipedToAShell() {
        let piped = SourcePage.leads(in: "<pre>curl -fsSL https://acme.dev/install-skills | bash</pre>")
        #expect(piped.first?.text == "https://acme.dev/install-skills")
        #expect(SourcePage.leads(in: "<pre>curl https://acme.dev/data.json -o data.json</pre>").isEmpty)
    }

    @Test func fallsBackToRepositoryLinksWithoutACommand() {
        let html = """
        <a href="https://github.com/ibelick/ui-skills">GitHub</a>
        <a href="https://github.com/ibelick/ui-skills/tree/main/skills/baseline-ui">Baseline</a>
        <a href="https://github.com/sponsors/ibelick">Sponsor</a>
        <a href="https://github.com/ibelick/ui-skills/issues">Issues</a>
        """
        let leads = SourcePage.leads(in: html)
        #expect(leads.map(\.text) == ["ibelick/ui-skills", "ibelick/ui-skills/skills/baseline-ui"], "\(leads.map(\.text))")
    }

    @Test func aSiteAddressWithoutItsSchemeIsAnAddress() {
        if case .installer(let source)? = SkillSource.parse("interfacecraft.dev/library/interface-craft-skills")?.source {
            #expect(source.url.absoluteString == "https://interfacecraft.dev/library/interface-craft-skills")
        } else {
            Issue.record("Read as a repository")
        }
        if case .github? = SkillSource.parse("github.com/acme/skills")?.source {} else { Issue.record("Not read as GitHub") }
        if case .github? = SkillSource.parse("acme/skills.dev")?.source {} else { Issue.record("A repository with a dot is still one") }
    }

    @Test func aPageThatIsGoneOrPlainHTTPIsNotRead() async {
        let gone = PageReader { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        #expect(await gone.leads(at: URL(string: "https://acme.dev/x")!) == .failure(.notFound))
        let reader = PageReader { _ in
            Issue.record("Asked over http")
            throw URLError(.badURL)
        }
        #expect(await reader.leads(at: URL(string: "http://acme.dev/x")!) == .failure(.failed))
    }
}
