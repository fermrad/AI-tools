---
name: repo-recon-remote
description: Read-only survey of the fermrad org from a Claude Code remote session (claude.ai/code, GitHub Action, mobile) — where there is no `gh` CLI, no developer laptop and only the repos in session scope. Use instead of /repo-recon whenever the session runs in a cloud container. Loads context and stops; ends by prescribing the fixed skill flow for the work that follows
argument-hint: [app/repo name or topic]
allowed-tools: Read, Grep, Glob, Bash, ToolSearch, mcp__github__*, mcp__devhub__*, mcp__Claude_Code_Remote__list_repos, mcp__Claude_Code_Remote__add_repo, mcp__Claude_Code_Remote__register_repo_root
---

Run this recon BEFORE proposing solutions or writing code for any Ferm app when the
session runs in a remote container. GitHub (org `fermrad`) is the source of truth.

**Use this instead of `/repo-recon` in remote sessions.** `/repo-recon` assumes a
developer laptop: a `gh` CLI, clones in the user's home directory, and a working
tree that may hold days of uncommitted work. A remote session has none of those. Running it
unmodified fails at the first `gh` call and — worse — its step 3b returns a clean
`git status` that means nothing, which reads as "no work in flight" when in fact
you simply cannot see any.

**Read-only by design.** Recon loads the guide, the real repo state and any
overlapping work — then reports and stops (step 6). It does not begin the work
it surveys.

## 0. Establish what this session can actually see

Remote sessions are scoped. Do this first — every later step depends on it.

1. **Load the deferred tools.** GitHub and DevHub MCP tools are not in the prompt
   by default; calling one before loading its schema fails. Fetch what you need:
   `ToolSearch("select:mcp__github__list_pull_requests,mcp__github__search_code,mcp__devhub__get_overview")`
2. **Confirm identity and scope:** `mcp__github__get_me`, then
   `mcp__Claude_Code_Remote__list_repos` for every repo the account can reach.
3. **Compare** that list against the session's Repository Scope. Repos outside it
   are unreadable until added — a 404 on an in-org repo means *out of scope*, not
   *does not exist*. Never conclude something is missing from a denied call.
4. **Add what the task needs:** `add_repo`, then clone **once, inline, serially**
   to the path it reports (`/workspace/<repo>`). The git proxy caps concurrent
   operations — parallel clones return 429 and break each other. Give the clone a
   generous timeout (~10 min); a large shallow pack is slow through the proxy and
   `index-pack` looks stalled while it is working. After a verified clone, call
   `register_repo_root` so the repo's CLAUDE.md and skills load.

State in the report which repos were in scope, which you added, and which you
never looked at.

## 1. Refresh and read the Ferm Claude guide

The AI-tools clone is the session's primary working directory and was cloned
fresh at container start — but the container may have been running for hours:

```bash
git checkout main && git pull origin main
```

Then read (once per session):

- `claude/rules/development-practices.md` — read library docs before use, code quality, security
- `claude/CLAUDE.md.template` — PR rules for all app repos (branch from `main`, target `main` — there is no `staging` branch; every PR = code + tests + docs)
- `claude/rules/infrastructure.md` — only when the task touches servers, Docker, Caddy/Nginx, Terraform, or databases

## 2. Resolve the real repo

Folder names still lie, and in a remote session a folder may simply not exist.
Resolve through the remote, never the directory name:

```bash
git -C <folder> remote get-url origin
```

Known traps (verify, they can change): `ferm-tools` → `fermrad/project`,
`fermvault` → `fermrad/ferm-os`, `crm-fermrad` → `fermrad/crm`.

If the repo is not cloned, resolve it entirely over MCP — `get_file_contents`
reads any file at any ref without a clone. Clone only when you need history,
`grep` across the tree, or to run the code.

## 3. Sync check — the `gh` → MCP mapping

Every `gh` command in `/repo-recon` has an MCP equivalent. There is no `gh`,
`hub`, or GitHub API access via `curl` in a remote session.

| `/repo-recon` (laptop) | Remote session |
|---|---|
| `gh pr list -R fermrad/<repo>` | `mcp__github__list_pull_requests` (`state: "open"`) |
| `gh pr view <n> --json files` | `mcp__github__pull_request_read` |
| `gh api repos/.../commits/main` | `mcp__github__get_commit` (`ref: "main"`) |
| `gh repo list fermrad` | `mcp__Claude_Code_Remote__list_repos` |
| `gh search code --owner fermrad` | `mcp__github__search_code` |
| `gh issue list` | `mcp__github__list_issues` / `search_issues` |
| `gh run list` / `gh run view --log` | `mcp__github__actions_list` / `get_job_logs` |
| `git branch -a --no-merged` | `mcp__github__list_branches` (no clone needed) |

For a cloned repo, ordinary git still works and is cheaper than MCP for history:

```bash
git -C <folder> fetch origin
git -C <folder> log --oneline HEAD..origin/main    # main is the only long-lived branch
```

An open PR or branch may already implement what you are about to propose.

## 3b. Work in flight — and the blind spot that replaces it

This is where remote recon differs most, and getting it wrong is the failure
mode this skill exists to prevent.

