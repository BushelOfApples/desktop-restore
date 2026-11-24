#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Install','Save','Restore','Preview','Status','Edit','Uninstall')]
    [string]$Action = 'Status',
    [string]$LayoutPath = '',
    [ValidateRange(0,3600)][int]$WaitSeconds = 0,
    [ValidateRange(0,300)][int]$DelaySeconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Run this tool on Windows 11.' }
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run with Windows PowerShell (powershell.exe), not pwsh.exe.' }
if ($PSVersionTable.BuildVersion.Build -lt 22621 -and $Action -notin @('Status','Edit','Uninstall')) {
    throw 'This tool requires Windows 11 22H2 (build 22621) or later, with current updates.'
}
$dataDirectory = Join-Path $env:LOCALAPPDATA 'DesktopRestore'
if (-not $LayoutPath) { $LayoutPath = Join-Path $dataDirectory 'layout.json' }
$LayoutPath = [IO.Path]::GetFullPath($LayoutPath)
$null = New-Item -ItemType Directory -Path $dataDirectory -Force
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Desktop Restore.lnk'
$logPath = Join-Path $dataDirectory 'restore.log'
Import-Module (Join-Path $PSScriptRoot 'Restore.Core.psm1') -Force

function Write-RestoreLog([string]$Message) {
    if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 1MB) {
        Move-Item -LiteralPath $logPath -Destination ($logPath + '.old') -Force
    }
    Add-Content -LiteralPath $logPath -Value ('{0:o} {1}' -f [DateTime]::Now, $Message) -Encoding UTF8
}

