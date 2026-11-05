#Requires -Version 7.0
<# Codex -> Devin/Claude Code. One session directory, one subdirectory per run.
   All raw output stays on disk; only a bounded summary reaches Codex. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)][ValidateSet('devin','claude')][string]$Agent,
    [Parameter(Mandatory, Position=1)][string]$TaskFile,
    [Parameter(Position=2)][string]$ResumeSessionId = ''
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if (-not (Test-Path -LiteralPath $TaskFile -PathType Leaf)) { throw "Task file not found: $TaskFile" }
if ($ResumeSessionId -and $ResumeSessionId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$') {
    throw 'Unsafe resume session ID'
}
if (-not (Get-Command $Agent -ErrorAction SilentlyContinue)) { throw "$Agent CLI not found in PATH" }

function Read-JsonFile([string]$File) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return $null }
    try { return ,(Get-Content -LiteralPath $File -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -NoEnumerate -ErrorAction Stop) }
    catch { return $null }
}
function Clean-Ansi([string]$Value) {
    if (-not $Value) { return '' }
    $Value = $Value -replace '\x1B\][^\x07]*(?:\x07|\x1B\\)', ''
    $Value = $Value -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
    $Value = $Value -replace '\x1B[P_^].*?\x1B\\', ''
    $Value = $Value -replace "`r`n", "`n"
    return ($Value -replace '[\x00-\x08\x0B-\x1F\x7F]', '')
}
function Get-SessionMap([string]$File) {
    $value = Read-JsonFile $File
    if ($value -is [System.Collections.IDictionary]) {
        foreach ($key in @('sessions','items','data')) {
            if ($value[$key] -is [array]) { $value = $value[$key]; break }
        }
    }
    if ($value -isnot [array]) { return $null }
    $result = @{}
    foreach ($entry in $value) {
        if ($entry -isnot [System.Collections.IDictionary]) { continue }
        $id = @($entry['id'], $entry['session_id'], $entry['sessionId']) |
            Where-Object { $_ -is [string] -and $_.Length -gt 0 } | Select-Object -First 1
        if ($id) { $result[$id] = $entry }
    }
    return ,$result
}
function Last-Utf8Bytes([string]$Value, [int]$Limit) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    if ($bytes.Length -le $Limit) { return $Value }
    $start = $bytes.Length - $Limit
    while ($start -lt $bytes.Length -and ($bytes[$start] -band 0xC0) -eq 0x80) { $start++ }
    return [Text.Encoding]::UTF8.GetString($bytes, $start, $bytes.Length - $start)
}

$root = $env:DELEGATE_LOG_DIR
if (-not $root) {
    $state = $env:LOCALAPPDATA
    if (-not $state) { $state = Join-Path $HOME 'AppData/Local' }
    $root = Join-Path $state 'codex-agent-delegate'
}
$base = Join-Path $root $Agent
[void](New-Item -ItemType Directory -Path $base -Force)
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' +
    [Environment]::ProcessId + '-' + ([Guid]::NewGuid().ToString('N').Substring(0,8))
$pending = Join-Path $base ('.pending.' + $runId)
[void](New-Item -ItemType Directory -Path $pending)
$task = Join-Path $pending 'task.md'
$stdout = Join-Path $pending 'stdout.log'
$stderr = Join-Path $pending 'stderr.log'
$transcript = Join-Path $pending 'transcript.json'
Copy-Item -LiteralPath $TaskFile -Destination $task
Add-Content -LiteralPath $task -Encoding utf8 -Value "`nFor the final reply, use concise Markdown: result, modified files, tests, and blockers. Do not repeat tool logs."
$started = (Get-Date).ToUniversalTime().ToString('o')
$cwd = (Get-Location).Path

# Before/after catalogs are a fallback when the Devin ATIF export has no session ID.
$beforeFile = Join-Path $pending 'before.json'
$afterFile = Join-Path $pending 'after.json'
if ($Agent -eq 'devin' -and -not $ResumeSessionId) {
    & devin list --format json 1> $beforeFile 2> $null
}

$oldCI = $env:CI
$oldNoColor = $env:NO_COLOR
$oldTerm = $env:TERM
$env:CI = '1'
$env:NO_COLOR = '1'
$env:TERM = 'dumb'
$code = 1
try {
    if ($Agent -eq 'devin') {
        $model = if ($env:DELEGATE_DEVIN_MODEL) { $env:DELEGATE_DEVIN_MODEL } else { 'claude-opus-5-5-high' }
        $arguments = @('--print','--model',$model,'--permission-mode','smart',
            '--respect-workspace-trust','false','--prompt-file',$task,'--export',$transcript)
        if ($ResumeSessionId) { $arguments += @('--resume',$ResumeSessionId) }
        & devin @arguments 1> $stdout 2> $stderr
    } else {
        $arguments = @('--print','--output-format','json')
        if ($ResumeSessionId) { $arguments += @('--resume',$ResumeSessionId) }
        # Claude CLI reads the task file from stdin; avoid putting large prompts in argv.
        Get-Content -LiteralPath $task -Raw -Encoding utf8 |
            & claude @arguments 'Complete the task specified in standard input.' 1> $stdout 2> $stderr
    }
    $code = $LASTEXITCODE
} catch {
    [IO.File]::AppendAllText($stderr, "`nCLI invocation error: $($_.Exception.Message)`n", [Text.Encoding]::UTF8)
    $code = 1
} finally {
    $env:CI = $oldCI
    $env:NO_COLOR = $oldNoColor
    $env:TERM = $oldTerm
}
if ($null -eq $code) { $code = 1 }
if ($Agent -eq 'devin' -and -not $ResumeSessionId) {
    & devin list --format json 1> $afterFile 2> $null
}

