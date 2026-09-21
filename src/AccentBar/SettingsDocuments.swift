import Foundation

func settingsError(_ message: String) -> NSError {
    NSError(domain: "AccentBar.Settings", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

/// UTF-8 offsets let us replace only the selected setting, preserving all other
/// bytes (including Korean comments, line endings, and unrelated credentials).
struct JSONCDocument {
    let bytes: [UInt8]
    let masked: [UInt8]
    let object: [String: Any]

    init(_ text: String) throws {
        bytes = Array(text.utf8)
        var clean = bytes
        var i = 0
        while i < clean.count {
            if bytes[i] == 34 {
                i = try Self.stringEnd(bytes, i)
            } else if i + 1 < bytes.count && bytes[i] == 47 && [47, 42].contains(bytes[i + 1]) {
                let start = i
                if bytes[i + 1] == 47 {
                    while i < bytes.count && bytes[i] != 10 { i += 1 }
                } else {
                    i += 2
                    while i + 1 < bytes.count && !(bytes[i] == 42 && bytes[i + 1] == 47) { i += 1 }
                    guard i + 1 < bytes.count else { throw settingsError("닫히지 않은 JSONC 주석입니다.") }
                    i += 2
                }
                for p in start..<i where ![10, 13].contains(bytes[p]) { clean[p] = 32 }
            } else { i += 1 }
        }
        masked = clean
        i = 0
        while i < clean.count {
            if clean[i] == 34 { i = try Self.stringEnd(clean, i); continue }
            if clean[i] == 44 {
                var next = i + 1
                while next < clean.count && Self.space(clean[next]) { next += 1 }
                if next < clean.count && [93, 125].contains(clean[next]) { clean[i] = 32 }
            }
            i += 1
        }
        guard let parsed = try JSONSerialization.jsonObject(with: Data(clean)) as? [String: Any] else {
            throw settingsError("VS Code 설정은 JSON 객체여야 합니다.")
        }
        object = parsed
    }

    static func space(_ byte: UInt8) -> Bool { [9, 10, 13, 32].contains(byte) }
    static func stringEnd(_ bytes: [UInt8], _ start: Int) throws -> Int {
        var i = start + 1
        while i < bytes.count {
            if bytes[i] == 92 { i += 2 }
            else if bytes[i] == 34 { return i + 1 }
            else { i += 1 }
        }
        throw settingsError("닫히지 않은 JSON 문자열입니다.")
    }

    func colorsRange() throws -> Range<Int> {
        var i = 0, depth = 0
        var ranges = [Range<Int>]()
        while i < masked.count {
            let byte = masked[i]
            if byte == 34 {
                let end = try Self.stringEnd(masked, i)
                if depth == 1 {
                    let key = try JSONSerialization.jsonObject(with: Data(masked[i..<end]), options: [.fragmentsAllowed]) as? String
                    if key == "workbench.colorCustomizations" {
                        var start = end
                        while start < masked.count && Self.space(masked[start]) { start += 1 }
                        guard start < masked.count && masked[start] == 58 else { throw settingsError("VS Code 색상 설정 형식이 올바르지 않습니다.") }
                        start += 1
                        while start < masked.count && Self.space(masked[start]) { start += 1 }
                        guard start < masked.count && masked[start] == 123 else { throw settingsError("VS Code 색상 설정은 객체여야 합니다.") }
                        var p = start, nesting = 0
                        while p < masked.count {
                            if masked[p] == 34 { p = try Self.stringEnd(masked, p); continue }
                            if [123, 91].contains(masked[p]) { nesting += 1 }
                            if [125, 93].contains(masked[p]) {
                                nesting -= 1
                                if nesting == 0 { ranges.append(start..<(p + 1)); break }
                            }
                            p += 1
                        }
                    }
                }
                i = end; continue
            }
            if [123, 91].contains(byte) { depth += 1 }
            if [125, 93].contains(byte) { depth -= 1 }
            i += 1
        }
        guard ranges.count == 1 else { throw settingsError("VS Code의 workbench.colorCustomizations 항목을 정확히 찾지 못했습니다.") }
        return ranges[0]
    }

    func replacingColors(_ replacement: String) throws -> String {
        let range = try colorsRange()
        let oldText = String(decoding: bytes, as: UTF8.self)
        var replacement = replacement.trimmingCharacters(in: .newlines)
        if oldText.contains("\r\n") { replacement = replacement.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n") }
        var updated = bytes
        updated.replaceSubrange(range, with: replacement.utf8)
        let result = String(decoding: updated, as: UTF8.self)
        var expected = object
        expected["workbench.colorCustomizations"] = try JSONCDocument(replacement).object
        guard NSDictionary(dictionary: try JSONCDocument(result).object).isEqual(to: expected) else {
            throw settingsError("VS Code 색상 이외의 설정 변경이 감지되어 중단했습니다.")
        }
        return result
    }
}

/// A targeted TOML editor, not a reserializer. A lexical scanner recognizes
/// whole statements so section-like text in comments, arrays, and multiline
/// strings can never be mistaken for the real desktop theme sections.
struct CodexThemeDocument {
    static let themes = ["appearanceLightChromeTheme", "appearanceDarkChromeTheme"]
    struct Field { let range: Range<Int>; let value: String }
    let bytes: [UInt8]
    let fields: [String: [String: Field]]

    init(_ text: String) throws {
        bytes = Array(text.utf8)
        var found = [String: [String: Field]]()
        var section: String?
        for range in try Self.statements(bytes) {
            let raw = String(decoding: bytes[range], as: UTF8.self)
            let header = try NSRegularExpression(pattern: "^\\s*\\[([^\\r\\n]+)\\][ \\t]*(?:#[^\\r\\n]*)?[\\r\\n]*$")
            if let match = header.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)), let keyRange = Range(match.range(at: 1), in: raw) {
                let key = String(raw[keyRange]).trimmingCharacters(in: .whitespaces)
                section = Self.themes.first { "desktop." + $0 == key }
                if let section {
                    guard found[section] == nil else { throw settingsError("Codex 색상 섹션이 중복되어 있습니다.") }
                    found[section] = [:]
                }
                continue
            }
            guard let section else { continue }
            let pattern = #"\A[ \t]*(accent|accentSource)[ \t]*=[ \t]*("(?:\\.|[^"\\])*"|'[^']*')[ \t]*(?:#[^\r\n]*)?[\r\n]*\z"#
            let regex = try NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                  let keyRange = Range(match.range(at: 1), in: raw), let valueRange = Range(match.range(at: 2), in: raw) else { continue }
            let key = String(raw[keyRange]), quoted = String(raw[valueRange])
            guard found[section]?[key] == nil else { throw settingsError("Codex 색상 항목이 중복되어 있습니다.") }
            let value: String
            if quoted.first == "'" { value = String(quoted.dropFirst().dropLast()) }
            else {
                guard let decoded = try JSONSerialization.jsonObject(with: Data(quoted.utf8), options: [.fragmentsAllowed]) as? String else { throw settingsError("Codex 색상 문자열을 읽지 못했습니다.") }
                value = decoded
            }
            let start = range.lowerBound + raw[..<valueRange.lowerBound].utf8.count
            found[section]?[key] = Field(range: start..<(start + quoted.utf8.count), value: value)
        }
        for theme in Self.themes {
            guard found[theme]?["accent"] != nil, found[theme]?["accentSource"] != nil else {
                throw settingsError("Codex에서 강조색을 한 번 선택한 뒤 다시 실행하세요: " + theme)
            }
        }
        fields = found
    }

    func replacingAccents(_ accents: [String: [String: String]]) throws -> String {
        var changes = [(Range<Int>, [UInt8])]()
        for theme in Self.themes {
            guard let accent = accents[theme]?["accent"], accent.range(of: #"\A#[0-9a-fA-F]{6}\z"#, options: .regularExpression) != nil,
                  accents[theme]?["accentSource"] == "custom" else { throw settingsError("Codex 색상 구성이 올바르지 않습니다.") }
            for key in ["accent", "accentSource"] {
                let value = accents[theme]![key]!
                changes.append((fields[theme]![key]!.range, Array(("\"" + value + "\"").utf8)))
            }
        }
        var updated = bytes
        for (range, value) in changes.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) { updated.replaceSubrange(range, with: value) }
        let result = String(decoding: updated, as: UTF8.self)
        let check = try Self(result)
        for theme in Self.themes {
            for key in ["accent", "accentSource"] where check.fields[theme]?[key]?.value != accents[theme]?[key] {
                throw settingsError("Codex 색상 저장 내용을 확인하지 못했습니다.")
            }
        }
        return result
    }

    private static func statements(_ bytes: [UInt8]) throws -> [Range<Int>] {
        var result = [Range<Int>]()
        var i = 0, start = 0, depth = 0
        var quote: UInt8?, triple = false, comment = false
        while i < bytes.count {
            let c = bytes[i]
            if comment {
                if c != 10 { i += 1; continue }
                comment = false
            } else if let q = quote {
                if q == 34 && c == 92 { i += 2; continue }
                if c == q {
                    if triple {
                        if i + 2 < bytes.count && bytes[i + 1] == q && bytes[i + 2] == q {
                            i += 3
                            while i < bytes.count && bytes[i] == q { i += 1 }
                            quote = nil; triple = false; continue
                        }
                    } else { quote = nil }
                } else if c == 10 && !triple { throw settingsError("Codex 설정의 문자열이 닫히지 않았습니다.") }
                i += 1; continue
            } else {
                if c == 35 { comment = true; i += 1; continue }
                if c == 34 || c == 39 {
                    quote = c
                    triple = i + 2 < bytes.count && bytes[i + 1] == c && bytes[i + 2] == c
                    i += triple ? 3 : 1; continue
                }
                if [91, 123].contains(c) { depth += 1 }
                if [93, 125].contains(c) { depth -= 1 }
                guard depth >= 0 else { throw settingsError("Codex 설정의 괄호 형식을 확인해 주세요.") }
            }
            if c == 10 && depth == 0 {
                result.append(start..<(i + 1)); start = i + 1
            }
            i += 1
        }
        guard quote == nil && depth == 0 else { throw settingsError("Codex 설정에 닫히지 않은 문자열 또는 괄호가 있습니다.") }
        if start < bytes.count { result.append(start..<bytes.count) }
        return result
    }
}
