# Builds PureSweep.exe (bin\) and the installer (dist\PureSweepSetup.exe).
# Needs Visual Studio 2022 or the VS Build Tools (MSBuild) and the .NET Framework 4.8.1 targeting pack.
$ErrorActionPreference = 'Stop'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
if (-not $msbuild) { throw "MSBuild not found." }

if (-not (Test-Path "$PSScriptRoot\app.ico")) { & "$PSScriptRoot\tools\make-icon.ps1" }
& $msbuild "$PSScriptRoot\PureSweep.csproj" /nologo /v:m /p:Configuration=Release
if ($LASTEXITCODE) { throw "App build failed." }
& $msbuild "$PSScriptRoot\Setup\PureSweepSetup.csproj" /nologo /v:m /p:Configuration=Release
if ($LASTEXITCODE) { throw "Installer build failed." }
& "$PSScriptRoot\tools\make-msi.ps1" | Out-Null
Get-ChildItem "$PSScriptRoot\dist" | Select-Object Name, Length, LastWriteTime
