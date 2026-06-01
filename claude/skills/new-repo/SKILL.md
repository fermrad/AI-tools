---
description: Create a new GitHub repository with standard structure, branch protection, labels, and a CLAUDE.md
---

Create a new GitHub repository following the Ferm conventions. Steps:

1. **Ask** (if not already provided): repo name and short description. Always use the `fermrad` org and always create repos as **private** — never ask about either.

2. **Create the repo** via `gh repo create`:
   ```bash
   gh repo create fermrad/<name> --private --description "<desc>"
   ```

3. **Clone or init locally**, then create the initial structure:
   - `README.md` — structured as follows (required):
     1. **Project title + one-sentence tagline**
     2. **What this is** — a plain-language paragraph (2–4 sentences) that a non-technical person can understand. No jargon, no acronyms without explanation. Describe what the tool does and who uses it.
     3. **Purpose & responsibility** — who owns this repo, what decisions it is responsible for, and who to contact if something goes wrong. Example: "Owned by the Ferm tech team. This service handles [X]. Questions → [team/person]."
     4. **Getting started** — the commands a developer needs to run to get up and running
     5. **Architecture overview** — brief, with folder structure
   - `CLAUDE.md` — copy from `fermrad/AI-tools/claude/CLAUDE.md.template` and fill in all TODO sections based on what you know about the project
   - `.gitignore` — appropriate for the stack (Node, Python, etc.)
   - `.claude/settings.json` — minimal permissions block (allow test/lint/build commands, deny destructive ones)

4. **Commit and push** the initial files to `main`.

5. **Create standard labels** (idempotent with `--force`):
   ```bash
   gh label create "bug"         --color "D93F0B" --force
   gh label create "enhancement" --color "0075CA" --force
   gh label create "security"    --color "D93F0B" --force
   gh label create "compliance"  --color "E4E669" --force
   gh label create "repo"        --color "6E7781" --force
   ```
   If the project is a monorepo with named apps, also create an app label per app.

6. **Set branch protection on `main` and `staging`** (both branches, same settings):
   ```bash
   for branch in main staging; do
     gh api repos/fermrad/<name>/branches/$branch/protection \
       --method PUT \
       --input - <<'JSON'
   {
     "required_status_checks": {"strict": true, "contexts": []},
     "enforce_admins": false,
     "required_pull_request_reviews": {"required_approving_review_count": 1},
     "restrictions": null
   }
   JSON
     echo "✓ $branch protected" || true  # staging may not exist yet — non-fatal
   done
   ```
   Branch protection is non-negotiable — always apply it. Never skip this step.

7. **Wire up reusable AI workflows** — always add docs and error-reporting; ask about others:
   - **Documentation update** (always) → create `.github/workflows/update-docs.yml` calling `fermrad/AI-tools/.github/workflows/update-docs.yml@main`. This runs on every PR and keeps docs in sync.
   - **Runtime error reporting** (always) → copy `claude/widget/src/report-error-route.ts` into `src/app/api/report-error/route.ts` and `claude/widget/src/error-reporter.ts` into `src/lib/error-reporter.ts`. Add `GITHUB_ISSUES_TOKEN` and `GITHUB_REPO` to the app's env vars. The route auto-creates GitHub issues for unhandled runtime errors in production/staging.
   - **CI failure reporting** (always) → add an `on-failure` job to CI that calls `fermrad/AI-tools/.github/workflows/report-failure.yml@main` so any broken build creates a GitHub issue automatically.
   - Issue triage (ask) → `.github/workflows/ai-issue-triage.yml`
   - Compliance check (ask) → add compliance job to CI
   - Pentest (ask) → `.github/workflows/pentest.yml`
   - PR preview (ask, requires dev server) → `.github/workflows/pr-preview.yml`
   - Remind the user to add `ANTHROPIC_API_KEY` to the repo's Actions secrets (needed for docs workflow + triage).
   - Issue triage → create `.github/workflows/ai-issue-triage.yml` calling `fermrad/AI-tools/.github/workflows/ai-issue-triage.yml@main`
   - Compliance check → add compliance job to CI calling `fermrad/AI-tools/.github/workflows/compliance-check.yml@main`
   - Pentest → create `.github/workflows/pentest.yml` calling `fermrad/AI-tools/.github/workflows/pentest.yml@main`
   - Remind the user to add `ANTHROPIC_API_KEY` to the repo's Actions secrets.

8. **Confirm** by printing the repo URL and a summary of what was created.
