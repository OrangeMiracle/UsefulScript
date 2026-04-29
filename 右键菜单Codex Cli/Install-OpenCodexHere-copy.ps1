param(
    [switch]$RestartExplorer
)

$ErrorActionPreference = 'Stop'

# Per-user stable install directory. Do not store runtime assets beside this installer.
$InstallDir = Join-Path $env:LOCALAPPDATA 'OpenCodexHere'
$HelperPath = Join-Path $InstallDir 'Open-CodexHere-Helper.ps1'
$IconPath = Join-Path $InstallDir 'codex.ico'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceIcon = Join-Path $ScriptDir 'codex.ico'

# Menu text: "通过 Codex CLI 打开". Built with code points to avoid Windows PowerShell 5.1 UTF-8 issues.
$MenuText = ([char]0x901A) + ([char]0x8FC7) + ' Codex CLI ' + ([char]0x6253) + ([char]0x5F00)

if (-not (Test-Path -LiteralPath $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $SourceIcon)) {
    Write-Host 'Missing icon file: codex.ico' -ForegroundColor Red
    Write-Host 'Put codex.ico in the same folder as this installer, then run again.' -ForegroundColor Yellow
    Write-Host "Expected path: $SourceIcon" -ForegroundColor Yellow
    exit 1
}

Copy-Item -LiteralPath $SourceIcon -Destination $IconPath -Force

$HelperContent = @'
param(
    [Parameter(Mandatory=$false)]
    [string]$TargetPath
)

$ErrorActionPreference = 'Stop'

function Start-CodexShell {
    param([string]$PathToOpen)

    $escapedPath = $PathToOpen.Replace("'", "''")
    $cmd = "Set-Location -LiteralPath '$escapedPath'; if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { Write-Host 'codex command was not found in PATH.' -ForegroundColor Red; Write-Host 'Restart Explorer, or sign out and sign in after installing Codex CLI.' -ForegroundColor Yellow; Write-Host ''; Write-Host 'Current path:'; Get-Location } else { codex }"

    Start-Process powershell.exe -ArgumentList @(
        '-NoExit',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        $cmd
    )
}

try {
    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        $TargetPath = $env:USERPROFILE
    }

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw "Target path not found: $TargetPath"
    }

    $resolved = (Resolve-Path -LiteralPath $TargetPath).Path
    Start-CodexShell -PathToOpen $resolved
}
catch {
    $message = $_.Exception.Message.Replace("'", "''")
    $cmd = "Write-Host 'Open Codex Here failed.' -ForegroundColor Red; Write-Host '$message' -ForegroundColor Yellow"
    Start-Process powershell.exe -ArgumentList @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-Command',$cmd)
}
'@

# Windows PowerShell 5.1 reads UTF-8 with BOM reliably.
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($HelperPath, $HelperContent, $Utf8Bom)

function Install-CodexMenu {
    param(
        [Parameter(Mandatory=$true)][string]$BaseKey,
        [Parameter(Mandatory=$true)][string]$TargetArgument
    )

    $KeyPath = Join-Path $BaseKey 'OpenWithCodexCLI'
    $CmdPath = Join-Path $KeyPath 'command'

    New-Item -Path $KeyPath -Force | Out-Null
    New-Item -Path $CmdPath -Force | Out-Null

    # Use MUIVerb instead of default value for clearer shell menu behavior.
    New-ItemProperty -Path $KeyPath -Name 'MUIVerb' -Value $MenuText -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $KeyPath -Name 'Icon' -Value $IconPath -PropertyType String -Force | Out-Null

    # Make sure it is not pinned to the top.
    Remove-ItemProperty -Path $KeyPath -Name 'Position' -ErrorAction SilentlyContinue

    $CommandValue = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HelperPath`" `"$TargetArgument`""
    Set-Item -LiteralPath $CmdPath -Value $CommandValue
}

Install-CodexMenu -BaseKey 'HKCU:\Software\Classes\Directory\Background\shell' -TargetArgument '%V'
Install-CodexMenu -BaseKey 'HKCU:\Software\Classes\Directory\shell' -TargetArgument '%1'
Install-CodexMenu -BaseKey 'HKCU:\Software\Classes\Drive\shell' -TargetArgument '%1'

Write-Host 'Installed Open Codex Here context menu.' -ForegroundColor Green
Write-Host "Icon copied to: $IconPath" -ForegroundColor Green
Write-Host "Helper installed to: $HelperPath" -ForegroundColor Green
Write-Host 'You can delete or move the original installer folder after installation.' -ForegroundColor Green

if ($RestartExplorer) {
    Write-Host 'Restarting Explorer...' -ForegroundColor Yellow
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
    Write-Host 'Explorer restarted.' -ForegroundColor Green
}
else {
    Write-Host 'If the menu does not refresh immediately, rerun with -RestartExplorer.' -ForegroundColor Yellow
}
