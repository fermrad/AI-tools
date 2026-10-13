#!/usr/bin/env bash
#
# Test af S-737: AI-tools' pr-preview-cleanup.yml er fjernet, fordi den var
# død — et levn fra ferm-tools-monorepoets tid (`for APP in crm komm risk`),
# som ingen kaldte. Uden en vagt kan den liste tilbage på to måder: filen
# selv genopstår, eller en reference til den lever videre et sted og narrer
# den næste til at tro, der findes en delt oprydning.
#
# Testen måler FEM ting:
#   1. .github/workflows/pr-preview-cleanup.yml findes ikke.
#   2. Intet sted i repoet KALDER den længere (uses:, gh workflow run, eller
#      et markdown-link til den) — forklarende prosa, der siger den er
#      fjernet, er ikke et kald og skal IKKE fælde testen.
#   3. pr-preview.yml's PR-kommentar lover ikke længere automatisk oprydning
#      og linker ikke til den døde workflow.
#   4. claude/skills/pr-preview/ (kilden) og .claude/skills/pr-preview/ (den
#      synkede kopi) er byte-identiske — sync-skills.sh er kørt efter rettelsen.
#   5. Skillens tekst siger, at automatiske per-PR-stakke (deploy-pr-stack.yml
#      / teardown-pr-stack.yml) kun findes i project — den forveksling var
#      hele pointen med at rette referencerne.
#
# Kør: bash scripts/test-pr-preview-cleanup-removed.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok    $1"; }
fejl() { FAIL=$((FAIL+1)); echo "FEJL  $1"; }

# --- 1: den døde workflow findes ikke ---------------------------------------
if [ -e ".github/workflows/pr-preview-cleanup.yml" ]; then
  fejl "1) .github/workflows/pr-preview-cleanup.yml findes stadig"
else
  ok "1) .github/workflows/pr-preview-cleanup.yml er fjernet"
fi

# --- 2: ingen levende kaldesteder --------------------------------------------
# Kun egentlige kald fælder — forklarende prosa om at den er fjernet må gerne
# nævne filnavnet.
KALD_MOENSTRE=(
  'uses:.*pr-preview-cleanup\.yml'
  'gh workflow run[[:space:]]+pr-preview-cleanup\.yml'
  '\]\([^)]*pr-preview-cleanup\.yml\)'
)
FUNDET=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  for m in "${KALD_MOENSTRE[@]}"; do
    if grep -Eqn "$m" "$f" 2>/dev/null; then
      FUNDET="$FUNDET$f: $(grep -En "$m" "$f" | head -1)"$'\n'
    fi
  done
done < <(git ls-files)
if [ -n "$FUNDET" ]; then
  fejl "2) der findes stadig et kald til pr-preview-cleanup.yml:"
  printf '%s' "$FUNDET"
else
  ok "2) intet sted i repoet kalder pr-preview-cleanup.yml længere"
fi

# --- 3: pr-preview.yml's PR-kommentar lover ikke automatisk oprydning -------
PRP=".github/workflows/pr-preview.yml"
if grep -q "torn down automatically" "$PRP" || grep -q "pr-preview-cleanup" "$PRP"; then
  fejl "3) $PRP lover stadig automatisk oprydning eller linker til den døde workflow"
else
  ok "3) $PRP's PR-kommentar lover ikke automatisk oprydning"
fi

# --- 4: kilde og synket kopi er identiske ------------------------------------
if diff -rq "claude/skills/pr-preview" ".claude/skills/pr-preview" >/dev/null 2>&1; then
  ok "4) claude/skills/pr-preview og .claude/skills/pr-preview er identiske"
else
  fejl "4) claude/skills/pr-preview og .claude/skills/pr-preview er løbet fra hinanden — kør scripts/sync-skills.sh"
fi

# --- 5: skillen nævner, at automatiske PR-stakke kun findes i project -------
SKILL="claude/skills/pr-preview/SKILL.md"
if grep -qi "project" "$SKILL" && grep -qi "deploy-pr-stack" "$SKILL"; then
  ok "5) skillen siger, at automatiske per-PR-stakke kun findes i project"
else
  fejl "5) skillen nævner ikke, at automatiske per-PR-stakke (deploy-pr-stack.yml) kun findes i project"
fi

echo
echo "$PASS ok, $FAIL fejl"
[ "$FAIL" -eq 0 ]
