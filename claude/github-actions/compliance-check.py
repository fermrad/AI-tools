#!/usr/bin/env python3
"""
ISO 27001 / SOC 2 compliance analysis: reads security-relevant files, asks
Claude to identify gaps against specific controls, and files GitHub issues
for any new gaps. Always exits 0 — gaps are informational, not PR blockers.
"""
import json
import os
import subprocess
import sys

import anthropic

REPO = os.environ.get("GITHUB_REPOSITORY", "")
MODEL = "claude-sonnet-4-6"
COMPLIANCE_LABEL = "compliance"
COMPLIANCE_LABEL_COLOR = "E4E669"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, **kwargs)


def capture(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.stdout.strip()


def read_file(path, max_chars=6000):
    try:
        with open(path) as f:
            return f.read()[:max_chars]
    except Exception:
        return None


def ensure_label():
    subprocess.run(
        ["gh", "label", "create", COMPLIANCE_LABEL,
         "--repo", REPO, "--color", COMPLIANCE_LABEL_COLOR,
         "--description", "ISO 27001 / SOC 2 compliance gap", "--force"],
        capture_output=True,
    )


def existing_issues():
    out = capture([
        "gh", "issue", "list", "--repo", REPO,
        "--label", COMPLIANCE_LABEL, "--state", "open",
        "--json", "title", "--limit", "200",
    ])
    try:
        return {i["title"].lower() for i in json.loads(out)}
    except Exception:
        return set()


def create_issue(title, body):
    run(["gh", "issue", "create", "--repo", REPO,
         "--title", title, "--body", body, "--label", COMPLIANCE_LABEL])
    print(f"  + {title}")


def is_new(title, existing):
    t = title.lower()
    if t in existing:
        return False
    return not any(t[:50] in e for e in existing if t[:50])


def main():
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("ANTHROPIC_API_KEY not set — skipping compliance check")
        sys.exit(0)

    client = anthropic.Anthropic()
    ensure_label()
    existing = existing_issues()

    # Security-relevant files to include in the analysis
    files_to_read = [
        "CLAUDE.md",
        "docs/ferm-tech-stack.md",
        # komm auth
        "apps/komm/src/lib/auth.ts",
        "apps/komm/src/lib/auth-entra.ts",
        "apps/komm/middleware.ts",
        "apps/komm/src/app/api/auth/login/route.ts",
        # risk auth
        "apps/risk/src/lib/auth.ts",
        "apps/risk/src/middleware.ts",
        "apps/risk/src/app/api/auth/route.ts",
        # crm auth
        "apps/crm/app/src/lib/auth.ts",
        "apps/crm/app/src/middleware.ts",
        # infrastructure
        "apps/komm/docker-compose.yml",
        "apps/risk/docker-compose.yml",
        "apps/crm/app/docker-compose.yml",
        "apps/komm/Dockerfile",
        "apps/risk/Dockerfile",
        # CI / change management
        ".github/workflows/ci.yml",
        ".github/workflows/promote-staging-to-main.yml",
    ]

    sections = []
    for path in files_to_read:
        content = read_file(path)
        if content:
            sections.append(f"--- {path} ---\n{content}")

    # Add API route listing to show attack surface
    try:
        api_files = capture(["git", "ls-files", "--", "*/api/**/*.ts"]).splitlines()[:30]
        if api_files:
            sections.append("--- API route listing (attack surface) ---\n" + "\n".join(api_files))
    except Exception:
        pass

    files_block = "\n\n".join(sections)

    prompt = f"""You are a senior security and compliance auditor reviewing a codebase against ISO 27001 and SOC 2 Type II.

## Codebase context
- Three Next.js apps (komm, risk, crm) in a monorepo, deployed on Hetzner VPS behind Caddy (auto-TLS)
- Auth per app: HMAC-signed session cookies + bcrypt magic-link tokens; partial Entra OIDC (PKCE)
- Drizzle ORM (risk), Prisma (komm, crm); PostgreSQL databases per app
- Apps are fully independent Docker containers — no shared runtime

## Task
Review the files below. Identify **specific, evidence-backed** compliance gaps at the code or configuration level.

**ISO 27001 controls to check:**
- A.9 Access Control: session timeout enforcement, MFA, account lockout, least privilege
- A.10 Cryptography: algorithm choices (HMAC-SHA256, bcrypt cost), secret rotation, env handling
- A.12 Operations Security: audit logging, monitoring, patch management evidence
- A.14 System Acquisition: input validation, output encoding, parameterised queries
- A.16 Incident Management: error messages (stack traces exposed?), alerting, response process
- A.18 Compliance: GDPR relevance (PII in logs/responses?), data retention policy

**SOC 2 Trust Service Criteria to check:**
- CC6: Auth strength, session management, brute-force protection, privilege escalation risks
- CC7: Centralised logging, anomaly alerting, change detection
- CC8: Code review gates (branch protection, CI checks, deploy controls)
- Availability: health checks, graceful degradation, error boundaries
- Confidentiality: secrets in env vs code, PII handling, data classification

**Rules:**
- Only flag gaps clearly evidenced in the files — no speculation
- Skip controls handled entirely by infrastructure (e.g. TLS is Caddy's responsibility)
- Do NOT duplicate a gap across apps unless the evidence differs meaningfully
- Severity: critical = active breach risk; high = significant control failure; medium = partial control; low = best-practice gap

Return a **JSON array only** (no prose outside the JSON). Each item:
{{
  "title": "[ISO 27001 A.X] or [SOC 2 CC#] Gap title (≤80 chars)",
  "severity": "critical|high|medium|low",
  "body": "Markdown with sections: **Control**, **Gap**, **Evidence** (file:line if possible), **Remediation**"
}}

Files:
{files_block}
"""

    print("Running ISO 27001 / SOC 2 analysis with Claude...")
    response = client.messages.create(
        model=MODEL,
        max_tokens=8096,
        messages=[{"role": "user", "content": prompt}],
    )

    text = response.content[0].text.strip()
    if "```json" in text:
        text = text.split("```json", 1)[1].split("```", 1)[0]
    elif "```" in text:
        text = text.split("```", 1)[1].split("```", 1)[0]

    try:
        gaps = json.loads(text.strip())
    except Exception as exc:
        print(f"Failed to parse compliance response: {exc}", file=sys.stderr)
        print(text[:2000], file=sys.stderr)
        sys.exit(0)

    print(f"Identified {len(gaps)} gap(s)")

    created = 0
    for gap in gaps:
        title = gap.get("title", "").strip()
        body = gap.get("body", "").strip()
        severity = gap.get("severity", "medium")
        if not title or not body:
            continue
        if not is_new(title, existing):
            print(f"  ~ already tracked: {title}")
            continue
        full_body = (
            f"**Severity:** {severity}\n\n"
            f"{body}\n\n"
            f"---\n_Detected by compliance-check workflow (ISO 27001 / SOC 2 analysis)._"
        )
        create_issue(title, full_body)
        created += 1

    print(f"Created {created} new compliance issue(s)")
    # Always exit 0 — compliance gaps do not block PRs


if __name__ == "__main__":
    main()
