#!/bin/bash
# Installs Fermrad Claude Code skills as slash commands.
#
# Uses $CLAUDE_CONFIG_DIR if set, otherwise falls back to ~/.claude.
#
# One-liner (requires gh CLI authenticated):
#   bash <(curl -fsSL https://raw.githubusercontent.com/fermrad/AI-tools/main/claude/install-claude-skills.sh)
#
# For claude-ferm (CLAUDE_CONFIG_DIR=~/.claude-ferm):
#   CLAUDE_CONFIG_DIR=~/.claude-ferm bash ~/repos/AI-tools/claude/install-claude-skills.sh
#
# After running: restart Claude Code and type / to see the skills.
set -euo pipefail

REPO_DIR="$HOME/repos/AI-tools"
SKILLS_SRC="$REPO_DIR/claude/skills"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
COMMANDS_DST="$CONFIG_DIR/commands"

# Clone or update AI-tools (claude/ folder only)
if [ -d "$REPO_DIR/.git" ]; then
  echo "Updating AI-tools..."
  git -C "$REPO_DIR" pull --ff-only
else
  echo "Cloning AI-tools (claude/ only)..."
  gh repo clone fermrad/AI-tools "$REPO_DIR" -- --filter=blob:none --sparse
  git -C "$REPO_DIR" sparse-checkout set claude
fi

mkdir -p "$COMMANDS_DST"

INSTALLED=0
for skill_dir in "$SKILLS_SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  name="$(basename "$skill_dir")"
  # Skip hidden dirs like .claude-plugin
  [[ "$name" == .* ]] && continue
  ln -sfn "$skill_dir/SKILL.md" "$COMMANDS_DST/$name.md"
  echo "  /$name"
  INSTALLED=$((INSTALLED + 1))
done

if [ "$INSTALLED" -eq 0 ]; then
  echo "No skills found in $SKILLS_SRC"
  exit 1
fi

echo ""
echo "Installed $INSTALLED skill(s) into $COMMANDS_DST"
echo "Restart Claude Code and type / to see them."
