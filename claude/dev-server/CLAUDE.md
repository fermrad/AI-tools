# CLAUDE.md — Ferm Dev Server

This file is placed in `~/CLAUDE.md` for every developer account on the shared Claude Code dev server. It describes what this environment is, how to work on existing Ferm apps, how to create new apps, and how the CI/CD pipeline works.

---

## What this environment is

You are running on a shared Hetzner server dedicated to AI-assisted development of Ferm apps. Every developer has their own Unix account; your files, sessions, and credentials are fully isolated from other users.

**Network access:**
- Internet — available (Anthropic API, GitHub, npm, etc.)
- Dev project servers — reachable via private network
- **Production servers — unreachable by design.** This server lives in the Hetzner dev project. Prod is in a separate project with no network bridge.

**Your workspace layout:**
```
~/repos/     ← one clone per repo, used as the base for worktrees
~/prs/       ← one worktree per active PR branch
```

---

## Access modes

There are two ways to work with Claude Code on this server. Both share the same persistent home directory, so repos, worktrees, and conversation history are identical regardless of which mode you use.

| Mode | How to access | Best for |
|---|---|---|
| **CLI + tmux** | SSH into your account, run `claude` inside a named tmux session | Heads-down coding, terminal comfort |
| **Remote Control** | Connect from `claude.ai/code`, the Claude desktop app, or the Claude mobile app | Reviews, quick follow-ups, switching between devices |

**Remote Control:** a `claude remote-control` process runs permanently in your account as a systemd user service. It phones home to Anthropic's API over outbound HTTPS — no ports need to be open. Connect from any client via `claude.ai/code`. When you disconnect, the session stays live on the server; reconnect from a different device and pick up exactly where you left off. To check it is running:

```bash
systemctl --user status claude-remote.service
```

**Resuming after API credit limits:** if Claude Code stops because credits ran out, top up the Anthropic account, then either reattach to your tmux session and run `claude --continue`, or reconnect via `claude.ai/code` — both resume the conversation from `~/.claude/conversations/` on the persistent volume.

---

## Session start

Before any work:

```bash
gh pr list                   # see what PRs you already have open
cd ~/repos/<appname>
git fetch --all
```

Never start from a stale branch. Always fetch first.

---

## Working on an existing app

### 1. Clone the repo (first time only)

```bash
cd ~/repos
git clone git@github.com:fermrad/<appname>.git
```

Repos: `risk`, `crm`, `komm`, `project`, `area51`, `infrastructure`, `AI-tools`, `lib`.

### 2. Create a worktree for your PR

Each PR gets its own directory so multiple PRs can be active simultaneously without switching branches.

```bash
cd ~/repos/<appname>
git fetch
git checkout staging && git pull origin staging
git checkout -b feat/my-feature
git push -u origin feat/my-feature

git worktree add ~/prs/<appname>-my-feature feat/my-feature
```

### 3. Open a tmux session for the PR

```bash
tmux new-session -s <appname>-my-feature
cd ~/prs/<appname>-my-feature
claude                       # start Claude Code in the worktree context
```

Detach with `Ctrl-b d`. Reattach later with `tmux attach -t <appname>-my-feature`.

### 4. Branch rules

- **Always branch from `staging`** — never from `main` or another feature branch
- Branch name format: `feat/`, `fix/`, `ci/`, `docs/`, `refactor/`
- PR title format: `type(scope): description` — e.g. `feat(auth): add token refresh`
- Target branch for the PR: `staging`

### 5. Open the PR

```bash
gh pr create --base staging --title "feat(scope): description" --body "..."
```

Check for open PRs first to avoid duplicates:

```bash
gh pr list --repo fermrad/<appname>
```

### 6. What happens after the PR is merged

Merging to `main` (via `staging → main`) triggers the **staging deploy** automatically — see CI/CD pipeline below.

### 7. Clean up the worktree after the PR is merged

```bash
git worktree remove ~/prs/<appname>-my-feature
tmux kill-session -t <appname>-my-feature
cd ~/repos/<appname> && git branch -d feat/my-feature
```

---

## Creating a new app

Ferm apps are based on the `fermrad/boilerplate` template: Next.js 15, Prisma, Postgres, SSO login, Docker, and GitHub Actions already wired up.

