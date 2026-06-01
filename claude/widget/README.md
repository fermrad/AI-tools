# AI Widget

A floating Claude chat panel that can be embedded in any Next.js app. Developers type questions; Claude responds with context-awareness about which app and page they're on.

## What it looks like

- **Floating button** (bottom-right, violet) — click or press ⌘⇧K to toggle
- **Chat panel** — streaming responses, code block rendering, typing indicator
- **Zero per-page setup** — the widget automatically sends the app name and current pathname with every message

## Files

| File | Purpose |
|---|---|
| `src/AIWidget.tsx` | React component — drop into `src/components/ai/` |
| `src/chat-route.ts` | Next.js API route — drop into `src/app/api/ai/chat/route.ts` |
| `INSTALL.md` | Step-by-step installation guide |
| `../../scripts/sync-ai-widget.sh` | Sync script — copies both files into an app |

## Quick install

```bash
# From the AI-tools root:
bash scripts/sync-ai-widget.sh apps/komm

# Then:
cd apps/komm && npm install ai @ai-sdk/anthropic
```

See [INSTALL.md](./INSTALL.md) for the full setup including auth wiring and env vars.

## Architecture decision: skill or agent?

Neither — this is a **vendored component**, not a Claude Code skill or agent.

- A **skill** is invoked by the developer inside the Claude Code CLI.
- An **agent** is a subagent that Claude Code delegates work to.
- This widget is a **runtime UI feature** embedded in the deployed web app itself, so end users (or developers using the app in the browser) can talk to Claude without leaving the page.

The component lives in `AI-tools` as the source of truth and is synced into each app the same way `ferm-shared-auth` is vendored — run the sync script to update.
