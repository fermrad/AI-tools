/**
 * Next.js API route: POST /api/report-error
 *
 * Receives error reports from the frontend/backend and creates a GitHub issue
 * in the app's repository. Uses GITHUB_TOKEN (a fine-grained PAT with issues:write)
 * stored as a server-side environment variable.
 *
 * Copy this file to src/app/api/report-error/route.ts in your app.
 * Required env vars:
 *   GITHUB_ISSUES_TOKEN  — fine-grained PAT with issues:write on this repo
 *   GITHUB_REPO          — "owner/repo" (e.g. "fermrad/crm")
 *   APP_ENV              — "production" | "staging" | "development"
 */

import { NextRequest, NextResponse } from "next/server"
import { getSession } from "@/lib/auth"

export async function POST(req: NextRequest) {
  // Only enabled in production/staging to avoid noise from local dev
  const env = process.env.APP_ENV ?? "development"
  if (env === "development") {
    return NextResponse.json({ ok: true, skipped: true })
  }

  const token = process.env.GITHUB_ISSUES_TOKEN
  const repo  = process.env.GITHUB_REPO
  if (!token || !repo) {
    console.error("[report-error] GITHUB_ISSUES_TOKEN or GITHUB_REPO not set")
    return NextResponse.json({ ok: false }, { status: 500 })
  }

  let body: { message?: string; stack?: string; context?: Record<string, string> }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ ok: false }, { status: 400 })
  }

  const { message = "Unknown error", stack = "", context = {} } = body

  // Optionally attach userId from session
  let userId: string | undefined
  try {
    const session = await getSession()
    userId = session?.userId ?? session?.email ?? undefined
  } catch { /* ignore */ }

  const title = `[${env}] Runtime error: ${message.slice(0, 80)}`
  const issueBody = [
    `## Runtime error report`,
    ``,
    `| Field | Value |`,
    `|---|---|`,
    `| Environment | \`${env}\` |`,
    userId ? `| User | \`${userId}\` |` : "",
    ...Object.entries(context).map(([k, v]) => `| ${k} | \`${v}\` |`),
    ``,
    `### Error`,
    `\`\`\``,
    message,
    `\`\`\``,
    stack
      ? `### Stack trace\n\`\`\`\n${stack.slice(0, 2000)}\n\`\`\``
      : "",
  ]
    .filter(Boolean)
    .join("\n")

  // Deduplicate: search for an existing open issue with the same message
  const searchRes = await fetch(
    `https://api.github.com/search/issues?q=${encodeURIComponent(`repo:${repo} is:issue is:open label:runtime-error "${message.slice(0, 40)}"`)}&per_page=1`,
    { headers: { Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28" } }
  )
  const searchData = await searchRes.json()
  if (searchData.total_count > 0) {
    return NextResponse.json({ ok: true, duplicate: true })
  }

  const res = await fetch(`https://api.github.com/repos/${repo}/issues`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
    body: JSON.stringify({ title, body: issueBody, labels: ["bug", "runtime-error"] }),
  })

  if (!res.ok) {
    console.error("[report-error] GitHub API error:", await res.text())
    return NextResponse.json({ ok: false }, { status: 502 })
  }

  return NextResponse.json({ ok: true })
}
