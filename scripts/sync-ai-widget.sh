#!/usr/bin/env bash
# Sync the AI widget from AI-tools into a ferm-tools app.
# Usage: bash scripts/sync-ai-widget.sh apps/komm
#        bash scripts/sync-ai-widget.sh apps/risk
#        bash scripts/sync-ai-widget.sh apps/crm/app
set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "Usage: $0 <app-dir>  (e.g. apps/komm)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_TOOLS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WIDGET_SRC="$AI_TOOLS_ROOT/claude/widget/src"

# Resolve target relative to ferm-tools root (two levels up from AI-tools)
FERM_TOOLS_ROOT="$(cd "$AI_TOOLS_ROOT/.." && pwd)"
APP_DIR="$FERM_TOOLS_ROOT/$TARGET"

if [ ! -d "$APP_DIR" ]; then
  echo "Error: directory not found: $APP_DIR"
  exit 1
fi

SRC_DIR="$APP_DIR/src"
if [ ! -d "$SRC_DIR" ]; then
  echo "Error: no src/ directory in $APP_DIR"
  exit 1
fi

COMPONENT_DIR="$SRC_DIR/components/ai"
ROUTE_DIR="$SRC_DIR/app/api/ai/chat"

mkdir -p "$COMPONENT_DIR" "$ROUTE_DIR"

cp "$WIDGET_SRC/AIWidget.tsx"   "$COMPONENT_DIR/AIWidget.tsx"
cp "$WIDGET_SRC/chat-route.ts"  "$ROUTE_DIR/route.ts"

echo "✓ Synced AI widget into $TARGET"
echo "  $COMPONENT_DIR/AIWidget.tsx"
echo "  $ROUTE_DIR/route.ts"
echo ""
echo "Next steps:"
echo "  1. cd $TARGET && npm install ai @ai-sdk/anthropic"
echo "  2. Add <AIWidget appName=\"$(basename $TARGET)\" /> to src/app/layout.tsx"
echo "  3. Add ANTHROPIC_API_KEY and AI_WIDGET_ENABLED=true to .env.local"
echo "  4. Uncomment the auth check in $ROUTE_DIR/route.ts"
