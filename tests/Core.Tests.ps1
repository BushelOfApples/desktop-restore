$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Restore.Core.psm1') -Force
$script:passed = 0
function Assert($Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
function Saved([string]$Title, [string]$Desktop, [string]$Pattern = '', [string]$Path = 'C:\Apps\Code.exe') {
    [pscustomobject]@{ Path=$Path; Class='Chrome_WidgetWin_1'; Title=$Title; DesktopId=$Desktop; TitlePattern=$Pattern }
}
function Live([string]$Title, [string]$Path = 'C:\Apps\Code.exe') {
    [pscustomobject]@{ Handle=10; ProcessId=100; Path=$Path; Class='Chrome_WidgetWin_1'; Title=$Title }
}
$saved = @((Saved 'Project Alpha - Visual Studio Code' 'a'), (Saved 'Project Beta - Visual Studio Code' 'b'))
$plan = @(Get-RestorePlan $saved @((Live 'Project Beta - Visual Studio Code'), (Live 'Project Alpha - Visual Studio Code')))
Assert ($plan.Count -eq 2 -and $plan[0].DesktopId -eq 'b' -and $plan[1].DesktopId -eq 'a') 'Same app routes by exact title, independent of enumeration order'
$plan = @(Get-RestorePlan $saved @((Live 'Welcome - Visual Studio Code')))
Assert ($null -eq $plan[0].DesktopId) 'Changed titles across desktops do not guess'
$duplicates = @((Saved 'New Tab' 'a'), (Saved 'New Tab' 'b'))
$plan = @(Get-RestorePlan $duplicates @((Live 'New Tab')))
Assert ($null -eq $plan[0].DesktopId) 'Identical titles on different desktops are ambiguous'
$plan = @(Get-RestorePlan @((Saved 'Old' 'a')) @((Live 'New')))
Assert ($plan[0].DesktopId -eq 'a') 'Single-desktop app can change title'
$rules = @((Saved 'Old' 'a' '*Project Alpha*'), (Saved 'Old 2' 'b' '*Project Beta*'))
$plan = @(Get-RestorePlan $rules @((Live 'file.c - Project Alpha - Visual Studio Code')))
Assert ($plan[0].DesktopId -eq 'a') 'Stable wildcard rule handles changing editor title'
$plan = @(Get-RestorePlan $rules @((Live 'Project Alpha Project Beta')))
Assert ($null -eq $plan[0].DesktopId) 'Overlapping wildcard rules do not guess'
$plan = @(Get-RestorePlan @((Saved 'Old' 'a' '*Project Alpha*')) @((Live 'Project Beta')))
Assert ($null -eq $plan[0].DesktopId) 'App fallback cannot bypass explicit pattern'
$plan = @(Get-RestorePlan $saved @((Live 'Project Alpha - Visual Studio Code' 'C:\Other\Code.exe')))
Assert ($plan.Count -eq 0) 'Different executable paths are isolated'
$plan = @(Get-RestorePlan $saved @((Live 'Project Alpha - Visual Studio Code' 'c:\apps\code.EXE')))
Assert ($plan[0].DesktopId -eq 'a') 'Windows executable paths are case insensitive'
$plan = @(Get-RestorePlan @((Saved 'Same' 'a'),(Saved 'Same' 'a')) @((Live 'Same'),(Live 'Same')))
Assert ($plan.Count -eq 2 -and $plan[0].DesktopId -eq 'a' -and $plan[1].DesktopId -eq 'a') 'Duplicate windows on one desktop have one safe target'
$plan = @(Get-RestorePlan $saved @())
Assert ($plan.Count -eq 0) 'Empty live snapshot is allowed'
$hostPath = 'C:\Windows\System32\ApplicationFrameHost.exe'
$plan = @(Get-RestorePlan @((Saved 'Calculator' 'a' '' $hostPath)) @((Live 'Settings' $hostPath)))
Assert ($null -eq $plan[0].DesktopId) 'Shared application host cannot trigger app fallback'
$s = [pscustomobject]@{Id='a';Name='Work';Index=0}
$current = @([pscustomobject]@{Id='a';Name='Renamed';Index=1},[pscustomobject]@{Id='b';Name='Work';Index=0})
Assert ((Resolve-SavedDesktop $s $current).Id -eq 'a') 'GUID wins after desktop rename or reorder'
$current = @([pscustomobject]@{Id='b';Name='Work';Index=2})
Assert ((Resolve-SavedDesktop $s $current).Id -eq 'b') 'Unique name recovers changed GUID'
$current = @([pscustomobject]@{Id='b';Name='Work';Index=0},[pscustomobject]@{Id='c';Name='Work';Index=1})
Assert ($null -eq (Resolve-SavedDesktop $s $current)) 'Duplicate names are ambiguous'
$current = @([pscustomobject]@{Id='b';Name='Other';Index=0})
Assert ($null -eq (Resolve-SavedDesktop $s $current)) 'No positional fallback to the wrong desktop'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('desktop-restore-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temp
try {
    $path = Join-Path $temp 'layout.json'
    $id = '11111111-1111-1111-1111-111111111111'
    $layout = [pscustomobject]@{SchemaVersion=1;SavedAt='test';Desktops=@([pscustomobject]@{Id=$id;Name='Work';Index=0});Windows=@((Saved 'original' $id))}
    Write-LayoutFile $path $layout
    Assert ((Read-LayoutFile $path).Windows[0].Title -eq 'original') 'Layout round trip'
    $layout.Windows[0].Title = 'changed'
    Write-LayoutFile $path $layout
    Assert ((Read-LayoutFile $path).Windows[0].Title -eq 'changed') 'Layout atomic replacement'
    Assert ((Read-LayoutFile ($path+'.bak')).Windows[0].Title -eq 'original') 'Previous save retained as backup'
    $layout.Windows[0].Title = "caf$([char]0x00e9) - $([char]0x65e5)$([char]0x672c)"
    Write-LayoutFile $path $layout
    Assert ((Read-LayoutFile $path).Windows[0].Title -ceq $layout.Windows[0].Title) 'Unicode survives layout round trip'
    $layout.Windows[0].TitlePattern = '[abc'
    Write-LayoutFile $path $layout
    $rejected = $false
    try { $null = Read-LayoutFile $path } catch { $rejected = $true }
    Assert $rejected 'Malformed wildcard rejected before any move'
    $layout.Windows[0].TitlePattern = ''
    $layout.Windows[0].DesktopId = 'missing'
    Write-LayoutFile $path $layout
    $rejected = $false
    try { $null = Read-LayoutFile $path } catch { $rejected = $true }
    Assert $rejected 'Unknown desktop reference rejected'
    [IO.File]::WriteAllText($path, '{ broken json')
    $rejected = $false
    try { $null = Read-LayoutFile $path } catch { $rejected = $true }
    Assert $rejected 'Corrupt JSON rejected'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }

foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot '..') -Recurse -File | Where-Object { $_.Extension -in '.ps1','.psm1' }) {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) ('Parses: ' + $file.Name)
}
Add-Type -Path (Join-Path $PSScriptRoot '../Windows.cs')
Assert ($null -ne ('DesktopRestore.Native' -as [type])) 'Native C# bridge compiles (Win32 calls require Windows)'
Write-Host "$script:passed checks passed. Windows integration still requires a Windows session."
