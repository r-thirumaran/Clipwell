# SnapBoard

A menu-bar-only macOS utility that brings two things over from Windows:

- **Window snapping** with Windows semantics — halves, maximize, `Win+Down`-style
  restore-or-minimize, and Windows 11 multi-display cycling.
- **Clipboard history** — a `Win+V` replacement that survives reboots.

macOS 15+, Apple silicon and Intel. Swift 5, AppKit + SwiftUI. **Zero third-party
dependencies** — AppKit, SwiftUI, Carbon, ApplicationServices, ServiceManagement, CryptoKit,
Combine.

---

## Build and install

```bash
make install
```

That builds a Release bundle and copies it to `/Applications`, then prints the Accessibility
instructions. Then launch it and grant the permission — nothing works until you do.

`make` picks a build backend automatically:

| Backend | Used when | Notes |
|---|---|---|
| `xcodebuild` | full Xcode installed | `xcodebuild -project SnapBoard.xcodeproj -scheme SnapBoard -configuration Release` |
| `Tools/build.sh` | Command Line Tools only | plain `swiftc` + `codesign`; produces the same bundle |

Other targets: `make build`, `make run`, `make stop`, `make test`, `make uninstall`,
`make clean`, `make project`.

### Granting Accessibility

SnapBoard needs **System Settings ▸ Privacy & Security ▸ Accessibility** for two things: moving
other apps' windows, and pressing ⌘V for you. Both are the same permission. On first launch it
opens a setup window with a button straight to that pane.

> **Rebuilds and the Accessibility permission.** macOS ties the grant to the app's code
> signature. An ad-hoc signature (`CODE_SIGN_IDENTITY = "-"`) changes on every rebuild, so after
> reinstalling you may need to select SnapBoard in the Accessibility list, press **−**, and
> re-add it. If you have an Apple Development certificate, `Tools/build.sh` picks it up
> automatically and the grant then survives rebuilds.

---

## Shortcuts

All configurable in **Settings ▸ Shortcuts**.

| Default | Action |
|---|---|
| `⌃⌘←` | Snap left half |
| `⌃⌘→` | Snap right half |
| `⌃⌘↑` | Maximize to the screen's `visibleFrame` (*not* a macOS full-screen Space) |
| `⌃⌘↓` | Restore if maximized, otherwise minimize |
| `⌘⇧V` | Clipboard history panel |

**Display cycling.** Pressing ← or → again on an already-snapped window walks it across your
displays, as Windows 11 does:

```
press ←   left-half of S   →  right-half of the display left of S
          right-half of S  →  left-half of S
          anything else    →  left-half of the display it is on
press →   mirror image
```

On one display this collapses to a left/right toggle. At the outermost display the window stays
put and beeps, unless you enable **Cycling wraps around** in Settings.

**⌘+Arrow mode** (off by default) additionally binds plain `⌘←`/`⌘→`. It is off for good reason:
those keys normally jump to line start/end and go back/forward in browsers, and SnapBoard takes
them over everywhere. The Settings UI warns about this inline.

### Clipboard panel keys

| Key | Action |
|---|---|
| `↑` `↓` | Move selection (walks across the pinned/recent boundary as one list) |
| `↩` | Paste |
| `⇧↩` | Paste as plain text |
| `⌘P` | Pin / unpin |
| `⌘⌫` | Delete item (plain `⌫` also deletes when the search field is empty) |
| `⎋` | Close |

---

## How it works

```
App/                 entry point, AppDelegate wiring, status item, permission window,
                     FrontmostAppTracker
Hotkeys/             Carbon RegisterEventHotKey wrapper, KeyCombo model, recorder control
WindowManagement/    coordinate conversion, AX window wrapper, previous-frame store,
                     the snap state machine
Clipboard/           ClipItem model, store + eviction, changeCount poller, paste injection,
                     floating panel + SwiftUI list
Settings/            preferences (UserDefaults), SwiftUI settings, launch-at-login
Persistence/         Application Support paths, atomic JSON I/O
```

A few decisions worth knowing about when you maintain this:

**Carbon for hot keys, not an event tap.** `RegisterEventHotKey` genuinely *consumes* the
keystroke system-wide, so `⌃⌘←` never leaks into the focused app, and it needs no permission of
its own — hot keys work while you are still in System Settings granting the other one. Global
`NSEvent` monitors are observe-only and would not do.

**The coordinate flip is the whole ballgame.** Cocoa's origin is the bottom-left of the primary
screen; the Accessibility API's is the top-left. `ScreenGeometry` converts with
`axY = primary.maxY - cocoaRect.maxY` — the same arithmetic in both directions. Get this wrong
and windows do not drift slightly, they land on the wrong physical display. "Primary" always
means `NSScreen.screens[0]`, never `NSScreen.main` (which is merely wherever the key window is).

**Size → position → size.** Apps clamp to their own min/max, and some quantise to a character
grid. Setting the size first lets the app clamp at the old origin, the position then lands, and
the second size call re-applies the target on the destination display.

