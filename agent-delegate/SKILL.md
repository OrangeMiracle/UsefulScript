---
name: agent-delegate
description: Delegate coding or reviews from Codex to Devin CLI or Claude Code CLI without flooding Codex context. Save Markdown results and private per-session logs on Linux/macOS or Windows PowerShell 7.
---

# Agent delegate (Devin / Claude Code)

Codex remains the planner and final reviewer. Delegate only independent work. **Never relay a full child-agent terminal transcript into Codex.**

Run from the **target project's directory**, with a UTF-8 task file (`.md` recommended):

```bash
# Linux / macOS
bash ~/.agents/skills/agent-delegate/scripts/delegate.sh devin /tmp/task.md
bash ~/.agents/skills/agent-delegate/scripts/delegate.sh claude /tmp/task.md
# Continue an existing session (third argument is the native session ID)
bash ~/.agents/skills/agent-delegate/scripts/delegate.sh claude /tmp/followup.md SESSION_ID
```

```powershell
# Windows / PowerShell 7+
pwsh -NoProfile -File "$HOME/.agents/skills/agent-delegate/scripts/delegate.ps1" devin C:/tasks/task.md
pwsh -NoProfile -File "$HOME/.agents/skills/agent-delegate/scripts/delegate.ps1" claude C:/tasks/task.md
# To resume: append the native SESSION_ID as the last argument.
```

- **Devin** uses `--print` with ATIF `--export`; **Claude Code** uses `--print --output-format json`. No interactive TUI is forwarded.
- Per invocation: `<log-root>/<agent>/<session-id>/<run-id>/result.md`, `status.json`, `task.md`, `stdout.log`, `stderr.log`. Devin also saves `transcript.json` (ATIF). Reusing a session creates **another run directory**, never overwriting earlier output.
- Claude's native ID comes from JSON. Devin's native ID comes from the ATIF export; if unavailable, the script checks `devin list --format json` before/after as a **best-effort fallback**. Unconfirmed IDs go to `unresolved/<run-id>`; a run ID is never misrepresented as the native session ID.
- Codex receives only status, native ID (if known), artifact paths and the last **1,500 UTF-8 bytes** of the Markdown result. Read only specific log sections on error; use Git diff and focused tests to verify the work.
- Default logs: Linux `~/.local/state/codex-agent-delegate`; Windows `%LOCALAPPDATA%/codex-agent-delegate`. Override with `DELEGATE_LOG_DIR`. Logs may contain secrets: keep them private.
- Default Devin model `claude-opus-5-5-high`; override with `DELEGATE_DEVIN_MODEL`. Scripts preserve the previous Devin `smart` permission mode and workspace-trust override; review that policy before use. Do not automatically escalate CLI permissions.
- Claude `--print` is **not** an attachable `claude --bg` Agent View session. Use official background mode separately for live monitoring; keep any status polling output equally bounded.
