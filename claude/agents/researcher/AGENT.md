# Researcher Agent

**Type:** subagent  
**When to use:** Delegate open-ended research — technology comparisons, CVE lookups, dependency health checks, API documentation reading — where you want a contained agent that cannot accidentally modify files or run arbitrary code.

## Tool restrictions
- ✅ WebSearch, WebFetch, Read, grep, find
- ❌ Write, Edit, Bash (except grep/find), Agent

## Example delegation
```
Agent({
  subagent_type: "researcher",
  prompt: "Research whether @hono/node-server v1.x is production-ready for a Next.js API layer. Check: maturity, known issues, community size. Report in under 200 words."
})
```