**On a laptop**, the risk is destroying local work: uncommitted changes,
unpushed commits. **In a remote session that risk is invisible, not absent.**
The container cloned from origin minutes ago, so:

- `git status --porcelain` is clean **by construction**. It is not evidence.
- `git log @{upstream}..HEAD` is empty for the same reason.
- The user's laptop may hold days of uncommitted work on this exact file. You
  cannot see it, and nothing in the container will ever hint at it.

So do not report "no uncommitted work". Report **"cannot observe local work —
verify with the user before editing shared files"**, and establish what *is*
observable, all of which lives on origin:

- `mcp__github__list_pull_requests` — open and draft PRs, including `headRefName`
- `mcp__github__list_branches` — branches carrying unmerged work
- `mcp__github__list_commits` on `main` — what landed recently
- Other remote sessions push to `claude/*` branches; a branch matching the task
  may be another agent working right now.

Then: **is `main` actually deployed?** Merged ≠ running.

```
mcp__github__get_commit  (ref "main")     # what main is
mcp__devhub__get_overview                 # what each environment reports running
```

Prefer DevHub over probing health endpoints yourself. Remote egress goes through
the agent proxy, and dev/staging live behind Tailscale (see sprint S-5) — a
failed `curl` from this container proves nothing about whether the app is up.
DevHub holds both what CI *says* it deployed and what each app *reports*
running, so drift shows up directly.

Flag: a merged PR that never reached prod, a feature living only on a branch, an
open PR overlapping the task — and the local blind spot above.

## 4. Scan across the org

```
mcp__github__search_code   query: "<keyword> org:fermrad"
mcp__Claude_Code_Remote__list_repos
```

`search_code` reaches every repo the token can see, **including repos not in
session scope** — use it to discover prior art, then `add_repo` before reading
in depth. Before building anything new, check whether it already exists in:

- `boilerplate` — standard app skeleton (Next.js, Prisma, SSO, deploy-ready)
- `lib` — shared libraries vendored into apps via sync scripts
- `AI-tools` — Claude conventions, skills, reusable workflows
- `infrastructure` — IaC, Caddy routing, DNS, deploys on the Hetzner servers
- `devhub` — feedback, issues, deploys and roadmap (also `mcp__devhub__list_sprint`)

## 5. Note what the container costs you

Record these in the report; they change what the follow-up work can promise:

- **The container is ephemeral.** Uncommitted work dies with it. Anything worth
  keeping must be committed and pushed — there is no "leave it for tomorrow".
- **Disk is a fixed allowance.** "No space left on device" with low `df` usage
  means the allowance is spent; delete build artifacts and stale clones rather
  than declaring the session broken.
- **`/run` is limited.** Ports are not reachable from the user's browser. Verify
  via tests, headless Chromium (pre-installed; never `playwright install`), or
  `/pr-preview` on a real box — and say which you used.
- **`/new-remote-session` and `/push-to-remote` are no-ops here** — you are
  already the remote session.

## 6. Report — and then STOP

**This skill is read-only. It never starts work.** Its job is to load context so
the next decision is well-informed — the decision belongs to the user.

End with a short recon summary:

- **Which environment the work concerns — prod, staging or dev.** Never assume
  it. If the user hasn't said, **ask before anything is started**; the answer
  changes the blast radius, whether real data and users are involved, and which
  box you are touching. State it explicitly so it is on the record.
- **Session scope:** repos in scope, repos added, repos not examined.
- **Work in flight (step 3b):** open/draft PRs, unmerged branches, merged work
  not yet deployed — plus the explicit note that **local uncommitted work is
  unobservable from here.**
- which repo(s) the task concerns, and clone vs. origin state
- anything existing (`lib`, `boilerplate`, another app, an existing playbook)
  that already covers the need
- what you'd suggest doing next — as a **proposal**, not a plan you begin
  executing. Map it onto the fixed skill flow (step 7).

Then **hand back to the user and wait.** Do not create branches, edit files,
open PRs, or run migrations/deploys as part of recon — not even the "obvious
first step". Recon that slides into implementation defeats its purpose: the user
loses the review point the recon exists to create.

## 7. The fixed skill flow — recon hands off to it, never around it

Once the user gives the go-ahead, the work that follows uses these skills at
these points — invoke them, don't reimplement what they do:

1. **Build** — branch from `main`, develop, verify with **`/run`** (tests
   passing is not the same as the app working; see the step 5 limits).
2. **`/simplify`** — after any substantial change: reuse/simplification pass.
   Quality only; it does not hunt bugs.
3. **`/code-review`** — before every PR, on the staged diff. Add
   **`/security-review`** whenever the change touches auth, sessions, file
   handling/uploads, or API boundaries.
4. **`/new-pr`** — creates the PR to Ferm conventions. If the fix lives in code
   copied from `boilerplate`/`lib` or duplicated across apps: patch upstream
   first and sweep the other apps (`search_code` with `org:fermrad`) in the same
   flow — a bug fixed in one app still exists in the others.
5. **`/pr-preview`** — see the branch live before merging. Never debug deploy or
   CI behaviour with guess-commits on `main`; move to a branch with
   `workflow_dispatch` after two failed attempts and squash the result.

Skipping a stage is the user's call, not a default.
