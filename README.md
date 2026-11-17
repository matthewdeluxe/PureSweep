# PureSweep

A PC cleaner for Windows, in the spirit of CleanMyPC. It finds junk files, lists installed programs, manages sign-in startup items, shows what hibernation costs you in disk space, and securely shreds files. Built with WPF on .NET Framework 4.8.1 and styled with [ModernWpf](https://github.com/Kinnara/ModernWpf) so it looks like a native Windows 11 app, with light and dark themes and a choice of accent colour.

> **macOS:** a native SwiftUI version lives in [`macOS/`](macOS/README.md). It has the same tools adapted to macOS, plus Large Files, Time Machine snapshots and a menu bar extra.

> **Status: early release (1.0).** Scanning is read-only and safe. Cleaning, shredding, uninstalling and the hibernation toggle delete or change real things, and have had limited real-world testing. Try them on throwaway data first. See [Safety](#safety).

## Features

| Page | What it does |
| --- | --- |
| **Home** | Live disk, memory and CPU gauges, a one-click Smart Scan, cleaning history, and shortcuts to every tool. |
| **Cleanup** | Scans nine categories of junk, lets you drill into each one to keep or clean individual groups, then deletes what you ticked and reports how much was freed. |
| **Uninstaller** | Lists installed programs with size, publisher and version. Search, sort, and launch a program's own uninstaller. |
| **Startup** | Shows what runs at sign-in (registry Run keys and Startup folders) and turns items on or off using the same flags as Task Manager. Nothing is deleted, so every change is reversible. |
| **Hibernation** | Shows how much space `hiberfil.sys` uses and turns hibernation on or off (UAC prompt). |
| **Shredder** | Overwrites files or whole folders with random data (1, 3 or 7 passes) before deleting them. |
| **Settings** | Theme (follow Windows, light, dark), accent colour, and whether recent temp files are kept. |

### What Cleanup looks for

Temporary files, Windows temporary files, browser caches (Chrome, Edge, Brave, Firefox), the Windows Update download cache, thumbnail and icon caches, crash dumps and error reports, the DirectX shader cache, Windows log files, and the Recycle Bin.

There is deliberately **no registry cleaner**.

## Install

Build it as described [below](#build), then run `PureSweep.msi` (recommended) or `PureSweepSetup.exe`. Prebuilt installers will be attached to the releases page. Both install **per user** to `%LocalAppData%\Programs\PureSweep` and need no administrator rights.

- Requires 64-bit Windows 10 or 11 and the .NET Framework 4.8.1 runtime (included with Windows 11 22H2 and later, a separate install on Windows 10).
- Nothing is code-signed yet. SmartScreen may warn, and some antivirus products flag `PureSweepSetup.exe` because it is an unsigned exe that unpacks other exes. The MSI avoids that.
- Use one installer or the other, not both.
- Uninstalling removes the program and its settings folder (`%AppData%\PureSweep`).

### Administrator mode

PureSweep runs as the invoking user. Cleaning the Windows temp folder, the Windows Update cache and Windows logs, and changing all-users startup items, need elevation. Use **Restart as administrator** on the Cleanup page. The hibernation toggle asks for UAC on its own.

## Safety

- **Scanning never deletes anything.** Cleaning asks for confirmation and names the categories it is about to empty.
- **Recent temp files are kept.** Temp and log categories skip files changed in the last 24 hours (they may be in use) unless you turn that off in Settings. The age check is repeated at the moment of deletion, not just at scan time.
- **Recycle Bin is not ticked by default**, since it is the safety net for deleted files.
- **Browser caches only.** History, cookies and saved logins are not touched. Files that are in use are left in place.
- **Shredder refuses dangerous targets:** drive roots, anything inside the Windows folder, and Program Files, ProgramData or user profile folders. Shredding is permanent and bypasses the Recycle Bin.
- **Shredding is not a guarantee on every disk.** Overwriting in place works best on hard disks. SSDs (wear levelling), cloud-synced folders such as OneDrive, and Volume Shadow Copy backups can keep other copies of the data. For SSDs, full-disk encryption is the dependable protection.
- **The uninstaller runs each program's own uninstaller** from its registry entry. If PureSweep is running as administrator, uninstallers started from per-user entries also run elevated, so only elevate when you need to.
- Not covered by Startup management: RunOnce keys, scheduled tasks and services.

Settings and cleaning history live in `%AppData%\PureSweep\settings.txt`. Unhandled errors are appended to `%AppData%\PureSweep\crash.log`.

## Build

Needs Visual Studio 2022 or the VS Build Tools (MSBuild with Roslyn) and the .NET Framework 4.8.1 targeting pack. There is no .NET SDK, NuGet restore or WiX involved.

```powershell
.\PureSweep\build.ps1
```

Output (all git-ignored):

- `PureSweep\bin\PureSweep.exe`
- `PureSweep\dist\PureSweep.msi`
- `PureSweep\dist\PureSweepSetup.exe`

The MSI is built with the Windows Installer COM API and `makecab.exe` (`tools\make-msi.ps1`). Each build gets a new ProductCode and the fixed UpgradeCode makes it replace any installed version. ModernWpf is referenced as two prebuilt DLLs checked in under `PureSweep\lib`.

## Project layout

```
PureSweep/
  Core/       logic with no UI: junk scanning and cleaning, installed apps, startup items, shredder, helpers
  Controls/   Hero (page banner) and RingGauge (dashboard dial)
  Pages/      one page per sidebar item
  Setup/      single-file exe installer (embeds the app)
  tools/      MSI builder and icon generator
  App.xaml    shared styles (cards, raised 3D buttons, tiles)
```

`CLAUDE.md` holds longer developer notes: behaviour worth knowing, build gotchas and testing status.

## Contributing

Issues and pull requests are welcome. There are no automated tests yet, so please describe how you verified a change. Anything that deletes files should be tried against throwaway data.

## License

MIT, see [LICENSE](LICENSE). ModernWpf is also MIT licensed.
