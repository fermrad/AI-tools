# AI-tools

Centralised repository for AI tool configurations, system prompts, and GitHub Actions workflows used across Ferm projects.

## Structure

| Folder | Tool | Contents |
|---|---|---|
| [`claude/`](./claude/) | Claude Code (Anthropic) | `CLAUDE.md` templates, GitHub Actions workflows, Python scripts |
| [`cursor/`](./cursor/) | Cursor | `.cursorrules` templates |
| [`github-copilot/`](./github-copilot/) | GitHub Copilot | `copilot-instructions.md` templates |
| [`openai/`](./openai/) | OpenAI / ChatGPT | System prompt templates |
| [`perplexity/`](./perplexity/) | Perplexity AI | Search prompt templates |

## Usage

### Claude Code workflows

The `claude/github-actions/` folder contains reusable GitHub Actions workflows and Python scripts that use the Claude API:

- **`ai-issue-triage`** — when a GitHub issue is opened, Claude reads relevant files and either opens a draft fix PR or posts an analysis comment.
- **`compliance-check`** — reads auth code, middleware, Dockerfiles, and CI workflows; maps gaps against ISO 27001 and SOC 2 controls; files labelled GitHub issues for new gaps.

To use in a project: copy only the `.yml` workflow files into `.github/workflows/` (typically just a thin caller that delegates to `fermrad/AI-tools/.github/workflows/<workflow>.yml@main`). The supporting Python scripts are fetched at workflow runtime via `actions/checkout` of `fermrad/AI-tools` — **do not copy the `.py` files into the calling repo**. Then add `ANTHROPIC_API_KEY` to the repo's Actions secrets (only required for `ai-issue-triage` and `compliance-check`; `pentest` does not need it).

### CLAUDE.md template

`claude/CLAUDE.md.template` is a starting point for new projects. Fill in the sections marked `TODO`.

### Cursor / Copilot / OpenAI templates

Each folder contains a template file. Copy it into your project root and customise.
