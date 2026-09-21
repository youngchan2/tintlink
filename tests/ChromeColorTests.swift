import Foundation

@main struct ChromeColorTests {
    static func main() {
        // All Chrome-specific targets share the same bounded hue tolerance.
        let pairs = [("#FFFA00", "#FFCC00"), ("#FF00C6", "#FF4FA3"),
                     ("#00BDFF", "#0A84FF"), ("#7600FF", "#B8A1FF"),
                     ("#FF0000", "#FF453A"), ("#FFC300", "#FF9F0A"),
                     ("#00FF08", "#30D158")]
        for (actual, requested) in pairs {
            precondition(ChromeColor.matches(actual, requested), "Incorrect matching for \(actual) / \(requested)")
            precondition(ChromeColor.matches(actual.lowercased(), requested.lowercased()))
            let targetHue = ChromeColor.hue(actual)!
            for offset in [-0.4, 0.4] {
                let hue = (targetHue + offset + 360).truncatingRemainder(dividingBy: 360)
                precondition(ChromeColor.matches(ChromeColor.seedColor(forHue: hue), requested), "Small rounding differences should pass for every preset")
            }
            for offset in [-1.3, 1.3] {
                let hue = (targetHue + offset + 360).truncatingRemainder(dividingBy: 360)
                precondition(!ChromeColor.matches(ChromeColor.seedColor(forHue: hue), requested), "Every preset must reject colors outside the shared tolerance")
            }
            let readback = Double(Float(ChromeColor.hue(actual)!))
            precondition(ChromeColor.seedColor(forHue: readback) == actual)
            for (_, other) in pairs where other != requested {
                precondition(!ChromeColor.matches(actual, other), "Preset recognition must stay unambiguous")
            }
        }
        precondition(ChromeColor.seedColor(forHue: ChromeColor.hue("#7702FF")!) == "#7600FF")
        precondition(ChromeColor.seedColor(forHue: ChromeColor.hue("#F8B0E8")!) == "#FF00C6")
        precondition(ChromeColor.matches("#7500FF", "#B8A1FF"), "Accept the observed Chrome rounding within the approved purple approximation")
        precondition(!ChromeColor.matches("#7000FF", "#B8A1FF"), "Purple approximation must stay tightly bounded")
        precondition(ChromeColor.matches("#FF00C7", "#FF4FA3"))
        precondition(!ChromeColor.matches("#FF007A", "#FF4FA3"), "Old pink must not match the new requested hue")
        precondition(ChromeColor.matches("#FF0001", "#FF0100"), "Hue must wrap around zero")
        precondition(!ChromeColor.matches("#808080", "#FFCC00"), "Gray must not match a color preset")
        precondition(!ChromeColor.matches("#FF4FA3", "#B8A1FF"), "Different presets must stay distinct")
        precondition(ChromeColor.hue("#bad") == nil)
        precondition(ChromeColor.hue("#zzzzzz") == nil)
        precondition(!ChromeColor.matches("#FFCD00", "#FFCC00"), "The old approximate yellow must no longer match")
        precondition(ChromeColor.matches("#FFFB00", "#FFCC00"), "Yellow now allows the same rounding difference as all other presets")
        precondition(ChromeColor.matches("#fffa00", "#ffcc00"))
        precondition(!ChromeColor.matches("#00FF3F", "#30D158"), "The old green must no longer match")
        // Yellow and its neighboring byte values remain distinct
        // when converting the slider's readback, including float32 precision.
        for seed in ["#FFF900", "#FFFA00", "#FFFB00"] {
            let readback = Double(Float(ChromeColor.hue(seed)!))
            precondition(ChromeColor.seedColor(forHue: readback) == seed)
        }
        precondition(ChromeColor.seedColor(forHue: 0) == "#FF0000")
        precondition(ChromeColor.seedColor(forHue: 240) == "#0000FF")
        precondition(ChromeColor.seedColor(forHue: 360) == "#FF0000")

        // Regression: the native window and toolbar arrive before web content,
        // and share the new-tab URL. Neither is the owned page's identity.
        let loadingTree = [("AXWindow", "chrome://newtab/"), ("AXGroup", "chrome://newtab/")]
        precondition(!loadingTree.contains { ChromePageIdentity.isNewTab(role: $0.0, url: $0.1) })
        precondition(ChromePageIdentity.isNewTab(role: "AXWebArea", url: "chrome://new-tab-page/"))
        precondition(!ChromePageIdentity.isNewTab(role: "AXWebArea", url: "https://example.com/"))

        // Replay delayed renderer/panel updates: exactly one press, even if the
        // AX pressed value stays stale while Chrome loads the panel.
        var gate = ChromeToggleGate()
        let delayedStates: [(Bool, Bool?)] = [(false, nil), (false, false), (false, false), (false, true), (true, true)]
        let presses = delayedStates.map { gate.shouldPress(panelPresent: $0.0, pressed: $0.1) }
        precondition(presses == [false, true, false, false, false])
        var alreadyOpen = ChromeToggleGate()
        precondition(!alreadyOpen.shouldPress(panelPresent: false, pressed: true), "Do not close a panel whose AX tree is still loading")
        precondition(!alreadyOpen.shouldPress(panelPresent: true, pressed: false), "The visible panel takes precedence over a stale button value")

        let plans = ["Default", "Profile 2", "Profile 3"].map { ChromeUIAction(hex: "#FFCC00", profile: $0, label: "사용자 이름") }
        var visited = [String]()
        let success = ChromeBatch.run(plans) { plan in
            visited.append(plan.profile)
            return "#FFCD00"
        }
        precondition(visited == plans.map(\.profile))
        precondition(success.allSatisfy { $0.outcome == .applied })
        visited = []
        let partial = ChromeBatch.run(plans) { plan in
            visited.append(plan.profile)
            if plan.profile == "Profile 2" { throw NSError(domain: "test", code: 1) }
            return "#FFCD00"
        }
        precondition(visited == ["Default", "Profile 2"], "Never start another profile after an interruption")
        precondition(partial.map(\.outcome) == [.applied, .failed, .skipped])
        precondition(ChromeBatch.run([], apply: { _ in fatalError("Empty selection must not apply") }).isEmpty)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: root.appendingPathComponent("Profile 2"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try! Data("{}".utf8).write(to: root.appendingPathComponent("Profile 2/Preferences"))
        precondition((try? plans[1].preferencesURL(root: root)) != nil)
        for name in ["../Profile 2", "Profile 2/Preferences", "Guest Profile", "System Profile", "", "Missing"] {
            precondition((try? ChromeUIAction(hex: "#FFCC00", profile: name, label: "이름").preferencesURL(root: root)) == nil)
        }
        try! FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias"), withDestinationURL: root.appendingPathComponent("Profile 2"))
        precondition((try? ChromeUIAction(hex: "#FFCC00", profile: "Alias", label: "이름").preferencesURL(root: root)) == nil)
        print("Chrome color matching checks passed.")
    }
}
