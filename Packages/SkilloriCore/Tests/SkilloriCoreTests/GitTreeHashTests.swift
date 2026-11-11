import Foundation
import Testing
@testable import SkilloriCore

@Suite struct GitTreeHashTests {
    @Test func matchesGitForMixedContent() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file("SKILL.md", "---\nname: x\n---\nbody\n")
        try tree.file("scripts/run.sh", "#!/bin/sh\necho hi\n", executable: true)
        try tree.file("references/deep/notes.md", "deep\n")
        // Names that exercise git's "directories sort as name/" rule.
        try tree.file("a.b", "file a.b\n")
        try tree.file("a/inner.txt", "dir a\n")
        try tree.file("a-b", "file a-b\n")
        try tree.link("link-to-skill", to: "SKILL.md")
        try tree.dir("empty-dir")
        try tree.file("unicode-å.txt", "å\n")

        let ours = try GitTreeHash.hashDirectory(at: tree.root)
        let reference = try referenceTreeHash(of: tree.root)
        #expect(ours.treeID == reference, "entries: \(ours.entries.map(\.path))")
        #expect(ours.entries.contains { $0.path == "scripts/run.sh" && $0.kind == .executable })
        #expect(ours.entries.contains { $0.path == "link-to-skill" && $0.kind == .symlink })
    }

    @Test func ignoresFinderMetadata() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file("SKILL.md", "x\n")
        let before = try GitTreeHash.hashDirectory(at: tree.root).treeID
        try tree.file(".DS_Store", "finder noise")
        #expect(try GitTreeHash.hashDirectory(at: tree.root).treeID == before)
    }

    @Test func contentChangeChangesHash() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file("SKILL.md", "one\n")
        let first = try GitTreeHash.hashDirectory(at: tree.root).treeID
        try tree.file("SKILL.md", "two\n")
        #expect(try GitTreeHash.hashDirectory(at: tree.root).treeID != first)
    }

    @Test func emptyDirectoryIsEmptyTree() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        #expect(try GitTreeHash.hashDirectory(at: tree.root).treeID == "4b825dc642cb6eb9a060e54bf8d69288fbee4904")
    }
}

@Suite struct FrontmatterTests {
    @Test func parsesSimpleAndQuotedValues() {
        let fm = SkillFrontmatter.parse("---\nname: \"my-skill\"\ndescription: >\n  Folded line one\n  and two\nlicense: MIT\n---\nBody")
        #expect(fm.name == "my-skill")
        #expect(fm.description == "Folded line one and two")
        #expect(fm.fields["license"] == "MIT")
        #expect(fm.problems.isEmpty)
    }

    @Test func reportsProblemsWithoutFailing() {
        let fm = SkillFrontmatter.parse("# Just markdown\n$(rm -rf /)\n")
        #expect(fm.name == nil)
        #expect(fm.problems.contains("Missing front matter"))
    }
}
