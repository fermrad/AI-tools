---
name: repo-recon
description: Read-only survey of the fermrad GitHub org and Ferm's Claude guide before proposing or building anything — loads context and stops; the local clone is never the source of truth
argument-hint: [app/repo name or topic]
---

Run this recon BEFORE proposing solutions or writing code for any Ferm app. Local
folders (e.g. under `~/localprojects`) are often stale, and their names do not match
the repo names. GitHub (org `fermrad`) is the source of truth.

**Read-only by design.** Recon loads the guide, the real repo state and any
overlapping work — then reports and stops (see step 5). It does not begin the
work it surveys.

## 1. Refresh and read the Ferm Claude guide

```bash
git -C ~/repos/AI-tools checkout main && git -C ~/repos/AI-tools pull --ff-only
```

Then read (once per session):

- `~/repos/AI-tools/claude/rules/development-practices.md` — read library docs before use, code quality, security
- `~/repos/AI-tools/claude/CLAUDE.md.template` — PR rules that apply in all app repos (branch from `main` and target `main` — there is no `staging` branch; every PR = code + tests + docs)
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
git -C <folder> log --oneline HEAD..origin/main      # commits you haven't seen (main is the only long-lived branch)
gh pr list -R fermrad/<repo> --state open
```

- Local behind origin → pull (or read the missing commits) before drawing any conclusion about the code.
- An open PR or branch may already implement what you are about to propose.

## 3b. What is NOT committed, pushed or deployed

Work in flight is invisible in `origin/main` and is the easiest thing to destroy
or duplicate. Establish it explicitly — and report it (step 5) **before** anything
new is started:

```bash
git -C <folder> status --porcelain                       # uncommitted changes in the working tree
git -C <folder> log --oneline @{upstream}..HEAD          # committed locally, NOT pushed
git -C <folder> branch -a --no-merged origin/main        # branches carrying unmerged work
gh pr list -R fermrad/<repo> --state open --json number,title,headRefName,isDraft
```

Then: **is `main` actually deployed?** Merged ≠ running. Compare the commit each
environment reports against `origin/main`:

```bash
gh api repos/fermrad/<repo>/commits/main --jq '.sha[:7]'  # what main is
curl -s https://<app>.ferm.dk/api/health                  # what prod actually runs
```

Or ask DevHub for all apps and environments at once (`get_overview` via the DevHub
MCP connector) — it holds both what CI *says* it deployed and what each app
*reports* running, so a mismatch shows up as drift.

Flag anything you find: uncommitted work someone may lose, a local commit never
pushed, a merged PR that never reached prod, or a feature living only on a branch.

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

## 5. Report — and then STOP

**This skill is read-only. It never starts work.** Its whole job is to load
context and process so the next decision is well-informed — the decision itself
belongs to the user.

End with a short recon summary:

- **Which environment the work concerns — prod, staging or dev.** Never assume it.
  If the user hasn't said, **ask before anything is started**; the answer changes
  the blast radius, whether real data and users are involved, whether a deploy is
  a `push` or a manual `workflow_dispatch`, and which box you are touching. State
  the answer explicitly in the report so it is on the record.
- **Work in flight (from step 3b):** uncommitted changes, commits pushed but not
  merged, merged work not yet deployed, and features living only on a branch.
  Say plainly what is at risk of being lost, duplicated or overwritten.
- which repo(s) the task concerns, and local vs. origin state
- open PRs/issues/branches that overlap (someone may already be doing it)
- anything existing (`lib`, `boilerplate`, another app, an existing playbook or
  reference implementation) that already covers the need
- what you'd suggest doing next — as a **proposal**, not a plan you begin executing

Then **hand back to the user and wait.** Do not create branches, edit files, open
PRs, or run migrations/deploys as part of recon — not even the "obvious first
step". Recon that slides into implementation defeats its purpose: the user loses
the review point that the recon exists to create.
