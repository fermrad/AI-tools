# Contributing

This document covers how to contribute to `fermrad/AI-tools`. Read `CLAUDE.md` first — it contains the repo structure and template management workflow.

---

## Development workflow

Follow these steps in order for every change to a template, workflow, or config.

### Step 1 — Validate main before branching

```bash
git checkout main && git pull origin main
gh pr list
```

Check for open PRs that might conflict, particularly those touching the same templates or workflows.

### Step 2 — Push branch early and open a Draft PR

```bash
git checkout -b feat/my-change   # or fix/
git push -u origin feat/my-change
gh pr create --draft
```

Open the PR immediately with a thorough description covering:
- **What** changed (which template, workflow, or config file)
- **Why** — the use case or gap this addresses
- **Which repos** are affected and whether they need follow-up PRs
- **Breaking changes** — if a CLAUDE.md template or workflow changes behaviour that consuming repos depend on

### Step 3 — Audit scope & ownership

Before making changes, check:
- Is this change general enough to belong in AI-tools, or is it specific to one app repo? App-specific agent instructions belong in that app's CLAUDE.md, not in a shared template.
- Does this affect a template that's already been deployed to multiple repos? If so, note the propagation work required in the PR.

### Step 4 — Confirm baseline CI passes on the draft PR

Wait for CI to pass on your fresh branch before writing. If CI fails with no changes, investigate main first.

### Step 5 — Make the change

Edit the relevant file in the appropriate tool directory:

```
claude/              # CLAUDE.md templates, skills, hooks, settings, MCP configs
cursor/              # Cursor .cursorrules templates
github-copilot/      # Copilot instruction templates
openai/              # ChatGPT system prompt templates
perplexity/          # Perplexity search prompt templates
scripts/             # Utility scripts
```

For GitHub Actions workflows (`claude/github-actions/`): test the workflow in a single repo before opening the PR for review.

### Step 6 — PR quality audit

Before marking the PR ready for review, confirm all of the following:

- [ ] `CLAUDE.md` updated if the repo structure or workflow changed
- [ ] PR body lists all affected repos and whether follow-up PRs are needed
- [ ] No real secrets or credentials in the diff — use `${{ secrets.NAME }}` or `<YOUR_TOKEN_HERE>` placeholders
- [ ] Template placeholders use clear, consistent naming (`<REPO>`, `<APPNAME>`, `${{ secrets.NAME }}`)
- [ ] If a GitHub Actions workflow changed: tested in at least one consuming repo
- [ ] Branch is up to date with remote main — rebase if needed:
  ```bash
  git fetch origin && git rebase origin/main
  ```

### Step 7 — Mark ready and request review

Mark the PR as ready for review. After approval, merge.

### Step 8 — Propagate to consuming repos

After merge, open follow-up PRs in each affected repo to apply the change. Note the follow-up PR numbers as comments on this PR for tracking.

There is no staging or production deploy for this repo itself — changes take effect when consuming repos pick up the updated templates.

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
- [ ] `CLAUDE.md` updated if repo structure changed
