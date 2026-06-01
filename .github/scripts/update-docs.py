#!/usr/bin/env python3
"""
Documentation updater — runs inside a GitHub Actions workflow on every PR.

Reads the PR diff, checks what documentation exists, and uses Claude to:
  - Update existing docs to reflect new behaviour
  - Create initial documentation if none exists
  - Leave files unchanged if nothing warrants a docs update

Writes changes directly to the working tree; the workflow commits them.
"""

import os
import sys
import json
import pathlib
import anthropic

client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

REPO_ROOT = pathlib.Path(".")
DOCS_DIR  = REPO_ROOT / "docs"
README    = REPO_ROOT / "README.md"

PR_TITLE       = os.getenv("PR_TITLE", "")
PR_NUMBER      = os.getenv("PR_NUMBER", "")
CHANGED_FILES  = os.getenv("CHANGED_FILES", "").split(",")
BASE_REF       = os.getenv("BASE_REF", "main")

def read_file_safe(path: pathlib.Path, max_chars: int = 4000) -> str:
    try:
        content = path.read_text(encoding="utf-8")
        return content[:max_chars] if len(content) > max_chars else content
    except Exception:
        return ""

def collect_existing_docs() -> dict[str, str]:
    docs = {}
    if README.exists():
        docs["README.md"] = read_file_safe(README)
    if DOCS_DIR.exists():
        for f in sorted(DOCS_DIR.glob("**/*.md")):
            key = str(f.relative_to(REPO_ROOT))
            docs[key] = read_file_safe(f)
    return docs

def collect_source_context() -> str:
    """Grab key source files to give Claude context about the codebase."""
    snippets = []
    for pattern in ["package.json", "pyproject.toml", "*.tf", "docker-compose.yml"]:
        for f in REPO_ROOT.glob(pattern):
            snippets.append(f"--- {f} ---\n{read_file_safe(f, 1000)}")
    return "\n\n".join(snippets[:5])  # cap at 5 files

def main():
    diff = pathlib.Path("/tmp/pr_diff.txt").read_text(encoding="utf-8") if pathlib.Path("/tmp/pr_diff.txt").exists() else ""
    existing_docs = collect_existing_docs()
    source_ctx    = collect_source_context()

    docs_summary = "\n".join(
        f"=== {path} ===\n{content}"
        for path, content in existing_docs.items()
    ) or "(no documentation exists yet)"

    changed_list = "\n".join(f"  - {f}" for f in CHANGED_FILES if f.strip())

    prompt = f"""You are a technical writer reviewing a pull request and updating project documentation.

## PR info
- Title: {PR_TITLE} (#{PR_NUMBER})
- Base branch: {BASE_REF}
- Changed files:
{changed_list}

## Code diff (first 12 000 chars)
```
{diff[:12000]}
```

## Key source files (for context)
{source_ctx}

## Existing documentation
{docs_summary}

## Your task

1. Decide whether any documentation needs updating based on the changes.
2. If the README is missing or skeletal (under 100 words), create a proper one:
   - Project title + one-sentence tagline
   - What this is (plain language, 2–4 sentences, no jargon)
   - Purpose & responsibility (who owns it, who to contact)
   - Getting started commands
   - Architecture overview with folder structure
3. If docs need updating (new features, changed APIs, new config, etc.), update them.
4. If nothing warrants documentation changes, output ONLY: {{"changes": []}}

Respond with a JSON object. No markdown fences, no preamble. Schema:
{{
  "changes": [
    {{
      "path": "README.md",          // relative path from repo root
      "content": "full file content here"
    }}
  ]
}}

Rules:
- Only include files that actually need changes — omit files that are fine as-is
- Full file content (not diffs) — the workflow writes the whole file
- Keep docs concise and factual — no speculation about future plans
- Max 3 file changes per PR to stay focused
"""

    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=4096,
        messages=[{"role": "user", "content": prompt}],
    )

    text = response.content[0].text.strip()

    # Parse JSON — Claude sometimes wraps in fences despite instructions
    if text.startswith("```"):
        lines = text.splitlines()
        text  = "\n".join(lines[1:-1] if lines[-1] == "```" else lines[1:])

    try:
        result = json.loads(text)
    except json.JSONDecodeError as e:
        print(f"Failed to parse Claude response as JSON: {e}", file=sys.stderr)
        print(f"Response was:\n{text}", file=sys.stderr)
        sys.exit(0)  # non-fatal — don't fail the workflow

    changes = result.get("changes", [])
    if not changes:
        print("No documentation changes needed.")
        sys.exit(0)

    for change in changes:
        path    = pathlib.Path(change["path"])
        content = change["content"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        print(f"Updated: {path}")

    print(f"Documentation update complete — {len(changes)} file(s) changed.")

if __name__ == "__main__":
    main()
