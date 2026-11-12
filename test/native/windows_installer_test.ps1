param([Parameter(Mandatory=$true)][string]$InstallerPath)
$ErrorActionPreference = 'Stop'
$installer = (Resolve-Path -LiteralPath $InstallerPath).Path
$directory = Join-Path ([IO.Path]::GetTempPath()) ('lockin-installer-test-' + [Guid]::NewGuid())
$installed = Join-Path $directory 'installed'
[void][IO.Directory]::CreateDirectory($directory)
$uninstaller = Join-Path $installed 'unins000.exe'
try {
    $setup = Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR="' + $installed + '"')) -PassThru -Wait
    if ($setup.ExitCode -ne 0) { throw "Installer failed: $($setup.ExitCode)" }
    $executable = Join-Path $installed 'lockin.exe'
    if (-not (Test-Path -LiteralPath $executable)) { throw 'Installer did not install Lockin.' }
    & (Join-Path $PSScriptRoot 'windows_startup_test.ps1') -ExecutablePath $executable
    Write-Output 'PASS: the installed application loads and passes native startup checks.'
    $remove = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -PassThru -Wait
    if ($remove.ExitCode -ne 0 -or (Test-Path -LiteralPath $executable)) { throw 'Uninstaller did not remove the installed executable.' }
    Write-Output 'PASS: the per-user installer uninstalls without elevation.'
} finally {
    if (Test-Path -LiteralPath $uninstaller) {
        Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait
    }
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
}
