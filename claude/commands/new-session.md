---
description: Start a new Claude remote session on the claude-dev server
---

Start a new Claude Code remote session on claude-dev.ferm.dk. Runs entirely via GitHub Actions — no terminal access needed.

Steps:
1. Get the GitHub username: run `gh api user --jq '.login'` and capture the result
2. Trigger the session workflow: `gh workflow run start-claude-session.yml --repo fermrad/infrastructure --field github_username=<username from step 1>`
3. Wait 3 seconds, then get the run ID: `gh run list --repo fermrad/infrastructure --workflow=start-claude-session.yml --limit 1 --json databaseId --jq '.[0].databaseId'`
4. Watch the run until it completes: `gh run watch <run-id> --repo fermrad/infrastructure --exit-status`
5. Report the job summary URL to the user: `https://github.com/fermrad/infrastructure/actions/runs/<run-id>`

The job summary contains a direct link to the claude.ai/code session. Tell the user to open it.
