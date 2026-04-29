$ErrorActionPreference = "Stop"

$BaseDir = Join-Path $env:LOCALAPPDATA "ExplorerCopyPathMenu-Git"
$Helper = Join-Path $BaseDir "CopyGitPathMenu.ps1"
$Launcher = Join-Path $BaseDir "CopyGitPathMenu.vbs"
$ConfigPath = Join-Path $BaseDir "RepoDetectConfig.json"
$PowerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$WScriptExe = Join-Path $env:SystemRoot "System32\wscript.exe"

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
function Set-HKCURegString {
    param([string]$SubKey,[AllowEmptyString()][string]$Name,[string]$Value)
    $Key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($SubKey)
    try { $Key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::String) } finally { $Key.Close() }
}
function New-UString { param([int[]]$Codes) -join ($Codes | ForEach-Object { [char]$_ }) }
function Read-YesNo {
    param([string]$Prompt,[bool]$Default=$true)
    while ($true) {
        $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
        $answer = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        switch -Regex ($answer.Trim().ToLowerInvariant()) {
            "^(y|yes)$" { return $true }
            "^(n|no)$" { return $false }
            default { Write-Host "Please input y/yes or n/no." -ForegroundColor Yellow }
        }
    }
}
function Test-GitAvailable { try { $null = & git --version 2>$null; $LASTEXITCODE -eq 0 } catch { $false } }

Write-Host ""
Write-Host "1) Git command detection (most accurate, requires git in PATH)." -ForegroundColor Cyan
$wantGitDetect = Read-YesNo -Prompt "Enable Git command detection?" -Default $true
$enableGitDetect = $false
if ($wantGitDetect -and (Test-GitAvailable)) { $enableGitDetect = $true }
elseif ($wantGitDetect) { Write-Host "Git not detected. Skip Git command detection and continue." -ForegroundColor Yellow }

Write-Host ""
Write-Host "2) Upward .git fallback (no Windows Search, no full-disk scan)." -ForegroundColor Cyan
$enableDotGitFallback = Read-YesNo -Prompt "Enable upward .git fallback detection?" -Default $true

if (-not $enableGitDetect -and -not $enableDotGitFallback) {
    Write-Host "You disabled all repo root detection methods; Git-relative features cannot determine repository root." -ForegroundColor Yellow
    if (-not (Read-YesNo -Prompt "Continue installation anyway?" -Default $false)) { exit 1 }
}

foreach ($SubKey in $MenuSubKeys) { Remove-HKCURegTreeIfExists -SubKey $SubKey }
Remove-Item -LiteralPath $BaseDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
[pscustomobject]@{ EnableGitCommandDetection=$enableGitDetect; EnableDotGitFallback=$enableDotGitFallback } | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8

