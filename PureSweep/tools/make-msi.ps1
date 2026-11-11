# Builds dist\PureSweep.msi from the files in bin\ using only what ships with Windows
# (the Windows Installer COM API and makecab.exe) - no WiX needed.
# Per-user install to %LocalAppData%\Programs\PureSweep, Start menu shortcut, no admin rights.
param([string]$Version = "1.0.0")
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$bin  = Join-Path $root 'bin'
$dist = Join-Path $root 'dist'
$work = Join-Path $root 'obj\msi'
$msi  = Join-Path $dist 'PureSweep.msi'
$upgradeCode   = '{6B0F6E0C-3D0B-4B7E-9C55-2B6E5B1F4A10}'   # never change: lets new versions replace old ones
$componentGuid = '{A1C3D5E7-0F21-4C3B-8D6A-7E9B1C2D3F40}'
$productCode   = '{' + [guid]::NewGuid().ToString().ToUpper() + '}'
$packageCode   = '{' + [guid]::NewGuid().ToString().ToUpper() + '}'

$files = @(
    @{ Key = 'filPureSweepExe';      Path = "$bin\PureSweep.exe";          Name = 'PURESW~1.EXE|PureSweep.exe' }
    @{ Key = 'filModernWpfDll';      Path = "$bin\ModernWpf.dll";          Name = 'MODERN~1.DLL|ModernWpf.dll' }
    @{ Key = 'filModernWpfControls'; Path = "$bin\ModernWpf.Controls.dll"; Name = 'MODERN~2.DLL|ModernWpf.Controls.dll' }
)
foreach ($f in $files) { if (-not (Test-Path $f.Path)) { throw "Missing $($f.Path) - build the app first." } }

New-Item -ItemType Directory -Force $dist, $work | Out-Null
Remove-Item $msi -Force -ErrorAction SilentlyContinue

