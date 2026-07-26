import AppKit
import SwiftUI

struct SettingsView: View {

    @ObservedObject var preferences: Preferences
    @ObservedObject var store: ClipboardStore

    @State private var accessibilityGranted = AccessibilityPermission.isTrusted

    var body: some View {
        TabView {
            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            clipboardTab
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 440)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibilityGranted = AccessibilityPermission.isTrusted
        }
    }

    // MARK: - Shortcuts

    private var shortcutsTab: some View {
        Form {
            Section {
                recorder("Snap Left Half", $preferences.snapLeft)
                recorder("Snap Right Half", $preferences.snapRight)
                recorder("Maximize", $preferences.maximize)
                recorder("Restore / Minimize", $preferences.restoreOrMinimize)
            } header: {
                Text("Window Snapping")
            } footer: {
                Text("Press Left or Right again on a window that is already snapped to move it "
                     + "to the next display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Clipboard") {
                recorder("Show History Panel", $preferences.showClipboard)
            }

            Section {
                Toggle("Also use ⌘← and ⌘→ to snap", isOn: $preferences.cmdArrowMode)
                if preferences.cmdArrowMode {
                    Label {
                        Text("⌘← and ⌘→ normally jump to the start and end of a line, and go "
                             + "back and forward in browsers. While this is on, SnapBoard takes "
                             + "them over everywhere and those uses stop working.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("⌘+Arrow Mode")
            }

            Section {
                Toggle("Cycling wraps around at the outermost display",
                       isOn: $preferences.wrapDisplays)
                HStack {
                    Spacer()
                    Button("Reset Shortcuts to Defaults") {
                        preferences.resetHotKeysToDefaults()
                    }
                }
            } header: {
                Text("Displays")
            }
        }
        .formStyle(.grouped)
    }

    private func recorder(_ label: String, _ binding: Binding<KeyCombo>) -> some View {
        HStack {
            Text(label)
            Spacer()
            HotKeyRecorder(combo: binding)
                .frame(width: 130, height: 24)
        }
    }

    // MARK: - Clipboard

    private var clipboardTab: some View {
        Form {
            Section {
                Picker("Keep items for", selection: $preferences.retention) {
                    ForEach(Retention.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Stepper(value: $preferences.historyLimit, in: 10...2000, step: 10) {
                    HStack {
                        Text("Maximum items")
                        Spacer()
                        Text("\(preferences.historyLimit)").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("History")
            } footer: {
                Text("Pinned items are never evicted and never expire.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Currently stored")
                    Spacer()
                    Text("\(store.items.count) items · \(store.items.filter(\.isPinned).count) pinned")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Clear History (Keeps Pinned)", role: .destructive) {
                        store.clearUnpinned()
                    }
                    .disabled(!store.items.contains { !$0.isPinned })
                }
            }

            Section {
                HStack {
                    Text("Paste delay")
                    Spacer()
                    Text("\(Int(preferences.pasteDelayMs)) ms").foregroundStyle(.secondary)
                }
                Slider(value: $preferences.pasteDelayMs, in: 40...400, step: 10)
            } header: {
                Text("Advanced")
            } footer: {
                Text("How long SnapBoard waits after switching back to the target app before "
                     + "pressing ⌘V. Increase it if pasting occasionally lands in the wrong "
                     + "place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch SnapBoard at login", isOn: $preferences.launchAtLogin)
                if LaunchAtLogin.requiresApproval {
                    HStack {
                        Text("macOS is waiting for your approval in Login Items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("Enable this after running `make install`, so the login item points at the "
                     + "copy in /Applications rather than a build directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Image(systemName: accessibilityGranted
                          ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(accessibilityGranted ? Color.green : Color.orange)
                    Text(accessibilityGranted
                         ? "Accessibility access granted"
                         : "Accessibility access is required")
                    Spacer()
                    Button("Open Settings") { AccessibilityPermission.openSystemSettings() }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Needed to move windows and to press ⌘V for you. If you rebuild SnapBoard, "
                     + "macOS may ask for it again — remove the old entry in the list and "
                     + "re-add the new app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.shortVersion).foregroundStyle(.secondary)
                }
                HStack {
                    Text("History file")
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Storage.historyFile])
                    }
                }
                HStack {
                    Spacer()
                    Button("Quit SnapBoard") { NSApp.terminate(nil) }
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
    }
}

extension Bundle {
    var shortVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
