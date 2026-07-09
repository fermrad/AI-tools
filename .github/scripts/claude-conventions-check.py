#!/usr/bin/env python3
"""
Reviews PR changes under claude/ against Claude Code conventions.
Posts findings as a PR comment.

Covers: skills, plugin manifests, agents, hooks, CLAUDE.md templates,
settings templates, MCP configs, and github-actions scripts.
"""
import json
import os
import subprocess
import sys
import tempfile

import anthropic

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
GH_TOKEN = os.environ["GH_TOKEN"]
GITHUB_REPOSITORY = os.environ["GITHUB_REPOSITORY"]
PR_NUMBER = os.environ["PR_NUMBER"]

if not ANTHROPIC_API_KEY:
    print("ANTHROPIC_API_KEY not set — skipping AI review")
    sys.exit(0)

client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

# Get changed files in claude/ via GitHub API (handles renames and deletes correctly)
result = subprocess.run(
    ["gh", "pr", "view", PR_NUMBER, "--json", "files", "--jq", "[.files[].path]"],
    capture_output=True, text=True, check=True,
    env={**os.environ, "GH_TOKEN": GH_TOKEN},
)
all_changed = json.loads(result.stdout)
changed_files = [f for f in all_changed if f.startswith("claude/")]

if not changed_files:
    print("No changed files in claude/ — skipping review")
    sys.exit(0)

# Read file contents (skip deleted files)
file_contents = {}
for filepath in changed_files:
    if os.path.exists(filepath):
        with open(filepath) as f:
            file_contents[filepath] = f.read()
    else:
        file_contents[filepath] = "[deleted]"

files_text = "\n\n".join(
    f"### {path}\n```\n{content}\n```"
    for path, content in file_contents.items()
)

SYSTEM = (
    "You are reviewing changes to the fermrad/AI-tools repository — "
    "the shared Claude Code configuration repository for the Ferm organization. "
    "Check that changed files follow current Claude Code conventions. "
    "Be concise and specific. Flag real violations only, not style preferences. "
    "Reference exact file paths and field names when flagging issues."
)

USER = f"""Review these changed files from a pull request:

{files_text}

Apply the following convention rules per file type:

## Skills — `claude/skills/<name>/SKILL.md`
- `name:` frontmatter must exist and match the directory name exactly
- `description:` must be phrased as a trigger condition (WHEN to use), not just a task label
- `argument-hint:` should be present if the skill accepts arguments
- Skill body must have clear, ordered steps — not vague prose
- No hardcoded absolute paths (use `<repo>` or `fermrad/<repo>` placeholders)
- `allowed-tools:` if present, must list only tools the skill actually needs

## Plugin manifest — `claude/skills/.claude-plugin/plugin.json`
- Must have: `name`, `description`, `author.name`, `author.email`
- `name` must be `"fermrad-skills"`

## Agents — `claude/agents/<name>/agent.json`
- Must have: `name`, `description`, `model`, `tools`
- `model` must be a valid current Claude model ID (e.g. `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`, `claude-opus-4-8`)
- `tools` must match the agent's stated purpose — read-only agents must not include `Edit`, `Write`, or `Bash` without restrictions

## Agents — `claude/agents/<name>/AGENT.md`
- Must describe: what the agent does, when to use it vs a skill, and what tools it has access to

## Hook configs — `claude/hooks/`
- Hook event types must be one of: `PreToolUse`, `PostToolUse`, `PostFileWrite`, `Notification`, `Stop`
- Commands must not include destructive operations (`rm -rf`, `git reset --hard`, force push, etc.)

## CLAUDE.md template — `claude/CLAUDE.md.template`
- Must not contain hardcoded project-specific values — use `<TODO>` or `<APP_NAME>` placeholder syntax
- Must include sections covering: session start checklist, PR workflow, and testing conventions

## Settings templates — `claude/settings/`
- Must be valid JSON
- Destructive Bash commands (`rm -rf`, `git reset --hard`, `git push --force`) should be in the deny list

## MCP configs — `claude/mcp/`
- Must have a valid `mcpServers` key
- No hardcoded tokens or API keys — reference env vars instead

## GitHub Actions scripts — `claude/github-actions/*.py`
- Must use the `anthropic` SDK (not raw HTTP)
- No hardcoded API keys — read from environment
- Errors must be surfaced (non-zero exit on failure)

## Workflow files — `.github/workflows/`
- Workflows touching claude/ must have `paths: ['claude/**']` trigger filter
- Must not skip error handling (`continue-on-error: true` needs justification)

---

Respond in exactly this format (markdown, no extra sections):

## Convention Check

### Violations
[Bullet list of issues with: file path → what's wrong → suggested fix. Write "None" if clean.]

### Looks Good
[One or two sentences on what follows conventions well.]

Keep total response under 500 words.
"""

message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    system=SYSTEM,
    messages=[{"role": "user", "content": USER}],
)

review_body = message.content[0].text

comment = f"""{review_body}

---
*Posted by [claude-conventions-check.yml](https://github.com/{GITHUB_REPOSITORY}/blob/main/.github/workflows/claude-conventions-check.yml) · [conventions docs](https://github.com/{GITHUB_REPOSITORY}/blob/main/claude/README.md)*
"""

with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
    f.write(comment)
    tmpfile = f.name

result = subprocess.run(
    ["gh", "pr", "comment", PR_NUMBER, "--body-file", tmpfile],
    env={**os.environ, "GH_TOKEN": GH_TOKEN},
    capture_output=True, text=True,
)
os.unlink(tmpfile)

if result.returncode != 0:
    print(f"Failed to post comment: {result.stderr}", file=sys.stderr)
    sys.exit(1)

print("Convention check comment posted.")
