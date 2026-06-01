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

## `.gitignore` entry to add
```
.claude/settings.local.json
```
