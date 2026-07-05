---
description: Start a new Claude remote session on claude-dev.ferm.dk, or resume an existing one
---

Start or resume a Claude Code remote session on claude-dev.ferm.dk. Runs via GitHub Actions — no terminal needed.

$ARGUMENTS optionally contains a session ID to resume. If not provided, a new conversation is started.

Steps:
1. Get the GitHub username: run `gh api user --jq '.login'` and capture the result
2. Build the workflow trigger command:
   - If $ARGUMENTS contains a session ID: `gh workflow run start-claude-session.yml --repo fermrad/infrastructure --field github_username=<username> --field session_id=<session-id>`
   - Otherwise: `gh workflow run start-claude-session.yml --repo fermrad/infrastructure --field github_username=<username>`
3. Wait 3 seconds, then get the run ID: `gh run list --repo fermrad/infrastructure --workflow=start-claude-session.yml --limit 1 --json databaseId --jq '.[0].databaseId'`
4. Watch the run until it completes: `gh run watch <run-id> --repo fermrad/infrastructure --exit-status`
5. Report the job summary URL to the user: `https://github.com/fermrad/infrastructure/actions/runs/<run-id>`

The job summary contains a direct link to the claude.ai/code session.
