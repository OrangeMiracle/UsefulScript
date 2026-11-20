$ErrorActionPreference = "Stop"

$BaseDir = Join-Path $env:LOCALAPPDATA "ExplorerCopyPathMenu-Basic"
$Helper = Join-Path $BaseDir "CopyPathMenu.ps1"
$Launcher = Join-Path $BaseDir "CopyPathMenu.vbs"
$PowerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$WScriptExe = Join-Path $env:SystemRoot "System32\wscript.exe"

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
function Set-HKCURegString {
    param([string]$SubKey,[AllowEmptyString()][string]$Name,[string]$Value)
    $Key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($SubKey)
    try { $Key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::String) } finally { $Key.Close() }
}
function New-UString { param([int[]]$Codes) -join ($Codes | ForEach-Object { [char]$_ }) }

foreach ($SubKey in $MenuSubKeys) { Remove-HKCURegTreeIfExists -SubKey $SubKey }
Remove-Item -LiteralPath $BaseDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

@'
param([string]$Target,[ValidateSet("Full","Parent")][string]$Mode)
$ErrorActionPreference = "Stop"
function Copy-TextToClipboard { param([string]$Text) try { Set-Clipboard -Value $Text } catch { Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::SetText($Text) } }
function Show-ErrorMessage { param([string]$Message) try { Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show($Message, "Copy Path", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null } catch {} }
try {
  $fullPath=[System.IO.Path]::GetFullPath($Target)
  if($Mode -eq "Full"){ Copy-TextToClipboard $fullPath; exit 0 }
  if(Test-Path -LiteralPath $fullPath -PathType Container){ $p=[System.IO.Directory]::GetParent($fullPath); Copy-TextToClipboard ($(if($null -eq $p){$fullPath}else{$p.FullName})) } else { Copy-TextToClipboard ([System.IO.Path]::GetDirectoryName($fullPath)) }
  exit 0
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

$NameFileParent = New-UString @(0x590d,0x5236,0x5f53,0x524d,0x9009,0x62e9,0x6587,0x4ef6,0x6240,0x5728,0x76ee,0x5f55,0x8def,0x5f84)
$NameFileFull   = New-UString @(0x590d,0x5236,0x5f53,0x524d,0x9009,0x62e9,0x6587,0x4ef6,0x8def,0x5f84)
$NameDirParent  = New-UString @(0x590d,0x5236,0x5f53,0x524d,0x9009,0x62e9,0x6587,0x4ef6,0x5939,0x6240,0x5728,0x76ee,0x5f55,0x8def,0x5f84)
$NameDirFull    = New-UString @(0x590d,0x5236,0x5f53,0x524d,0x9009,0x62e9,0x6587,0x4ef6,0x5939,0x8def,0x5f84)

function Add-ClassicContextMenuItem {
    param([string]$Class,[string]$Verb,[string]$DisplayName,[ValidateSet("Full","Parent")][string]$Mode)
    $SubKey = "Software\Classes\$Class\shell\$Verb"
    $CommandSubKey = "$SubKey\command"
    $Command = "`"$WScriptExe`" `"$Launcher`" `"$Mode`" `"%1`""
    Set-HKCURegString -SubKey $SubKey -Name "" -Value $DisplayName
    Set-HKCURegString -SubKey $SubKey -Name "Icon" -Value "imageres.dll,-5302"
    Set-HKCURegString -SubKey $SubKey -Name "MultiSelectModel" -Value "Single"
    Set-HKCURegString -SubKey $CommandSubKey -Name "" -Value $Command
}

Add-ClassicContextMenuItem -Class "*" -Verb "01_CopySelectedFullPath" -DisplayName $NameFileFull -Mode "Full"
Add-ClassicContextMenuItem -Class "*" -Verb "02_CopySelectedParentDirectoryPath" -DisplayName $NameFileParent -Mode "Parent"
Add-ClassicContextMenuItem -Class "Directory" -Verb "01_CopySelectedFolderFullPath" -DisplayName $NameDirFull -Mode "Full"
Add-ClassicContextMenuItem -Class "Directory" -Verb "02_CopySelectedFolderParentDirectoryPath" -DisplayName $NameDirParent -Mode "Parent"

Write-Host ""
Write-Host "Done."
Write-Host "Classic context menu items installed (basic copy-path only)."
Write-Host "Windows 11: use Show more options or Shift + Right Click."
Write-Host ""
