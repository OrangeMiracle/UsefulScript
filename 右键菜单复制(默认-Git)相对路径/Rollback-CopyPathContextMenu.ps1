$ErrorActionPreference = "Continue"

$BaseDir = Join-Path $env:LOCALAPPDATA "ExplorerCopyPathMenu-Basic"

$MenuSubKeys = @(
    "Software\Classes\*\shell\CopySelectedFullPath",
    "Software\Classes\*\shell\CopySelectedParentDirectoryPath",
    "Software\Classes\*\shell\01_CopySelectedFullPath",
    "Software\Classes\*\shell\02_CopySelectedParentDirectoryPath",
    "Software\Classes\Directory\shell\CopySelectedFolderFullPath",
    "Software\Classes\Directory\shell\CopySelectedFolderParentDirectoryPath",
    "Software\Classes\Directory\shell\01_CopySelectedFolderFullPath",
    "Software\Classes\Directory\shell\02_CopySelectedFolderParentDirectoryPath"
)

function Remove-HKCURegTreeIfExists {
    param([Parameter(Mandatory = $true)][string]$SubKey)
    try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($SubKey, $false) } catch {}
}

foreach ($SubKey in $MenuSubKeys) {
    Remove-HKCURegTreeIfExists -SubKey $SubKey
}

Remove-Item -LiteralPath $BaseDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done."
Write-Host "Basic copy-path context menu items have been removed."
Write-Host ""
