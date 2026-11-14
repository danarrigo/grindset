param(
    [string]$BuildDirectory = 'build/windows/x64/runner/Release',
    [string]$OutputDirectory = 'build/installers',
    [string]$Compiler = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
)
$ErrorActionPreference = 'Stop'
$build = (Resolve-Path -LiteralPath $BuildDirectory).Path
$executable = Join-Path $build 'lockin.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Build the complete Flutter Windows release first.' }
if (-not (Test-Path -LiteralPath $Compiler)) { throw 'Install Inno Setup 6.4 or newer, or pass -Compiler.' }

# Bundle the redistributable CRT app-locally so a per-user install needs neither
# administrator rights nor an existing Visual Studio/VC++ runtime installation.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio C++ build tools are required to package the CRT.' }
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $visualStudio) { throw 'Could not find the Visual C++ redistributable files.' }
# Toolset aliases such as v145 are not semantic version directories. Select
# by the actual runtime DLL version, supporting both aliases and numeric paths.
$crt = Get-ChildItem -Path (Join-Path $visualStudio 'VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT') -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'vcruntime140.dll') } |
    Sort-Object {
        $info = (Get-Item -LiteralPath (Join-Path $_.FullName 'vcruntime140.dll')).VersionInfo
        [version]::new($info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart)
    } -Descending | Select-Object -First 1
if (-not $crt) { throw 'The x64 Visual C++ redistributable directory is missing.' }
Copy-Item -Path (Join-Path $crt.FullName '*.dll') -Destination $build -Force
foreach ($runtime in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $build $runtime))) { throw "Required runtime is missing: $runtime" }
}

[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
$version = (Get-Item -LiteralPath $executable).VersionInfo.ProductVersion.Split('+')[0]
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Unsupported application version: $version" }
$definition = Join-Path $PSScriptRoot '..\packaging\windows\grindset.iss'
& $Compiler "/DBuildDir=$build" "/DOutputDir=$output" "/DAppVersion=$version" $definition
if ($LASTEXITCODE -ne 0) { throw 'Windows installer compilation failed.' }
$installer = Join-Path $output "grindset-$version-windows-x64-setup.exe"
if (-not (Test-Path -LiteralPath $installer)) { throw 'The installer was not produced.' }
Write-Output $installer
