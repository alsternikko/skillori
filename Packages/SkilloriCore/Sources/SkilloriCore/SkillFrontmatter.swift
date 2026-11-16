import Foundation

/// The parts of a `SKILL.md` front matter block that Skillori displays.
///
/// The file is untrusted data. This parser only reads simple `key: value` lines between the
/// opening and closing `---` and never evaluates anything. Fields it does not understand are
/// kept as raw strings. It is deliberately not a full YAML parser (spike scope).
public struct SkillFrontmatter: Sendable, Equatable {
    public var name: String?
    public var description: String?
    public var fields: [String: String]
    public var problems: [String]

    public static let maxBytes = 256 * 1024

    public static func parse(fileAt url: URL) -> SkillFrontmatter {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return SkillFrontmatter(name: nil, description: nil, fields: [:], problems: ["Can't read SKILL.md"])
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maxBytes)) ?? Data()
        return parse(String(decoding: data, as: UTF8.self))
    }

    public static func parse(_ text: String) -> SkillFrontmatter {
        var result = SkillFrontmatter(name: nil, description: nil, fields: [:], problems: [])
        // Editors on Windows often start a UTF-8 file with a byte order mark.
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            result.problems.append("Missing front matter")
            return result
        }

        var currentKey: String?
        var closed = false
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { closed = true; break }
            if let first = line.first, first == " " || first == "\t" {
                // Continuation of a folded or block value.
                if let key = currentKey {
                    let existing = result.fields[key] ?? ""
                    result.fields[key] = existing.isEmpty ? trimmed : existing + " " + trimmed
                }
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if [">", "|", ">-", "|-"].contains(value) { value = "" }
            value = unquote(value)
            result.fields[key] = value
            currentKey = key
        }

        if !closed { result.problems.append("Front matter is not closed") }
        result.name = result.fields["name"].flatMap { $0.isEmpty ? nil : $0 }
        result.description = result.fields["description"].flatMap { $0.isEmpty ? nil : $0 }
        if result.name == nil { result.problems.append("Missing name") }
        if result.description == nil { result.problems.append("Missing description") }
        return result
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else { return value }
        return String(value.dropFirst().dropLast())
    }
}
