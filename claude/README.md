# Claude Code

Tools, templates, and configurations for [Claude Code](https://claude.ai/code).

## Folder structure

| Folder | Contents |
|---|---|
| `skills/` | Custom `/skill-name` commands — reusable procedures Claude follows when invoked |
| `agents/` | Subagent definitions — specialised agents with restricted tools and their own model |
| `hooks/` | Hook configuration examples and scripts for `.claude/settings.json` |
| `mcp/` | MCP server configuration templates |
| `settings/` | `.claude/settings.json` templates for project permission and hook setup |
| `github-actions/` | Reusable GitHub Actions workflows and supporting Python scripts |
| `CLAUDE.md.template` | Drop-in `CLAUDE.md` for new projects |

---

## Installing skills

Run the install script — it clones this repo (sparse, `claude/` only) and symlinks each skill into `~/.claude/skills/`. Claude Code auto-discovers skills in that directory.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fermrad/AI-tools/main/claude/install-claude-skills.sh)
```

> **Restart Claude Code after running** — skills are discovered at startup. Type `/` to see them.

### Updating

Skills are installed as symlinks, so `git pull` in `~/repos/AI-tools` picks up changes automatically. Restart Claude Code to load updated skill content.

### On `claude-dev.ferm.dk`

The `start-claude-session.yml` workflow runs the install script automatically before each remote session — no manual step needed.

---

## Skills vs Agents — when to use which

| | Skill | Agent |
|---|---|---|
| **Trigger** | User types `/skill-name` | Main Claude delegates with `Agent(...)` |
| **Tools** | All normal tools | Restricted to a defined subset |
| **Model** | Same as main Claude | Can use a different model (e.g. Haiku for speed, Opus for depth) |
| **Use for** | Step-by-step procedures, checklists, repeatable workflows | Parallel workstreams, read-only research, specialised review |

**Rule of thumb:** if it's a *what to do* checklist → skill. If it's a *who does it* role with different capabilities → agent.

---

## Skills

### `/new-repo` — `skills/new-repo/SKILL.md`
Creates a new GitHub repo under `fermrad` with standard structure, branch protection, labels, CLAUDE.md, and optionally wires up reusable AI workflows.

### `/new-pr` — `skills/new-pr/SKILL.md`
Opens a well-formed pull request with a conventional commit title, descriptive body, and correct labels.

### `/code-review` — `skills/code-review/SKILL.md`
Reviews staged changes, a PR diff, or specific files for bugs, security issues, and quality — grouped by severity.

---

## Agents

### `researcher` — `agents/researcher/`
Read-only (WebSearch, WebFetch, Read, grep, find). Use for technology research, CVE lookups, and documentation reading without risk of file modification.

### `security-reviewer` — `agents/security-reviewer/`
Read-only security review using Opus. Use for independent auth, middleware, and API route security analysis.

---

## GitHub Actions (reusable workflows)

Callable from any repo with:
```yaml
jobs:
  compliance:
    uses: fermrad/AI-tools/.github/workflows/compliance-check.yml@main
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

| Workflow | Trigger | What it does |
|---|---|---|
| `ai-issue-triage.yml` | `workflow_call` (called on `issues: [opened]` from caller) | Claude reads the issue + relevant files; opens a draft fix PR or posts analysis |
| `compliance-check.yml` | `workflow_call` only (called from a caller's CI on PR) | Claude maps the codebase against ISO 27001 and SOC 2 controls; files labelled issues |
| `pentest.yml` | `workflow_call` (caller exposes `workflow_dispatch` for manual runs) | Semgrep + Trivy + Gitleaks + npm audit + optional ZAP scan; files `security` issues |