$session = $ResumeSessionId
$source = if ($session) { 'resume' } else { 'unresolved' }
$agentError = $false
$resultFile = Join-Path $pending 'result.md'
if ($Agent -eq 'claude') {
    $json = Read-JsonFile $stdout
    if ($json -is [System.Collections.IDictionary]) {
        $reply = $json['result']
        if ($reply -isnot [string]) { $reply = if ($null -ne $reply) { $reply | ConvertTo-Json -Depth 30 } else { '' } }
        [IO.File]::WriteAllText($resultFile, (Clean-Ansi $reply), [Text.Encoding]::UTF8)
        if ($json['session_id'] -is [string] -and $json['session_id']) {
            $session = $json['session_id']; $source = 'claude-json'
        }
        $agentError = ($json['is_error'] -eq $true) -or ([string]$json['subtype']).StartsWith('error')
    } else {
        [IO.File]::WriteAllText($resultFile, 'Claude did not return valid JSON. See stdout.log and stderr.log.', [Text.Encoding]::UTF8)
        $agentError = $true
    }
} else {
    $raw = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw -Encoding utf8 } else { '' }
    [IO.File]::WriteAllText($resultFile, (Clean-Ansi $raw), [Text.Encoding]::UTF8)
    $atif = Read-JsonFile $transcript
    if ($atif -is [System.Collections.IDictionary] -and $atif['session_id'] -is [string] -and $atif['session_id']) {
        $session = $atif['session_id']; $source = 'devin-atif'
    } elseif (-not $session -and $code -eq 0) {
        $before = Get-SessionMap $beforeFile
        $after = Get-SessionMap $afterFile
        if ($null -ne $before -and $null -ne $after) {
            $delta = @($after.Keys | Where-Object { -not $before.ContainsKey($_) })
            if ($delta.Count -eq 1) {
                $session = $delta[0]; $source = 'devin-list-diff-best-effort'
            } elseif ($delta.Count -gt 1) {
                $matches = @($delta | Where-Object {
                    $entry = $after[$_]
                    @($entry['working_directory'], $entry['cwd'], $entry['workingDirectory']) -contains $cwd
                })
                if ($matches.Count -eq 1) {
                    $session = $matches[0]; $source = 'devin-list-cwd-best-effort'
                }
            }
        }
    }
    if ($code -eq 0 -and [string]::IsNullOrWhiteSpace($raw)) { $agentError = $true }
}
if (-not $session -or $session -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$') {
    $session = ''; $source = 'unresolved'
    $run = Join-Path (Join-Path $base 'unresolved') $runId
} else {
    $run = Join-Path (Join-Path $base $session) $runId
}
[void](New-Item -ItemType Directory -Path (Split-Path -Parent $run) -Force)
Move-Item -LiteralPath $pending -Destination $run
$resultFile = Join-Path $run 'result.md'
$stdout = Join-Path $run 'stdout.log'
if ($code -ne 0 -or $agentError) {
    $status = 'failed'; if ($code -eq 0) { $code = 1 }
} else { $status = 'done' }
$metadata = [ordered]@{
    agent = $Agent
    session_id = if ($session) { $session } else { $null }
    session_id_source = $source
    run_id = $runId
    status = $status
    exit_code = [int]$code
    working_directory = $cwd
    started_at_utc = $started
    finished_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    result_md = $resultFile
    raw_log = $stdout
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'status.json') -Encoding utf8

Write-Output "AGENT=$Agent STATUS=$status EXIT_CODE=$code SESSION_ID=$(if ($session) { $session } else { 'UNKNOWN' })"
Write-Output "RUN=$runId"
Write-Output "RESULT=$resultFile"
Write-Output "LOG=$stdout"
Write-Output 'FINAL_REPLY_LAST_1500_BYTES:'
Write-Output (Last-Utf8Bytes (Get-Content -LiteralPath $resultFile -Raw -Encoding utf8) 1500)
if (-not $session) { Write-Output 'NOTE=Native session ID could not be confirmed. Stored under unresolved/<run-id>.' }
exit [int]$code
