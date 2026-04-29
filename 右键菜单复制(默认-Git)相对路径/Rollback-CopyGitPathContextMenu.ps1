$ErrorActionPreference = "Continue"

$BaseDir = Join-Path $env:LOCALAPPDATA "ExplorerCopyPathMenu-Git"

$MenuSubKeys = @(
    "Software\Classes\*\shell\CopySelectedGitRelativePath",
    "Software\Classes\*\shell\CopySelectedGitParentRelativePath",
    "Software\Classes\*\shell\03_CopySelectedGitRelativePath",
    "Software\Classes\*\shell\04_CopySelectedGitParentRelativePath",
    "Software\Classes\Directory\shell\CopySelectedFolderGitRelativePath",
    "Software\Classes\Directory\shell\CopySelectedFolderGitParentRelativePath",
    "Software\Classes\Directory\shell\03_CopySelectedFolderGitRelativePath",
    "Software\Classes\Directory\shell\04_CopySelectedFolderGitParentRelativePath"
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
Write-Host "Git-relative copy-path context menu items have been removed."
Write-Host ""
