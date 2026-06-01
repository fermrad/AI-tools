#!/usr/bin/env python3
"""
AI issue triage: reads a GitHub issue, gives Claude context from the repo,
and either opens a fix PR (if confident) or posts an analysis comment.
"""
import json
import os
import subprocess
import sys

import anthropic

REPO = os.environ["GITHUB_REPOSITORY"]
ISSUE_NUMBER = int(os.environ["ISSUE_NUMBER"])
ISSUE_TITLE = os.environ["ISSUE_TITLE"]
ISSUE_BODY = os.environ.get("ISSUE_BODY", "").strip()
MODEL = "claude-sonnet-4-6"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, **kwargs)


def capture(cmd):
    return subprocess.check_output(cmd).decode().strip()


def read_file(path, max_chars=6000):
    try:
        with open(path) as f:
            return f.read()[:max_chars]
    except Exception:
        return None


def post_comment(body):
    run(["gh", "issue", "comment", str(ISSUE_NUMBER), "--repo", REPO, "--body", body])


def extract_json(text):
    """Pull JSON out of a response that may be wrapped in a markdown code fence."""
    if "```json" in text:
        text = text.split("```json", 1)[1].split("```", 1)[0]
    elif "```" in text:
        text = text.split("```", 1)[1].split("```", 1)[0]
    return json.loads(text.strip())


def main():
    client = anthropic.Anthropic()

    claude_md = read_file("CLAUDE.md") or ""

    # Shallow file tree — keep it short so it fits in context
    try:
        tree_raw = capture(["git", "ls-files", "--", "*.ts", "*.tsx", "*.yml", "*.py", "*.json", "*.md"])
        # Drop lock files and generated files to save tokens
        tree = "\n".join(
            l for l in tree_raw.splitlines()
            if not any(x in l for x in ["package-lock.json", "node_modules", ".next", "prisma/migrations"])
        )[:4000]
    except Exception:
        tree = ""

    # ── Step 1: identify which files to read ────────────────────────────────
    step1 = client.messages.create(
        model=MODEL,
        max_tokens=512,
        messages=[{
            "role": "user",
            "content": (
                f"Issue #{ISSUE_NUMBER}: {ISSUE_TITLE}\n\n"
                f"{ISSUE_BODY}\n\n"
                f"Repo overview (CLAUDE.md):\n{claude_md}\n\n"
                f"File tree:\n{tree}\n\n"
                "List up to 6 file paths you need to read to understand and potentially fix this issue. "
                "One path per line, no extra text. "
                "If the issue is a design question, feature request, or clearly doesn't need file reading, "
                "respond with exactly: NONE"
            ),
        }],
    )

    files_response = step1.content[0].text.strip()
    file_contents: dict[str, str] = {}

    if files_response.upper() != "NONE":
        for path in files_response.splitlines()[:6]:
            path = path.strip().lstrip("/")
            if not path:
                continue
            content = read_file(path)
            if content is not None:
                file_contents[path] = content

    # ── Step 2: full analysis + optional fix ─────────────────────────────────
    files_section = ""
    if file_contents:
        parts = [f"--- {p} ---\n{c}" for p, c in file_contents.items()]
        files_section = "\n\nRelevant files:\n" + "\n\n".join(parts)

    fix_schema = json.dumps({
        "action": "fix",
        "branch": f"fix/issue-{ISSUE_NUMBER}-short-description",
        "pr_title": "fix(scope): short description",
        "pr_body": f"Fixes #{ISSUE_NUMBER}\n\nWhat changed and why.",
        "files": [{"path": "relative/path", "content": "full new file content"}],
        "issue_comment": "One paragraph explaining what was fixed and how.",
    }, indent=2)

    comment_schema = json.dumps({
        "action": "comment",
        "issue_comment": (
            "Markdown. Sections: **What this issue is about**, "
            "**What needs to change**, **Suggested steps for a human**."
        ),
    }, indent=2)

    step2 = client.messages.create(
        model=MODEL,
        max_tokens=8096,
        messages=[{
            "role": "user",
            "content": (
                f"Issue #{ISSUE_NUMBER}: {ISSUE_TITLE}\n\n"
                f"{ISSUE_BODY}\n\n"
                f"Repo overview (CLAUDE.md):\n{claude_md}"
                f"{files_section}\n\n"
                "Analyze this issue. Respond with **JSON only** (no prose outside the JSON).\n\n"
                f"If you are confident you can produce a correct, complete code fix:\n{fix_schema}\n\n"
                f"Otherwise (needs design input, too risky, insufficient context):\n{comment_schema}\n\n"
                "Rules for a 'fix':\n"
                "- Only attempt fixes that are clearly scoped bug fixes or small changes.\n"
                "- Provide the complete new content of each changed file.\n"
                "- PR title must follow: type(scope): description  "
                "(types: feat/fix/refactor/ci/docs, scopes: komm/risk/crm/shared-auth/repo).\n"
                "- If in doubt, use 'comment' — a good analysis is more useful than a bad fix."
            ),
        }],
    )

    text = step2.content[0].text.strip()

    try:
        result = extract_json(text)
    except Exception as exc:
        post_comment(
            f"🤖 **AI Issue Analysis** — _could not parse structured response_\n\n"
            f"```\n{text[:3000]}\n```"
        )
        print(f"JSON parse error: {exc}", file=sys.stderr)
        sys.exit(0)

    # ── Act on the result ─────────────────────────────────────────────────────
    if result.get("action") == "fix" and result.get("files"):
        branch = result["branch"]

        run(["git", "config", "user.email", "github-actions[bot]@users.noreply.github.com"])
        run(["git", "config", "user.name", "github-actions[bot]"])
        run(["git", "checkout", "-b", branch])

        for fc in result["files"]:
            path = fc["path"].lstrip("/")
            parent = os.path.dirname(path)
            if parent:
                os.makedirs(parent, exist_ok=True)
            with open(path, "w") as f:
                f.write(fc["content"])
            run(["git", "add", path])

        commit_msg = (
            f"{result['pr_title']}\n\n"
            f"Fixes #{ISSUE_NUMBER}\n\n"
            "Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
        )
        run(["git", "commit", "-m", commit_msg])
        run(["git", "push", "origin", branch])

        pr_url = capture([
            "gh", "pr", "create",
            "--repo", REPO,
            "--base", "staging",
            "--head", branch,
            "--draft",          # always a draft — a human must review and merge
            "--title", result["pr_title"],
            "--body", result["pr_body"],
        ])

        post_comment(
            f"🤖 I've analyzed this issue and opened a fix PR: {pr_url}\n\n"
            f"{result['issue_comment']}"
        )
        print(f"Fix PR opened: {pr_url}")

    else:
        post_comment(f"🤖 **AI Issue Analysis**\n\n{result.get('issue_comment', text)}")
        print("Analysis comment posted.")


if __name__ == "__main__":
    main()
