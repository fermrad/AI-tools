# Cursor

Configurations for [Cursor](https://cursor.sh), the AI-powered code editor.

## `.cursorrules`

Cursor reads `.cursorrules` from the project root to give the AI context about the codebase. Copy `cursorrules.template` into your project root as `.cursorrules` and fill in the blanks.

The rules file supports the same kind of project context as `CLAUDE.md` — folder structure, conventions, commands — but is formatted for Cursor's system prompt injection.
