import AppKit
import ApplicationServices

struct ChromeUIAction: Decodable {
    let hex: String
    let profile: String
    let label: String

    func preferencesURL(root: URL) throws -> URL {
        guard !profile.isEmpty, !profile.contains("/"), !profile.contains("\0"),
              ![".", "..", "Guest Profile", "System Profile"].contains(profile),
              !label.isEmpty, ChromeColor.hue(hex) != nil else {
            throw NSError(domain: "AccentBar.Chrome", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chrome 프로필의 색상 요청을 확인하지 못했습니다."])
        }
        let path = root.appendingPathComponent(profile).appendingPathComponent("Preferences")
        let resolved = path.resolvingSymlinksInPath().standardizedFileURL
        let expected = root.resolvingSymlinksInPath().appendingPathComponent(profile).appendingPathComponent("Preferences").standardizedFileURL
        guard resolved == expected, FileManager.default.fileExists(atPath: path.path) else {
            throw NSError(domain: "AccentBar.Chrome", code: 1, userInfo: [NSLocalizedDescriptionKey: "선택한 Chrome 프로필을 찾지 못했습니다. 목록을 새로고침해 주세요."])
        }
        return path
    }
}

struct ChromeApplyResult: Identifiable {
    enum Outcome { case applied, failed, skipped }
    let id: String
    let label: String
    let outcome: Outcome
    let detail: String
}

enum ChromeBatch {
    /// Stop after a failure; switching to another app or window is not a failure.
    static func run(_ plans: [ChromeUIAction], progress: (Int, ChromeUIAction) -> Void = { _, _ in },
                    apply: (ChromeUIAction) throws -> String) -> [ChromeApplyResult] {
        var results = [ChromeApplyResult]()
        var stopped = false
        for (index, plan) in plans.enumerated() {
            if stopped {
                results.append(ChromeApplyResult(id: plan.profile, label: plan.label, outcome: .skipped, detail: "앞선 프로필에서 중단되어 적용하지 않았습니다."))
                continue
            }
            progress(index + 1, plan)
            do {
                let actual = try apply(plan)
                results.append(ChromeApplyResult(id: plan.profile, label: plan.label, outcome: .applied, detail: "적용 완료 · \(actual)"))
            } catch {
                stopped = true
                results.append(ChromeApplyResult(id: plan.profile, label: plan.label, outcome: .failed, detail: error.localizedDescription))
            }
        }
        return results
    }
}

enum ChromeColor {
    // Chrome-specific seeds; other applications retain their own presets.
    static let yellowSeed = "#FFFA00"
    static let seeds = [
        "#0A84FF": "#00BDFF", // blue
        "#B8A1FF": "#7600FF", // requested #7702FF, projected to Chrome's hue wheel
        "#FF4FA3": "#FF00C6", // requested #F8B0E8, projected to Chrome's hue wheel
        "#FF453A": "#FF0000", // red
        "#FF9F0A": "#FFC300", // orange
        "#FFCC00": yellowSeed,
        "#30D158": "#00FF08"  // green
    ]
    static let tolerance = 0.65
    static func target(for requested: String) -> String {
        seeds[requested.uppercased()] ?? requested.uppercased()
    }
    /// Chromium's hue picker uses HSL saturation 1 and lightness 0.5, then
    /// quantizes to 8-bit RGB. Match that round-trip before another AX step.
    static func seedColor(forHue hue: Double) -> String {
        let h = min(360, max(0, hue)) / 60
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let rgb: (Double, Double, Double)
        switch h {
        case ..<1: rgb = (1, x, 0)
        case ..<2: rgb = (x, 1, 0)
        case ..<3: rgb = (0, 1, x)
        case ..<4: rgb = (0, x, 1)
        case ..<5: rgb = (x, 0, 1)
        default: rgb = (1, 0, x)
        }
        return String(format: "#%02X%02X%02X", Int((rgb.0 * 255).rounded()), Int((rgb.1 * 255).rounded()), Int((rgb.2 * 255).rounded()))
    }
    static func hue(_ hex: String) -> Double? {
        guard hex.count == 7, hex.first == "#", let n = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        let r = Double((n >> 16) & 255) / 255, g = Double((n >> 8) & 255) / 255, b = Double(n & 255) / 255
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        guard delta > 0.05 else { return nil }
        let h = high == r ? (g - b) / delta : (high == g ? (b - r) / delta + 2 : (r - g) / delta + 4)
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    }
    static func distance(_ a: Double, _ b: Double) -> Double { min(abs(a - b), 360 - abs(a - b)) }
    static func matches(_ actual: String, _ requested: String) -> Bool {
        guard let a = hue(actual), let b = hue(target(for: requested)) else { return false }
        return distance(a, b) <= tolerance
    }
}

enum ChromePageIdentity {
    static func isNewTab(role: String, url: String) -> Bool {
        // Chrome also exposes the new-tab URL on its native window and groups.
        role == "AXWebArea" && ["chrome://new-tab-page/", "chrome://newtab/"].contains(url)
    }
}

struct ChromeToggleGate {
    private var requested = false

