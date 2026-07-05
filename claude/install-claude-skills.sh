#!/bin/bash
# Installs ferm Claude Code skills into ~/.claude/commands/
#
# One-liner (works with private repo via gh auth):
#   gh api repos/fermrad/AI-tools/contents/claude/install-claude-skills.sh --jq '.content' | base64 -d | bash
set -euo pipefail

REPO_DIR="$HOME/repos/AI-tools"
COMMANDS_SRC="$REPO_DIR/claude/commands"
COMMANDS_DST="$HOME/.claude/commands"

# Clone or update AI-tools
if [ -d "$REPO_DIR/.git" ]; then
  echo "Updating AI-tools..."
  git -C "$REPO_DIR" pull --ff-only
else
  echo "Cloning AI-tools..."
  gh repo clone fermrad/AI-tools "$REPO_DIR"
fi

mkdir -p "$COMMANDS_DST"

INSTALLED=0
for skill in "$COMMANDS_SRC"/*.md; do
  [ -f "$skill" ] || continue
  name="$(basename "$skill")"
  ln -sf "$skill" "$COMMANDS_DST/$name"
  echo "  /$(basename "$name" .md)"
  INSTALLED=$((INSTALLED + 1))
done

if [ "$INSTALLED" -eq 0 ]; then
  echo "No skills found in $COMMANDS_SRC"
  exit 1
fi

echo ""
echo "Installed $INSTALLED skill(s) into $COMMANDS_DST"
echo "Restart Claude Code and type / to see them."
