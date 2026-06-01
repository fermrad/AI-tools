---
description: Create a well-formed pull request following the project's PR conventions
---

Open a pull request for the current branch. Steps:

1. **Verify the branch** is not `main` or `staging`. If it is, stop and ask the user to create a feature branch first.

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

6. **Write the PR body** — include:
   - Short bullet summary of what changed and why (not just what — the diff shows that)
   - Test plan: what a reviewer should check manually
   - Any migration steps, env var changes, or breaking changes

7. **Create the PR** targeting the correct base branch (default: `staging`):
   ```bash
   gh pr create --base staging --title "<title>" --body-file /tmp/pr-body.txt
   ```

8. **Apply labels** matching the scope and target branch:
   ```bash
   gh pr edit <number> --add-label "<scope>" --add-label "staging"
   ```

9. **Confirm** by printing the PR URL.
