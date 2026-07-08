#!/bin/bash
# Installs Fermrad Claude Code skills as a plugin into ~/.claude/plugins/local/fermrad-skills/
#
# One-liner (requires gh CLI authenticated):
#   bash <(curl -fsSL https://raw.githubusercontent.com/fermrad/AI-tools/main/claude/install-claude-skills.sh)
#
# Or clone first:
#   gh repo clone fermrad/AI-tools ~/repos/AI-tools -- --filter=blob:none --sparse \
#     && git -C ~/repos/AI-tools sparse-checkout set claude \
#     && bash ~/repos/AI-tools/claude/install-claude-skills.sh
#
# After running: open a new Claude Code session and run /plugin install to register,
# or restart Claude Code — it will prompt to install the plugin on next launch.
set -euo pipefail

REPO_DIR="$HOME/repos/AI-tools"
PLUGIN_SRC="$REPO_DIR/claude/skills"
PLUGIN_DST="$HOME/.claude/plugins/local/fermrad-skills"

# Clone or update AI-tools (claude/ folder only)
if [ -d "$REPO_DIR/.git" ]; then
  echo "Updating AI-tools..."
  git -C "$REPO_DIR" pull --ff-only
else
  echo "Cloning AI-tools (claude/ only)..."
  gh repo clone fermrad/AI-tools "$REPO_DIR" -- --filter=blob:none --sparse
  git -C "$REPO_DIR" sparse-checkout set claude
fi

# Symlink the entire skills directory as a local plugin
mkdir -p "$(dirname "$PLUGIN_DST")"
ln -sfn "$PLUGIN_SRC" "$PLUGIN_DST"

echo ""
echo "Plugin symlinked: $PLUGIN_DST -> $PLUGIN_SRC"
echo ""
echo "Next step: in Claude Code run:"
echo "  /plugin install https://github.com/fermrad/AI-tools/tree/main/claude/skills"
echo ""
echo "Or register locally by running this in a Claude Code session:"
echo "  /plugin install $PLUGIN_DST"
echo ""
echo "After installing, type / to see the skills."
