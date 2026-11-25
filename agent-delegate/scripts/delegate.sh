#!/usr/bin/env bash
# Codex -> Devin / Claude Code / Antigravity: per-run artifacts, bounded stdout.
set -u
umask 077

if [[ $# -lt 2 || $# -gt 3 || ( "$1" != devin && "$1" != claude && "$1" != agy ) || ! -f "$2" ]]; then
  echo 'Usage: delegate.sh {devin|claude|agy} /path/to/task.md [resume-session-id]' >&2
  exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo 'ERROR: python3 required' >&2; exit 2; }
agent=$1
prompt=$2
resume=${3:-}
if [[ -n "$resume" && ! "$resume" =~ ^[[:alnum:]][[:alnum:]_.-]{0,159}$ ]]; then
  echo 'ERROR: unsafe resume session ID' >&2; exit 2
fi
command -v "$agent" >/dev/null 2>&1 || { echo "ERROR: $agent CLI not found" >&2; exit 127; }

root="${DELEGATE_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/codex-agent-delegate}"
base="$root/$agent"
mkdir -p "$base" || exit 2
runid="$(date -u +%Y%m%dT%H%M%SZ)-$$-$(python3 -c 'import secrets; print(secrets.token_hex(4))')"
pending=$(mktemp -d "$base/.pending.XXXXXXXX") || exit 2
raw="$pending/stdout.log"
err="$pending/stderr.log"
task="$pending/task.md"
cp -- "$prompt" "$task" || exit 2
cat >> "$task" <<'PROMPT'

For the final reply, use concise Markdown: result, modified files, tests, and blockers. Do not repeat tool logs.
PROMPT
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Snapshot session catalog as a fallback. Devin's ATIF --export is the preferred ID source.
if [[ "$agent" == devin && -z "$resume" ]]; then
  devin list --format json > "$pending/before.json" 2>/dev/null || rm -f "$pending/before.json"
fi

code=0
if [[ "$agent" == devin ]]; then
  args=(--print --model "${DELEGATE_DEVIN_MODEL:-claude-opus-5-5-high}" \
    --permission-mode smart --respect-workspace-trust false \
    --prompt-file "$task" --export "$pending/transcript.json")
  [[ -z "$resume" ]] || args+=(--resume "$resume")
  CI=1 NO_COLOR=1 TERM=dumb devin "${args[@]}" > "$raw" 2> "$err" || code=$?
elif [[ "$agent" == claude ]]; then
  args=(--print --output-format json)
  [[ -z "$resume" ]] || args+=(--resume "$resume")
  CI=1 NO_COLOR=1 TERM=dumb claude "${args[@]}" \
    'Complete the task specified in standard input.' < "$task" > "$raw" 2> "$err" || code=$?
else
  args=(--input-format stream-json --output-format stream-json)
  [[ -z "$resume" ]] || args+=(--conversation "$resume")
  {
    python3 - "$task" <<'PY' | CI=1 NO_COLOR=1 TERM=dumb agy "${args[@]}" > "$raw"
import json, pathlib, sys

task = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8-sig')
print(json.dumps({'event': 'user', 'message': {'content': task}}))
PY
  } 2> "$err" || code=$?
fi

if [[ "$agent" == devin && -z "$resume" ]]; then
  devin list --format json > "$pending/after.json" 2>/dev/null || rm -f "$pending/after.json"
fi

# One output row: session-id, detection source, agent-reported error (pipe-separated).
parse=$(python3 - "$agent" "$pending" "$resume" "$PWD" "$code" <<'PY'
import json, pathlib, re, sys
agent, folder, resume, cwd, cli_exit = sys.argv[1:]
p = pathlib.Path(folder)

def load(name):
    try:
        with (p / name).open(encoding='utf-8-sig') as f:
            return json.load(f)
    except (OSError, ValueError, TypeError):
        return None

def clean(s):
    s = re.sub(r'\x1b\][^\x07]*(?:\x07|\x1b\\)', '', s)
    s = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', s)
    s = re.sub(r'\x1b[P_^].*?\x1b\\', '', s, flags=re.S)
    return re.sub(r'[\x00-\x08\x0b-\x1f\x7f]', '', s.replace('\r\n', '\n'))

session, source, agent_error = resume, 'resume' if resume else 'unresolved', False
if agent == 'claude':
    obj = load('stdout.log')
    if isinstance(obj, dict):
        result = obj.get('result')
        if not isinstance(result, str):
            result = json.dumps(result, ensure_ascii=False) if result is not None else ''
        (p / 'result.md').write_text(clean(result), encoding='utf-8')
        actual = obj.get('session_id')
        if isinstance(actual, str) and actual:
            session, source = actual, 'claude-json'
        agent_error = obj.get('is_error') is True or str(obj.get('subtype', '')).startswith('error')
    else:
        (p / 'result.md').write_text('Claude did not return valid JSON. See `stdout.log` and `stderr.log`.\n', encoding='utf-8')
        agent_error = True
elif agent == 'agy':
    result = None
    with (p / 'stdout.log').open(encoding='utf-8-sig', errors='replace') as stream:
        for line in stream:
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if isinstance(event, dict) and event.get('event') == 'result':
                result = event.get('result')

    reply = 'Antigravity did not return a valid result event. See `stdout.log` and `stderr.log`.\n'
    agent_error = True
    if isinstance(result, dict):
        actual = result.get('conversation_id')
        if isinstance(actual, str) and actual:
            session, source = actual, 'agy-json'
        response = result.get('response')
        if isinstance(response, str):
            agent_error = result.get('status') != 'SUCCESS'
            reply = response
            if agent_error and not response.strip():
                reply = 'Antigravity did not complete the turn. See `stdout.log` and `stderr.log`.\n'
    (p / 'result.md').write_text(clean(reply), encoding='utf-8')
else:
    output = (p / 'stdout.log').read_text(encoding='utf-8-sig', errors='replace')
    (p / 'result.md').write_text(clean(output), encoding='utf-8')
    obj = load('transcript.json')
    if isinstance(obj, dict) and isinstance(obj.get('session_id'), str) and obj['session_id']:
        session, source = obj['session_id'], 'devin-atif'
    elif not session and cli_exit == '0':
        def sessions(name):
            v = load(name)
            if isinstance(v, dict):
                for key in ('sessions', 'items', 'data'):
                    if isinstance(v.get(key), list):
                        v = v[key]
                        break
            if not isinstance(v, list):
                return None
            rows = {}
            for x in v:
                if not isinstance(x, dict):
                    continue
                identity = x.get('id') or x.get('session_id') or x.get('sessionId')
                if isinstance(identity, str):
                    rows[identity] = x
            return rows
        before, after = sessions('before.json'), sessions('after.json')
        if before is not None and after is not None:
            delta = {k: v for k, v in after.items() if k not in before}
            if len(delta) == 1:
                session = next(iter(delta))
                source = 'devin-list-diff-best-effort'
            elif len(delta) > 1:
                matched = [(k, v) for k, v in delta.items()
                           if (v.get('working_directory') or v.get('cwd') or v.get('workingDirectory')) == cwd]
                if len(matched) == 1:
                    session = matched[0][0]
                    source = 'devin-list-cwd-best-effort'
    if cli_exit == '0' and not output.strip():
        agent_error = True
if not isinstance(session, str) or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]{0,159}', session):
    session, source = '', 'unresolved'
(p / 'session-detection.json').write_text(json.dumps({'session_id': session or None, 'source': source,
    'agent_error': agent_error}, ensure_ascii=False, indent=2), encoding='utf-8')
print(session + '|' + source + '|' + ('true' if agent_error else 'false'))
PY
)
IFS='|' read -r session source agent_error <<< "$parse"
if [[ "$source" == 'unresolved' || -z "$session" ]]; then
  session=''
  run="$base/unresolved/$runid"
