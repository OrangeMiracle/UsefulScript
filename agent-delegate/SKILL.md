---
name: agent-delegate
description: Delegate coding or reviews from Codex to Devin CLI, Claude Code CLI, or Google Antigravity CLI (agy). Save Markdown results and private per-session logs on Linux/macOS or Windows PowerShell 7.
---

# Agent delegate (Devin / Claude Code / Antigravity)

Codex remains the planner and final reviewer. Delegate only independent work. **Never relay a full child-agent terminal transcript into Codex.**

Run from the **target project's directory**, with a UTF-8 task file (`.md` recommended):

```bash
# Linux / macOS
bash ~/.agents/skills/agent-delegate/scripts/delegate.sh devin /tmp/task.md
bash ~/.agents/skills/agent-delegate/scripts/delegate.sh claude /tmp/task.md
bash ~/.agents/skills/agent-delegate/scripts/delegate.sh agy /tmp/task.md
# Continue an existing session (third argument is the native session ID)
bash ~/.agents/skills/agent-delegate/scripts/delegate.sh agy /tmp/followup.md SESSION_ID
```

```powershell
# Windows / PowerShell 7+
pwsh -NoProfile -File "$HOME/.agents/skills/agent-delegate/scripts/delegate.ps1" devin C:/tasks/task.md
pwsh -NoProfile -File "$HOME/.agents/skills/agent-delegate/scripts/delegate.ps1" claude C:/tasks/task.md
pwsh -NoProfile -File "$HOME/.agents/skills/agent-delegate/scripts/delegate.ps1" agy C:/tasks/task.md
# To resume: append the native SESSION_ID as the last argument.
```

- **Devin** uses `--print` with ATIF `--export`. **Claude Code** uses `--print --output-format json`. **Antigravity** uses headless `stream-json` input and output, sends one task on stdin, and resumes with `--conversation`. Use an authenticated `agy` that supports `--input-format stream-json`. [Antigravity headless mode](https://antigravity.google/docs/cli/headless/)
- Per invocation: `<log-root>/<agent>/<session-id>/<run-id>/result.md`, `status.json`, `task.md`, `stdout.log`, `stderr.log`. Devin also saves `transcript.json` (ATIF). Reusing a session creates **another run directory**, never overwriting earlier output.
- Claude's native ID comes from `session_id` in the JSON output. Antigravity's comes from `result.conversation_id` in the final event. Devin's comes from the ATIF export or a best-effort comparison of `devin list --format json` before and after the run. Runs without a known native ID go to `unresolved/<run-id>`.
- Codex receives status, the native ID if known, artifact paths, and up to the last **1,500 UTF-8 bytes** of `result.md`. The complete Markdown result stays on disk. Claude takes the JSON `result` field and Antigravity takes the final event's `result.response`. Devin uses cleaned print-mode stdout, which can include more than the final reply. Read specific log sections on error and verify the work with Git diff and focused tests.
- Default logs: Linux `~/.local/state/codex-agent-delegate`; Windows `%LOCALAPPDATA%/codex-agent-delegate`. Override with `DELEGATE_LOG_DIR`. Logs may contain secrets: keep them private.
- Default Devin model `claude-opus-5-5-high`; override with `DELEGATE_DEVIN_MODEL`. Scripts preserve the previous Devin `smart` permission mode and workspace-trust override; review that policy before use. Do not automatically escalate CLI permissions.
- Claude `--print` is **not** an attachable `claude --bg` Agent View session. Use official background mode separately for live monitoring; keep any status polling output equally bounded.
