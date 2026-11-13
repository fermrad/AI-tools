---
name: new-remote-session
description: Start en ny interaktiv Claude-session i browseren via claude-dev.ferm.dk (GitHub Actions → claude.ai/code-link). Til HEADLESS agentarbejde uden laptoppen er `hest-agent` husets primære remote fra 03-09-2026.
---

> **Hesten er husets primære remote (Jakob, 03-09-2026).** Denne skill giver en *interaktiv* session i browseren og går stadig via claude-dev.ferm.dk, fordi den kræver `start-claude-session.yml` i `fermrad/infrastructure` (root-SSH til 178.105.186.39). At pege den på `fermhest` er sin egen opgave med en credential-beslutning — se S-700. Skal arbejdet bare *køre*, uden dig ved tastaturet: brug **`hest-agent`**.

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
