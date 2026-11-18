# PureSweep for macOS

A native SwiftUI version of PureSweep for macOS 14 (Sonoma) and later. It does the same jobs as the Windows app, mapped to how macOS works, in a dark full-window style with a gradient that changes per section and one big round action button per page.

> **Status: early release (1.0).** Scanning is read-only and safe. Cleaning, shredding, uninstalling, snapshot deletion and the login-item switches change real things and have had limited real-world testing. Try them on throwaway data first.

## Features

| Page | What it does | Windows counterpart |
| --- | --- | --- |
| **Home** | Live disk, memory and CPU gauges, Smart Scan, cleaning history, and shortcuts to each tool. | Home |
| **Cleanup** | Scans seven categories of junk, lets you open each one to keep or clean individual folders, then deletes what you ticked. | Cleanup |
| **Snapshots** | Lists Time Machine local snapshots, shows purgeable space, and deletes snapshots (macOS password prompt if needed). | Hibernation |
| **Uninstaller** | Lists apps in /Applications and ~/Applications with size and version. Uninstalling quits the app, then moves it **and its leftover support files** in ~/Library to the Trash, so it can be undone. | Uninstaller |
| **Login Items** | Lists launch agents (yours and all users') and, optionally, system daemons. Switches use `launchctl disable/enable`: nothing is deleted. Links to System Settings for login items macOS manages itself. | Startup |
| **Large Files** | Finds the biggest files in your home folder (50 MB to 1 GB and up). Show in Finder or move to the Trash. | (new) |
| **Maintenance** | One-click resets for system caches: DNS, Quick Look previews, fonts, the "Open With" menu (Launch Services) and the Spotlight index. DNS and Spotlight ask for your password. | Maintenance |
| **Shredder** | Overwrites files or folders with random data (1, 3 or 7 passes) before deleting them. Shows whether FileVault is on. | Shredder |
| **Settings** (⌘,) | Keep recent files, menu bar extra, open at login, Full Disk Access status, appearance of Settings and the menu bar. | Settings |

Mac-only extras: a **menu bar extra** with live disk, memory and CPU meters and a Smart Scan button (closing the window keeps PureSweep running there), **Open at login** through `SMAppService`, keyboard shortcuts (⌘1–⌘8 for the pages, ⇧⌘R for Smart Scan), and drag-and-drop onto the Shredder.

### What Cleanup looks for

User caches (`~/Library/Caches`), temporary files (`$TMPDIR`), browser caches (Safari, Chrome, Edge, Brave, Arc, Firefox), app logs (`~/Library/Logs`), crash and hang reports, developer caches (Xcode DerivedData and device support files, simulator caches, Homebrew, pip, Yarn and npm downloads) and the Trash.

Only your own account's files are touched. There are no system-wide categories, because deleting from `/Library` or `/private/var` needs root and is rarely worth it.

## Safety

- **Scanning never deletes anything.** Cleaning asks for confirmation and names the categories it will empty.
- **Recent files are kept.** Caches, temporary files and logs changed in the last 24 hours are skipped (apps may still be using them) unless you turn that off. The check is repeated at the moment of deletion.
- **The Trash is not ticked by default**, since it is the safety net for deleted files.
- **Browser caches only.** History, cookies and saved logins are not touched.
- **Some cache folders are always skipped** because emptying them can sign you out or break syncing (CloudKit, iCloud Drive's `com.apple.bird`, HomeKit and similar).
- **Uninstalling moves to the Trash**, never deletes. Leftovers are matched only by the app's exact bundle identifier or exact name, and you can untick any of them. Apple's own apps are not listed.
- **Shredder refuses dangerous targets:** volume roots, anything in `/System`, `/usr`, `/bin`, `/sbin` or `/Library`, your home folder and its standard folders (Desktop, Documents, …), and any folder that contains one of those. Symbolic links are removed, never followed.
- **Shredding is not a guarantee on a Mac.** Macs use solid-state disks, and APFS, Time Machine local snapshots and iCloud can keep other copies of the data. FileVault is the dependable protection, and the Shredder page says whether it is on.

### Full Disk Access

macOS privacy protection blocks reading the Trash and Safari's cache. Those categories show a **Full Disk Access** badge until you allow PureSweep in System Settings → Privacy & Security → Full Disk Access. Everything else works without it. Large Files may make macOS ask once for access to Desktop, Documents and Downloads.

## Build

Needs Xcode 15 or later (or its command line tools). There is no Xcode project: it is a plain Swift package.

```bash
./macOS/build.sh            # universal app (Apple silicon + Intel)
./macOS/build.sh --native   # this Mac's architecture only, faster
```

Output (git-ignored): `macOS/dist/PureSweep.app` and `macOS/dist/PureSweep.dmg` (drag-to-Applications disk image).

The default build is ad-hoc signed. That is fine on the Mac that built it, but a copy downloaded from the internet is blocked by Gatekeeper. On macOS 15 and later the user has to try to open it, then go to System Settings → Privacy & Security and click **Open Anyway**. To avoid that, publish a notarized build (below).

The app is not sandboxed (a cleaner has to reach other apps' caches), so it can't go on the Mac App Store as it is. Distribution is a direct download.

## Sharing without a developer account

The default build is all you need to give PureSweep to someone: send them `macOS/dist/PureSweep.dmg` (AirDrop, Messages, email, a file link or a GitHub release). It runs on Apple silicon and Intel Macs with macOS 14 or later. Don't send a `--native` build, which only runs on the architecture it was built on.

Because it isn't notarized, the recipient approves it once: open it, click **Done** at the warning, then System Settings → Privacy & Security → **Open Anyway**. The DMG includes `How to open PureSweep.txt` with these steps. Only send it to people who trust you, since they are skipping Apple's check.

## Release (optional: notarized, needs a paid Apple Developer account)

One-time setup:

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) (US$99 a year).
2. In Xcode → Settings → Accounts → Manage Certificates, create a **Developer ID Application** certificate. Check it with `security find-identity -v -p codesigning`.
3. Create an [app-specific password](https://account.apple.com) for your Apple Account, then store notarization credentials in the keychain:

   ```bash
   xcrun notarytool store-credentials puresweep --apple-id you@example.com --team-id TEAMID
   ```

Each release:

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Build, sign, notarize and staple:

   ```bash
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=puresweep ./macOS/build.sh
   ```

   The last line should say `accepted` and `source=Notarized Developer ID`.
3. Upload `macOS/dist/PureSweep.dmg` to a GitHub release (for example `gh release create v1.0 macOS/dist/PureSweep.dmg`).

Users download the DMG, open it and drag PureSweep to Applications. The first launch shows only the normal "downloaded from the internet" confirmation.

For development, `swift build` and run `.build/debug/PureSweep`, or open `macOS/Package.swift` in Xcode.

## Layout

```
macOS/
  Package.swift
  build.sh                 app bundle, icon, ad-hoc signing and DMG
  Resources/Info.plist     bundle metadata and privacy prompt texts
  Resources/AppIcon.icns   generated by tools/make-icon.swift if missing
  Sources/PureSweep/
    PureSweepApp.swift     scenes (window, Settings, menu bar extra), window shell and sidebar
    Core/                  logic with no UI: Junk, CleanupModel, Apps, LoginItems, Snapshots, LargeFiles, Maintenance, Shredder, Stats, Util
    Views/                 one view per page, plus Components (theme, glass cards, big button, gauges)
```

Settings and cleaning history are kept in `~/Library/Preferences/com.puresweep.mac.plist`.