# --- cabinet: file names inside the cab are the File-table keys, in sequence order
$ddf = @(
    '.Set CabinetNameTemplate=app.cab', ".Set DiskDirectoryTemplate=`"$work`"", '.Set Cabinet=on', '.Set Compress=on',
    '.Set CompressionType=LZX', '.Set MaxDiskSize=0', ".Set RptFileName=`"$work\cab.rpt`"", ".Set InfFileName=`"$work\cab.inf`""
) + ($files | ForEach-Object { "`"$($_.Path)`" $($_.Key)" })
Set-Content "$work\app.ddf" $ddf -Encoding ASCII
& makecab.exe /F "$work\app.ddf" | Out-Null
if ($LASTEXITCODE -or -not (Test-Path "$work\app.cab")) { throw "makecab failed." }

# --- late-bound helpers for the Windows Installer automation objects
# (arguments are unwrapped from PSObject first, otherwise COM reports a type mismatch)
function Raw([object[]]$a) { [object[]]@($a | ForEach-Object { if ($_ -is [psobject]) { $_.PSObject.BaseObject } else { $_ } }) }
function Call($o, $name, [object[]]$a = @())    { $o.GetType().InvokeMember($name, 'InvokeMethod', $null, $o, (Raw $a)) }
function MsiGet($o, $name, [object[]]$a = @())  { $o.GetType().InvokeMember($name, 'GetProperty', $null, $o, (Raw $a)) }
function MsiSet($o, $name, [object[]]$a)        { [void]$o.GetType().InvokeMember($name, 'SetProperty', $null, $o, (Raw $a)) }

$installer = New-Object -ComObject WindowsInstaller.Installer
$db = Call $installer OpenDatabase @($msi, 3)     # 3 = create

function Sql([string]$q) { $v = Call $db OpenView @($q); [void](Call $v Execute); [void](Call $v Close) }
function Stream([string]$q, [string]$path) {
    $v = Call $db OpenView @($q); $r = Call $installer CreateRecord @(1)
    [void](Call $r SetStream @(1, $path)); [void](Call $v Execute @($r)); [void](Call $v Close)
}

# --- schema
Sql 'CREATE TABLE `Property` (`Property` CHAR(72) NOT NULL, `Value` LONGCHAR NOT NULL LOCALIZABLE PRIMARY KEY `Property`)'
Sql 'CREATE TABLE `Directory` (`Directory` CHAR(72) NOT NULL, `Directory_Parent` CHAR(72), `DefaultDir` CHAR(255) NOT NULL LOCALIZABLE PRIMARY KEY `Directory`)'
Sql 'CREATE TABLE `Component` (`Component` CHAR(72) NOT NULL, `ComponentId` CHAR(38), `Directory_` CHAR(72) NOT NULL, `Attributes` SHORT NOT NULL, `Condition` CHAR(255), `KeyPath` CHAR(72) PRIMARY KEY `Component`)'
Sql 'CREATE TABLE `Feature` (`Feature` CHAR(38) NOT NULL, `Feature_Parent` CHAR(38), `Title` CHAR(64) LOCALIZABLE, `Description` CHAR(255) LOCALIZABLE, `Display` SHORT, `Level` SHORT NOT NULL, `Directory_` CHAR(72), `Attributes` SHORT NOT NULL PRIMARY KEY `Feature`)'
Sql 'CREATE TABLE `FeatureComponents` (`Feature_` CHAR(38) NOT NULL, `Component_` CHAR(72) NOT NULL PRIMARY KEY `Feature_`, `Component_`)'
Sql 'CREATE TABLE `File` (`File` CHAR(72) NOT NULL, `Component_` CHAR(72) NOT NULL, `FileName` CHAR(255) NOT NULL LOCALIZABLE, `FileSize` LONG NOT NULL, `Version` CHAR(72), `Language` CHAR(20), `Attributes` SHORT, `Sequence` SHORT NOT NULL PRIMARY KEY `File`)'
Sql 'CREATE TABLE `Media` (`DiskId` SHORT NOT NULL, `LastSequence` SHORT NOT NULL, `DiskPrompt` CHAR(64) LOCALIZABLE, `Cabinet` CHAR(255), `VolumeLabel` CHAR(32), `Source` CHAR(72) PRIMARY KEY `DiskId`)'
Sql 'CREATE TABLE `Registry` (`Registry` CHAR(72) NOT NULL, `Root` SHORT NOT NULL, `Key` CHAR(255) NOT NULL LOCALIZABLE, `Name` CHAR(255) LOCALIZABLE, `Value` LONGCHAR LOCALIZABLE, `Component_` CHAR(72) NOT NULL PRIMARY KEY `Registry`)'
Sql 'CREATE TABLE `Shortcut` (`Shortcut` CHAR(72) NOT NULL, `Directory_` CHAR(72) NOT NULL, `Name` CHAR(128) NOT NULL LOCALIZABLE, `Component_` CHAR(72) NOT NULL, `Target` CHAR(72) NOT NULL, `Arguments` CHAR(255), `Description` CHAR(255) LOCALIZABLE, `Hotkey` SHORT, `Icon_` CHAR(72), `IconIndex` SHORT, `ShowCmd` SHORT, `WkDir` CHAR(72) PRIMARY KEY `Shortcut`)'
Sql 'CREATE TABLE `Icon` (`Name` CHAR(72) NOT NULL, `Data` OBJECT NOT NULL PRIMARY KEY `Name`)'
Sql 'CREATE TABLE `RemoveFile` (`FileKey` CHAR(72) NOT NULL, `Component_` CHAR(72) NOT NULL, `FileName` CHAR(255) LOCALIZABLE, `DirProperty` CHAR(72) NOT NULL, `InstallMode` SHORT NOT NULL PRIMARY KEY `FileKey`)'
Sql 'CREATE TABLE `Upgrade` (`UpgradeCode` CHAR(38) NOT NULL, `VersionMin` CHAR(20), `VersionMax` CHAR(20), `Language` CHAR(255), `Attributes` LONG NOT NULL, `Remove` CHAR(255), `ActionProperty` CHAR(72) NOT NULL PRIMARY KEY `UpgradeCode`, `VersionMin`, `VersionMax`, `Language`, `Attributes`)'
Sql 'CREATE TABLE `InstallExecuteSequence` (`Action` CHAR(72) NOT NULL, `Condition` CHAR(255), `Sequence` SHORT PRIMARY KEY `Action`)'
Sql 'CREATE TABLE `InstallUISequence` (`Action` CHAR(72) NOT NULL, `Condition` CHAR(255), `Sequence` SHORT PRIMARY KEY `Action`)'

# --- properties (ALLUSERS is deliberately absent => per-user install, no elevation)
$props = [ordered]@{
    ProductCode = $productCode; ProductName = 'PureSweep'; ProductVersion = $Version; Manufacturer = 'PureSweep'
    ProductLanguage = '1033'; UpgradeCode = $upgradeCode; ARPPRODUCTICON = 'app.ico'; ARPNOMODIFY = '1'; ARPNOREPAIR = '1'
    SecureCustomProperties = 'OLDVERSIONFOUND'
}
foreach ($k in $props.Keys) { Sql "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('$k', '$($props[$k])')" }

# --- directories
Sql "INSERT INTO ``Directory`` (``Directory``, ``DefaultDir``) VALUES ('TARGETDIR', 'SourceDir')"
foreach ($d in @(
    @('LocalAppDataFolder', 'TARGETDIR', '.'), @('ProgramsDir', 'LocalAppDataFolder', 'Programs'), @('INSTALLDIR', 'ProgramsDir', 'PURESW~1|PureSweep'),
    @('ProgramMenuFolder', 'TARGETDIR', '.'), @('AppDataFolder', 'TARGETDIR', '.'), @('SettingsDir', 'AppDataFolder', 'PURESW~1|PureSweep'))) {
    Sql "INSERT INTO ``Directory`` (``Directory``, ``Directory_Parent``, ``DefaultDir``) VALUES ('$($d[0])', '$($d[1])', '$($d[2])')"
}

# --- one component (registry key path, as required for per-user data), one feature
Sql "INSERT INTO ``Component`` (``Component``, ``ComponentId``, ``Directory_``, ``Attributes``, ``KeyPath``) VALUES ('Main', '$componentGuid', 'INSTALLDIR', 260, 'regInstallDir')"
Sql "INSERT INTO ``Feature`` (``Feature``, ``Title``, ``Display``, ``Level``, ``Directory_``, ``Attributes``) VALUES ('Complete', 'PureSweep', 1, 1, 'INSTALLDIR', 0)"
Sql "INSERT INTO ``FeatureComponents`` (``Feature_``, ``Component_``) VALUES ('Complete', 'Main')"
Sql "INSERT INTO ``Registry`` (``Registry``, ``Root``, ``Key``, ``Name``, ``Value``, ``Component_``) VALUES ('regInstallDir', 1, 'Software\PureSweep', 'InstallDir', '[INSTALLDIR]', 'Main')"

# --- files
$seq = 0
foreach ($f in $files) {
    $seq++
    $vi = (Get-Item $f.Path).VersionInfo
    $ver = '{0}.{1}.{2}.{3}' -f $vi.FileMajorPart, $vi.FileMinorPart, $vi.FileBuildPart, $vi.FilePrivatePart
    Sql "INSERT INTO ``File`` (``File``, ``Component_``, ``FileName``, ``FileSize``, ``Version``, ``Language``, ``Attributes``, ``Sequence``) VALUES ('$($f.Key)', 'Main', '$($f.Name)', $((Get-Item $f.Path).Length), '$ver', '0', 512, $seq)"
}
Sql "INSERT INTO ``Media`` (``DiskId``, ``LastSequence``, ``Cabinet``) VALUES (1, $seq, '#app.cab')"
Stream "INSERT INTO ``_Streams`` (``Name``, ``Data``) VALUES ('app.cab', ?)" "$work\app.cab"

# --- shortcut, Add/Remove Programs icon, settings cleanup on uninstall
Stream "INSERT INTO ``Icon`` (``Name``, ``Data``) VALUES ('app.ico', ?)" "$root\app.ico"
Sql "INSERT INTO ``Shortcut`` (``Shortcut``, ``Directory_``, ``Name``, ``Component_``, ``Target``, ``Description``, ``WkDir``) VALUES ('scStartMenu', 'ProgramMenuFolder', 'PURESW~1|PureSweep', 'Main', '[#filPureSweepExe]', 'Clean up and maintain your PC', 'INSTALLDIR')"
Sql "INSERT INTO ``RemoveFile`` (``FileKey``, ``Component_``, ``FileName``, ``DirProperty``, ``InstallMode``) VALUES ('rmSettingsFiles', 'Main', '*.*', 'SettingsDir', 2)"
Sql "INSERT INTO ``RemoveFile`` (``FileKey``, ``Component_``, ``DirProperty``, ``InstallMode``) VALUES ('rmSettingsDir', 'Main', 'SettingsDir', 2)"

# --- installing a newer (or rebuilt) package replaces whatever version is there
Sql "INSERT INTO ``Upgrade`` (``UpgradeCode``, ``VersionMin``, ``Attributes``, ``ActionProperty``) VALUES ('$upgradeCode', '0.0.0', 256, 'OLDVERSIONFOUND')"

# --- action sequences
$exec = [ordered]@{
    FindRelatedProducts = 25; CostInitialize = 800; FileCost = 900; CostFinalize = 1000; InstallValidate = 1400
    RemoveExistingProducts = 1410; InstallInitialize = 1500; ProcessComponents = 1600; UnpublishFeatures = 1800
    RemoveRegistryValues = 2600; RemoveShortcuts = 3200; RemoveFiles = 3500; InstallFiles = 4000; CreateShortcuts = 4500
    WriteRegistryValues = 5000; RegisterUser = 6000; RegisterProduct = 6100; PublishFeatures = 6300; PublishProduct = 6400
    InstallFinalize = 6600
}
foreach ($k in $exec.Keys) { Sql "INSERT INTO ``InstallExecuteSequence`` (``Action``, ``Sequence``) VALUES ('$k', $($exec[$k]))" }
$ui = [ordered]@{ FindRelatedProducts = 25; CostInitialize = 800; FileCost = 900; CostFinalize = 1000; ExecuteAction = 1300 }
foreach ($k in $ui.Keys) { Sql "INSERT INTO ``InstallUISequence`` (``Action``, ``Sequence``) VALUES ('$k', $($ui[$k]))" }

# --- summary information
$si = MsiGet $db SummaryInformation @(20)
MsiSet $si Property @(1, 1252)
MsiSet $si Property @(2, 'Installation Database')
MsiSet $si Property @(3, 'PureSweep')
MsiSet $si Property @(4, 'PureSweep')
MsiSet $si Property @(5, 'Installer')
MsiSet $si Property @(6, "Installs PureSweep $Version")
MsiSet $si Property @(7, 'x64;1033')          # 64-bit package, English
MsiSet $si Property @(9, $packageCode)
MsiSet $si Property @(14, 200)                # Windows Installer 2.0 schema (needed for x64)
MsiSet $si Property @(15, 10)                 # compressed, long file names, no elevation required
MsiSet $si Property @(18, 'PureSweep make-msi.ps1')
MsiSet $si Property @(19, 2)
[void](Call $si Persist)
[void](Call $db Commit)

foreach ($o in $si, $db, $installer) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) }
[GC]::Collect(); [GC]::WaitForPendingFinalizers()
Get-Item $msi | Select-Object Name, Length, LastWriteTime
