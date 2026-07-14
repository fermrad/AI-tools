---
name: new-remote-session
description: Start a new Claude remote session on claude-dev.ferm.dk
---

Start a fresh Claude Code remote session on claude-dev.ferm.dk. Runs via GitHub Actions — no terminal needed.

Steps:
1. Get the GitHub username: run `gh api user --jq '.login'` and capture the result.

2. Trigger the workflow:
   ```
   gh workflow run start-claude-session.yml \
     --repo fermrad/infrastructure \
     --field github_username=<username>
   ```

3. Wait 3 seconds, then get the run ID:
   ```
   gh run list --repo fermrad/infrastructure --workflow=start-claude-session.yml --limit 1 --json databaseId --jq '.[0].databaseId'
   ```

4. Watch the run: `gh run watch <run-id> --repo fermrad/infrastructure --exit-status`

5. Report the job summary URL to the user: `https://github.com/fermrad/infrastructure/actions/runs/<run-id>`

The job summary contains a direct link to the claude.ai/code session.
