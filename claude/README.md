# Claude Code

Tools and configurations for [Claude Code](https://claude.ai/code) (Anthropic's AI coding CLI).

## Files

### `CLAUDE.md.template`
Drop into a project root as `CLAUDE.md`. Claude Code reads this file at the start of every session to understand the project structure, conventions, and rules.

### `github-actions/`
Reusable GitHub Actions workflows and supporting Python scripts that call the Claude API.

| File | Purpose |
|---|---|
| `ai-issue-triage.yml` | Triggered on issue open — Claude analyses the issue, reads relevant files, and either opens a draft fix PR or posts an analysis comment |
| `triage-issue.py` | Script called by `ai-issue-triage.yml` |
| `compliance.yml` | Job that runs on every PR — Claude maps the codebase against ISO 27001 and SOC 2 controls and files labelled issues for new gaps |
| `compliance-check.py` | Script called by the compliance job |

## Setup

1. Add `ANTHROPIC_API_KEY` to the repo's Actions secrets (Settings → Secrets and variables → Actions).
2. Copy the workflow files into `.github/workflows/` and the Python scripts into `.github/scripts/`.
3. The compliance job runs on every PR automatically. The issue triage runs when issues are opened.

## Model

All scripts default to `claude-sonnet-4-6`. Update the `MODEL` constant in each script to change it.
