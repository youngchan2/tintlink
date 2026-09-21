import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Palette { var color: Color { Color(hex: hex) } }

enum TargetIcons {
    private static let fallback = NSWorkspace.shared.icon(for: .application)
    private static let images: [String: NSImage] = {
        let workspace = NSWorkspace.shared
        var icons = [String: NSImage]()
        icons["system"] = NSImage(named: NSImage.computerName)
        for (target, bundleID) in [
            "vscode": "com.microsoft.VSCode",
            "codex": "com.openai.codex",
            "chrome": "com.google.Chrome"
        ] {
            // Resolve each user's installed app, including apps outside /Applications.
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                icons[target] = workspace.icon(forFile: url.path)
            }
        }
        return icons
    }()

    static func image(for target: String) -> NSImage { images[target] ?? fallback }
}

extension Color {
    init(hex: String) {
        let n = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x8E8E93
        self.init(.sRGB, red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
}

enum Backend {
    static func execute(_ request: [String: Any], progress: @escaping (String) -> Void = { _ in }) throws -> Reply {
        var request = request
        request["chromeMode"] = "ui"
        var reply = try invoke(request)
        if reply.ok, let plans = reply.chromeUIActions, !plans.isEmpty {
            let previous = NSWorkspace.shared.frontmostApplication
            let results = ChromeBatch.run(plans, progress: { index, plan in
                progress("Chrome · \(plan.label) 적용 중 (\(index)/\(plans.count))…")
            }) { try ChromeAutomation($0).apply() }
            reply.chromeResults = results
            let completed = results.filter { $0.outcome == .applied }.count
            reply.ok = completed == plans.count
            reply.message += (reply.message.isEmpty ? "" : " ") + "Chrome \(completed)/\(plans.count)개 프로필 적용 완료."
            if !reply.ok { reply.message += " 프로필별 결과를 확인해 주세요." }
            if reply.ok, let previous, previous.bundleIdentifier != "com.google.Chrome",
               NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome" {
                DispatchQueue.main.async { previous.activate(options: []) }
            }
            var refresh = request
            refresh["action"] = "status"
            if let refreshed = try? invoke(refresh) {
                let message = reply.message, ok = reply.ok
                reply = refreshed
                reply.message = message; reply.ok = ok; reply.chromeResults = results
            }
        }
        if !ChromeAutomation.isAuthorized, let index = reply.rows?.firstIndex(where: { $0.id == "chrome" }) {
            reply.rows?[index].applyReady = false
            reply.rows?[index].detail = "Chrome 연결 권한 필요"
        }
        return reply
    }

    private static func invoke(_ request: [String: Any]) throws -> Reply {
        guard let resources = Bundle.main.resourceURL else { throw issue("앱의 색상 구성을 찾지 못했습니다.") }
        return try NativeSettings(resources: resources).run(request)
    }
    static func issue(_ message: String) -> NSError {
        NSError(domain: "AccentBar", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

@MainActor final class AppState: ObservableObject {
    @Published var rows = [TargetRow]()
    @Published var targets: Set<String>
    @Published var busy = false
    @Published var message = "색상을 누르면 선택한 대상에 함께 적용됩니다."
    @Published var isError = false
    @Published var chromeProfiles = [ChromeProfile]()
    @Published var chromeProfileIDs = Set<String>()
    @Published var chromeResults = [ChromeApplyResult]()
    private var hasProfileSelection = false
    @Published var chromeAuthorized = ChromeAutomation.isAuthorized

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "selectedTargets")
        targets = Set(saved ?? ["system", "vscode", "codex", "chrome"])
        if let ids = UserDefaults.standard.stringArray(forKey: "chromeProfileIDs") {
            chromeProfileIDs = Set(ids)
            hasProfileSelection = true
        } else if let legacy = UserDefaults.standard.string(forKey: "chromeProfile"), !legacy.isEmpty {
            chromeProfileIDs = [legacy]
            hasProfileSelection = true
        } else if saved != nil {
            // Version 1.3 always used Default. Preserve that choice on upgrade.
            chromeProfileIDs = ["Default"]
            hasProfileSelection = true
        }
    }
    var readyTargets: [String] { rows.filter { $0.available && targets.contains($0.id) && ($0.id != "chrome" || !chromeProfileIDs.isEmpty) }.map(\.id) }
    var allProfilesSelected: Bool { !chromeProfiles.isEmpty && chromeProfiles.allSatisfy { chromeProfileIDs.contains($0.id) } }
    var canApply: Bool { !busy && !readyTargets.isEmpty }
    var canImport: Bool { !busy && readyTargets.contains(where: { $0 != "system" }) && rows.contains(where: { $0.id == "system" && $0.available }) }
    var currentPalette: Palette? {
        var colors = rows.filter { $0.id != "chrome" && $0.available && targets.contains($0.id) }.map(\.color)
        if targets.contains("chrome") && chromeAuthorized {
            colors += chromeProfiles.filter { chromeProfileIDs.contains($0.id) }.map { profile in
                Palette.all.first(where: { ChromeColor.matches(profile.color, $0.hex) })?.hex ?? profile.color
            }
        }
        guard let first = colors.first, !first.isEmpty, colors.allSatisfy({ $0.lowercased() == first.lowercased() }) else { return nil }
        return Palette.all.first { $0.hex.lowercased() == first.lowercased() }
    }
    func toggle(_ id: String, on: Bool) {
        if on { targets.insert(id) } else { targets.remove(id) }
        UserDefaults.standard.set(Array(targets).sorted(), forKey: "selectedTargets")
    }
    func selectProfile(_ id: String, on: Bool) {
        guard !busy else { return }
        if on { chromeProfileIDs.insert(id) } else { chromeProfileIDs.remove(id) }
        saveProfileSelection()
    }
    func selectAllProfiles(_ on: Bool) {
        guard !busy else { return }
        chromeProfileIDs = on ? Set(chromeProfiles.map(\.id)) : []
        saveProfileSelection()
    }
    private func saveProfileSelection() {
        hasProfileSelection = true
        UserDefaults.standard.set(chromeProfileIDs.sorted(), forKey: "chromeProfileIDs")
    }
    func perform(_ action: String, extra: [String: Any] = [:]) {
        guard !busy else { return }
        busy = true
        if action != "status" { message = "색상을 처리하고 있습니다…"; isError = false; chromeResults = [] }
        var request: [String: Any] = ["action": action, "targets": readyTargets]
        if hasProfileSelection { request["chromeProfileIDs"] = chromeProfileIDs.sorted() }
        for (key, value) in extra { request[key] = value }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Backend.execute(request) { message in
                DispatchQueue.main.async { self.message = message }
            } }
            DispatchQueue.main.async {
                self.busy = false
                self.chromeAuthorized = ChromeAutomation.isAuthorized
                switch result {
                case .success(let reply):
                    if let rows = reply.rows { self.rows = rows }
                    if let profiles = reply.chromeProfiles { self.chromeProfiles = profiles }
                    if let ids = reply.chromeProfileIDs { self.chromeProfileIDs = Set(ids); self.saveProfileSelection() }
                    if let results = reply.chromeResults { self.chromeResults = results }
                    if !reply.ok || !reply.message.isEmpty { self.message = reply.message; self.isError = !reply.ok }
                case .failure(let error):
                    self.message = error.localizedDescription
                    self.isError = true
                }
            }
        }
    }

}

