Set-StrictMode -Version Latest

function Resolve-SavedDesktop {
    param($Saved, [object[]]$Current)
    $found = @($Current | Where-Object { $_.Id -eq $Saved.Id })
    if ($found.Count -eq 1) { return $found[0] }
    # Desktop GUIDs can change. A unique, unchanged name is the only fallback.
    $found = @($Current | Where-Object { $_.Name -ceq $Saved.Name })
    if ($found.Count -eq 1) { return $found[0] }
    return $null
}

function Get-WindowKey {
    param($Window)
    return ('{0}|{1}' -f $Window.Path.ToLowerInvariant(), $Window.Class.ToLowerInvariant())
}

function Get-RestorePlan {
    param([object[]]$SavedWindows, [object[]]$LiveWindows)
    # Evaluate against the WHOLE saved layout, including already restored slots.
    # Removing completed slots would turn a cross-desktop app into an unsafe fallback.
    foreach ($live in $LiveWindows) {
        $group = @($SavedWindows | Where-Object { (Get-WindowKey $_) -eq (Get-WindowKey $live) })
        if ($group.Count -eq 0) { continue }
        $candidates = @($group | Where-Object {
            if (-not [string]::IsNullOrWhiteSpace($_.TitlePattern)) {
                $live.Title -like $_.TitlePattern
            } else {
                $live.Title -ceq $_.Title
            }
        })
        $reason = 'title'
        if ($candidates.Count -eq 0) {
            $targets = @($group.DesktopId | Select-Object -Unique)
            # Explicit patterns are restrictions. Never bypass them with app fallback.
            $patterns = @($group | Where-Object { -not [string]::IsNullOrWhiteSpace($_.TitlePattern) })
            $hosted = $live.Class -eq 'ApplicationFrameWindow' -or $live.Path -match '(?i)(^|[\\/])ApplicationFrameHost\.exe$'
            if ($targets.Count -eq 1 -and $patterns.Count -eq 0 -and -not $hosted) {
                $candidates = $group
                $reason = 'app has one saved desktop'
            }
        }
        $targets = @($candidates | ForEach-Object { $_.DesktopId } | Select-Object -Unique)
        if ($targets.Count -ne 1) {
            [pscustomobject]@{ Window = $live; DesktopId = $null; Reason = 'No unique title rule; leave in place' }
        } else {
            [pscustomobject]@{ Window = $live; DesktopId = $targets[0]; Reason = $reason }
        }
    }
}

function Write-LayoutFile {
    param([string]$Path, $Layout)
    $full = [IO.Path]::GetFullPath($Path)
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))
    $temp = $full + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, ($Layout | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
        if ([IO.File]::Exists($full)) {
            # Replace atomically, retaining the previous explicit save.
            [IO.File]::Replace($temp, $full, ($full + '.bak'))
        } else {
            [IO.File]::Move($temp, $full)
        }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

function Read-LayoutFile {
    param([string]$Path)
    $layout = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($layout.SchemaVersion -ne 1) { throw 'Unsupported layout schema.' }
    if (@($layout.Desktops).Count -eq 0 -or @($layout.Windows).Count -eq 0) {
        throw 'Layout has no desktops or windows. Save a layout first.'
    }
    $ids = @{}
    foreach ($desktop in $layout.Desktops) {
        $null = [guid]::Parse($desktop.Id)
        if ($ids.ContainsKey($desktop.Id)) { throw 'Duplicate desktop ID in layout.' }
        $ids[$desktop.Id] = $true
        if ([string]::IsNullOrWhiteSpace($desktop.Name)) { throw 'Desktop name is missing.' }
    }
    foreach ($window in $layout.Windows) {
        if (-not $ids.ContainsKey($window.DesktopId)) { throw 'Window refers to an unknown desktop.' }
        if ([string]::IsNullOrWhiteSpace($window.Path) -or [string]::IsNullOrWhiteSpace($window.Class)) {
            throw 'Window identity is missing.'
        }
        $null = $window.Title
        $null = $window.TitlePattern
        if ($window.TitlePattern) {
            $pattern = [System.Management.Automation.WildcardPattern]::new($window.TitlePattern)
            $null = $pattern.IsMatch('')
        }
    }
    return $layout
}

Export-ModuleMember -Function Resolve-SavedDesktop, Get-WindowKey, Get-RestorePlan, Write-LayoutFile, Read-LayoutFile
