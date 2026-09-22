import Foundation

@main struct TargetSelectionTests {
    static func main() {
        var fresh = TargetSelection(visible: nil, enabled: nil)
        precondition(fresh.visible.isEmpty && fresh.enabled.isEmpty, "Fresh installs choose their targets")
        let oldDefaults = TargetSelection(visible: nil, enabled: nil, previouslyLaunched: true)
        precondition(oldDefaults.visible == Set(TargetSelection.supported), "Preserve implicit all-app selection in older installs")
        let restartedEmpty = TargetSelection(visible: [], enabled: [], previouslyLaunched: true)
        precondition(restartedEmpty.visible.isEmpty, "Discovery of Chrome profiles does not populate a new user's empty list")
        let migrated = TargetSelection(visible: nil, enabled: ["system", "chrome", "unknown"])
        precondition(migrated.visible == ["system", "chrome"] && migrated.enabled == migrated.visible)
        fresh.add("chrome")
        fresh.setEnabled("chrome", false)
        precondition(fresh.visible == ["chrome"] && fresh.enabled.isEmpty, "Temporarily disabled rows stay visible")
        let restored = TargetSelection(visible: Array(fresh.visible), enabled: Array(fresh.enabled))
        precondition(restored.visible == fresh.visible && restored.enabled.isEmpty, "Disabled state survives restart")
        fresh.setEnabled("chrome", true)
        fresh.remove("chrome")
        precondition(fresh.visible.isEmpty && fresh.enabled.isEmpty, "Removed apps must never receive color changes")
        fresh.setEnabled("chrome", true)
        precondition(fresh.enabled.isEmpty, "Hidden apps cannot be enabled")
        let empty = TargetSelection(visible: [], enabled: ["system", "chrome"])
        precondition(empty.visible.isEmpty && empty.enabled.isEmpty, "An intentionally empty list stays empty")
        fresh.add("chrome")
        precondition(fresh.visible == ["chrome"] && fresh.enabled == ["chrome"], "Re-add enables the target")
        fresh.add("unsupported")
        precondition(fresh.visible == ["chrome"], "Unsupported apps cannot be added")
        print("Target selection migration and persistence checks passed")
    }
}