    mutating func shouldPress(panelPresent: Bool, pressed: Bool?) -> Bool {
        // Customize Chrome toggles the panel. A delayed AX tree must never
        // cause a second press to close the panel we just requested.
        guard !panelPresent, pressed == false, !requested else { return false }
        requested = true
        return true
    }
}

/// Runs inside the signed menu app so Accessibility permission belongs to this app.
/// Chrome owns all preference writes and sync; this code only uses visible controls.
final class ChromeAutomation {
    private let plan: ChromeUIAction
    private var application: AXUIElement!
    private var window: AXUIElement!
    private var ownedNewTab: AXUIElement?
    private var ownedTabCloseButton: AXUIElement?
    private var accessibilityProcessID: pid_t?
    private let deadline: Date
    private var preferences: URL!

    init(_ plan: ChromeUIAction) {
        self.plan = plan
        deadline = Date().addingTimeInterval(60)
    }

    static var isAuthorized: Bool { AXIsProcessTrusted() }

    @MainActor static func openPermissionSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func apply() throws -> String {
        guard Self.isAuthorized else { throw failure("Chrome 연결을 위해 손쉬운 사용에서 ‘TinkLink’를 허용해 주세요.") }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome")
        preferences = try plan.preferencesURL(root: root)
        guard let desired = ChromeColor.hue(ChromeColor.target(for: plan.hex)),
              let bytes = try? Data(contentsOf: root.appendingPathComponent("Local State")),
              let data = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let profileInfo = data["profile"] as? [String: Any], let cache = profileInfo["info_cache"] as? [String: Any],
              let info = cache[plan.profile] as? [String: Any],
              (info["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == plan.label else {
            throw failure("Chrome 프로필 이름이 바뀌었거나 삭제되었습니다. 목록을 새로고침해 주세요.")
        }
        // Preserve an already acceptable color, including its saved RGB rounding.
        if let actual = savedColor(), ChromeColor.matches(actual, plan.hex) { return actual }
        var previousWindows = [AXUIElement]()
        if let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first {
            connect(to: chrome)
            previousWindows = elements(application, kAXWindowsAttribute)
        }
        // Chrome's process singleton forwards these arguments to an existing
        // browser, selecting the requested profile without touching other tabs.
        guard let bundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else { throw failure("Google Chrome 앱을 찾지 못했습니다.") }
        let executable = bundle.appendingPathComponent("Contents/MacOS/Google Chrome")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw failure("Google Chrome 앱을 찾지 못했습니다.") }
        let launch = Process()
        launch.executableURL = executable
        launch.arguments = ["--profile-directory=" + plan.profile, "--new-window", "chrome://newtab/"]
        launch.standardOutput = FileHandle.nullDevice
        launch.standardError = FileHandle.nullDevice
        try launch.run()
        try wait("Chrome의 ‘\(plan.label)’ 프로필 창을 열지 못했습니다.", seconds: 15) {
            guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else { return false }
            self.connect(to: chrome)
            let fresh = self.elements(self.application, kAXWindowsAttribute).filter { candidate in
                !previousWindows.contains(where: { CFEqual($0, candidate) }) && self.isProfileWindow(candidate)
            }
            guard fresh.count == 1 else { return false }
            self.window = fresh[0]
            return self.newTabArea() != nil
        }
        ownedNewTab = newTabArea()
        if let tabs = find(window, { self.string($0, kAXRoleAttribute) == kAXTabGroupRole }) {
            ownedTabCloseButton = find(tabs) { element in
                self.string(element, kAXRoleAttribute) == kAXButtonRole &&
                [kAXTitleAttribute, kAXDescriptionAttribute].contains { attribute in
                    ["닫기", "Close"].contains(self.string(element, attribute))
                }
            }
        }
        try checkTarget()
        let newTab = try require("Chrome 새 탭을 확인하지 못했습니다.") { self.newTabArea() }
        var gate = ChromeToggleGate()
        let panel = try require("Chrome 색상 패널이 응답하지 않습니다. Chrome을 업데이트한 뒤 다시 시도해 주세요.", seconds: 12) {
            if let panel = self.colorPanel() { return panel }
            if let customize = self.find(newTab, { self.isControl($0) && self.hasLabel($0, ["Chrome 맞춤설정", "Customize Chrome"]) }),
               gate.shouldPress(panelPresent: false, pressed: self.number(customize, kAXValueAttribute).map { $0 != 0 }) {
                try self.press(customize)
            }
            return nil
        }
        if hueSlider(in: panel) == nil {
            let customColor = try require("Chrome 맞춤 색상을 찾지 못했습니다. Chrome 기본 색상 테마를 사용해 주세요.") {
                self.find(panel) { self.isControl($0) && self.hasLabel($0, ["맞춤 색상", "Custom color"]) }
            }
            try press(customColor)
        }
        let slider = try require("Chrome 색조 슬라이더를 찾지 못했습니다.") {
            self.hueSlider(in: panel)
        }
        try adjust(slider, to: desired)
        // Read-only verification waits for Chrome's own delayed preference save.
        var actual = ""
        try wait("Chrome 화면의 색은 바뀌었지만 저장 결과를 확인하지 못했습니다. 다시 시도해 주세요.", seconds: 10) {
            actual = self.savedColor() ?? ""
            return ChromeColor.matches(actual, self.plan.hex)
        }
        // Close our exact tab through its own AX button. Keyboard shortcuts
        // would target whichever Chrome window happens to have keyboard focus.
        // A user navigating this tab after save must not turn success into failure.
        // Dismiss Chrome's modal color picker first. Otherwise an action on the
        // tab close button may merely dismiss the dialog and leave a new window.
        if let closePicker = find(panel, { self.string($0, kAXRoleAttribute) == kAXButtonRole && self.hasExactLabel($0, ["닫기", "Close"]) }) {
            try? press(closePicker)
            try? wait("", seconds: 2) { self.hueSlider(in: panel) == nil }
        }
        if let close = ownedTabCloseButton { try? press(close) }
        return actual
    }