struct AccentView: View {
    @ObservedObject var state: AppState
    private let border = Color.primary.opacity(0.09)
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { mainView }
                .padding(.bottom, 2)
            }
            feedback
            footer
        }
        .padding(22)
        .frame(width: 438, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))

    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill((state.currentPalette?.color ?? .secondary).opacity(0.15))
                Image(systemName: "paintpalette.fill").font(.system(size: 23)).foregroundStyle(state.currentPalette?.color ?? .primary)
            }.frame(width: 48, height: 48)
            Text("TintLink").font(.system(size: 20, weight: .bold))
            Spacer()
            if state.busy { ProgressView().controlSize(.small).accessibilityLabel("처리 중") }
            else {
                Button { state.perform("status") } label: { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium)) }
                    .buttonStyle(.plain).help("현재 색상 새로고침").accessibilityLabel("현재 색상 새로고침")
            }
        }
    }
    private var mainView: some View {
        Group {
            VStack(alignment: .leading, spacing: 14) {
                Text("색상 선택").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(Palette.all) { palette in
                        Button { state.perform("apply", extra: ["color": palette.id]) } label: {
                            ZStack {
                                Circle().fill(palette.color).frame(width: 34, height: 34)
                                Circle().strokeBorder(Color.primary.opacity(state.currentPalette?.id == palette.id ? 0.75 : 0), lineWidth: 1.5).frame(width: 42, height: 42)
                                if state.currentPalette?.id == palette.id {
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.black.opacity(0.8))
                                }
                            }.frame(maxWidth: .infinity).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(!state.canApply)
                        .help(palette.label + " · " + palette.hex)
                        .accessibilityLabel(palette.label + " 적용")
                        .accessibilityValue(state.currentPalette?.id == palette.id ? "현재 색상" : palette.hex)
                    }
                }
            }.padding(.vertical, 5)
            VStack(alignment: .leading, spacing: 9) {
                Text("적용 대상").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(state.rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 11) {
                            Image(nsImage: TargetIcons.image(for: row.id))
                                .resizable().renderingMode(.original).interpolation(.high).scaledToFit()
                                .frame(width: 26, height: 26).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.label).font(.system(size: 13, weight: .medium))
                                Text(row.id == "chrome" && row.available ? (state.chromeProfileIDs.isEmpty ? "적용할 프로필을 선택해 주세요" : "\(state.chromeProfileIDs.count)개 프로필 선택 · Chrome에서 직접 적용") : row.detail)
                                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                                if row.id == "chrome" && !state.chromeAuthorized {
                                    Button("Chrome 연결 허용") { ChromeAutomation.openPermissionSettings() }
                                        .font(.system(size: 11)).buttonStyle(.link).disabled(state.busy)
                                }
                            }
                            Spacer()
                            if !row.color.isEmpty { Circle().fill(Color(hex: row.color)).frame(width: 9, height: 9).accessibilityHidden(true) }
                            Toggle(row.label, isOn: Binding(get: { state.targets.contains(row.id) && row.available }, set: { state.toggle(row.id, on: $0) }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.mini).disabled(state.busy || !row.available)
                                .accessibilityLabel(row.label + " 적용 대상")
                        }.padding(.horizontal, 13).padding(.vertical, 11)
                        if row.id == "chrome" && state.targets.contains("chrome") && !state.chromeProfiles.isEmpty {
                            chromeProfilePicker
                        }
                        if index < state.rows.count - 1 { Divider().padding(.leading, 50) }
                    }
                    if state.rows.isEmpty { Text("현재 색상을 확인하고 있습니다…").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(35) }
                }
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(border))
            }
            VStack(spacing: 8) {
                actionButton("시스템 색상 가져오기", symbol: "arrow.down.circle", disabled: !state.canImport) { state.perform("system") }
            }
        }
    }
    private var chromeProfilePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            HStack {
                Toggle("모두 선택", isOn: Binding(get: { state.allProfilesSelected }, set: { state.selectAllProfiles($0) }))
                    .toggleStyle(.checkbox).font(.system(size: 11, weight: .medium))
                    .accessibilityLabel("Chrome 프로필 모두 선택")
                Spacer()
                Text("\(state.chromeProfileIDs.count)/\(state.chromeProfiles.count)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(state.chromeProfiles) { profile in
                        HStack(alignment: .top, spacing: 8) {
                            Toggle(isOn: Binding(get: { state.chromeProfileIDs.contains(profile.id) }, set: { state.selectProfile(profile.id, on: $0) })) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.label).font(.system(size: 12)).lineLimit(2)
                                    if state.chromeProfiles.filter({ $0.label == profile.label }).count > 1 {
                                        Text(profile.id).font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    if let result = state.chromeResults.first(where: { $0.id == profile.id }) {
                                        Text(result.detail).font(.system(size: 10))
                                            .foregroundStyle(result.outcome == .failed ? Color.red : Color.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    } else if !profile.available {
                                        Text(profile.detail).font(.system(size: 10)).foregroundStyle(.red)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox).accessibilityLabel(profile.label + " 프로필 선택")
                            Spacer(minLength: 0)
                            if !profile.color.isEmpty {
                                Circle().fill(Color(hex: profile.color)).frame(width: 8, height: 8).padding(.top, 4).help(profile.color)
                            }
                        }.help(profile.label)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
            }
            .frame(height: min(CGFloat(state.chromeProfiles.count * (state.chromeResults.isEmpty ? 30 : 66)), 156))
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
        .disabled(state.busy)
    }
    private func actionButton(_ title: String, symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 17)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(disabled)
    }
    private var feedback: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: state.isError ? "exclamationmark.circle" : "info.circle").font(.system(size: 12)).padding(.top, 1)
            Text(state.message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(state.isError ? Color.red : Color.secondary).frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            .accessibilityElement(children: .combine)
    }
    private var footer: some View {
        HStack(spacing: 16) {
            Spacer()
            Button("종료") { NSApp.terminate(nil) }.buttonStyle(.plain).disabled(state.busy)
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 5)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let state = AppState()
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Reopening the bundle should reveal the existing item, not create duplicates.
        if let identifier = Bundle.main.bundleIdentifier,
           let previous = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            previous.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: 30)
        item.autosaveName = "AccentBarStatusItem"
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "paintpalette.fill", accessibilityDescription: "TintLink")
            button.image?.isTemplate = true
            button.toolTip = "TintLink"
            button.setAccessibilityLabel("TintLink 열기")
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 438, height: 660)
        popover.contentViewController = NSHostingController(rootView: AccentView(state: state))
        showPopover()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    private func showPopover() {
        guard let button = item?.button else { return }
        state.perform("status")
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

@main struct AccentBarMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
