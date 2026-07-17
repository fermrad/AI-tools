---
name: new-pr
description: Create a well-formed pull request following the project's PR conventions
---

Open a pull request for the current branch. Steps:

1. **Verify the branch** is not `main`. If it is, stop and tell the user to create a feature branch based on `main` first:
   ```bash
   git checkout main && git pull origin main
   git checkout -b feat/my-feature
   ```
   All new branches must start from `main`, not from another feature branch.

   Also verify that branch protection is enabled on `main`. If it isn't, apply it now before creating the PR:
   ```bash
   REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   gh api repos/$REPO/branches/main/protection \
     --method PUT \
     --input - <<'JSON'
   {
     "required_status_checks": {"strict": true, "contexts": []},
     "enforce_admins": false,
     "required_pull_request_reviews": {"required_approving_review_count": 1},
     "restrictions": null
   }
   JSON
   ```

2. **Pull latest** from the base branch to check for conflicts:
   ```bash
   git fetch origin
   git log HEAD..origin/<base> --oneline
   ```

3. **Check if a PR already exists** for this branch:
   ```bash
   gh pr view --json number,url 2>/dev/null
   ```
   If one exists, offer to update it instead.

4. **Gather the diff** to write the PR description:
   ```bash
   git diff origin/<base>...HEAD --stat
   git log origin/<base>...HEAD --oneline
   ```

5. **Choose a title** in conventional commit format: `type(scope): description`
   - type: `feat`, `fix`, `refactor`, `ci`, `docs`
   - scope: the app or area affected (e.g. `komm`, `risk`, `repo`)

6. **Verify the PR contains all three required elements** — do not open the PR until all three are present:

   **The change:**
   - All code changes must be committed and pushed to the feature branch.
   - Do not open a PR with partial or placeholder work.

   **Tests:**
   - Every new feature must have tests covering the happy path and key edge cases.
   - Every bug fix must have a regression test that would have caught the bug.
   - Run the test suite and confirm it passes: `npm test` (or the project's equivalent).
   - For UI-only changes with no logic, document in the PR body why tests aren't applicable.

   **Updated documentation — audit the whole org, not just this repo:**
   A change in one repo routinely makes docs stale in *other* repos. Before opening
   the PR, run this cross-repo docs audit and fix (or open follow-up PRs for) whatever it surfaces:

   - **This repo:** README, CLAUDE.md, architecture/deploy docs, and inline docs made stale by the change.
   - **The ferm-os vault (`fermrad/ferm-os`) — the single source of truth.** If the change touches any of the following, the vault's `41.10 App-arkitektur`, `41.12 Miljøer og deploy`, and the relevant `13.x Drift`-notes almost certainly need updating:
     - **Topology / hosting:** which box an app runs on, DNS records, public vs. Tailscale-only, Caddy/nginx.
     - **Deploy model:** how an app deploys (Model A vs. B), triggers, branch/dispatch semantics.
     - **App surface:** new/removed endpoints, MCP tools, service APIs, env vars.
     - **New environment going live** (a prod that didn't exist before), or an app moving between boxes.
   - **Sibling apps:** if the change alters a shared contract (an endpoint area51 calls, a cross-app SSO cookie, a shared library), update the consuming app's docs too.
   - **How to audit fast:** `git grep -n` the old fact (old IP, old box name, "not set up yet", old tool count) across each repo on `origin/main` — stale docs repeat the superseded claim verbatim. Verify topology claims against reality (`dig`, `docker ps`) rather than trusting the doc.

   Do not leave documentation out of sync — docs updates belong in the same PR as the change that made them stale (or a linked follow-up PR when they live in another repo).

7. **Write the PR body** — include:
   - Short bullet summary of what changed and why (not just what — the diff shows that)
   - Test coverage: list the test files added/changed and what they cover
   - Test plan: what a reviewer should check manually (especially for UI)
   - Any migration steps, env var changes, or breaking changes

8. **Create the PR** targeting `main` (there is no `staging` branch — miljøer er servere, ikke brancher):
   ```bash
   gh pr create --base main --title "<title>" --body-file /tmp/pr-body.txt
   ```

9. **Apply labels** matching the scope and target branch:
   ```bash
   gh pr edit <number> --add-label "<scope>" --add-label "main"
   ```

10. **Confirm** by printing the PR URL.
