import AppKit
import Combine

/// How long clipboard items are kept before they are swept.
enum Retention: String, Codable, CaseIterable, Identifiable {
    case forever
    case days30
    case days7

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forever: return "Forever"
        case .days30:  return "30 days"
        case .days7:   return "7 days"
        }
    }

    /// `nil` means "never expire".
    var maxAge: TimeInterval? {
        switch self {
        case .forever: return nil
        case .days30:  return 30 * 24 * 60 * 60
        case .days7:   return 7 * 24 * 60 * 60
        }
    }
}

/// All user-facing settings, backed by `UserDefaults`.
///
/// Anything that changes hot key registration or the capture timer posts
/// `Preferences.didChangeNotification`; `AppDelegate` is the single listener and re-applies
/// the world from scratch. That keeps the "who reacts to what" story to one place.
final class Preferences: ObservableObject {

    static let shared = Preferences()
    static let didChangeNotification = Notification.Name("SnapBoardPreferencesDidChange")

    private let defaults = UserDefaults.standard

    // MARK: - Hot keys

    @Published var snapLeft: KeyCombo {
        didSet { store(snapLeft, "hk.snapLeft"); announce() }
    }
    @Published var snapRight: KeyCombo {
        didSet { store(snapRight, "hk.snapRight"); announce() }
    }
    @Published var maximize: KeyCombo {
        didSet { store(maximize, "hk.maximize"); announce() }
    }
    @Published var restoreOrMinimize: KeyCombo {
        didSet { store(restoreOrMinimize, "hk.restoreOrMinimize"); announce() }
    }
    @Published var showClipboard: KeyCombo {
        didSet { store(showClipboard, "hk.showClipboard"); announce() }
    }

    /// When on, plain ⌘← / ⌘→ *additionally* snap. The primary bindings keep working.
    /// This steals text-navigation (line start/end) and browser back/forward — the Settings
    /// UI says so in as many words.
    @Published var cmdArrowMode: Bool {
        didSet { defaults.set(cmdArrowMode, forKey: "cmdArrowMode"); announce() }
    }

    // MARK: - Window management

    /// Whether display cycling wraps around at the outermost screen. Windows does not wrap;
    /// off by default to match.
    @Published var wrapDisplays: Bool {
        didSet { defaults.set(wrapDisplays, forKey: "wrapDisplays") }
    }

    // MARK: - Clipboard

    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: "historyLimit"); announce() }
    }
    @Published var retention: Retention {
        didSet { defaults.set(retention.rawValue, forKey: "retention"); announce() }
    }
    /// Milliseconds to wait after re-activating the target app before synthesizing ⌘V.
    /// Too short and the keystroke lands in the wrong process; 120 ms is comfortable on
    /// Apple silicon, but slow-launching apps may want more.
    @Published var pasteDelayMs: Double {
        didSet { defaults.set(pasteDelayMs, forKey: "pasteDelayMs") }
    }

    // MARK: - Login item

    /// Mirrors `SMAppService.mainApp.status`; the setter is driven by `LaunchAtLogin`.
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LaunchAtLogin.isEnabled else { return }
            LaunchAtLogin.set(launchAtLogin)
        }
    }

    // MARK: - Init

    private init() {
        snapLeft          = Preferences.load("hk.snapLeft") ?? .defaultSnapLeft
        snapRight         = Preferences.load("hk.snapRight") ?? .defaultSnapRight
        maximize          = Preferences.load("hk.maximize") ?? .defaultMaximize
        restoreOrMinimize = Preferences.load("hk.restoreOrMinimize") ?? .defaultRestoreOrMinimize
        showClipboard     = Preferences.load("hk.showClipboard") ?? .defaultShowClipboard

        let d = UserDefaults.standard
        cmdArrowMode = d.bool(forKey: "cmdArrowMode")
        wrapDisplays = d.bool(forKey: "wrapDisplays")
        historyLimit = d.object(forKey: "historyLimit") as? Int ?? 500
        retention    = Retention(rawValue: d.string(forKey: "retention") ?? "") ?? .forever
        pasteDelayMs = d.object(forKey: "pasteDelayMs") as? Double ?? 120
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    // MARK: - Bindings snapshot

    /// The hot key set to hand to `HotKeyManager`, honouring `cmdArrowMode`.
    var hotKeyBindings: [HotKeyAction: KeyCombo] {
        var map: [HotKeyAction: KeyCombo] = [
            .snapLeft: snapLeft,
            .snapRight: snapRight,
            .maximize: maximize,
            .restoreOrMinimize: restoreOrMinimize,
            .showClipboard: showClipboard,
        ]
        if cmdArrowMode {
            map[.cmdArrowLeft] = .cmdArrowLeft
            map[.cmdArrowRight] = .cmdArrowRight
        }
        return map
    }

    func resetHotKeysToDefaults() {
        snapLeft = .defaultSnapLeft
        snapRight = .defaultSnapRight
        maximize = .defaultMaximize
        restoreOrMinimize = .defaultRestoreOrMinimize
        showClipboard = .defaultShowClipboard
    }

    // MARK: - Storage plumbing

    private static func load(_ key: String) -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    private func store(_ combo: KeyCombo, _ key: String) {
        guard let data = try? JSONEncoder().encode(combo) else { return }
        defaults.set(data, forKey: key)
    }

    private func announce() {
        NotificationCenter.default.post(name: Preferences.didChangeNotification, object: self)
    }
}
