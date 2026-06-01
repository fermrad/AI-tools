# Hooks

Hooks run shell commands in response to Claude Code events. They go in `.claude/settings.json` under the `hooks` key.

## Event types

| Event | Fires when |
|---|---|
| `PreToolUse` | Before Claude calls any tool — can block the call |
| `PostToolUse` | After a tool completes |
| `PostFileWrite` | After Claude writes or edits a file |
| `Notification` | When Claude sends a notification |
| `Stop` | When Claude finishes a turn |

## Template — `.claude/settings.json`

```json
{
  "hooks": {
    "PostFileWrite": [
      {
        "matcher": ".*\\.(ts|tsx)$",
        "hooks": [
          {
            "type": "command",
            "command": "npx tsc --noEmit 2>&1 | head -20"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/validate-bash.sh"
          }
        ]
      }
    ]
  }
}
```

## Example hook scripts

### `validate-bash.sh` — block dangerous commands
```bash
#!/bin/bash
# Read the command Claude wants to run from stdin (JSON)
INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('command',''))")

# Block rm -rf on anything outside /tmp
if echo "$CMD" | grep -qE 'rm\s+-rf\s+(?!/tmp)'; then
  echo "Blocked: rm -rf outside /tmp requires manual confirmation"
  exit 1
fi
exit 0
```

### `typecheck-on-save.sh` — run tsc after every TS file write
```bash
#!/bin/bash
FILE=$(echo "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path',''))")
DIR=$(dirname "$FILE")
# Walk up to find tsconfig.json
while [ "$DIR" != "/" ]; do
  [ -f "$DIR/tsconfig.json" ] && (cd "$DIR" && npx tsc --noEmit 2>&1 | head -10) && break
  DIR=$(dirname "$DIR")
done
exit 0
```
