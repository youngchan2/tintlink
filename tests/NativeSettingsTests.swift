import Foundation

final class FakeAccent: SystemAccentAccess {
    var state: AccentPreferences = ["AppleAccentColor": AccentPreference(present: true, value: 2), "AppleAquaColorVariant": AccentPreference(present: true, value: 1)]
    var failAfterWrite = false
    var concurrentWrite = false
    func read() throws -> AccentPreferences { state }
    func write(_ value: AccentPreferences) throws {
        state = value
        if concurrentWrite {
            state["AppleAccentColor"] = AccentPreference(present: true, value: 6)
            throw settingsError("concurrent change")
        }
        if failAfterWrite && value["AppleAccentColor"]?.value != 2 { throw settingsError("simulated write failure") }
    }
}

final class FaultFiles: SettingsFileAccess {
    let normal = AtomicSettingsFiles()
    var failPath: URL?
    var concurrentPath: URL?
    func read(_ path: URL) throws -> Data { try normal.read(path) }
    func write(_ path: URL, data: Data) throws {
        if path == failPath {
            if let concurrentPath { try normal.write(concurrentPath, data: Data("external editor contents".utf8)) }
            throw settingsError("simulated file failure")
        }
        try normal.write(path, data: data)
    }
}

@main struct NativeSettingsTests {
    static var checks = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try value() else { throw settingsError(message) }
    }
    static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        checks += 1
        do { try operation() } catch { return }
        throw settingsError("Expected rejection: " + message)
    }
    static func write(_ text: String, _ path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: path)
    }
    static func writeJSON(_ object: Any, _ path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: path)
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AccentBar-native-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "src/AccentBar/Presets")
        let fake = FakeAccent(), io = FaultFiles()
        let engine = NativeSettings(home: root, resources: resources, codexHome: nil, system: fake, files: io)
        let vs = engine.paths["vscode"]!, codex = engine.paths["codex"]!
        let themeBlocks = CodexThemeDocument.themes.map {
            "[desktop.\($0)] # 테마\naccent = '#ffcc00' # 색상\naccentSource = \"custom\"\nsurface=\"#181818\"\n"
        }.joined()
        // Fake headers and keys inside multiline strings/arrays must be inert.
        let preamble = "model=\"test-model\"\nnotes = \"\"\"\n[desktop.appearanceDarkChromeTheme]\naccent = '#badbad'\n\"\"\"\narray=[\n\"accent = '#badbad'\",\n]\n"
        let originalCodex = (preamble + themeBlocks + "[other]\naccent='keep'\n").replacingOccurrences(of: "\n", with: "\r\n")
        let originalVS = "{\r\n// 메모는 보존\r\n\"workbench.colorTheme\":\"Dark Modern\",\r\n\"url\":\"https://example.test/a/*b*/\",\r\n\"nested\":{\"workbench.colorCustomizations\":{\"keep\":1}},\r\n\"workbench.colorCustomizations\":{\"[Dark Modern]\":{\"focusBorder\":\"#ffcc00\",},},\r\n\"editor.fontSize\":16,\r\n}\r\n"
        try write(originalVS, vs); try write(originalCodex, codex)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: vs.path)
        var cache: [String: Any] = ["profile": ["last_used": "Profile 2", "info_cache": ["Default": ["name": "개인 작업용 💛"], "Profile 2": ["name": "친구의 업무"]]]]
        let local = engine.chromeRoot.appendingPathComponent("Local State")
        let prefs1 = engine.chromeRoot.appendingPathComponent("Default/Preferences")
        let prefs2 = engine.chromeRoot.appendingPathComponent("Profile 2/Preferences")
        try writeJSON(cache, local)
        try writeJSON(["browser": ["theme": ["user_color2": -1536]], "account_values": ["browser": ["theme": ["user_color": -1536]]], "sync": ["keep_everything_synced": true]], prefs1)
        try writeJSON(["browser": ["theme": ["is_grayscale2": true]]], prefs2)
        let chromeBefore = try [prefs1: Data(contentsOf: prefs1), prefs2: Data(contentsOf: prefs2)]
        let initial = try engine.run(["action": "status"])
        try check(initial.chromeProfileIDs == ["Profile 2"], "First run uses this user's last-used profile")
        try check(initial.chromeProfiles?.map(\.label) == ["개인 작업용 💛", "친구의 업무"], "Custom profile names")
        try check(initial.rows?.allSatisfy(\.available) == true, "All configured apps available")
        try check(try String(contentsOf: vs, encoding: .utf8) == originalVS, "Status is read only")
        try check(try String(contentsOf: codex, encoding: .utf8) == originalCodex, "Status preserves Codex")
        try check(try engine.run(["action": "status", "chromeProfileIDs": []]).chromeProfileIDs == [], "Explicit empty selection is kept")

        for palette in Palette.all {
            let result = try engine.run(["action": "apply", "color": palette.id, "targets": ["system", "vscode", "codex", "chrome"], "chromeProfileIDs": ["Profile 2", "Default"]])
            try check(result.ok && result.chromeUIActions?.map(\.profile) == ["Default", "Profile 2"], "Prepare both Chrome profiles in stable order")
            try check(result.chromeUIActions?.allSatisfy { $0.hex == palette.hex } == true, "Correct Chrome request color")
            let vsText = try String(contentsOf: vs, encoding: .utf8)
            let doc = try JSONCDocument(vsText)
            let colors = (doc.object["workbench.colorCustomizations"] as? [String: Any])?["[Dark Modern]"] as? [String: Any]
            try check(colors?["editor.selectionBackground"] as? String == palette.hex.lowercased() + "66", "Selection color preserved in all presets")
            try check(doc.object["editor.fontSize"] as? Int == 16 && vsText.contains("// 메모는 보존\r\n"), "Other settings and CRLF comments preserved")
            let newCodex = try String(contentsOf: codex, encoding: .utf8)
            try check(newCodex.hasPrefix(preamble.replacingOccurrences(of: "\n", with: "\r\n")), "Multiline fake TOML headers are untouched")
            try check(newCodex.hasSuffix("[other]\r\naccent='keep'\r\n"), "Unrelated TOML sections preserved")
            let cd = try CodexThemeDocument(newCodex)
            try check(CodexThemeDocument.themes.allSatisfy { cd.fields[$0]?["accent"]?.value == palette.hex.lowercased() }, "Both Codex themes changed")
            try check(fake.state["AppleAccentColor"]?.value == NativeSettings.systemIDs.firstIndex(of: palette.id), "System preset identity")
        }
        try check((try FileManager.default.attributesOfItem(atPath: vs.path)[.posixPermissions] as? NSNumber)?.intValue == 0o640, "Atomic replacement preserves permissions")
        for (path, data) in chromeBefore { try check(try Data(contentsOf: path) == data, "Native backend must never write Chrome/account preferences") }
        let contents = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Library/Application Support/AccentBar").path)
        try check(contents == [".lock"], "No color history or backup files")

        fake.state["AppleAccentColor"] = AccentPreference(present: true, value: 5)
        let beforeImport = try Data(contentsOf: vs)
        _ = try engine.run(["action": "system", "targets": ["system", "codex", "chrome"], "chromeProfileIDs": ["Default"]])
        try check(try Data(contentsOf: vs) == beforeImport, "System import changes only selected apps")
        try check(fake.state["AppleAccentColor"]?.value == 5, "System import does not rewrite the system")
        fake.state["AppleAccentColor"] = AccentPreference(present: true, value: -1)
        try rejects("gray system import") { _ = try engine.run(["action": "system", "targets": ["codex"]]) }

        try write(originalVS, vs); try write(originalCodex, codex)
        fake.state["AppleAccentColor"] = AccentPreference(present: true, value: 2)
        fake.failAfterWrite = true
        try rejects("system failure rolls files back") { _ = try engine.run(["action": "apply", "color": "blue", "targets": ["system", "vscode", "codex"]]) }
        try check(try String(contentsOf: vs, encoding: .utf8) == originalVS, "VS Code rolled back")
        try check(try String(contentsOf: codex, encoding: .utf8) == originalCodex, "Codex rolled back")
        try check(fake.state["AppleAccentColor"]?.value == 2, "System rolled back")
        fake.failAfterWrite = false; fake.concurrentWrite = true
        try rejects("external system update") { _ = try engine.run(["action": "apply", "color": "blue", "targets": ["system", "vscode", "codex"]]) }
        try check(fake.state["AppleAccentColor"]?.value == 6, "Never undo another app's system change")
        fake.concurrentWrite = false
        io.failPath = codex
        try rejects("second file failure") { _ = try engine.run(["action": "apply", "color": "red", "targets": ["vscode", "codex"]]) }
        try check(try String(contentsOf: vs, encoding: .utf8) == originalVS, "First file rolled back when second fails")
        io.concurrentPath = vs
        try rejects("concurrent editor save") { _ = try engine.run(["action": "apply", "color": "red", "targets": ["vscode", "codex"]]) }
        try check(try String(contentsOf: vs, encoding: .utf8) == "external editor contents", "Rollback preserves a concurrent editor save")
        io.failPath = nil; io.concurrentPath = nil; try write(originalVS, vs)

        for ids: Any in [["../Default"], ["Guest Profile"], ["Default", "Default"], [123], "Default"] {
            try rejects("invalid profile selection") { _ = try engine.run(["action": "apply", "targets": ["chrome"], "color": "red", "chromeProfileIDs": ids]) }
        }
        try rejects("empty Chrome selection") { _ = try engine.run(["action": "apply", "targets": ["chrome"], "color": "red", "chromeProfileIDs": []]) }
        var state = cache["profile"] as! [String: Any]
        var info = state["info_cache"] as! [String: Any]
        info["Default"] = ["name": "바뀐 이름"]
        info["Profile 2"] = ["name": "바뀐 이름"]
        info["Profile 3"] = ["name": "새 프로필"]
        info["Profile 9"] = ["name": "심볼릭 링크"]
        state["info_cache"] = info; cache["profile"] = state
        try writeJSON(cache, local)
        try writeJSON([:], engine.chromeRoot.appendingPathComponent("Profile 3/Preferences"))
        try FileManager.default.createSymbolicLink(at: engine.chromeRoot.appendingPathComponent("Profile 9"), withDestinationURL: prefs1.deletingLastPathComponent())
        let renamed = try engine.run(["action": "status", "chromeProfileIDs": ["Default"]])
        try check(renamed.chromeProfileIDs == ["Default"], "Rename/add preserves selected IDs")
        try check(renamed.chromeProfiles?.map(\.id) == ["Default", "Profile 2", "Profile 3"], "Symlink profile excluded")
        try check(renamed.chromeProfiles?.prefix(2).map(\.label) == ["바뀐 이름", "바뀐 이름"], "Duplicate labels retain distinct IDs")
        try FileManager.default.removeItem(at: prefs1)
        try rejects("removed selected profile") { _ = try engine.run(["action": "apply", "targets": ["system", "chrome"], "color": "red", "chromeProfileIDs": ["Default"]]) }
        try check(try engine.run(["action": "status", "chromeProfileIDs": ["Default"]]).chromeProfileIDs == [], "Missing profile pruned on refresh")
        try FileManager.default.removeItem(at: codex)
        try rejects("missing selected settings") { _ = try engine.run(["action": "apply", "targets": ["vscode", "codex"], "color": "red"]) }
        try check(try String(contentsOf: vs, encoding: .utf8) == originalVS, "No partial writes for missing settings")

        try rejects("duplicate JSONC setting") { _ = try JSONCDocument("{\"workbench.colorCustomizations\":{},\"workbench.colorCustomizations\":{}}").colorsRange() }
        try rejects("unterminated JSONC comment") { _ = try JSONCDocument("{/* open") }
        try rejects("duplicate TOML section") { _ = try CodexThemeDocument(themeBlocks + themeBlocks) }
        try rejects("unterminated TOML multiline string") { _ = try CodexThemeDocument("note=\"\"\"\n" + themeBlocks) }
        try rejects("duplicate TOML accent") { _ = try CodexThemeDocument(themeBlocks.replacingOccurrences(of: "accent = '#ffcc00'", with: "accent='#ffffff'\naccent = '#ffcc00'")) }
        print("Native settings checks passed: \(checks)")
    }
}
