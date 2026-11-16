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
        // Front matter sits at the top and is usually a few hundred bytes. Read in small pieces
        // and stop once the closing line has arrived, instead of reading the whole body.
        var data = Data()
        while data.count < maxBytes {
            guard let piece = try? handle.read(upToCount: min(chunk, maxBytes - data.count)), !piece.isEmpty else { break }
            let searchFrom = max(data.count - 5, 0)
            data.append(piece)
            if hasClosingLine(data, from: searchFrom) { break }
        }
        return parse(String(decoding: data, as: UTF8.self))
    }

    private static let chunk = 4096

    /// Whether `data`, which starts with the opening `---`, has its closing `---` line yet.
    /// Searches only from `start`, so each piece is looked at once.
    static func hasClosingLine(_ data: Data, from start: Int) -> Bool {
        let bytes = [UInt8]("\n---".utf8)
        guard data.count >= 4 else { return false }
        // The opening line itself must not count as the closing one.
        let first = data.firstIndex(of: UInt8(ascii: "\n")).map { data.distance(from: data.startIndex, to: $0) } ?? data.count
        var index = max(start, first)
        while index + bytes.count <= data.count {
            let at = data.index(data.startIndex, offsetBy: index)
            if data[at..<data.index(at, offsetBy: bytes.count)].elementsEqual(bytes) {
                // `---` and then the end of the line. At the end of what has been read, the next
                // piece decides, so a longer line of dashes is not taken for the closing one.
                let after = data.index(at, offsetBy: bytes.count)
                if after != data.endIndex, data[after] == UInt8(ascii: "\n") || data[after] == UInt8(ascii: "\r") { return true }
            }
            index += 1
        }
        return false
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
