#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$scriptPath = Join-Path $PSScriptRoot 'DesktopRestore.ps1'
Start-Sleep -Seconds 15
for ($attempt = 0; $attempt -lt 3; $attempt++) {
    & $powershell -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $scriptPath -Action Restore -WaitSeconds 180
    if ($LASTEXITCODE -eq 0) { exit 0 }
    if ($attempt -lt 2) { Start-Sleep -Seconds 10 }
}
exit 1