    private func connect(to chrome: NSRunningApplication) {
        guard accessibilityProcessID != chrome.processIdentifier else { return }
        accessibilityProcessID = chrome.processIdentifier
        application = AXUIElementCreateApplication(chrome.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1)
        // Reading native window attributes alone does not enable web AX on
        // modern macOS. Chromium debounces this request for about two seconds;
        // the subsequent AXWebArea lookup waits for actual renderer readiness.
        // Request once per process, not in the polling loop (which restarts the
        // debounce). Do not turn it off: that could disable another AT's tree.
        _ = AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private func colorPanel() -> AXUIElement? {
        find(window) { self.string($0, kAXRoleAttribute) == "AXWebArea" && self.url($0).hasPrefix("chrome://customize-chrome-side-panel.top-chrome/") }
    }

    private func hueSlider(in panel: AXUIElement) -> AXUIElement? {
        find(panel) { self.string($0, kAXRoleAttribute) == kAXSliderRole && self.hasLabel($0, ["색조", "Hue", "hue"]) }
    }

    private func adjust(_ slider: AXUIElement, to target: Double) throws {
        // Direct AX actions operate on this slider even while another window
        // has focus. Read back every step because Chrome quantizes generated RGB.
        var steps = 0
        while steps < 390 {
            try checkTarget()
            guard let value = number(slider, kAXValueAttribute) else { throw failure("Chrome 색조 값을 읽지 못했습니다.") }
            // Aim within half a step; final saved-color verification allows
            // a little extra room for Chrome's 8-bit RGB rounding.
            if abs(value - target) <= 0.5 { return }
            let action = value < target ? kAXIncrementAction : kAXDecrementAction
            guard AXUIElementPerformAction(slider, action as CFString) == .success else {
                throw failure("Chrome 색조 슬라이더를 조절하지 못했습니다.")
            }
            try wait("Chrome 색조 슬라이더가 응답하지 않습니다.", seconds: 1) {
                guard let next = self.number(slider, kAXValueAttribute) else { return false }
                return abs(next - value) > 0.01
            }
            steps += 1
        }
        throw failure("Chrome 색조 조절을 완료하지 못했습니다.")
    }

    private func checkTarget() throws {
        guard Date() < deadline else { throw failure("Chrome 색상 적용 시간이 초과됐습니다.") }
        guard elements(application, kAXWindowsAttribute).contains(where: { CFEqual($0, window) }),
              isProfileWindow(window), let currentTab = newTabArea(),
              let ownedNewTab, CFEqual(currentTab, ownedNewTab) else {
            throw failure("색상 설정용 Chrome 탭이 닫혔거나 다른 페이지로 바뀌었습니다. 색상을 다시 선택해 주세요.")
        }
    }

    private func isProfileWindow(_ element: AXUIElement) -> Bool {
        let title = string(element, kAXTitleAttribute)
        return title.hasSuffix(" - Chrome - " + plan.label)
    }
    private func newTabArea() -> AXUIElement? {
        guard let window else { return nil }
        return find(window) { ChromePageIdentity.isNewTab(role: self.string($0, kAXRoleAttribute), url: self.url($0)) }
    }
    private func press(_ element: AXUIElement) throws {
        try checkTarget()
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { throw failure("Chrome 색상 설정 버튼을 누르지 못했습니다.") }
    }
    private func require(_ message: String, seconds: Double = 8, _ lookup: () throws -> AXUIElement?) throws -> AXUIElement {
        var found: AXUIElement?
        try wait(message, seconds: seconds) { try self.checkTarget(); found = try lookup(); return found != nil }
        return found!
    }
    private func wait(_ message: String, seconds: Double, _ ready: () throws -> Bool) throws {
        let end = min(Date().addingTimeInterval(seconds), deadline)
        repeat {
            if try ready() { return }
            Thread.sleep(forTimeInterval: 0.03)
        } while Date() < end
        throw failure(message)
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
    private func string(_ element: AXUIElement, _ name: String) -> String { attribute(element, name) as? String ?? "" }
    private func number(_ element: AXUIElement, _ name: String) -> Double? {
        if let n = attribute(element, name) as? NSNumber { return n.doubleValue }
        return Double(string(element, name))
    }
    private func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] { attribute(element, name) as? [AXUIElement] ?? [] }
    private func url(_ element: AXUIElement) -> String {
        if let value = attribute(element, kAXURLAttribute) as? URL { return value.absoluteString }
        return string(element, kAXURLAttribute)
    }
    private func isControl(_ element: AXUIElement) -> Bool {
        [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole].contains(string(element, kAXRoleAttribute))
    }
    private func hasLabel(_ element: AXUIElement, _ names: [String]) -> Bool {
        let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].map { string(element, $0) }.joined(separator: " ")
        return names.contains { label.contains($0) }
    }
    private func hasExactLabel(_ element: AXUIElement, _ names: [String]) -> Bool {
        [kAXTitleAttribute, kAXDescriptionAttribute].contains { names.contains(string(element, $0)) }
    }
    private func find(_ root: AXUIElement, _ matches: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue = [root], index = 0
        while index < queue.count && index < 1200 {
            let current = queue[index]; index += 1
            if matches(current) { return current }
            queue.append(contentsOf: elements(current, kAXChildrenAttribute))
        }
        return nil
    }
    private func savedColor() -> String? {
        guard let bytes = try? Data(contentsOf: preferences), let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let browser = root["browser"] as? [String: Any], let theme = browser["theme"] as? [String: Any],
              let value = theme["user_color2"] as? Int, theme["is_grayscale2"] as? Bool != true else { return nil }
        return String(format: "#%06X", value & 0xFFFFFF)
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "AccentBar.Chrome", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
