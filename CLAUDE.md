# PureSweep

A Windows PC cleaner in the style of CleanMyPC: WPF on .NET Framework 4.8.1, styled with
ModernWpf 0.9.6 (the WPF port of the WinUI 2 controls). Full-trust desktop app, not UWP.

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

Prefer the MSI for deployment. The owner's antivirus deleted `PureSweepSetup.exe` (an unsigned
exe that unpacks other exes). Nothing is code-signed.

## Layout

- `Core/` - logic with no UI: `Junk.cs` (scan/clean categories and drill-down groups),
  `Apps.cs` (installed programs), `Startup.cs` (sign-in items via the StartupApproved registry
  flags Task Manager uses), `Shredder.cs`, `Util.cs` (helpers and `AppSettings`).
- `Controls/` - `Hero` (coloured page banner) and `RingGauge` (dashboard dial).
- `Pages/` - one UserControl per sidebar item: Home, Cleanup, Uninstaller, Startup, Hibernation,
  Shredder, Settings. `MainWindow` hosts them in a `NavigationView` and caches each instance.
- `Setup/` - the single-file exe installer (embeds the app as resources).
- `App.xaml` - shared styles: `Card`, `Push3D` / `Push3DAccent` / `Push3DHero` / `Push3DDanger`
  (raised buttons that depress), `RoundPush3D`, `TileButton`, and the `Hero` template.

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