function Initialize-DesktopApi {
    if (-not ('VirtualDesktop.Desktop' -as [type])) {
        Import-Module (Join-Path $PSScriptRoot 'vendor/VirtualDesktop.psm1') -DisableNameChecking
    }
    if (-not ('DesktopRestore.Native' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Windows.cs') }
    # Trigger COM initialization now, so an unsupported build fails before saving.
    if ([VirtualDesktop.Desktop]::Count -lt 1) { throw 'Windows returned no virtual desktops.' }
}

function Get-DesktopSnapshot {
    for ($i = 0; $i -lt [VirtualDesktop.Desktop]::Count; $i++) {
        $desktop = [VirtualDesktop.Desktop]::FromIndex($i)
        [pscustomobject]@{
            Id = $desktop.Id.ToString()
            Name = [VirtualDesktop.Desktop]::DesktopNameFromDesktop($desktop)
            Index = $i
            Object = $desktop
        }
    }
}

function Get-LiveWindows {
    foreach ($window in [DesktopRestore.Native]::ListWindows()) {
        try {
            $handle = [IntPtr]$window.Handle
            if ([VirtualDesktop.Desktop]::IsWindowPinned($handle) -or [VirtualDesktop.Desktop]::IsApplicationPinned($handle)) { continue }
            $desktop = [VirtualDesktop.Desktop]::FromWindow($handle)
            [pscustomobject]@{
                Handle = $window.Handle; ProcessId = $window.ProcessId
                Path = $window.Path; Class = $window.Class; Title = $window.Title
                DesktopId = $desktop.Id.ToString()
            }
        } catch {
            # Some transient or system windows have no shell application view.
            Write-Verbose ('Cannot inspect window {0}: {1}' -f $window.Handle, $_.Exception.Message)
        }
    }
}

function Save-DesktopLayout {
    $desktops = @(Get-DesktopSnapshot)
    $windows = @(Get-LiveWindows | Select-Object Path, Class, Title, DesktopId, @{Name='TitlePattern';Expression={''}})
    if ($windows.Count -eq 0) { throw 'No eligible windows found. Existing layout has been kept.' }
    foreach ($window in $windows) {
        if ($window.DesktopId -notin $desktops.Id) { throw 'Desktops changed during the save. Save again. Existing layout has been kept.' }
    }
    $layout = [pscustomobject]@{
        SchemaVersion = 1; SavedAt = [DateTime]::UtcNow.ToString('o')
        Desktops = @($desktops | Select-Object Id, Name, Index)
        Windows = $windows
    }
    Write-LayoutFile -Path $LayoutPath -Layout $layout
    Write-Host ('Saved {0} windows across {1} desktops to {2}' -f $windows.Count, $desktops.Count, $LayoutPath)
}

function Invoke-DesktopRestore([bool]$Preview) {
    $layout = Read-LayoutFile $LayoutPath
    $done = @{}
    $results = @{}
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $current = @(Get-DesktopSnapshot)
        $targets = @{}
        foreach ($saved in $layout.Desktops) {
            $target = Resolve-SavedDesktop -Saved $saved -Current $current
            if ($null -ne $target) { $targets[$saved.Id] = $target }
        }
        $liveWindows = @(Get-LiveWindows)
        foreach ($step in @(Get-RestorePlan -SavedWindows $layout.Windows -LiveWindows $liveWindows)) {
            $window = $step.Window
            $key = '{0}:{1}:{2}' -f $window.Handle, $window.ProcessId, $window.Path
            if ($done.ContainsKey($key)) { continue }
            $row = [pscustomobject]@{
                Title = $window.Title; App = [IO.Path]::GetFileName($window.Path)
                Handle = $window.Handle; Target = ''; Status = ''; Detail = $step.Reason
            }
            if (-not $step.DesktopId) {
                $row.Status = 'Unmatched'
            } elseif (-not $targets.ContainsKey($step.DesktopId)) {
                $row.Status = 'DesktopMissing'
                $row.Detail = 'Saved desktop ID and unique name were not found. Arrange desktops and save again.'
            } else {
                $target = $targets[$step.DesktopId]
                $row.Target = $target.Name
                if ($window.DesktopId -eq $target.Id) {
                    $row.Status = 'AlreadyCorrect'
                    $done[$key] = $true
                } elseif ($Preview) {
                    $row.Status = 'WouldMove'
                } else {
                    try {
                        # Recheck identity immediately before moving: handles can be reused.
                        $fresh = @([DesktopRestore.Native]::ListWindows() | Where-Object {
                            $_.Handle -eq $window.Handle -and $_.ProcessId -eq $window.ProcessId -and
                            $_.Path -eq $window.Path -and $_.Class -eq $window.Class -and $_.Title -ceq $window.Title
                        })
                        if ($fresh.Count -ne 1) { throw 'Window changed; retry on the next scan.' }
                        $handle = [IntPtr]$window.Handle
                        if ([VirtualDesktop.Desktop]::IsWindowPinned($handle) -or [VirtualDesktop.Desktop]::IsApplicationPinned($handle)) {
                            throw 'Window is now pinned to all desktops.'
                        }
                        $target.Object.MoveExactWindow($handle)
                        if ([VirtualDesktop.Desktop]::FromWindow($handle).Id.ToString() -ne $target.Id) {
                            throw 'Windows did not confirm the move.'
                        }
                        $row.Status = 'Moved'
                        $done[$key] = $true
                        Write-RestoreLog ('Moved handle {0} ({1}) to {2}' -f $window.Handle, $row.App, $row.Target)
                    } catch {
                        $row.Status = 'Failed'
                        $row.Detail = $_.Exception.Message
                    }
                }
            }
            $results[$key] = $row
        }
        if ($Preview -or $timer.Elapsed.TotalSeconds -ge $WaitSeconds) { break }
        Start-Sleep -Seconds 3
    } while ($true)
    $report = [pscustomobject]@{
        Time = [DateTime]::UtcNow.ToString('o'); Preview = $Preview
        LayoutPath = $LayoutPath; SavedWindowCount = @($layout.Windows).Count
        Results = @($results.Values | Sort-Object App, Title)
    }
    $reportPath = Join-Path $dataDirectory $(if ($Preview) { 'preview-report.json' } else { 'restore-report.json' })
    Write-LayoutFile -Path $reportPath -Layout $report
    $report.Results | Format-Table App, Title, Target, Status -AutoSize | Out-Host
    Write-Host ('Report: {0}' -f $reportPath)
    Write-Host 'Apps that did not reopen cannot be restored. Use Preview to check current windows.'
    Write-RestoreLog ('Finished {0}: {1} observed matching-app windows; report {2}' -f $Action, $results.Count, $reportPath)
}

$mutex = $null
$locked = $false
try {
    if ($Action -eq 'Status') {
        Write-Host ('Windows build: {0}' -f $PSVersionTable.BuildVersion)
        Write-Host ('Startup enabled: {0}' -f (Test-Path -LiteralPath $shortcutPath))
        Write-Host ('Layout: {0}' -f $LayoutPath)
        if (Test-Path -LiteralPath $LayoutPath) {
            $layout = Read-LayoutFile $LayoutPath
            Write-Host ('Saved: {0}; windows: {1}' -f $layout.SavedAt, @($layout.Windows).Count)
        }
        Write-Host ('Log: {0}' -f $logPath)
        return
    }
    if ($Action -eq 'Edit') {
        if (-not (Test-Path -LiteralPath $LayoutPath)) { throw 'Save a layout first.' }
        Start-Process notepad.exe -ArgumentList ('"{0}"' -f $LayoutPath)
        return
    }
    if ($Action -eq 'Uninstall') {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
        Write-Host 'Startup entry removed. Saved layout, reports and scripts have been kept.'
        return
    }
    if ($Action -eq 'Install') {
        if ($LayoutPath -ne (Join-Path $dataDirectory 'layout.json')) { throw 'Install uses the default layout path.' }
        $destination = Join-Path $dataDirectory 'app'
        $null = New-Item -ItemType Directory -Path (Join-Path $destination 'vendor') -Force
        if ([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') -ne $destination.TrimEnd('\')) {
            foreach ($file in @('DesktopRestore.ps1','StartRestore.ps1','Restore.Core.psm1','Windows.cs','README.md','THIRD-PARTY.md')) {
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $destination -Force
            }
            Copy-Item -Path (Join-Path $PSScriptRoot 'vendor/*') -Destination (Join-Path $destination 'vendor') -Force
            Copy-Item -Path (Join-Path $PSScriptRoot '*.cmd') -Destination $destination -Force
        }
        $installedScript = Join-Path $destination 'DesktopRestore.ps1'
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $LayoutPath)) {
            & $powershell -NoProfile -ExecutionPolicy Bypass -File $installedScript -Action Save
            if ($LASTEXITCODE -ne 0) { throw 'Initial save failed. Startup entry was not created.' }
        } else {
            $null = Read-LayoutFile $LayoutPath
            Write-Host 'Existing layout kept. Use Save to replace it.'
        }
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $powershell
        $shortcut.Arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $destination 'StartRestore.ps1')
        $shortcut.WorkingDirectory = $destination
        $shortcut.Description = 'Restore saved virtual desktop assignments after sign-in'
        $shortcut.Save()
        Write-Host ('Installed to {0}. Restore will run after sign-in.' -f $destination)
        return
    }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $mutex = New-Object Threading.Mutex($false, ('Local\DesktopRestore-' + $sid))
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Another save or restore is running. Wait for it to finish.' }
    if ($DelaySeconds) { Start-Sleep -Seconds $DelaySeconds }
    # Startup retries use fresh processes (StartRestore.ps1). A failed .NET
    # static constructor cannot be retried inside the same process.
    Initialize-DesktopApi
    switch ($Action) {
        'Save' { Save-DesktopLayout }
        'Preview' { Invoke-DesktopRestore $true }
        'Restore' { Invoke-DesktopRestore $false }
    }
} catch {
    Write-RestoreLog ('ERROR: ' + $_.Exception.Message)
    Write-Error $_
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
