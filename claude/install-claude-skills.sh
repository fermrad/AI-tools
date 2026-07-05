#!/bin/bash
# Installs ferm Claude Code skills into ~/.claude/skills/
#
# One-liner (works with private repo via gh auth):
#   gh api repos/fermrad/AI-tools/contents/claude/install-claude-skills.sh --jq '.content' | base64 -d | bash
set -euo pipefail

REPO_DIR="$HOME/repos/AI-tools"
SKILLS_SRC="$REPO_DIR/claude/skills"
SKILLS_DST="$HOME/.claude/skills"

# Clone or update AI-tools (claude/ folder only)
if [ -d "$REPO_DIR/.git" ]; then
  echo "Updating AI-tools..."
  git -C "$REPO_DIR" pull --ff-only
else
  echo "Cloning AI-tools (claude/ only)..."
  gh repo clone fermrad/AI-tools "$REPO_DIR" -- --filter=blob:none --sparse
  git -C "$REPO_DIR" sparse-checkout set claude
fi

mkdir -p "$SKILLS_DST"

INSTALLED=0
for skill_dir in "$SKILLS_SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  name="$(basename "$skill_dir")"
  ln -sfn "$skill_dir" "$SKILLS_DST/$name"
  echo "  /$name"
  INSTALLED=$((INSTALLED + 1))
done

if [ "$INSTALLED" -eq 0 ]; then
  echo "No skills found in $SKILLS_SRC"
  exit 1
fi

echo ""
echo "Installed $INSTALLED skill(s) into $SKILLS_DST"
echo "Restart Claude Code and type / to see them."
