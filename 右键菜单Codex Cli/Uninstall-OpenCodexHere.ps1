param(
    [switch]$RestartExplorer,
    [switch]$KeepFiles
)

$ErrorActionPreference = 'SilentlyContinue'

$Keys = @(
    'HKCU:\Software\Classes\Directory\Background\shell\OpenWithCodexCLI',
    'HKCU:\Software\Classes\Directory\shell\OpenWithCodexCLI',
    'HKCU:\Software\Classes\Drive\shell\OpenWithCodexCLI'
)

foreach ($key in $Keys) {
    Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue
}

$InstallDir = Join-Path $env:LOCALAPPDATA 'OpenCodexHere'

if (-not $KeepFiles) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Removed Open Codex Here context menu.' -ForegroundColor Green

if ($KeepFiles) {
    Write-Host "Kept installed files at: $InstallDir" -ForegroundColor Yellow
}
else {
    Write-Host "Removed installed files at: $InstallDir" -ForegroundColor Green
}

if ($RestartExplorer) {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
    Write-Host 'Explorer restarted.' -ForegroundColor Green
}