### 1. Clone and configure boilerplate

```bash
cd ~/repos
git clone git@github.com:fermrad/boilerplate.git <appname>
cd <appname>
```

Find and replace all `<appname>` placeholders in all files:

```bash
grep -rl '<appname>' . --include='*.yml' --include='*.yaml' \
  --include='*.json' --include='*.ts' --include='*.md' \
  | xargs sed -i 's/<appname>/<yourappname>/g'
```

Rename the remote and push to a new repo:

```bash
git remote set-url origin git@github.com:fermrad/<yourappname>.git
# Create the repo first: gh repo create fermrad/<yourappname> --private
git push -u origin main
```

### 2. Local development setup

```bash
cp .env.example .env          # fill in the values
npm install
npm run prisma:push            # create tables in the local/dev DB
npm run dev                    # starts on port 3000
```

### 3. Add GitHub Actions secrets

In the new repo, add these secrets via `gh secret set` or the GitHub UI:

| Secret | Value |
|---|---|
| `SSH_PRIVATE_KEY` | Ferm shared deploy key (from 1Password) |
| `STAGING_SSH_HOST` | `188.34.196.169` |
| `PRODUCTION_SSH_HOST` | `178.105.56.2` |
| `NPM_READ_TOKEN` | Org secret — add via GitHub org settings, not manually |

### 4. Register the app on the server

Follow `docs/add-new-app.md` in the `fermrad/infrastructure` repo. Summary:

1. Add a DNS A record: `<appname>.ferm.dk → <server-ip>`
2. Create `/opt/ferm-<appname>/` on the server, copy `.env`
3. Run `./scripts/add-subdomain.sh <appname>.ferm.dk ferm-<appname>-app` from the infrastructure repo
4. Commit the updated `nginx/nginx-active.conf` to the infrastructure repo

Container naming must match: `ferm-<appname>-app` (web) and `ferm-<appname>-db` (Postgres).

---

## CI/CD pipeline

### On every PR (targeting `staging` or `main`)

GitHub Actions runs `ci.yml`:

| Step | What it does |
|---|---|
| `npm ci` | Install dependencies |
| `prisma generate` | Generate Prisma client |
| `tsc --noEmit` | Type check |
| `npm run lint` | ESLint |
| `npm test` | Vitest unit tests |

All steps must pass before a PR can be merged. The `check` job acts as the merge gate.

### On push to `main` — staging deploy

`deploy-staging.yml` runs automatically:

1. `rsync` — syncs `src/`, `prisma/`, `Dockerfile`, `docker-compose.staging.yml`, and config files to `/opt/ferm-<appname>-staging/` on `188.34.196.169`
2. `docker compose -f docker-compose.staging.yml up -d --build` — rebuilds the image and restarts the container in place

The staging URL is `https://staging.<appname>.ferm.dk`. Verify it after every merge.

### Production deploy — manual

`deploy-prod.yml` is **never triggered automatically**. Run it via:

```bash
gh workflow run deploy-prod.yml --repo fermrad/<appname>
```

Or via GitHub UI: Actions → Deploy → Production → Run workflow.

Production is `178.105.56.2` at `https://<appname>.ferm.dk`. After a prod deploy, verify all affected subdomains respond.

### Shared library (`fermrad/lib`)

If a PR touches `fermrad/lib`, the consuming apps do not auto-update. After merging to `lib/main`, run the sync script in each consuming repo:

```bash
./scripts/sync-lib.sh   # copies updated lib files into src/lib/
```

Then open a follow-up PR in the consuming repo.

---

## Key rules

- **Never run commands against production IPs** (`178.105.56.2`) from this server — it is unreachable anyway, but do not attempt it
- **Always branch from `staging`** — branching from `main` will cause the PR to miss the staging gate
- **Always check `gh pr list` before opening a new PR** — another Claude session in this repo may already have one open
- **Never commit `.env` files or secrets** to any repo
- **Never use `set body text of doc`** in any Pages/AppleScript work — strips all formatting (see root `CLAUDE.md`)
- **Run `git pull` before reading files** — another session may have pushed since your last fetch
