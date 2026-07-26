# Distributing SnapBoard

## The Mac App Store is not an option

Not "hard" — impossible. The App Store requires **App Sandbox**, and the Accessibility API
does not function inside a sandbox. SnapBoard's two features *are* Accessibility: moving other
apps' windows, and synthesising ⌘V. Turning the sandbox on turns the app into a menu bar icon
that can do nothing.

This is why every comparable tool — Rectangle, Raycast, Maccy, Alfred, BetterTouchTool — ships
outside the store, direct from the developer. It is the normal, expected distribution model for
this category, not a workaround.

(Clipboard-history apps *do* exist on the store — Paste, Pastebot. They give up the automatic
⌘V injection, or use a separate helper the user installs manually. If you ever wanted store
distribution you would have to drop window snapping entirely and accept a worse paste flow.)

---

## The three ways to sign it

| | Cost | Recipient friction | Grant survives updates? | Good for |
|---|---|---|---|---|
| **Ad-hoc** (today) | free | must run `xattr -dr` | **no** — re-grant every build | you, 2–3 patient colleagues |
| **Apple Development** | free | same as ad-hoc | yes, but only on registered Macs | your own machines |
| **Developer ID + notarised** | $99/yr | none — just drag | **yes** | a real team test |

### What "grant survives updates" means, and why it matters most

macOS ties the Accessibility permission to the app's **code signature**. An ad-hoc signature is
regenerated on every single build, so every update you send your team is, to macOS, a different
app. They will see SnapBoard already listed with the switch ON while the newly installed copy is
silently denied — it looks like the app is broken for no reason.

This is not theoretical: it happened on this machine. `tccutil` found **three** stale entries
from three rebuilds, all of which had to be cleared before the permission worked.

Over a multi-week team test with a few updates, this will generate more confusion than every
other issue combined. It is the single strongest argument for paying the $99.

The fix, per update, is:

```bash
tccutil reset Accessibility com.thiru.snapboard
# then re-add the app in System Settings > Privacy & Security > Accessibility
```

---

## Option A — ship what you have now (free)

```bash
make dmg          # -> build/SnapBoard-1.0.dmg  (~850 KB)
```

The disk image contains the app, an Applications symlink to drag onto, and
`READ-ME-FIRST.txt` with install steps written for a non-technical colleague.

Send it however you like — Slack, email, Drive, AirDrop. Recipients must run:

```bash
xattr -dr com.apple.quarantine /Applications/SnapBoard.app
```

Without it: *"SnapBoard is damaged and can't be opened."* That message is Gatekeeper refusing an
ad-hoc signature that carries a download quarantine flag. Nothing is actually damaged.

**Honest assessment:** fine for a handful of colleagues who will tolerate a Terminal command and
an occasional re-grant. It does not scale past that, and it will make the app look flaky.

---

## Option B — Developer ID + notarisation ($99/yr) — recommended for a team test

Recipients just drag and go. No Terminal. No quarantine step. No "damaged" dialog. Permission
grants persist across updates because the signature is stable.

**One-time setup**

1. Join the Apple Developer Program (~$99/yr, ~24–48 h to activate).
2. Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ **+** ▸ *Developer ID Application*.
3. Create an app-specific password at appleid.apple.com, then store credentials:

```bash
xcrun notarytool store-credentials snapboard-notary \
  --apple-id you@example.com --team-id YOURTEAMID --password app-specific-password
```

**Required build change.** Notarisation requires the hardened runtime, which is currently off:

```
ENABLE_HARDENED_RUNTIME = YES
```

Set it in `Tools/generate_xcodeproj.py` (`shared_target_settings`) and re-run
`make project`. The hardened runtime does **not** interfere with Accessibility or
`CGEvent` posting — those are gated by TCC, not by entitlements, so no extra entitlement is
needed.

**Per release**

```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" build/SnapBoard.app

make dmg
xcrun notarytool submit build/SnapBoard-1.0.dmg --keychain-profile snapboard-notary --wait
xcrun stapler staple build/SnapBoard-1.0.dmg     # lets it validate offline
```

Check where you stand at any time:

```bash
make signing-status
```

---

## Before you send it to anyone

**Managed Macs may refuse it outright.** If your colleagues are on company-managed hardware, a
PPPC configuration profile likely governs which apps may receive Accessibility. An app that is
not on IT's allowlist cannot be enabled — the switch reverts silently and there is no user-side
workaround. Ask IT first; notarisation helps your case but does not override an MDM policy.

**Clipboard history is a data-handling question.** SnapBoard stores everything copied as
unencrypted JSON at `~/Library/Application Support/SnapBoard/history.json`. On work machines
that will accumulate customer data, internal material, and anything pasted from a vault that
does not set the concealed-type marker. Flag this to your team explicitly rather than letting
them discover it, suggest a 7-day retention, and check your company's policy before a wider
roll-out. If encryption at rest is needed, that is a contained change to the persistence layer —
worth doing before this spreads.

**Tell people what to report.** A short list beats vague feedback: which app the window was in,
which display, what they pressed, what happened instead.
