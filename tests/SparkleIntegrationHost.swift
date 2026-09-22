import AppKit
import Sparkle

/// An isolated, windowless host for the real Sparkle installer. No UI automation
/// or access to the user's target-app settings is involved in this test.
@MainActor final class IntegrationHost: NSObject, NSApplicationDelegate, SPUUserDriver {
    private var updater: SPUUpdater!
    private var current = 0
    private var expected = 0
    private var logURL: URL!

    func record(_ line: String) {
        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: logURL.path), let file = try? FileHandle(forWritingTo: logURL) {
            defer { try? file.close() }
            _ = try? file.seekToEnd(); try? file.write(contentsOf: data)
        } else { try? data.write(to: logURL) }
    }
    func finish(_ ok: Bool, _ message: String) {
        record((ok ? "PASS " : "FAIL ") + message)
        NSApp.terminate(nil)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        let info = Bundle.main.infoDictionary!
        logURL = URL(fileURLWithPath: info["TintLinkTestLog"] as! String)
        expected = Int(info["TintLinkTestBuild"] as! String)!
        current = Int(info["CFBundleVersion"] as! String)!
        record("START build=\(current) version=\(info["CFBundleShortVersionString"]!)")
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: "testLaunches") + 1
        defaults.set(count, forKey: "testLaunches")
        guard count <= 3 else { finish(false, "Repeated old version after replacement"); return }
        if current < expected {
            defaults.set(["vscode"], forKey: "visibleTargets")
            defaults.set([String](), forKey: "selectedTargets")
            defaults.set(["Default"], forKey: "chromeProfileIDs")
        } else {
            guard defaults.stringArray(forKey: "visibleTargets") == ["vscode"],
                  defaults.stringArray(forKey: "selectedTargets") == [],
                  defaults.stringArray(forKey: "chromeProfileIDs") == ["Default"] else {
                finish(false, "Preferences lost after update"); return
            }
            record("PREFERENCES retained")
        }
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        do { try updater.start(); updater.checkForUpdates() }
        catch { finish(false, error.localizedDescription) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { self.finish(false, "Updater timed out") }
    }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { record("CHECK") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard current < expected else { reply(.dismiss); finish(false, "Offered the installed version again"); return }
        record("FOUND \(appcastItem.versionString)"); reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { finish(false, error.localizedDescription) }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        finish(current == expected, "Latest version check at build \(current): \(error.localizedDescription)")
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement(); finish(false, String(describing: error))
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { record("DOWNLOAD") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { record("EXTRACT verified archive") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { record("INSTALL"); reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}

@main struct IntegrationMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let host = IntegrationHost()
        app.delegate = host
        withExtendedLifetime(host) { app.run() }
    }
}