else
  run="$base/$session/$runid"
fi
mkdir -p "$(dirname "$run")" || exit 2
mv -- "$pending" "$run" || exit 2
finish="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
status=done
if [[ "$code" -ne 0 || "$agent_error" == true ]]; then
  status=failed
  [[ "$code" -ne 0 ]] || code=1
fi
python3 - "$run" "$agent" "$session" "$source" "$runid" "$status" "$code" "$PWD" "$start" "$finish" <<'PY'
import json, pathlib, sys
run, agent, session, source, runid, status, code, cwd, start, finish = sys.argv[1:]
obj = {'agent': agent, 'session_id': session or None, 'session_id_source': source,
       'run_id': runid, 'status': status, 'exit_code': int(code), 'working_directory': cwd,
       'started_at_utc': start, 'finished_at_utc': finish,
       'result_md': str(pathlib.Path(run) / 'result.md'), 'raw_log': str(pathlib.Path(run) / 'stdout.log')}
(pathlib.Path(run) / 'status.json').write_text(json.dumps(obj, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY
# The parent sees only bounded completion data, never the child transcript.
printf 'AGENT=%s STATUS=%s EXIT_CODE=%s SESSION_ID=%s\nRUN=%s\nRESULT=%s\nLOG=%s\n' \
  "$agent" "$status" "$code" "${session:-UNKNOWN}" "$runid" "$run/result.md" "$run/stdout.log"
printf 'FINAL_REPLY_LAST_1500_BYTES:\n'
python3 - "$run/result.md" <<'PY'
from pathlib import Path
import sys
raw = Path(sys.argv[1]).read_bytes()
chunk = raw[-1500:]
print(chunk.decode('utf-8', 'ignore'))
PY
if [[ -z "$session" ]]; then
  echo 'NOTE=Native session ID could not be confirmed. Stored under unresolved/<run-id>.'
fi
exit "$code"
