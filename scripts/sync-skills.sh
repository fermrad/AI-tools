#!/usr/bin/env bash
# Sync Ferm's Claude skills into a repo's .claude/skills/ so they are available
# in Claude Code remote sessions (claude.ai/code, GitHub Actions, mobile).
#
# Why this exists: skills live here in claude/skills/ (no dot), which is a
# distribution directory, not a discovery path. Claude Code only reads
# ~/.claude/skills/ and <repo>/.claude/skills/. On a laptop, setup-tool installs
# to the former. A remote container never runs setup-tool, so without this sync
# no Ferm skill is invokable there.
#
# Usage: bash scripts/sync-skills.sh              # sync into AI-tools itself
#        bash scripts/sync-skills.sh ../crm       # sync into a sibling checkout
#        bash scripts/sync-skills.sh /workspace/devhub
#
# Commit the resulting .claude/skills/ — that is what makes it work in remote.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_TOOLS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_SRC="$AI_TOOLS_ROOT/claude/skills"

TARGET_ROOT="$(cd "${1:-$AI_TOOLS_ROOT}" 2>/dev/null && pwd)" || {
  echo "Error: directory not found: ${1:-}"
  exit 1
}

if [ ! -d "$SKILLS_SRC" ]; then
  echo "Error: no skills directory at $SKILLS_SRC"
  exit 1
fi

DST="$TARGET_ROOT/.claude/skills"
MANIFEST="$DST/.synced-from-ai-tools"

mkdir -p "$DST"

# Remove skills we synced previously that no longer exist upstream — renames and
# deletions would otherwise linger forever. Only names in the manifest are
# touched, so skills local to the target repo are left alone.
if [ -f "$MANIFEST" ]; then
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    if [ ! -d "$SKILLS_SRC/$name" ] && [ -d "$DST/$name" ]; then
      rm -rf "${DST:?}/$name"
      echo "  - removed $name (no longer in AI-tools)"
    fi
  done < "$MANIFEST"
fi

synced=0
: > "$MANIFEST.tmp"
for dir in "$SKILLS_SRC"/*/; do
  name="$(basename "$dir")"
  case "$name" in .*) continue ;; esac
  [ -f "$dir/SKILL.md" ] || continue

  mkdir -p "$DST/$name"
  # Copy SKILL.md verbatim — the YAML frontmatter must stay byte-identical — plus
  # any sibling reference files the skill ships (e.g. example workflow YAML).
  cp "$dir"* "$DST/$name/"
  echo "$name" >> "$MANIFEST.tmp"
  synced=$((synced + 1))
done
mv "$MANIFEST.tmp" "$MANIFEST"

cat > "$DST/README.md" <<'EOF'
# .claude/skills — generated, do not edit

These are copies, synced from `fermrad/AI-tools` (`claude/skills/`) so the skills
resolve in Claude Code **remote sessions**, which never run `setup-tool`.

Edit the original in AI-tools and re-run `scripts/sync-skills.sh <this-repo>`.
Edits made here are overwritten on the next sync.

`.synced-from-ai-tools` records which skills came from the sync, so removing one
upstream removes it here too — skills local to this repo are untouched.
EOF

echo "✓ Synced $synced skill(s) → ${DST#"$TARGET_ROOT"/}"
echo ""
echo "Next steps:"
echo "  1. git -C $TARGET_ROOT add .claude/skills"
echo "  2. Commit — the copies must be in git to work in remote sessions"
echo "  3. Start a remote session and confirm the skills are listed"
