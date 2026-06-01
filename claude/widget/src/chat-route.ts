/**
 * Drop this file into your Next.js app at:
 *   src/app/api/ai/chat/route.ts
 *
 * Install dependencies first:
 *   npm install ai @ai-sdk/anthropic
 *
 * Add to your environment:
 *   ANTHROPIC_API_KEY=sk-ant-...
 *   AI_WIDGET_ENABLED=true   (set false to disable in prod until ready)
 */

import { anthropic } from '@ai-sdk/anthropic'
import { convertToCoreMessages, streamText } from 'ai'
import { NextRequest } from 'next/server'

// ── Replace this import with your app's actual session helper ─────────────────
// import { getSession } from '@/lib/auth'

export const runtime = 'nodejs'
// Allow streaming responses up to 60 seconds
export const maxDuration = 60

export async function POST(req: NextRequest) {
  // ── Auth check — uncomment and adapt for your app ─────────────────────────
  // const session = await getSession()
  // if (!session) return new Response('Unauthorized', { status: 401 })

  if (process.env.AI_WIDGET_ENABLED !== 'true') {
    return new Response('AI widget not enabled', { status: 503 })
  }

  const { messages, appName, currentPath } = await req.json()

  const systemPrompt = buildSystemPrompt(appName, currentPath)

  const result = streamText({
    model: anthropic('claude-sonnet-4-6'),
    system: systemPrompt,
    messages: convertToCoreMessages(messages),
    maxTokens: 4096,
  })

  return result.toDataStreamResponse()
}

// ── System prompt ─────────────────────────────────────────────────────────────

function buildSystemPrompt(appName: string, currentPath: string): string {
  const appDescriptions: Record<string, string> = {
    komm: 'Komm — an internal Ferm dashboard (Next.js 14, Prisma, PostgreSQL). Handles komm-related data and views.',
    risk: 'Risk Tool — an internal Ferm risk management app (Next.js 16, Drizzle ORM, PostgreSQL). Tracks risk assessments and budgets.',
    crm: 'CRM — an internal Ferm customer relationship manager (Next.js, Prisma, PostgreSQL). Manages leads, contacts, and pipeline.',
  }

  const description = appDescriptions[appName] ?? `${appName} — a Ferm internal application`

  return `You are Claude, an AI development assistant embedded in the Ferm platform.

## Current context
- App: ${description}
- Current page: ${currentPath}

## Your role
You help the Ferm development team build, debug, and improve this application. You:
- Answer questions about the codebase, architecture, and technology stack
- Suggest implementations for new features
- Help debug issues — ask for error messages, stack traces, or code snippets when needed
- Review code for bugs, security issues, or improvements
- Explain how parts of the system work

## Ground rules
- Be concise. Developers read fast.
- When showing code, use the app's actual stack and conventions (TypeScript, Next.js App Router, Tailwind CSS, ${appName === 'risk' ? 'Drizzle ORM' : 'Prisma ORM'}).
- If you need to see a file to give a good answer, ask the developer to paste it.
- Do not invent file paths or APIs you haven't been shown — say "I'm not sure without seeing the file" instead.
- Flag security concerns immediately if you spot them.`
}
