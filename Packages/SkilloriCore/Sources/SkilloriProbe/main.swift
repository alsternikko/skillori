import Foundation
import SkilloriCore

// Usage: skillori-probe [--check-sources] [project-dir ...]
// Read-only. Prints what Skillori would show, for checking adapter rules against a real machine.
// With --check-sources it also asks each tracked skill's source whether it has changed. That is
// the only thing here that uses the network.
let checkSources = CommandLine.arguments.contains("--check-sources")
// With --signed-in as well, a source GitHub doesn't show signed out is asked again as you,
// with the token `gh auth token` gives, as the app does.
if CommandLine.arguments.contains("--signed-in") {
    GitHubSignIn.shared.use {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "token", "--hostname", "github.com"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0
            ? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
}
// With --find-source <repository or script address> <skill> it asks one repository which of its folders that skill
// on this Mac matches, the way "Link source" does.
var arguments = Array(CommandLine.arguments.dropFirst())
// `--read-page <address>`: what Link source finds on a page.
if let index = arguments.firstIndex(of: "--read-page"), arguments.count > index + 1,
   let url = URL(string: arguments[index + 1]) {
    switch await PageReader().leads(at: url) {
    case .success(let leads):
        if leads.isEmpty { print("Nothing on that page Skillori can follow.") }
        for lead in leads { print("\(lead.line)  →  \(lead.text)\(lead.skill.map { " (skill \($0))" } ?? "")") }
        exit(0)
    case .failure(let reason):
        print("Could not read the page: \(reason)")
        exit(1)
    }
}
// `--find-installer <site>`: the installers on npm whose homepage is that site, as Find sources offers them.
if let index = arguments.firstIndex(of: "--find-installer"), arguments.count > index + 1 {
    switch await NpmRegistry().installers(from: arguments[index + 1]) {
    case .success(let found):
        if found.isEmpty { print("No installer from \(arguments[index + 1]) on npm.") }
        for info in found {
            print("\(info.package) \(info.version ?? "?") · \(info.site?.absoluteString ?? "no site") · \(info.summary ?? "")")
        }
        exit(0)
    case .failure(let reason):
        print("No answer from npm: \(reason)")
        exit(1)
    }
}
var findSource: (repository: String, skill: String)?
if let index = arguments.firstIndex(of: "--find-source"), arguments.count > index + 2 {
    findSource = (arguments[index + 1], arguments[index + 2])
    arguments.removeSubrange(index...index + 2)
}
let projects = arguments.filter { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) }
let engine = DiscoveryEngine(home: FileManager.default.homeDirectoryForCurrentUser,
                             projects: projects, environment: ProcessInfo.processInfo.environment,
                             system: URL(fileURLWithPath: "/"))
let inventory = engine.scan()

print("Rules: \(AdapterRules.rulesVersion)")
print(String(format: "Scan: %.0f ms", inventory.duration * 1000))
print("Installations: \(inventory.installations.count) · bindings: \(inventory.bindingCount) · diagnostics: \(inventory.diagnostics.count)")
print("Lock file: \(inventory.lockFile ?? "none")\n")

var tally: [String: Int] = [:]
for inst in inventory.installations {
    let status: String
    switch inst.provenance {
    case .skillsLock(let source, _, _, _, let local):
        switch local {
        case .matchesBaseline: status = "npx skills · \(source) · matches baseline"
        case .modified: status = "npx skills · \(source) · LOCAL CHANGES"
        case .hashFailed(let e): status = "npx skills · \(source) · hash failed: \(e)"
        }
        tally["Tracked (npx skills)", default: 0] += 1
    case .managed(let owner):
        status = "Managed by \(owner)"
        tally["Managed by \(owner)", default: 0] += 1
    case .unknown:
        status = "Source unknown"
        tally["Source unknown", default: 0] += 1
    }
    if case .managed = inst.provenance { continue } // keep the listing short
    let agents = inst.agents.map(\.displayName).joined(separator: ", ")
    print("• \(inst.displayName) [\(inst.bindings.count) paths] — \(status)\n    agents: \(agents)")
}
print("\nBy provenance:")
for (k, v) in tally.sorted(by: { $0.value > $1.value }) { print("  \(v)\t\(k)") }
print("\nRoots found:")
for r in inventory.roots where r.state == .found { print("  \(r.skillCount)\t\(r.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))") }
print("Inactive roots: \(inventory.roots.filter { $0.state == .inactive }.count) · missing literal roots: \(inventory.roots.filter { $0.state == .missing }.count)")
for d in inventory.diagnostics { print("  ! \(d.message): \(d.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))") }

