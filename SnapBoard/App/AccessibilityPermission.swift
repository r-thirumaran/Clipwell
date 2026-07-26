import AppKit
import ApplicationServices

/// Accessibility (AX) permission gate.
///
/// SnapBoard needs `kTCCServiceAccessibility` for two distinct things:
///   1. reading and writing window position/size on other apps' windows, and
///   2. posting the synthetic ⌘V that performs the paste.
///
/// Both are the *same* permission, so one grant covers the whole app.
enum AccessibilityPermission {

    /// Non-prompting check. Safe to call as often as you like.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompting check — shows the system "…would like to control this computer" alert with
    /// a button through to System Settings. macOS only shows it once per app version, so we
    /// pair it with our own helper window for every subsequent nudge.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Deep-links straight to the Accessibility pane of Privacy & Security.
    static func openSystemSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Polls until the permission is granted, then calls back on the main queue.
    ///
    /// There is no notification for a TCC grant, and macOS does *not* restart the app when
    /// the user flips the switch — polling is the only option. 1 s is imperceptible to a
    /// human walking through System Settings and costs nothing.
    static func waitForTrust(timeout: TimeInterval = 300,
                             onGranted: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler {
            if isTrusted {
                timer.cancel()
                onGranted()
            } else if Date() > deadline {
                timer.cancel()
            }
        }
        timer.resume()
        // Keep the source alive for its lifetime.
        activeTimer = timer
    }

    private static var activeTimer: DispatchSourceTimer?
}
