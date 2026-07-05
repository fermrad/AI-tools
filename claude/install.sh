#!/bin/bash
# Installs ferm Claude Code skills into ~/.claude/commands/
# Usage: ./claude/install.sh  (or run via the one-liner in the README)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_SRC="$SCRIPT_DIR/commands"
COMMANDS_DST="$HOME/.claude/commands"

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