if checkSources {
    var questions: [UpstreamQuestion] = []
    for inst in inventory.installations {
        guard case .skillsLock(let source, let url, let subpath, let baseline, _) = inst.provenance else { continue }
        questions.append(UpstreamQuestion(key: inst.displayName,
                                          source: UpstreamSource(source: source, sourceURL: url, ref: inst.sourceRef, sourceType: inst.sourceType).map(SkillSource.github),
                                          subpath: subpath, baseline: baseline))
    }
    let answers = await UpstreamChecker.check(questions)
    print("\nSources asked: \(Set(questions.compactMap(\.source)).count)")
    for question in questions.sorted(by: { $0.key < $1.key }) {
        let text: String
        switch answers[question.key] {
        case .upToDate: text = "up to date"
        case .updateAvailable(let hash): text = "UPDATE AVAILABLE · source now \(hash.prefix(7))"
        case .cannotCheck(let reason): text = "CAN'T CHECK · \(reason.rawValue)"
        case nil: text = "no answer"
        }
        print("  \(question.key) [\(question.source?.name ?? "?")] — \(text)")
    }
}

if checkSources {
    var seen = Set<String>()
    let plugins = inventory.installations.compactMap(\.plugin).filter { seen.insert($0.id).inserted }
    var baselines: [String: String] = [:]
    let answers = await PluginChecker().check(plugins, baselines: &baselines)
    print("\nPlugins asked: \(plugins.count)")
    for plugin in plugins {
        let text: String
        switch answers[plugin.id] {
        case .upToDate: text = "up to date"
        case .updateAvailable(let hash): text = "UPDATE AVAILABLE · now \(hash.prefix(7))"
        case .cannotCheck(let reason): text = "CAN'T CHECK · \(reason.rawValue)"
        case nil: text = "no answer"
        }
        let from = plugin.repository ?? plugin.marketplaceRepository ?? "no source"
        let installed = plugin.version ?? plugin.commit.map { String($0.prefix(7)) } ?? "?"
        let off = plugin.enabled == false ? " · turned off" : ""
        print("  \(plugin.id) [\(from) · installed \(installed)\(off)] — \(text)")
    }
}

// With --find-sources it looks for where each skill with no known source came from.
if CommandLine.arguments.contains("--find-sources") {
    let finder = SourceFinder()
    var yours: [UpstreamSource] = []
    for inst in inventory.installations {
        if case .skillsLock(let source, let url, _, _, _) = inst.provenance,
           let parsed = UpstreamSource(source: source, sourceURL: url, sourceType: inst.sourceType), !yours.contains(parsed) {
            yours.append(parsed)
        }
    }
    print("\nFinding sources (your sources: \(yours.map(\.name).joined(separator: ", ")))")
    var done: Set<String> = []
    for inst in inventory.installations where inst.provenance == .unknown {
        guard let skill = try? LocalSkill(name: inst.directoryName, folder: URL(fileURLWithPath: inst.canonicalPath)),
              done.insert(inst.directoryName + skill.treeID).inserted else { continue }
        let found = await finder.proposals(for: skill, yourSources: yours)
        print("  \(inst.directoryName) · local \(skill.treeID.prefix(7))")
        if found.isEmpty { print("    nothing found") }
        for proposal in found {
            print("    \(proposal.evidence) · \(proposal.source.name)/\(proposal.subpath)\(proposal.rewritten ? " · Codex rewrite undone" : "")\(proposal.folderGone ? " · gone from source" : "") · via \(proposal.via)")
        }
    }
}

if let findSource {
    print("\nLooking for \(findSource.skill) in \(findSource.repository)")
    guard let (source, _) = SkillSource.parse(findSource.repository) else { print("  not a GitHub repository or script address"); exit(1) }
    // An installer run with your own key: nothing to compare, only npm to ask whether it exists.
    if case .package(let installer) = source {
        switch await NpmRegistry().info(for: installer.package) {
        case .failure(let reason): print("  npm: \(reason.rawValue)")
        case .success(let info):
            print("  \(info.package) \(info.version ?? "?") · site \(info.site?.absoluteString ?? "none") · \(info.summary ?? "")")
            print("  Link it in the app; it is never asked, and updates by running the installer again.")
        }
        exit(0)
    }
    let matches = inventory.installations.filter { $0.directoryName == findSource.skill && $0.provenance == .unknown }
    guard !matches.isEmpty else { print("  no skill with that folder name and no known source"); exit(1) }
    let answer: Result<SourceTree, UpstreamState.Reason> = switch source {
    case .github(let repository): await GitHubTrees().tree(of: repository)
    case .installer(let script): await InstallerScripts().tree(of: script)
    case .package: .failure(.unsupported)
    }
    switch answer {
    case .failure(let reason): print("  can't ask the source: \(reason.rawValue)")
    case .success(let tree):
        for inst in matches {
            let local = try? GitTreeHash.hashDirectory(at: URL(fileURLWithPath: inst.canonicalPath)).treeID
            let found = SourceMatcher.candidates(localHash: local, names: [inst.directoryName, inst.displayName], in: tree)
            print("  \(inst.canonicalPath) · local \((local ?? "?").prefix(7)) · \(found.count) skill folders in source")
            for candidate in found.prefix(3) {
                print("    \(candidate.match) · \(candidate.subpath) · \(candidate.hash.prefix(7))")
            }
        }
    }
}
