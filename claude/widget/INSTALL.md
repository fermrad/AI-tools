# AI Widget — Installation Guide

A floating Claude chat panel for Next.js apps. Developers can ask questions about the codebase, request feature implementations, or debug issues — without leaving the browser.

## Prerequisites

- Next.js 14+ with App Router
- Tailwind CSS
- `ANTHROPIC_API_KEY` environment variable

---

## 1. Sync the widget into your app

From the **ferm-tools** root (one level above AI-tools — the script resolves `apps/<name>` two levels up from itself, so it must be invoked from there):

```bash
bash AI-tools/scripts/sync-ai-widget.sh apps/komm   # or apps/risk / apps/crm/app
```

This copies `src/AIWidget.tsx` and `src/chat-route.ts` into:
```
apps/<app>/
  src/
    components/ai/
      AIWidget.tsx
    app/api/ai/chat/
      route.ts
```

---

## 2. Install dependencies

```bash
cd apps/<app>
npm install ai @ai-sdk/anthropic
```

---

## 3. Add to your root layout

```tsx
// src/app/layout.tsx
import { AIWidget } from '@/components/ai/AIWidget'

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html>
      <body>
        {children}
        <AIWidget appName="komm" />   {/* change appName per app */}
      </body>
    </html>
  )
}
```

---

## 4. Add environment variables

```bash
# .env.local
ANTHROPIC_API_KEY=sk-ant-...
AI_WIDGET_ENABLED=true
```

In `docker-compose.yml`, add:
```yaml
environment:
  ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
  AI_WIDGET_ENABLED: ${AI_WIDGET_ENABLED:-false}
```

> Keep `AI_WIDGET_ENABLED=false` in production until the team is ready to roll it out. The API route returns 503 when disabled.

---

## 5. Wire up auth (important)

The API route template (`src/app/api/ai/chat/route.ts`) has an auth check commented out. Uncomment and adapt it before deploying:

```ts
// Uncomment in chat-route.ts:
const session = await getSession()
if (!session) return new Response('Unauthorized', { status: 401 })
```

Use the same `getSession()` pattern the rest of the app uses.

---

## Usage

- Click the **✦ button** in the bottom-right corner to open/close the panel.
- Press **⌘⇧K** (Mac) or **Ctrl+Shift+K** (Windows/Linux) to toggle.
- Type a question and press Enter or click Send.
- Claude automatically knows which app and page you're on.

---

## Keeping it updated

When the widget is updated in AI-tools, re-run the sync script from the **ferm-tools** root:

```bash
bash AI-tools/scripts/sync-ai-widget.sh apps/komm
```

The sync script overwrites `AIWidget.tsx` and `chat-route.ts` — do not edit those files in the app directly. Customise the system prompt in `chat-route.ts` after syncing if needed.
