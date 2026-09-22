import Foundation

/// Visible targets and temporarily enabled targets are separate preferences.
/// Removing a target must also remove it from every future apply request.
struct TargetSelection {
    static let supported = ["system", "vscode", "codex", "chrome"]
    private(set) var visible: Set<String>
    private(set) var enabled: Set<String>

    init(visible: [String]?, enabled: [String]?, previouslyLaunched: Bool = false) {
        let allowed = Set(Self.supported)
        // Migrate earlier selections; a fresh install starts with no targets.
        self.visible = Set(visible ?? enabled ?? (previouslyLaunched ? Self.supported : [])).intersection(allowed)
        self.enabled = Set(enabled ?? Array(self.visible)).intersection(self.visible)
    }

    mutating func add(_ id: String) {
        guard Self.supported.contains(id) else { return }
        visible.insert(id)
        enabled.insert(id)
    }

    mutating func remove(_ id: String) {
        visible.remove(id)
        enabled.remove(id)
    }

    mutating func setEnabled(_ id: String, _ on: Bool) {
        guard visible.contains(id) else { return }
        if on { enabled.insert(id) } else { enabled.remove(id) }
    }
}
