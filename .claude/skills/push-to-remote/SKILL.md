---
name: push-to-remote
description: Push the current local Claude conversation to claude-dev.ferm.dk and resume it there
---

Push the current local Claude Code conversation to claude-dev.ferm.dk and resume it as a remote session.

Steps:
1. Get the GitHub username: run `gh api user --jq '.login'` and capture the result.

2. Find the active session file using lsof:
   ```
   lsof 2>/dev/null | grep -E '\.claude/projects/.+\.jsonl' | awk '{print $NF}' | sort -u
   ```
   - If **one file** is returned: use it automatically.
   - If **multiple files** are returned: for each file, extract the first 10 characters of the last human message:
     ```
     python3 -c "
     import json
     last = ''
     for line in open('FILEPATH'):
         try:
             o = json.loads(line)
             if o.get('type') == 'user':
                 c = (o.get('message') or o).get('content', '')
                 if isinstance(c, list):
                     c = next((x.get('text','') for x in c if isinstance(x,dict) and x.get('type')=='text'), '')
                 if c: last = str(c).strip()[:10]
         except: pass
     print(last)
     "
     ```
     Present the list as `<session-id>  "<last-prompt-preview>"` and ask which to push. Wait for the user's selection.
   - If **no files** are returned: tell the user no active session was found and stop.

3. SCP the selected session file to the server (using the username from step 1):
   ```
   ssh <username>@claude-dev.ferm.dk "mkdir -p ~/.claude/projects/-pushed"
   scp <full-path-to-jsonl> \
     <username>@claude-dev.ferm.dk:~/.claude/projects/-pushed/<session-id>.jsonl
   ```

4. Trigger the workflow with the session ID:
   ```
   gh workflow run start-claude-session.yml \
     --repo fermrad/infrastructure \
     --field github_username=<username> \
     --field session_id=<session-id>
   ```

5. Wait 3 seconds, then get the run ID:
   ```
   gh run list --repo fermrad/infrastructure --workflow=start-claude-session.yml --limit 1 --json databaseId --jq '.[0].databaseId'
   ```

6. Watch the run: `gh run watch <run-id> --repo fermrad/infrastructure --exit-status`

7. Report the job summary URL to the user: `https://github.com/fermrad/infrastructure/actions/runs/<run-id>`

The job summary contains a direct link to the resumed session on claude.ai/code.
