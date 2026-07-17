---
name: repo-recon
description: Survey the fermrad GitHub org and Ferm's Claude guide before proposing or building anything — the local clone is never the source of truth
argument-hint: [app/repo name or topic]
---

Run this recon BEFORE proposing solutions or writing code for any Ferm app. Local
folders (e.g. under `~/localprojects`) are often stale, and their names do not match
the repo names. GitHub (org `fermrad`) is the source of truth.

## 1. Refresh and read the Ferm Claude guide

```bash
git -C ~/repos/AI-tools checkout main && git -C ~/repos/AI-tools pull --ff-only
```

Then read (once per session):

- `~/repos/AI-tools/claude/rules/development-practices.md` — read library docs before use, code quality, security
- `~/repos/AI-tools/claude/CLAUDE.md.template` — PR rules that apply in all app repos (branch from `staging`; every PR = code + tests + docs)
- `~/repos/AI-tools/claude/rules/infrastructure.md` — only when the task touches servers, Docker, Caddy/Nginx, Terraform, or databases

## 2. Resolve the real repo

Never trust folder names — resolve via the remote:

```bash
git -C <folder> remote get-url origin
```

Known traps (verify, they can change): `ferm-tools` → `fermrad/project`,
`fermvault` → `fermrad/ferm-os`, `crm-fermrad` → `fermrad/crm`. Some org repos have
no local clone at all — never conclude something doesn't exist from the local disk.

## 3. Sync check on every relevant repo

```bash
git -C <folder> fetch origin
git -C <folder> status -sb
git -C <folder> log --oneline HEAD..origin/main      # commits you haven't seen
git -C <folder> log --oneline HEAD..origin/staging   # if the repo has staging
gh pr list -R fermrad/<repo> --state open
```

- Local behind origin → pull (or read the missing commits) before drawing any conclusion about the code.
- An open PR or branch may already implement what you are about to propose.

## 4. Scan across the org

```bash
gh repo list fermrad --limit 100 --json name,description --jq '.[] | "\(.name)\t\(.description // "")"'
gh search code --owner fermrad "<keyword>"
```

Before building anything new, check whether it already exists in:

- `boilerplate` — standard app skeleton (Next.js, Prisma, SSO, deploy-ready)
- `lib` — shared libraries vendored into apps via sync scripts
- `AI-tools` — Claude conventions, skills, reusable workflows
- `infrastructure` — IaC, Caddy routing, DNS, deploys on the Hetzner servers
- `devhub` — feedback, issues, deploys and roadmap for all apps (also reachable via the DevHub MCP connector)

## 5. Report before you build

Give a short recon summary before proposing anything: which repo(s) the task
concerns, local vs origin state, open PRs/issues/branches that overlap, and
anything existing (`lib`, `boilerplate`, another app) that already covers the
need. Only then propose or write code.
