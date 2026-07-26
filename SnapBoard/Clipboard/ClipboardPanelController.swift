import AppKit
import Carbon.HIToolbox
import SwiftUI

/// An `NSPanel` that takes keyboard focus **without** activating SnapBoard.
///
/// This is what makes the paste story work: the app stays in the background, so the app the
/// user was typing in is never displaced and we can hand focus straight back to it. A normal
/// `NSWindow` would activate SnapBoard. `canBecomeMain` stays false — a main window implies
/// activation.
final class NonactivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the ⌘⇧V history panel: presentation, keyboard handling and the paste hand-off.
final class ClipboardPanelController: NSObject, NSWindowDelegate {

    private let store: ClipboardStore
    private let preferences: Preferences
    private let tracker: FrontmostAppTracker
    private let model: ClipboardPanelModel

    /// Set by `AppDelegate` so a paste can suppress re-capturing its own pasteboard write.
    weak var monitor: ClipboardMonitor?

    private var panel: NonactivatingPanel?
    private var keyMonitor: Any?

    init(store: ClipboardStore,
         tracker: FrontmostAppTracker,
         preferences: Preferences = .shared) {
        self.store = store
        self.tracker = tracker
        self.preferences = preferences
        self.model = ClipboardPanelModel(store: store)
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Presentation

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        model.searchText = ""
        model.selectedIndex = 0

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)

        // The `.nonactivatingPanel` style mask stops the panel from *implicitly* activating
        // the app when ordered front, which is what keeps it floating over everything without
        // disturbing window layering. Keyboard focus is a separate question: a background app
        // is not guaranteed to receive key events, and a search field that silently swallows
        // typing would make the whole panel useless. So we activate explicitly.
        //
        // This costs nothing here because the paste target is tracked independently by
        // `FrontmostAppTracker` rather than read at paste time — and for an `.accessory` app
        // activation is invisible: no Dock icon, no menu bar change.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    /// - Parameter restoringFocus: hand activation back to the app the user came from. False
    ///   when the user has already chosen where focus goes (they clicked another app), or when
    ///   the caller is about to activate a target itself (the paste path).
    func close(restoringFocus: Bool = true) {
        removeKeyMonitor()
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        if restoringFocus { tracker.lastExternalApp?.activate() }
    }

    private func makePanel() -> NonactivatingPanel {
        let panel = NonactivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false)

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        // Follow the user across Spaces and sit above full-screen apps, like Spotlight.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self

        let root = ClipboardHistoryView(
            model: model,
            onPaste: { [weak self] plainOnly in
                guard let self, let item = self.model.selectedItem else { NSSound.beep(); return }
                self.performPaste(item, plainTextOnly: plainOnly)
            },
            onClose: { [weak self] in self?.close() })
        panel.contentView = NSHostingView(rootView: root)

        return panel
    }

    /// Centres the panel on the display holding the pointer — the most reliable proxy for
    /// "the screen the user is looking at" on a multi-monitor desk.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             // Slightly above dead centre reads better than true centre.
                             y: visible.midY - size.height / 2 + visible.height * 0.06)
        panel.setFrameOrigin(origin)
    }

    /// Dismiss when the user clicks away, the way Spotlight does.
    ///
    /// Focus is deliberately *not* restored here: the user just clicked somewhere, so they
    /// have already said where they want to be. Re-activating the remembered app would yank
    /// them back out of it.
    func windowDidResignKey(_ notification: Notification) {
        close(restoringFocus: false)
    }

    // MARK: - Keyboard

    /// Keys are intercepted with a local monitor rather than SwiftUI's `.onKeyPress` because
    /// the search field is first responder and would otherwise swallow ↑/↓ (they move the
    /// insertion point) and ↩. A monitor sees the event first and decides per-key whether to
    /// consume it or let the field have it.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns `nil` to swallow the event, or the event to pass it through to the text field.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard panel?.isKeyWindow == true else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch Int(event.keyCode) {
        case kVK_Escape:
            close()
            return nil

        case kVK_DownArrow:
            model.moveSelection(by: 1)
            return nil

        case kVK_UpArrow:
            model.moveSelection(by: -1)
            return nil

        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = model.selectedItem {
                performPaste(item, plainTextOnly: flags.contains(.shift))
            } else {
                NSSound.beep()
            }
            return nil

        case kVK_ANSI_P where flags.contains(.command):
            model.togglePinSelected()
            return nil

        case kVK_ForwardDelete:
            model.removeSelected()
            return nil

        case kVK_Delete:
            // ⌫ has to keep editing the search field. It deletes the selected *item* only
            // when unambiguous: the field is empty, or ⌘ is held.
            if flags.contains(.command) || model.searchText.isEmpty {
                model.removeSelected()
                return nil
            }
            return event

        default:
            return event
        }
    }

    // MARK: - Paste

    /// Close → write pasteboard → re-activate the target → synthesize ⌘V.
    ///
    /// Order matters. The panel must be gone and the target app frontmost *before* the
    /// keystroke is posted, or the ⌘V lands somewhere useless. `activate()` is asynchronous,
    /// hence the short delay (tunable in Settings for slow apps).
    ///
    /// Takes the item explicitly rather than reading the panel's selection, so the status-bar
    /// menu — which has no selection and may be showing a different slice of history — pastes
    /// exactly what was clicked.
    func performPaste(_ item: ClipItem, plainTextOnly: Bool) {
        guard AccessibilityPermission.isTrusted else {
            // Without the permission we cannot synthesize the keystroke, but putting the item
            // on the pasteboard is still useful — the user can press ⌘V themselves.
            Paster.writeToPasteboard(item, plainTextOnly: plainTextOnly)
            close()
            NotificationCenter.default.post(name: .snapBoardNeedsAccessibility, object: nil)
            return
        }

        let target = tracker.lastExternalApp
        // This path activates `target` itself a few lines down; letting close() restore focus
        // first would just cause two activations to race.
        close(restoringFocus: false)

        let changeCount = Paster.writeToPasteboard(item, plainTextOnly: plainTextOnly)
        // Our own write must not come back as a new history entry attributed to SnapBoard.
        monitor?.suppressedChangeCount = changeCount

        target?.activate()

        let delay = max(0.02, preferences.pasteDelayMs / 1000)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Paster.synthesizeCommandV()
        }
    }
}
