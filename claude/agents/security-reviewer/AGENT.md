# Security Reviewer Agent

**Type:** subagent  
**When to use:** Get an independent security review of auth code, middleware, API routes, or infrastructure config. Uses Opus for deeper analysis. Read-only — it cannot modify files.

## Tool restrictions
- ✅ Read, grep, find, git log, git diff
- ❌ Write, Edit, Bash (unrestricted), WebSearch

## Example delegation
```
Agent({
  subagent_type: "security-reviewer",
  prompt: "Review apps/risk/src/lib/auth.ts and apps/risk/src/middleware.ts for security issues. Focus on: session fixation, HMAC timing attacks, cookie flags, and missing auth checks on API routes. Report findings with file:line references."
})
```
