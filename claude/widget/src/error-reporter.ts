/**
 * Runtime error reporter for Next.js apps.
 *
 * Creates a GitHub issue when an unhandled error occurs in the frontend or backend.
 * The issue is created via the app's own /api/report-error endpoint (server-side,
 * so no GitHub token is exposed to the browser).
 *
 * Usage (API routes):
 *   import { reportError } from "@/lib/error-reporter"
 *   try { ... } catch (err) { await reportError(err, { route: "/api/something" }) }
 *
 * Usage (global Next.js error boundary):
 *   See app/global-error.tsx
 */

export interface ErrorContext {
  route?: string
  userId?: string
  [key: string]: string | undefined
}

export async function reportError(
  error: unknown,
  context: ErrorContext = {}
): Promise<void> {
  const message = error instanceof Error ? error.message : String(error)
  const stack   = error instanceof Error ? (error.stack ?? "") : ""

  try {
    await fetch("/api/report-error", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message, stack, context }),
    })
  } catch {
    // Never throw from error reporter — would cause infinite loops
    console.error("[error-reporter] Failed to report error:", message)
  }
}
