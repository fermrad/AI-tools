#!/usr/bin/env bash
# Local build script — bundles the current skills into the binary.
# CI does the same thing before go build in build-setup-tool.yml.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS_SRC="${REPO_ROOT}/claude/skills"
SKILLS_DST="$(dirname "$0")/bundled/skills"

echo "Bundling skills from ${SKILLS_SRC}..."
mkdir -p "${SKILLS_DST}"
for dir in "${SKILLS_SRC}"/*/; do
  name="$(basename "$dir")"
  [[ "$name" == .* ]] && continue
  [ -f "${dir}SKILL.md" ] || continue
  mkdir -p "${SKILLS_DST}/${name}"
  cp "${dir}SKILL.md" "${SKILLS_DST}/${name}/SKILL.md"
  echo "  + ${name}"
done

echo "Building..."
CGO_ENABLED=0 go build "${@}" .