**Window identity uses `AXUIElement` itself**, boxed in a `Hashable` wrapper over
`CFEqual`/`CFHash`. The obvious alternative, `_AXUIElementGetWindow`, is a private symbol; this
stays on public API.

**Previous frames are saved only when leaving an *unmanaged* position.** So
snap-left → snap-right → maximize → `⌃⌘↓` restores to the frame you originally had, not to an
intermediate half.

**`changeCount` polling at 0.3 s is not a compromise** — `NSPasteboard` publishes no change
notification at all. Reading `changeCount` does not touch pasteboard contents, so the poll is
free until something actually changes.

**Image bytes never enter `history.json`.** They live at
`Application Support/SnapBoard/Images/<uuid>.png`. Five hundred inlined screenshots would mean
re-encoding a several-hundred-megabyte JSON file on every single copy.

**Hot keys are suspended while recording a shortcut.** Otherwise pressing `⌘⇧V` to re-record it
would just open the history panel — the registered hot key would eat the keystroke before the
recorder saw it.

### Privacy

Items are skipped when the pasteboard carries `org.nspasteboard.ConcealedType` (what password
managers set), `TransientType`, or `AutoGeneratedType`. Nothing ever leaves your Mac; the
Accessibility permission is used only to move windows and to press ⌘V.

---

## Decisions I made that the spec did not cover

- **`⌫` in the panel is overloaded.** The spec asked for `Delete` = remove, but `⌫` also has to
  edit the search field. It deletes the selected item only when unambiguous: the search field is
  empty, or `⌘` is held. Forward-delete (`⌦`) always deletes.
- **Mouse:** single click selects, double click pastes. Single-click-to-paste made stray clicks
  destructive.
- **`ClipItem.imagePNGData` is a computed accessor**, not a stored property — see the image
  storage note above. `hasImage` is what gets persisted.
- **⌘+Arrow mode adds bindings rather than replacing them**, so `⌃⌘←` keeps working when it is on.
- **Maximized window with no remembered frame** (it was already maximized before SnapBoard
  started) restores to a centred 70% rect, since there is nothing to restore *to*.
- **Pasting does not reorder history.** Re-*copying* moves an item to the top, as specified;
  pasting leaves the list where it was so it does not shuffle under you.
- **"Cycling wraps around" toggle** added, defaulting off to match Windows.
- **The panel activates the app explicitly.** The `.nonactivatingPanel` style mask is set as
  specified — it stops the panel from implicitly activating on order-front — but keyboard focus
  is a separate matter, and a search field that silently swallows typing would be useless. The
  paste target is preserved independently by `FrontmostAppTracker`, which watches
  `didActivateApplicationNotification`, so activating costs nothing. This also fixes a real bug:
  opening a status-bar menu makes SnapBoard frontmost, so reading `frontmostApplication` at
  paste time would have returned *us*.
- **Bundle ID is `com.thiru.snapboard`**; retention is swept hourly, not only at launch.

---

## Testing

```bash
make test
```

Ten automated checks (`Tools/smoketest.sh`), all passing:

```
✓ app launched and stayed running
✓ plain text copy recorded within 0.5 s
✓ concealed item was skipped                    (password-manager privacy filter)
✓ re-copy did not duplicate the entry
✓ image copy recorded as an image item
✓ image bytes stored as a separate PNG blob, not inlined in JSON
✓ history.json stayed free of image bytes
✓ history survived quit + relaunch
✓ LSUIElement is set (no Dock icon)
✓ SnapBoard does not appear as a foreground app
```

### Manual checklist

These need the Accessibility grant and a human at the keyboard:

- [ ] Snap works in Safari, Finder, VS Code and Terminal
- [ ] On two displays, `⌃⌘←`/`⌃⌘→` cycle to the correct monitor
- [ ] `⌃⌘↑` then `⌃⌘↓` returns the window to its exact previous frame
- [ ] `⌃⌘↓` again minimizes
- [ ] Copy a password from your password manager — it must **not** appear
- [ ] History survives a reboot
- [ ] `⌘⇧V` → type to search → `↩` pastes into the app you were just in
- [ ] Launch at login works after `make install` (enable it *after* installing, so the login
      item points at `/Applications` rather than a build directory)

---

## Known caveats

- **macOS ships its own window tiling shortcuts** (System Settings ▸ Desktop & Dock ▸ Windows,
  and Keyboard Shortcuts). If a default collides on your setup, SnapBoard logs it, and shows an
  alert if the collision appears while you are changing shortcuts in Settings. All five defaults
  registered cleanly on macOS 26.5 during testing.
- **Some windows resist exact sizing.** Terminal quantises to a character grid; apps with
  min/max constraints clamp. The size→position→size workaround handles most of it, and such
  windows still land at the correct origin.
- **Non-standard windows are skipped** — sheets, popovers and system dialogs report a subrole
  other than `AXStandardWindow` and are left alone; moving them is visually broken. Windows that
  publish no subrole at all (much of Electron) are treated as eligible.
- **`Tools/generate_xcodeproj.py` is optional.** The `.xcodeproj` is committed; regenerate it
  only after adding or moving source files. It writes deterministic IDs, so a no-op run produces
  a byte-identical file.
