# CLAUDE.md — AI-tools

Read this before making changes to this repo.

## Session start

- **`git pull origin main`** before any work.
- **All changes go through a PR to `main`** — never commit directly.

## Purpose

Central repository for AI configuration files, system prompts, and reusable GitHub Actions workflows used across Ferm projects.

## Repository structure

```
claude/
  CLAUDE.md.template   # Base CLAUDE.md template for Ferm app repos
  agents/              # Reusable agent configurations
  github-actions/      # Reusable GitHub Actions workflows for AI-powered automation
  hooks/               # Claude Code hook scripts
  mcp/                 # MCP server config templates
  rules/               # Extended rules (referenced from app CLAUDE.md files)
  settings/            # Claude Code settings templates
  skills/              # Claude Code skill definitions
  widget/              # AI widget configurations
cursor/                # Cursor AI .cursorrules templates
github-copilot/        # Copilot instructions templates
openai/                # OpenAI/ChatGPT system prompt templates
perplexity/            # Perplexity search prompt templates
scripts/               # Utility scripts
```

## PR workflow

All changes go through a PR to `main` — see `CONTRIBUTING.md` for branch naming, PR title format, and template propagation steps.

- Always `git pull origin main` before starting work.

## Updating a template

1. Edit the file in the relevant tool directory
2. List affected repos in the PR body — some templates are copied to app repos and need follow-up PRs there
3. After merge, open follow-up PRs in each affected repo

## Adding a GitHub Actions workflow

Workflows in `claude/github-actions/` are copied to consuming repos:
1. Test the workflow in a single repo before merging
2. Document inputs, outputs, and required secrets in the workflow file itself
3. After merge, copy to all consuming repos via separate PRs

## Security

- **Never commit API keys, tokens, or passwords** — use `${{ secrets.NAME }}` placeholders in workflow templates and `<YOUR_TOKEN_HERE>` in prompt templates
- If a template ever contains a real credential by mistake, rotate the credential immediately and audit which repos deployed it
