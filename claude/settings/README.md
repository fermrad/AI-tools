# Settings

Claude Code reads settings from three files in order (later values override earlier ones):

| File | Scope | Committed? |
|---|---|---|
| `~/.claude/settings.json` | User — all projects | N/A |
| `.claude/settings.json` | Project — shared with team | Yes |
| `.claude/settings.local.json` | Project — personal overrides | No (gitignore it) |

## Key settings

### `permissions`
Control which tools Claude can use without prompting.
- `allow` — patterns Claude can run automatically
- `deny` — patterns that are always blocked, even if the user approves

### `hooks`
Shell commands that run on Claude Code events (see `../hooks/README.md`).

### `env`
Environment variables injected into every Bash call Claude makes.

## Files in this folder

| File | Use it as |
|---|---|
| `project-settings.template.json` | `.claude/settings.json` in any project |

> **Note:** `project-settings.template.json` is strict JSON (no comments allowed). When you copy it into `.claude/settings.json`, do **not** also commit your `.claude/settings.local.json` — add it to `.gitignore` first (see below).

## `.gitignore` entry to add

Always add this line to the project's `.gitignore` **before** creating `.claude/settings.local.json` — personal overrides must never be committed:

```
.claude/settings.local.json
```