@'
param([string]$Target,[ValidateSet("GitRelative","GitParentRelative")][string]$Mode)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "RepoDetectConfig.json"
function Copy-TextToClipboard { param([string]$Text) try { Set-Clipboard -Value $Text } catch { Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::SetText($Text) } }
function Show-ErrorMessage { param([string]$Message) try { Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show($Message, "Copy Path", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null } catch {} }
function Normalize-Separators { param([string]$Path) $Path -replace '\\','/' }
function Get-DetectionConfig { $c=[pscustomobject]@{EnableGitCommandDetection=$true;EnableDotGitFallback=$true}; if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) { try { $l=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json; if($null -ne $l.EnableGitCommandDetection){$c.EnableGitCommandDetection=[bool]$l.EnableGitCommandDetection}; if($null -ne $l.EnableDotGitFallback){$c.EnableDotGitFallback=[bool]$l.EnableDotGitFallback} } catch {} }; $c }
function Get-WorkingDirectory { param([string]$Path) if (Test-Path -LiteralPath $Path -PathType Container) { $Path } else { [System.IO.Path]::GetDirectoryName($Path) } }
function Get-GitRepoRootByCommand { param([string]$WorkingDirectory) try { $r=& git -C $WorkingDirectory rev-parse --show-toplevel 2>$null; if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($r)){return $null}; [System.IO.Path]::GetFullPath(($r | Select-Object -First 1).Trim()) } catch { $null } }
function Get-GitRepoRootByDotGitFallback { param([string]$WorkingDirectory) $cur=[System.IO.Path]::GetFullPath($WorkingDirectory); while($true){ if(Test-Path -LiteralPath (Join-Path $cur ".git")){return $cur}; $p=[System.IO.Directory]::GetParent($cur); if($null -eq $p){break}; $cur=$p.FullName }; $null }
function Resolve-RepoRoot { param([string]$WorkingDirectory,[pscustomobject]$Config) if($Config.EnableGitCommandDetection){$a=Get-GitRepoRootByCommand -WorkingDirectory $WorkingDirectory; if($null -ne $a){return $a}}; if($Config.EnableDotGitFallback){$b=Get-GitRepoRootByDotGitFallback -WorkingDirectory $WorkingDirectory; if($null -ne $b){return $b}}; $null }
function Is-SubPath { param([string]$BasePath,[string]$CandidatePath) $base=[System.IO.Path]::GetFullPath($BasePath).TrimEnd('\'); $cand=[System.IO.Path]::GetFullPath($CandidatePath).TrimEnd('\'); if($cand.Equals($base,[System.StringComparison]::OrdinalIgnoreCase)){return $true}; $cand.StartsWith($base + '\',[System.StringComparison]::OrdinalIgnoreCase) }
function Convert-ToGitRelativeText { param([string]$RepoRoot,[string]$TargetPath) $repo=[System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\'); $target=[System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\'); if(-not (Is-SubPath -BasePath $repo -CandidatePath $target)){ throw "Target path is not inside repository root." }; if($target.Equals($repo,[System.StringComparison]::OrdinalIgnoreCase)){ return "." }; $rel=$target.Substring($repo.Length).TrimStart('\','/'); $rel=Normalize-Separators $rel; if([string]::IsNullOrWhiteSpace($rel)){ "." } else { "./$rel" } }
try {
  $fullPath=[System.IO.Path]::GetFullPath($Target)
  $isDir = Test-Path -LiteralPath $fullPath -PathType Container
  if($Mode -eq "GitRelative"){ $targetForRelative=$fullPath } else { if($isDir){ $pp=[System.IO.Directory]::GetParent($fullPath); $targetForRelative=$(if($null -eq $pp){$fullPath}else{$pp.FullName}) } else { $targetForRelative=[System.IO.Path]::GetDirectoryName($fullPath) } }
  $repoRoot = Resolve-RepoRoot -WorkingDirectory (Get-WorkingDirectory -Path $fullPath) -Config (Get-DetectionConfig)
  if([string]::IsNullOrWhiteSpace($repoRoot)){ Copy-TextToClipboard ""; Show-ErrorMessage "Unable to find Git repository root for selected path."; exit 1 }
  Copy-TextToClipboard (Convert-ToGitRelativeText -RepoRoot $repoRoot -TargetPath $targetForRelative); exit 0
} catch { Copy-TextToClipboard ""; Show-ErrorMessage ("Copy failed: " + $_.Exception.Message); exit 1 }
'@ | Set-Content -Path $Helper -Encoding UTF8

$VbsHelper = $Helper.Replace('"', '""')
$VbsPowerShell = $PowerShellExe.Replace('"', '""')
@"
Option Explicit
Dim args, mode, target, shell, ps, helper, cmd
Set args = WScript.Arguments
If args.Count < 2 Then WScript.Quit 1
mode = args.Item(0)
target = args.Item(1)
helper = "$VbsHelper"
ps = "$VbsPowerShell"
cmd = Chr(34) & ps & Chr(34) & " -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & helper & Chr(34) & " -Mode " & Chr(34) & mode & Chr(34) & " -Target " & Chr(34) & target & Chr(34)
Set shell = CreateObject("WScript.Shell")
shell.Run cmd, 0, True
"@ | Set-Content -Path $Launcher -Encoding Unicode

$NameFileGitRelative = New-UString @(0x590d,0x5236,0x6587,0x4ef6,0x0047,0x0069,0x0074,0x76f8,0x5bf9,0x8def,0x5f84)
$NameFileGitParentRelative = New-UString @(0x590d,0x5236,0x6587,0x4ef6,0x6240,0x5728,0x76ee,0x5f55,0x0047,0x0069,0x0074,0x76f8,0x5bf9,0x8def,0x5f84)
$NameDirGitRelative = New-UString @(0x590d,0x5236,0x6587,0x4ef6,0x5939,0x0047,0x0069,0x0074,0x76f8,0x5bf9,0x8def,0x5f84)
$NameDirGitParentRelative = New-UString @(0x590d,0x5236,0x6587,0x4ef6,0x5939,0x6240,0x5728,0x76ee,0x5f55,0x0047,0x0069,0x0074,0x76f8,0x5bf9,0x8def,0x5f84)

function Add-ClassicContextMenuItem {
    param(
        [string]$Class,
        [string]$Verb,
        [string]$DisplayName,
        [ValidateSet("GitRelative","GitParentRelative")][string]$Mode,
        [bool]$SeparatorBefore = $false
    )
    $SubKey = "Software\Classes\$Class\shell\$Verb"
    $CommandSubKey = "$SubKey\command"
    $Command = "`"$WScriptExe`" `"$Launcher`" `"$Mode`" `"%1`""
    Set-HKCURegString -SubKey $SubKey -Name "" -Value $DisplayName
    Set-HKCURegString -SubKey $SubKey -Name "Icon" -Value "imageres.dll,-5302"
    Set-HKCURegString -SubKey $SubKey -Name "MultiSelectModel" -Value "Single"
    if ($SeparatorBefore) {
        Set-HKCURegString -SubKey $SubKey -Name "SeparatorBefore" -Value ""
    }
    Set-HKCURegString -SubKey $CommandSubKey -Name "" -Value $Command
}

Add-ClassicContextMenuItem -Class "*" -Verb "03_CopySelectedGitRelativePath" -DisplayName $NameFileGitRelative -Mode "GitRelative" -SeparatorBefore $true
Add-ClassicContextMenuItem -Class "*" -Verb "04_CopySelectedGitParentRelativePath" -DisplayName $NameFileGitParentRelative -Mode "GitParentRelative"
Add-ClassicContextMenuItem -Class "Directory" -Verb "03_CopySelectedFolderGitRelativePath" -DisplayName $NameDirGitRelative -Mode "GitRelative" -SeparatorBefore $true
Add-ClassicContextMenuItem -Class "Directory" -Verb "04_CopySelectedFolderGitParentRelativePath" -DisplayName $NameDirGitParentRelative -Mode "GitParentRelative"

Write-Host ""
Write-Host "Done."
Write-Host "Classic context menu items installed (Git-relative path only)."
Write-Host "Windows 11: use Show more options or Shift + Right Click."
Write-Host ""
