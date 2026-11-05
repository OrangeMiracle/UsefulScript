[CmdletBinding()]
param([switch]$Audit, [switch]$Rollback)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = $PSScriptRoot
$run = Join-Path $root ('runs\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + $(if ($Rollback) {'-rollback'} else {'-clean'}))
New-Item -ItemType Directory -Path $run -Force | Out-Null
$closed = $false
$exitCode = 1
$phase = 'preflight'
$guard = $null
function Log-Event([string]$Name, $Data) {
    @{time=[DateTimeOffset]::UtcNow.ToString('o');event=$Name;data=$Data} |
        ConvertTo-Json -Compress -Depth 6 | Add-Content -LiteralPath (Join-Path $run 'desktop.jsonl') -Encoding UTF8
}
function Run-Python([string]$Mode) {
    $proc = Start-Process -FilePath $python -ArgumentList @('-X','utf8',('"'+(Join-Path $root 'cleaner.py')+'"'),$Mode,'--run',('"'+$run+'"')) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $run ($Mode+'-stdout.txt')) -RedirectStandardError (Join-Path $run ($Mode+'-stderr.txt'))
    if ($proc.ExitCode -ne 0) { throw "$Mode failed. See $run\$Mode-stderr.txt" }
}
try {
    $guard = [IO.File]::Open((Join-Path $root '.running.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if ($Audit -and $Rollback) { throw 'Choose Audit or Rollback, not both.' }
    $localData = Join-Path $env:USERPROFILE 'AppData\Local'
    $python = @(Get-ChildItem -LiteralPath (Join-Path $localData 'Programs\Python') -Filter python.exe -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName)[0]
    if (-not $python) { throw 'Python 3.10+ is required. No dependencies or API keys are needed.' }
    $packages = @(Get-AppxPackage | Where-Object Name -eq 'OpenAI.Codex')
    if ($packages.Count -ne 1) { throw 'Expected one OpenAI.Codex package. Installation review required.' }
    $package = $packages[0]
    $appPath = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
    if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) { throw 'Inspected application not found.' }
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'")
    if (@($processes | Where-Object { $_.ExecutablePath -ne $appPath }).Count) { throw 'Another ChatGPT installation is running; review required.' }
    $started = @{}
    foreach ($p in $processes) {
        $started[[string]$p.ProcessId] = $p.CreationDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }
    @{pids=@($processes | ForEach-Object {[int]$_.ProcessId});process_started=$started;app_path=$appPath;package_family=$package.PackageFamilyName;package_version=[string]$package.Version;local_appdata=$localData} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run 'context.json') -Encoding UTF8
    if ($Rollback) { Run-Python 'prepare-rollback' } else { Run-Python 'prepare' }
    if ($Audit -or -not (Test-Path -LiteralPath (Join-Path $run 'plan.json'))) {
        Write-Host 'Read-only audit finished. No database changes and no server requests.'
        if (Test-Path -LiteralPath (Join-Path $run 'plan.json')) {
            Write-Host 'Verified targets found. Audit mode only; run Clean.cmd to apply.'
        } else {
            Write-Host 'No safely verified target: open a known stale chat in the desktop app, then run again. Ambiguous evidence is skipped.'
        }
        Write-Host "Report: $run\audit.json"
        $exitCode = 0
    } else {
        $plan = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $run 'plan.json') | ConvertFrom-Json
        if (-not $Rollback -and $plan.app_path -ne $appPath) { throw 'Application changed after planning.' }
        $phase = 'closing'
        Write-Host ('Verified records: '+$plan.rows.Count+'. Closing desktop, backing up and applying one transaction...')
        Log-Event 'desktop_before_exit' @($processes | Select-Object ProcessId,ExecutablePath)
        # From here on always attempt to reopen, including when shutdown partially fails.
        $closed = $processes.Count -gt 0
        foreach ($p in $processes) {
            $native = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
            if ($native -and $native.MainWindowHandle -ne 0) { [void]$native.CloseMainWindow() }
        }
        if ($closed) { Start-Sleep -Seconds 5 }
        $remaining = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'")
        foreach ($p in $remaining) {
            if ($p.ExecutablePath -ne $appPath) { throw 'Unexpected desktop process appeared.' }
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 1
        if (@(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'").Count) { throw 'Desktop did not fully exit.' }
        Log-Event 'desktop_exited' @{remaining=0}
        $phase = 'transaction'
        Run-Python $(if ($Rollback) {'rollback'} else {'apply'})
        $exitCode = 0
    }
} catch {
    Log-Event 'failed' @{phase=$phase;error=$_.Exception.Message}
    Write-Host ('FAILED: '+$_.Exception.Message) -ForegroundColor Red
    $exitCode = 1
} finally {
    if ($closed) {
        try {
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\'+$package.PackageFamilyName+'!App') -WindowStyle Hidden
            Log-Event 'desktop_relaunch_requested' @{}
        } catch { $exitCode=1; Log-Event 'relaunch_failed' @{error=$_.Exception.Message} }
    }
}
if ($closed -and $exitCode -eq 0) {
    try {
        Start-Sleep -Seconds 5
        Run-Python $(if ($Rollback) {'verify-rollback'} else {'verify'})
        Write-Host 'SUCCESS: transaction committed, integrity checked, and targets verified after restart.' -ForegroundColor Green
    } catch { $exitCode=1; Log-Event 'post_restart_failed' @{error=$_.Exception.Message}; Write-Host $_.Exception.Message -ForegroundColor Red }
}
Write-Host "Logs and consistent backup (if changed): $run"
if ($guard) { $guard.Dispose() }
exit $exitCode
