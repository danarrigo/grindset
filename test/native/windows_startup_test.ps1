param([Parameter(Mandatory=$true)][string]$ExecutablePath)
$ErrorActionPreference = 'Stop'
$executable = (Resolve-Path -LiteralPath $ExecutablePath).Path
$workingDirectory = Split-Path -Parent $executable
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('lockin-startup-test-' + [Guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($testDirectory)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class LockinStartupWindow {
    delegate bool EnumProc(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr parameter);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int size);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr GetProp(IntPtr window, string name);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
    public static IntPtr Find(uint processId) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr window, IntPtr parameter) {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            if (owner == processId) {
                var name = new StringBuilder(256);
                GetClassName(window, name, name.Capacity);
                if (name.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW") {
                    found = window;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
'@

function Start-OwnedApp([string]$DataDirectory, [bool]$Background) {
    $arguments = @('"--data-dir=' + $DataDirectory + '"')
    if ($Background) { $arguments += '--background' }
    Start-Process -FilePath $executable -WorkingDirectory $workingDirectory -ArgumentList $arguments -PassThru
}

function Wait-FirstFrame($Process, [bool]$Hidden) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        if ($Process.HasExited) { throw 'The owned native app exited before its first frame.' }
        $window = [LockinStartupWindow]::Find($Process.Id)
        if ($window -ne [IntPtr]::Zero) {
            if ($Hidden -and [LockinStartupWindow]::IsWindowVisible($window)) {
                throw '--background opened a window instead of staying in the tray.'
            }
            $ready = [LockinStartupWindow]::GetProp($window, 'Lockin.FirstFrameRendered') -ne [IntPtr]::Zero
            if ($ready -and ($Hidden -or [LockinStartupWindow]::IsWindowVisible($window))) { return $window }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Native startup did not reach its expected first-frame visibility.'
}

function Stop-OwnedApp($Process) {
    if ($null -ne $Process) {
        if (-not $Process.HasExited) { $Process.Kill(); $Process.WaitForExit() }
        $Process.Dispose()
    }
}

$app = $null
$duplicate = $null
try {
    $app = Start-OwnedApp (Join-Path $testDirectory 'background') $true
    $window = Wait-FirstFrame $app $true
    if ($app.HasExited -or [LockinStartupWindow]::IsWindowVisible($window)) { throw 'Background startup did not remain hidden.' }
    Write-Output 'PASS: --background renders its first frame without exposing a window.'
    Stop-OwnedApp $app; $app = $null

    $app = Start-OwnedApp (Join-Path $testDirectory 'normal') $false
    $window = Wait-FirstFrame $app $false
    Write-Output 'PASS: normal startup exposes the window.'
    [void][LockinStartupWindow]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ([LockinStartupWindow]::IsWindowVisible($window) -and -not $app.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($app.HasExited -or [LockinStartupWindow]::IsWindowVisible($window)) { throw 'Closing the window did not retain a hidden tray process.' }
    Write-Output 'PASS: closing the window keeps the native process alive in the tray.'
    $duplicate = Start-OwnedApp (Join-Path $testDirectory 'normal') $true
    $duplicateWindow = Wait-FirstFrame $duplicate $false
    [void][LockinStartupWindow]::PostMessage($duplicateWindow, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $duplicate.WaitForExit(5000) -or $app.HasExited) { throw 'A second instance did not fail safely without replacing the journal owner.' }
    Write-Output 'PASS: a second instance cannot take over the same local journal.'
    Stop-OwnedApp $duplicate; $duplicate = $null
    Stop-OwnedApp $app; $app = $null

    $invalidDirectory = Join-Path $testDirectory 'not-a-directory'
    [IO.File]::WriteAllText($invalidDirectory, 'Owned invalid-directory fixture')
    $app = Start-OwnedApp $invalidDirectory $true
    $window = Wait-FirstFrame $app $false
    Write-Output 'PASS: fatal startup still exposes the error window for a background launch.'
    [void][LockinStartupWindow]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $app.WaitForExit(5000)) { throw 'The fatal-startup error window could not be closed.' }
    Write-Output 'PASS: fatal startup has no invisible, unclosable process.'
} finally {
    Stop-OwnedApp $duplicate
    Stop-OwnedApp $app
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
}
