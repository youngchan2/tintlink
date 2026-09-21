import AppKit
import CoreFoundation
import Darwin
import Foundation

struct AccentPreference: Equatable { let present: Bool; let value: Int? }
typealias AccentPreferences = [String: AccentPreference]

protocol SystemAccentAccess {
    func read() throws -> AccentPreferences
    func write(_ value: AccentPreferences) throws
}

final class MacSystemAccent: SystemAccentAccess {
    static let keys = ["AppleAccentColor", "AppleAquaColorVariant"]
    func read() throws -> AccentPreferences {
        // This now runs in a long-lived app, so refresh changes made in System
        // Settings instead of relying on a freshly launched helper process.
        guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { throw settingsError("시스템 색상 설정을 새로 읽지 못했습니다.") }
        var result = AccentPreferences()
        for key in Self.keys {
            if let value = CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == Double(number.intValue) else { throw settingsError("시스템 색상 설정이 숫자 형식이 아닙니다.") }
                result[key] = AccentPreference(present: true, value: number.intValue)
            } else { result[key] = AccentPreference(present: false, value: nil) }
        }
        return result
    }
    func write(_ value: AccentPreferences) throws {
        guard Set(value.keys) == Set(Self.keys) else { throw settingsError("macOS 색상 항목만 지정할 수 있습니다.") }
        for key in Self.keys {
            let entry = value[key]!
            let allowed = key == "AppleAccentColor" ? Array(-2...6) : [1, 6]
            guard (!entry.present && entry.value == nil) || (entry.present && entry.value.map(allowed.contains) == true) else { throw settingsError("지원하지 않는 macOS 색상 값입니다.") }
        }
        for key in Self.keys {
            let entry = value[key]!
            CFPreferencesSetValue(key as CFString, entry.value.map(NSNumber.init(value:)), kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        let saved = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        for name in ["AppleAquaColorVariantChanged", "AppleColorPreferencesChangedNotification"] {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
        }
        guard saved, try read() == value else { throw settingsError("macOS 색상 저장을 확인하지 못했습니다.") }
    }
}

protocol SettingsFileAccess {
    func read(_ path: URL) throws -> Data
    func write(_ path: URL, data: Data) throws
}

struct AtomicSettingsFiles: SettingsFileAccess {
    func read(_ path: URL) throws -> Data { try Data(contentsOf: path) }
    func write(_ path: URL, data: Data) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o600
        let temp = path.deletingLastPathComponent().appendingPathComponent("." + path.lastPathComponent + "-accent-" + UUID().uuidString)
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd); unlink(temp.path) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
        guard fchmod(fd, mode_t(mode)) == 0, fsync(fd) == 0, rename(temp.path, path.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

struct ThemePreset: Decodable {
    struct Apps: Decodable {
        struct VSCode: Decodable { let colorCustomizations: String }
        let vscode: VSCode
        let codex: [String: [String: String]]
    }
    let apps: Apps
}

/// Native replacement for the Python bridge. All paths are resolved from the
/// current user's home. Chrome files are read only; ChromeAutomation applies UI.
final class NativeSettings {
    let home: URL
    let resources: URL
    let codexHome: URL?
    let system: SystemAccentAccess
    let files: SettingsFileAccess
    static let systemIDs = ["red", "orange", "yellow", "green", "blue", "lavender", "pink"]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, resources: URL,
         codexHome: URL? = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) },
         system: SystemAccentAccess = MacSystemAccent(), files: SettingsFileAccess = AtomicSettingsFiles()) {
        self.home = home; self.resources = resources; self.codexHome = codexHome
        self.system = system; self.files = files
    }
    var chromeRoot: URL { home.appendingPathComponent("Library/Application Support/Google/Chrome") }
    var paths: [String: URL] {
        var candidates = [home.appendingPathComponent(".config/codex"), home.appendingPathComponent(".codex")]
        if let codexHome { candidates.insert(codexHome, at: 0) }
        let codex = candidates.map { $0.appendingPathComponent("config.toml") }.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0].appendingPathComponent("config.toml")
        return ["vscode": home.appendingPathComponent("Library/Application Support/Code/User/settings.json"), "codex": codex]
    }
    func text(_ path: URL) throws -> String {
        guard let text = String(data: try files.read(path), encoding: .utf8) else { throw settingsError("설정 파일이 UTF-8 형식이 아닙니다.") }
        return text
    }
    func json(_ path: URL) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: files.read(path)) as? [String: Any] else { throw settingsError("설정 파일 형식이 올바르지 않습니다.") }
        return object
    }

    static func validateProfileID(_ id: String) throws {
        guard !id.isEmpty, !id.contains("/"), !id.contains("\0"), ![".", "..", "Guest Profile", "System Profile"].contains(id) else { throw settingsError("올바른 Chrome 프로필을 선택해 주세요.") }
    }
    func profileURL(_ id: String) throws -> URL {
        try Self.validateProfileID(id)
        let directory = chromeRoot.appendingPathComponent(id)
        let path = directory.appendingPathComponent("Preferences")
        for url in [directory, path] {
            guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw settingsError("지원하지 않는 Chrome 프로필 경로입니다.") }
        }
        let expected = chromeRoot.resolvingSymlinksInPath().appendingPathComponent(id).appendingPathComponent("Preferences").standardizedFileURL
        guard path.resolvingSymlinksInPath().standardizedFileURL == expected,
              try path.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw settingsError("Chrome 프로필을 찾지 못했습니다.") }
        return path
    }
    func profiles() throws -> ([ChromeProfile], String?) {
        let local = chromeRoot.appendingPathComponent("Local State")
        guard FileManager.default.fileExists(atPath: local.path) else { return ([], nil) }
        let state = try json(local)["profile"] as? [String: Any] ?? [:]
        let cache = state["info_cache"] as? [String: [String: Any]] ?? [:]
        var profiles = [ChromeProfile]()
        for id in cache.keys.sorted() {
            guard let path = try? profileURL(id) else { continue }
            let name = (cache[id]?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = id == "Default" ? "기본 프로필" : (id.hasPrefix("Profile ") ? "프로필 " + id.dropFirst(8) : id)
            let label = name?.isEmpty == false ? name! : fallback
            do {
                let description = Self.chromeDescription(try json(path))
                profiles.append(ChromeProfile(id: id, label: label, color: description.0, detail: description.1, available: true))
            } catch { profiles.append(ChromeProfile(id: id, label: label, color: "", detail: "색상 설정을 읽지 못했습니다.", available: false)) }
        }
        let last = state["last_used"] as? String ?? "Default"
        return (profiles, profiles.contains { $0.id == last } ? last : profiles.first?.id)
    }
    static func chromeDescription(_ data: [String: Any]) -> (String, String) {
        let browser = data["browser"] as? [String: Any] ?? [:]
        let theme = browser["theme"] as? [String: Any] ?? [:]
        let extensions = data["extensions"] as? [String: Any] ?? [:]
        let id = (extensions["theme"] as? [String: Any])?["id"] as? String ?? ""
        if theme["is_grayscale2"] as? Bool == true { return ("", "회색") }
        var color = theme["user_color2"] as? NSNumber
        if id == "autogenerated_theme_id" { color = ((data["autogenerated"] as? [String: Any])?["theme"] as? [String: Any])?["color"] as? NSNumber }
        if let color, CFGetTypeID(color) != CFBooleanGetTypeID(), color.int64Value != 0 {
            let hex = String(format: "#%06X", color.int64Value & 0xffffff)
            return (hex, hex)
        }
        return ("", id.isEmpty ? "기본 테마" : "웹 스토어 테마")
    }
    static func systemPalette(_ state: AccentPreferences) throws -> (Palette?, String) {
        guard let entry = state["AppleAccentColor"] else { throw settingsError("macOS 색상 설정을 읽지 못했습니다.") }
        guard entry.present, let value = entry.value, value != -2 else { return (nil, "다색") }
        if value == -1 { return (nil, "회색") }
        guard systemIDs.indices.contains(value), let palette = Palette.all.first(where: { $0.id == systemIDs[value] }) else { throw settingsError("지원하지 않는 macOS 강조색입니다.") }
        return (palette, palette.id == "lavender" ? "보라" : palette.label)
    }

    func rows(profiles: [ChromeProfile], selected: [String]) -> [TargetRow] {
        var result = [TargetRow]()
        do {
            let (palette, label) = try Self.systemPalette(system.read())
            result.append(TargetRow(id: "system", label: "macOS", available: true, color: palette?.hex ?? "", detail: label))
        } catch { result.append(TargetRow(id: "system", label: "macOS", available: false, color: "", detail: error.localizedDescription)) }
        for (id, label) in [("vscode", "VS Code"), ("codex", "Codex")] {
            do {
                let raw = try text(paths[id]!)
                let color: String, detail: String
                if id == "vscode" {
                    let doc = try JSONCDocument(raw)
                    guard doc.object["workbench.colorTheme"] as? String == "Dark Modern" else { throw settingsError("VS Code에서 Dark Modern 테마를 선택해 주세요.") }
                    _ = try doc.colorsRange()
                    let colors = doc.object["workbench.colorCustomizations"] as? [String: Any] ?? [:]
                    color = ((colors["[Dark Modern]"] as? [String: Any] ?? colors)["focusBorder"] as? String ?? "").uppercased()
                    detail = color.isEmpty ? "테마 기본값" : color
                } else {
                    let doc = try CodexThemeDocument(raw)
                    let values = CodexThemeDocument.themes.map { doc.fields[$0]!["accent"]!.value.uppercased() }
                    color = values[0] == values[1] ? values[0] : ""
                    detail = color.isEmpty ? "라이트·다크 색상 다름" : color
                }
                result.append(TargetRow(id: id, label: label, available: true, color: color, detail: detail))
            } catch {
                let missing = !FileManager.default.fileExists(atPath: paths[id]!.path)
                result.append(TargetRow(id: id, label: label, available: false, color: "", detail: missing ? "설정 파일을 찾지 못했습니다." : error.localizedDescription))
            }
        }
        result.append(TargetRow(id: "chrome", label: "Chrome", available: !profiles.isEmpty, color: "", detail: profiles.isEmpty ? "Chrome 프로필을 찾지 못했습니다." : "\(selected.count)개 프로필 선택", applyReady: !selected.isEmpty))
        return result
    }

    func run(_ request: [String: Any]) throws -> Reply {
        // Preserve cross-process serialization with older app instances. The
        // lock contains no settings/history and persists no user profile data.
        let directory = home.appendingPathComponent("Library/Application Support/AccentBar")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw settingsError("색상 설정 잠금을 열지 못했습니다.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw settingsError("다른 색상 작업이 끝날 때까지 기다려 주세요.") }
        defer { flock(fd, LOCK_UN) }
        return try process(request)
    }

    private func process(_ request: [String: Any]) throws -> Reply {
        let action = request["action"] as? String ?? "status"
        guard ["status", "apply", "system"].contains(action) else { throw settingsError("지원하지 않는 작업입니다.") }
        let (profiles, last) = try profiles()
        let targets = request["targets"] as? [String] ?? []
        let ids: [String]
        if let value = request["chromeProfileIDs"] {
            guard let value = value as? [String] else { throw settingsError("올바른 Chrome 프로필 목록을 선택해 주세요.") }
            ids = value
        } else { ids = last.map { [$0] } ?? [] }
        for id in ids { try Self.validateProfileID(id) }
        guard Set(ids).count == ids.count else { throw settingsError("Chrome 프로필을 중복 선택할 수 없습니다.") }
        let missing = Set(ids).subtracting(profiles.map(\.id))
        if action != "status", targets.contains("chrome"), !missing.isEmpty { throw settingsError("선택한 Chrome 프로필이 삭제되었거나 사용할 수 없습니다. 목록을 새로고침해 주세요.") }
        let selected = profiles.filter { ids.contains($0.id) }.map(\.id)
        let before = rows(profiles: profiles, selected: selected)
        var plans = [ChromeUIAction](), message = ""
        if action != "status" {
            guard !targets.isEmpty, targets.count == Set(targets).count, Set(targets).isSubset(of: ["system", "vscode", "codex", "chrome"]) else { throw settingsError("적용할 대상을 하나 이상 선택해 주세요.") }
            if let unavailable = before.first(where: { targets.contains($0.id) && !$0.available }) { throw settingsError(unavailable.label + ": " + unavailable.detail) }
            if targets.contains("chrome") {
                guard !selected.isEmpty else { throw settingsError("적용할 Chrome 프로필을 하나 이상 선택해 주세요.") }
                guard profiles.filter({ selected.contains($0.id) }).allSatisfy(\.available) else { throw settingsError("선택한 Chrome 프로필의 색상 설정을 읽지 못했습니다.") }
            }
            let palette: Palette
            if action == "system" {
                let (value, label) = try Self.systemPalette(system.read())
                guard let value else { throw settingsError("시스템이 " + label + "입니다. 시스템에서 7가지 단색 중 하나를 선택해 주세요.") }
                guard targets.contains(where: { $0 != "system" }) else { throw settingsError("시스템 색상을 가져올 앱을 선택해 주세요.") }
                palette = value
            } else {
                guard let name = request["color"] as? String, let value = Palette.all.first(where: { $0.id == name }) else { throw settingsError("목록에서 색상을 선택해 주세요.") }
                palette = value
            }
            if targets.contains("chrome") { plans = profiles.filter { selected.contains($0.id) }.map { ChromeUIAction(hex: palette.hex, profile: $0.id, label: $0.label) } }
            let appTargets = targets.filter { ["vscode", "codex"].contains($0) }
            let includeSystem = action == "apply" && targets.contains("system")
            try apply(palette, targets: appTargets, includeSystem: includeSystem)
            if !appTargets.isEmpty || includeSystem {
                let labels = (includeSystem ? ["macOS"] : []) + ["vscode", "codex"].filter(appTargets.contains).map { $0 == "vscode" ? "VS Code" : "Codex" }
                message = action == "system" ? "선택한 앱을 시스템 색상에 맞췄습니다." : labels.joined(separator: " · ") + "에 " + palette.label + " 색상을 적용했습니다."
                if appTargets.contains("codex") { message += " Codex에 반영되지 않으면 작업 후 앱을 다시 여세요." }
            }
        }
        return Reply(ok: true, message: message, rows: rows(profiles: profiles, selected: selected), chromeProfiles: profiles, chromeProfileIDs: selected, chromeUIActions: plans)
    }

    func apply(_ palette: Palette, targets: [String], includeSystem: Bool) throws {
        guard !targets.isEmpty || includeSystem else { return }
        let preset = try JSONDecoder().decode(ThemePreset.self, from: files.read(resources.appendingPathComponent("preset-" + palette.id + ".json")))
        struct Change { let path: URL; let before: Data; let after: Data }
        var changes = [Change]()
        for id in ["vscode", "codex"] where targets.contains(id) {
            let path = paths[id]!.resolvingSymlinksInPath()
            let before = try files.read(path)
            guard let raw = String(data: before, encoding: .utf8) else { throw settingsError("설정 파일이 UTF-8 형식이 아닙니다.") }
            let updated = id == "vscode" ? try JSONCDocument(raw).replacingColors(preset.apps.vscode.colorCustomizations) : try CodexThemeDocument(raw).replacingAccents(preset.apps.codex)
            let after = Data(updated.utf8)
            if before != after { changes.append(Change(path: path, before: before, after: after)) }
        }
        let beforeSystem = includeSystem ? try system.read() : nil
        let targetSystem: AccentPreferences? = includeSystem ? ["AppleAccentColor": AccentPreference(present: true, value: Self.systemIDs.firstIndex(of: palette.id)!), "AppleAquaColorVariant": AccentPreference(present: true, value: 1)] : nil
        let systemChanged = beforeSystem != targetSystem
        var written = [Change](), attemptedSystem = false
        do {
            for change in changes {
                guard try files.read(change.path) == change.before else { throw settingsError("다른 곳에서 설정이 변경되었습니다. 다시 실행해 주세요.") }
                try files.write(change.path, data: change.after)
                written.append(change)
            }
            if systemChanged, let targetSystem {
                guard try system.read() == beforeSystem else { throw settingsError("다른 곳에서 시스템 색상이 변경되었습니다. 다시 실행해 주세요.") }
                attemptedSystem = true
                try system.write(targetSystem)
            }
            for change in written where try files.read(change.path) != change.after { throw settingsError("앱이 설정을 다시 저장했습니다. 다시 실행해 주세요.") }
            if systemChanged, try system.read() != targetSystem { throw settingsError("macOS가 색상 설정을 다시 저장했습니다.") }
        } catch {
            var rollbackErrors = [String]()
            if attemptedSystem, let beforeSystem {
                do { if try system.read() == targetSystem { try system.write(beforeSystem) } }
                catch { rollbackErrors.append("macOS: " + error.localizedDescription) }
            }
            for change in written.reversed() {
                do { if try files.read(change.path) == change.after { try files.write(change.path, data: change.before) } }
                catch { rollbackErrors.append(change.path.lastPathComponent + ": " + error.localizedDescription) }
            }
            if !rollbackErrors.isEmpty { throw settingsError(error.localizedDescription + " 일부 설정을 되돌리지 못했습니다: " + rollbackErrors.joined(separator: "; ")) }
            throw error
        }
    }
}
