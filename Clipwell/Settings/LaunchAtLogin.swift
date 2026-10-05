import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` — the modern (macOS 13+) replacement for
/// `SMLoginItemSetEnabled` and login-item helper bundles.
///
/// Note for future-you: registration is keyed off the app's *bundle identifier and location*.
/// Registering while the app runs from DerivedData and then moving it to /Applications leaves
/// a stale entry behind — which is why the first-run default below only fires for an
/// installed copy, and why a hand-enabled toggle should wait until after `make install`.
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `true` if macOS is holding the registration behind the user's approval in
    /// System Settings ▸ General ▸ Login Items.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// `true` when this copy runs from /Applications or ~/Applications — the place a login
    /// item should point at. A build directory, the mounted disk image, and Gatekeeper's
    /// App Translocation path (`/private/var/folders/…`) all come back `false`.
    static var isInstalled: Bool {
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let appDirs = FileManager.default.urls(for: .applicationDirectory,
                                               in: [.localDomainMask, .userDomainMask])
        return appDirs.contains { bundle.hasPrefix($0.resolvingSymlinksInPath().path + "/") }
    }

    /// Switches the login item on the first time the installed app runs, so Clipwell is back
    /// in the menu bar after a restart without anyone having to go looking for the setting.
    ///
    /// Fires once. After that the user owns it: turning it off in Settings, the menu bar, or
    /// System Settings ▸ Login Items is never undone. Launches from anywhere other than an
    /// Applications folder don't use up the one go, so `make run` followed by `make install`
    /// still gets the default on the installed copy.
    static func enableByDefaultIfNeeded() {
        let appliedKey = "launchAtLoginDefaultApplied"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: appliedKey), isInstalled else { return }
        defaults.set(true, forKey: appliedKey)

        switch SMAppService.mainApp.status {
        case .notRegistered, .notFound:
            // `.notFound` is what some macOS versions report for an app that has simply
            // never been registered, so it counts as a clean slate too.
            set(true)
        case .enabled, .requiresApproval:
            // Already on, or the user switched it off in System Settings — a decision either
            // way, not an absence of one.
            break
        @unknown default:
            break
        }
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                // Registering when already registered throws; harmless, but avoid the noise.
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Clipwell: launch-at-login \(enabled ? "register" : "unregister") failed: \(error)")
            return false
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
