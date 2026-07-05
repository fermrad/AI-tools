---
description: Start a new Claude remote session on claude-dev.ferm.dk, or resume an existing one
---

Start or resume a Claude Code remote session on claude-dev.ferm.dk. Runs via GitHub Actions — no terminal needed.

$ARGUMENTS optionally contains a session ID to resume. If not provided, a new conversation is started.

Steps:
1. Get the GitHub username: run `gh api user --jq '.login'` and capture the result.

2. Determine the session ID:
   - If $ARGUMENTS contains a session ID, use it directly.
   - Otherwise, find open Claude session files using lsof:
     ```
     lsof 2>/dev/null | grep -E '\.claude/projects/.+\.jsonl' | awk '{print $NF}' | sort -u
     ```
   - If that returns **one file**: use it automatically.
   - If it returns **multiple files**: for each file, extract the first 10 characters of the last human message with:
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
     Present the list to the user in the format `<session-id>  "<last-prompt-preview>"` and ask which to push. Wait for their selection before continuing.
   - If lsof returns **no files**: tell the user no active session was found and stop.

3. SCP the selected session file to the server:
   ```
   scp ~/.claude/projects/<encoded-path>/<session-id>.jsonl \
     MadsSFox@claude-dev.ferm.dk:~/.claude/projects/-pushed/<session-id>.jsonl
   ```

4. Trigger the workflow:
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

7. Report the job summary URL: `https://github.com/fermrad/infrastructure/actions/runs/<run-id>`

The job summary contains a direct link to the claude.ai/code session.
