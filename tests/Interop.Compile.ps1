# Compile the dependency's selected C# interface branch without invoking Win32.
param([int]$Build = 26100)
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$path = Join-Path $PSScriptRoot '../vendor/VirtualDesktop.psm1'
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Dependency parse failed.' }
$command = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Add-Type'
}, $true)
$OSBuild = $Build
$TestEdition = 'Desktop'
$compile = $command.Extent.Text.Replace('$PSEdition', '$TestEdition')
& ([scriptblock]::Create($compile))
if (-not [VirtualDesktop.Desktop].GetProperty('Id')) { throw 'Missing desktop ID addition.' }
if (-not [VirtualDesktop.Desktop].GetMethod('MoveExactWindow')) { throw 'Missing exact window move addition.' }
Write-Host "PASS: Windows build $Build C# branch compiles. COM calls have not been executed."
