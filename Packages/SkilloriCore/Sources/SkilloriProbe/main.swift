import Foundation
import SkilloriCore

// Usage: skillori-probe [--check-sources] [project-dir ...]
// Read-only. Prints what Skillori would show, for checking adapter rules against a real machine.
// With --check-sources it also asks each tracked skill's source whether it has changed. That is
// the only thing here that uses the network.
let checkSources = CommandLine.arguments.contains("--check-sources")
// With --find-source <repository> <skill> it asks one repository which of its folders that skill
// on this Mac matches, the way "Link source" does.
var arguments = Array(CommandLine.arguments.dropFirst())
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
                                          source: UpstreamSource(source: source, sourceURL: url, ref: inst.sourceRef),
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

if let findSource {
    print("\nLooking for \(findSource.skill) in \(findSource.repository)")
    guard let (source, _) = UpstreamSource.parse(findSource.repository) else { print("  not a GitHub repository"); exit(1) }
    let matches = inventory.installations.filter { $0.directoryName == findSource.skill && $0.provenance == .unknown }
    guard !matches.isEmpty else { print("  no skill with that folder name and no known source"); exit(1) }
    switch await GitHubTrees().tree(of: source) {
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
