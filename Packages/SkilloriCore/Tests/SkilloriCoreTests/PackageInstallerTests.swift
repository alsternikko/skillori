import Foundation
import Testing
@testable import SkilloriCore

@Suite struct PackageInstallerTests {
    @Test func readsThePastedCommandAndDropsTheKey() throws {
        let line = "npx @interfacecraft/install@latest --token=eyJ1aWQiOiJzZWNyZXQifQ.c2lnbmF0dXJl"
        let installer = try #require(PackageInstaller(line))
        #expect(installer.package == "@interfacecraft/install")
        #expect(installer.command == "npx @interfacecraft/install@latest")
        #expect(!String(describing: installer).contains("eyJ"))
        guard case .package(let parsed)? = SkillSource.parse(line)?.source else {
            Issue.record("Read as another kind of source")
            return
        }
        #expect(parsed == installer)
    }

    @Test func readsOtherRunnersAndFlags() {
        #expect(PackageInstaller("npx -y @acme/skills-install --token abc")?.package == "@acme/skills-install")
        #expect(PackageInstaller("bunx @acme/install@1.2.0")?.package == "@acme/install")
        #expect(PackageInstaller("pnpm dlx acme-install@latest")?.package == "acme-install")
        #expect(PackageInstaller("  @Acme/Install  ")?.package == "@acme/install")
    }

    @Test func leavesRepositoriesAndScriptsToTheirOwnKinds() {
        #expect(PackageInstaller("owner/repo") == nil)
        #expect(PackageInstaller("npx skills@latest add joshpuckett/skills") == nil)
        #expect(PackageInstaller("curl -fsSL https://example.com/install | bash") == nil)
        #expect(PackageInstaller("pnpm install @acme/install") == nil)
        #expect(PackageInstaller("npx") == nil)
        #expect(PackageInstaller("npx ../evil") == nil)
        if case .github? = SkillSource.parse("joshpuckett/skills")?.source {} else { Issue.record("Not read as GitHub") }
        if case .installer? = SkillSource.parse("curl -fsSL https://example.com/install | bash")?.source {} else {
            Issue.record("Not read as a script")
        }
    }

    @Test func namesTheSiteWhenThePackageGivesOne() {
        let bare = PackageInstaller(package: "@acme/install")
        #expect(bare.name == "@acme/install")
        #expect(SkillSource.package(bare).webURL() == URL(string: "https://www.npmjs.com/package/@acme/install"))
        let sited = PackageInstaller(package: "@acme/install", site: URL(string: "https://www.acme.dev"))
        #expect(sited.name == "acme.dev")
        #expect(SkillSource.package(sited).webURL() == URL(string: "https://www.acme.dev"))
        #expect(SkillSource.package(sited).historyURL(subpath: nil) == nil)
    }

    @Test func asksTheRegistryForThePackageOnly() async throws {
        let body = #"{"name":"@acme/install","version":"0.1.0","description":"Installs skills.","homepage":"https://www.acme.dev#readme"}"#
        let asked = Asked()
        let registry = NpmRegistry { request in
            await asked.set(request.url)
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let info = try await registry.info(for: "@acme/install").get()
        #expect(await asked.url?.absoluteString == "https://registry.npmjs.org/@acme%2Finstall/latest")
        #expect(info.version == "0.1.0")
        #expect(info.summary == "Installs skills.")
        #expect(info.site == URL(string: "https://www.acme.dev"))
    }

    @Test func aMissingPackageIsNotFoundAndAPlainHomepageIsLeftOut() async throws {
        let missing = NpmRegistry { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        #expect(await missing.info(for: "@acme/none") == .failure(.notFound))
        let body = #"{"name":"acme","homepage":"http://acme.dev"}"#
        let plain = NpmRegistry { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(try await plain.info(for: "acme").get().site == nil)
    }

    @Test func searchesBySiteNameOnly() throws {
        let request = try #require(NpmRegistry.searchRequest(for: "www.InterfaceCraft.dev"))
        #expect(request.url?.absoluteString == "https://registry.npmjs.org/-/v1/search?text=interfacecraft&size=20")
        #expect(NpmRegistry.searchRequest(for: "localhost") == nil)
    }

    @Test func offersOnlyInstallersWhoseHomepageIsTheSite() async throws {
        let body = #"""
        {"objects":[
          {"package":{"name":"@banjerluke/dialkit","description":"Real-time parameter tweaking","links":{"homepage":"https://github.com/joshpuckett/dialkit#readme"}}},
          {"package":{"name":"@acme/install","version":"0.1.0","description":"Installs the Acme members' agent skills.","links":{"homepage":"https://www.acme.dev#top"}}},
          {"package":{"name":"acme-ui","description":"Buttons and cards.","links":{"homepage":"https://acme.dev"}}},
          {"package":{"name":"skills","description":"Install agent skills","links":{"homepage":"https://acme.dev"}}},
          {"package":{"name":"@acme/plain","description":"Installs skills","links":{"homepage":"http://acme.dev"}}}
        ]}
        """#
        let asked = Asked()
        let registry = NpmRegistry { request in
            await asked.set(request.url)
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let found = try await registry.installers(from: "acme.dev").get()
        #expect(found.map(\.package) == ["@acme/install"])
        #expect(found.first?.site == URL(string: "https://www.acme.dev"))
        #expect(found.first?.installer.name == "acme.dev")
        #expect(await asked.url?.query == "text=acme&size=20")
    }

    @Test func keepsWhatFollowsThePackageOnlyWhenAsked() {
        let line = "npx -y @acme/install@latest --token=s3cret --agent claude && rm -rf ~"
        #expect(PackageInstaller.arguments(in: line) == ["--token=s3cret", "--agent", "claude"])
        #expect(PackageInstaller.arguments(in: "pnpm dlx @acme/install --token s3cret") == ["--token", "s3cret"])
        #expect(PackageInstaller.arguments(in: "npx @acme/install@latest") == nil)
        #expect(PackageInstaller.arguments(in: "@acme/install") == nil)
        #expect(PackageInstaller.arguments(in: "owner/repo --token=x") == nil)
        #expect(PackageInstaller.masked(["--token=s3cret", "--agent", "claude"]) == "--token=… --agent …")
        #expect(!PackageInstaller.masked(["--token", "s3cret"]).contains("s3cret"))
    }

    @Test func theCheckerNeverAsksAPackage() async {
        let question = UpstreamQuestion(key: "k", source: .package(PackageInstaller(package: "@acme/install")),
                                        subpath: nil, baseline: nil)
        let answers = await UpstreamChecker.check([question], using: GitHubTrees { _ in
            Issue.record("Asked GitHub")
            throw URLError(.badURL)
        }, installers: InstallerScripts { _ in
            Issue.record("Asked a site")
            throw URLError(.badURL)
        })
        #expect(answers["k"] == .cannotCheck(.unsupported))
    }
}

private actor Asked {
    var url: URL?
    func set(_ url: URL?) { self.url = url }
}
