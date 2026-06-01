---
name: Development Practice Rules
description: Rules for how Claude approaches code, libraries, and tools in Ferm projects — including reading docs before using unfamiliar APIs
---

# Development Practice Rules

---

## Always read the docs before using a tool or library

**Before writing code that uses any library, framework, or tool you haven't used in this session:**

1. Check the installed version: `cat package.json | grep <library>` or `pip show <library>`
2. Read the relevant section of the library's documentation or the installed `node_modules/<library>/README.md`
3. If the library version differs significantly from training data (e.g. Next.js 16 vs 14, Drizzle vs Prisma), treat all prior knowledge as unverified until confirmed by reading the actual source

**Why:** APIs change between versions. In this repo, `apps/risk` runs Next.js 16 — APIs that worked in Next.js 14 may be deprecated or removed. Drizzle and Prisma have different query APIs. Using assumptions from training data without verification causes type errors and runtime failures.

**How to apply:**
- Before using a Next.js API (route handlers, middleware, cookies, headers): check `node_modules/next/dist/` or the Next.js docs
- Before using Drizzle: re-read `apps/risk/src/lib/db/schema.ts` and confirm the query pattern against the Drizzle docs
- Before using any new npm package: read its README and check for breaking changes in the installed version

---

## Prefer explicit, verifiable patterns over assumptions

- Never guess at an API signature — look it up
- If unsure whether a function exists, grep for it: `grep -r "functionName" node_modules/library/dist/`
- If a pattern was used elsewhere in the codebase, prefer following that pattern unless there's a documented reason not to

---

## Code quality

- No comments that describe what the code does — only why (hidden constraints, workarounds, subtle invariants)
- No error handling for impossible cases — trust internal code and framework guarantees
- No backwards-compatibility shims — if something is unused, delete it
- Three similar lines is better than a premature abstraction

---

## Security (see also: infrastructure rules)

- Never introduce SQL injection, XSS, command injection, or path traversal vulnerabilities
- Validate at system boundaries (user input, external APIs) — not internally
- Never store secrets in code, env files committed to git, or application logs
- Use parameterized queries — never string-concatenate user input into SQL
