# Contributing

This document covers how to contribute to `fermrad/AI-tools`. Read `CLAUDE.md` first — it contains the repo structure and template management workflow.

---

## Before you start

1. Pull the latest `main`:
   ```bash
   git checkout main && git pull origin main
   ```
2. Check for open PRs that might conflict:
   ```bash
   gh pr list
   ```

---

## What this repo is

A **central store for AI configuration templates** — Claude Code CLAUDE.md templates, system prompts, GitHub Actions workflows for AI-powered automation, and tool configs for Cursor, Copilot, and others. Changes here may need to be propagated to individual app repos.

---

## Branch and PR conventions

Create a branch from `main` using one of these prefixes:

| Prefix | When to use |
|---|---|
| `feat/` | New template, workflow, or config |
| `fix/` | Correction to an existing template |
| `docs/` | Documentation-only |
| `refactor/` | Restructuring without functional change |

**PR title format:** `type(tool): short description`

- `tool`: `claude`, `cursor`, `copilot`, `openai`, `perplexity`, `scripts`, `github-actions`

Examples:
- `feat(claude): add skills directory with code-review skill`
- `fix(claude): correct PR workflow instructions in CLAUDE.md template`
- `docs(readme): update tool list`

---

## What every PR must include

1. **The change** — template, workflow, or config file
2. **Impact statement in the PR body** — which repos or tools are affected by this change, and whether existing deployments need to be updated
3. **No secrets** — templates must use placeholders, never real credentials

---

## Template changes that affect deployed repos

If you update a `CLAUDE.md` template or a GitHub Actions workflow that has been copied to app repos:

1. List the affected repos in the PR body
2. After merge, open follow-up PRs in each affected repo to apply the change
3. Note the follow-up PR numbers in this PR for tracking

---

## Adding a reusable workflow

Workflows in `claude/github-actions/` are copied to consuming repos. After adding or changing one:

1. Test it in a sandbox or against a single repo first
2. Document inputs, outputs, and secrets in the workflow file itself
3. After merge, copy to consuming repos via PR

---

## Security

- **Never commit API keys, tokens, or passwords** — use `${{ secrets.NAME }}` placeholders
- Templates must not contain real credentials even as examples — use `<YOUR_TOKEN_HERE>` style placeholders
- If a template accidentally exposed a secret, rotate it immediately and audit which repos deployed it

---

## Reviewing a PR

When reviewing:

- [ ] No real secrets or credentials in the diff
- [ ] PR body lists affected repos and whether follow-up PRs are needed
- [ ] Template placeholders use clear naming (`<REPO>`, `${{ secrets.NAME }}`)
- [ ] Workflow changes have been tested in at least one repo
