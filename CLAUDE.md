# PureSweep

A Windows PC cleaner: WPF on .NET Framework 4.8.1, using ModernWpf 0.9.6 (the WPF port of the WinUI 2
controls). Full-trust desktop app, not UWP. Its look matches the macOS version in `macOS/` (see below).

## Build

```powershell
.\PureSweep\build.ps1
```

Needs Visual Studio 2022 or the VS Build Tools (MSBuild + Roslyn) and the .NET Framework 4.8.1
targeting pack. There is no .NET SDK, NuGet restore or WiX involved:

- `PureSweep.csproj` is a classic (non-SDK) project. ModernWpf is referenced as two DLLs checked
  in under `PureSweep/lib/`.
- Output: `PureSweep/bin/PureSweep.exe`, `PureSweep/dist/PureSweep.msi`,
  `PureSweep/dist/PureSweepSetup.exe`. `bin`, `obj` and `dist` are git-ignored.
- `tools/make-msi.ps1` builds the MSI with the Windows Installer COM API and `makecab.exe`.
  Each build gets a new ProductCode; the fixed UpgradeCode makes it replace any installed version.
- The MSI has its own minimal UI (Dialog/Control tables in `make-msi.ps1`): a progress dialog,
  a finish dialog with a "Launch PureSweep" checkbox (`LAUNCHAPP`, custom action `LaunchApp`),
  and an error dialog. Text there can't contain apostrophes because of the SQL quoting.
- `tools/make-icon.ps1` regenerates `app.ico` (only runs if the icon is missing).
- No Windows PC? `dotnet build PureSweep/tools/compile-check` compiles the same C# and XAML on macOS or
  Linux (SDK-style project, net481, `EnableWindowsTargeting`). It catches code and most XAML errors, not
  missing `StaticResource` keys or anything else that only fails at runtime.

Prefer the MSI for deployment. The owner's antivirus deleted `PureSweepSetup.exe` (an unsigned
exe that unpacks other exes). Nothing is code-signed.

## Layout

- `Core/` - logic with no UI: `Junk.cs` (scan/clean categories and drill-down groups),
  `Apps.cs` (installed programs), `Startup.cs` (sign-in items via the StartupApproved registry
  flags Task Manager uses), `Shredder.cs`, `Util.cs` (helpers and `AppSettings`).
- `Controls/` - `Hero` (page header), `Emblem` (glowing start-screen circle, optional spinning arc) and
  `RingGauge` (dashboard dial, also the progress ring around Cleanup's button).
- `Pages/` - one UserControl per sidebar item: Home, Cleanup, Uninstaller, Startup, Hibernation,
  Shredder, Settings. `MainWindow` builds a custom sidebar (RadioButtons, style `NavItem`) from its
  `Pages` table and caches each page instance.
- `Setup/` - the single-file exe installer (embeds the app as resources).
- `App.xaml` - shared styles: `Card` (glass panel), `Push3D` / `Push3DAccent` / `Push3DHero` /
  `Push3DDanger` (frosted pill buttons; the old names were kept), `RoundPush3D` (the big glowing round
  action), `Link`, `TileButton`, `NavItem` / `NavSection`, and the `Hero` and `Emblem` templates.

## Look

Same as the macOS app: always dark (`AppSettings.Apply`), a full-window gradient per page that animates
on page change, and the page's bright accent pushed into `ThemeManager.Current.AccentColor`, so
anything using `SystemAccentColor` follows the page. Colours live in `MainWindow.Pages` and match
`macOS/Sources/PureSweep/Views/Components.swift`. The title bar is extended into the view
(`ui:TitleBar.ExtendViewIntoTitleBar`), so page content starts 32px down. Cleanup has four screens
(start, working, results, cleaned) switched by `CleanupPage.UpdateMode()`. The old theme and accent
settings are still read and written but no longer used.

## Behaviour worth knowing

- Runs as the invoking user. System locations (Windows temp, Update cache, Windows logs) only
  clean after "Restart as administrator". Hibernation toggles through an elevated `powercfg`.
- Installs per-user to `%LocalAppData%\Programs\PureSweep`; settings and cleaning history live in
  `%AppData%\PureSweep\settings.txt`.
- Temp and log categories skip files changed in the last 24 hours unless the setting is off.
- There is deliberately no registry cleaner.

## Gotchas found the hard way

- ModernWpf 0.9.6 has no `InfoBar`; banners are plain `Border`s.
- Don't put `x:Name`d elements inside a UserControl used as a container (XAML error MC3093).
  `Hero` is a `ContentControl` subclass for that reason.
- Brushes that use `DynamicResource` colours must be declared inline on an element or inside a
  template, not as shared resources, or they won't follow accent/theme changes.
- In `make-msi.ps1`, arguments passed to COM via `InvokeMember` must be unwrapped from PSObject
  or the call fails with a type mismatch.

## Testing

No automated tests. Verification so far was by launching the app and screenshotting each page in
light and dark themes, plus silent MSI install / upgrade / uninstall (`msiexec /i|/x ... /qn`).
Never exercised: pressing Clean, uninstalling a real program, shredding, toggling hibernation,
and the interactive setup window. Scanning is read-only and safe to run; cleaning and shredding
delete real files, so test those against throwaway data.

The dark look (custom sidebar, per-page gradients, Cleanup's four screens) was written on a Mac and has
only been compiled with `tools/compile-check`, never run. Check every page on Windows before release.

## macOS version (`macOS/`)

Native SwiftUI app, macOS 14+, plain SwiftPM package (no .xcodeproj). `macOS/build.sh` builds a
universal release, wraps it into `dist/PureSweep.app` (Info.plist from `Resources/`, icon from
`tools/make-icon.swift`), signs ad-hoc (or `SIGN_IDENTITY`) and makes `dist/PureSweep.dmg`.
`macOS/README.md` has the user-facing details.

- Page mapping: Hibernation → Snapshots (Time Machine local snapshots via `tmutil`), Startup →
  Login Items (launch agents/daemons toggled with `launchctl disable/enable`, never deleted),
  Settings → the standard Settings scene (⌘,). New: Large Files, menu bar extra, open at login.
- Admin actions go through `Util.runAsAdmin` (osascript `with administrator privileges`), the
  macOS counterpart of UAC. Only snapshot deletion and system daemons need it.
- Not sandboxed. The Trash and Safari's cache need Full Disk Access; `JunkScanner` marks a
  category `blocked` when listing a root fails with a permission error, and the UI shows a badge.
- Uninstall moves the app and its leftovers to the Trash (`Trash.move`), falling back to Finder
  via AppleScript for root-owned apps, which shows Finder's own password prompt.
- Look (shared with Windows): the main window is always dark, with a per-page gradient (`AppModel.Page.palette`/`accent`
  in `Views/Components.swift`), glass cards, `BigActionButton`, `HeroEmblem`. The window is
  styled through `WindowStyler` (transparent title bar). Keep MacPaw's names and artwork out.
- Debug builds: `PURESWEEP_SNAPSHOT=<dir> .build/debug/PureSweep` renders every page to PNG
  (runs a real, read-only Cleanup scan) and quits. Use it to check layouts without
  screen-recording permission.
- Never exercised on macOS either: Clean, Uninstall, Shred, snapshot deletion, login-item
  switches, open at login.
