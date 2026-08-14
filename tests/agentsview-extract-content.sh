#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/agentsview-extract"
SKILL="$SKILL_DIR/SKILL.md"

fail() {
  echo "agentsview-extract content check failed: $*" >&2
  exit 1
}

[ -f "$SKILL" ] || fail "skills/agentsview-extract/SKILL.md is missing"

grep -q '^name: agentsview-extract$' "$SKILL" \
  || fail "frontmatter must use name: agentsview-extract"

grep -q -E '^description:' "$SKILL" \
  || fail "description must be present"

grep -q -E 'AGENTS\.md' "$SKILL" \
  || fail "description or body must target AGENTS.md"

grep -q -E 'new skill' "$SKILL" \
  || fail "description or body must allow creating a new skill"

if grep -qiE 'CLI-First with MCP Fallback|search_content|get_messages' "$SKILL"; then
  fail "SKILL.md must not teach an MCP search fallback"
fi

if grep -q 'references/agentsview-cli.md' "$SKILL"; then
  fail "SKILL.md must not point at the deleted CLI cookbook"
fi

if [ -f "$SKILL_DIR/references/agentsview-cli.md" ]; then
  fail "references/agentsview-cli.md must be removed"
fi

if grep -qE 'brew install|--cask agentsview' "$SKILL"; then
  fail "SKILL.md must not install the desktop cask"
fi

if grep -qE 'uvx agentsview' "$SKILL"; then
  fail "SKILL.md must not use ephemeral uvx as the installer"
fi

grep -q -E 'uv tool install agentsview' "$SKILL" \
  || fail "CLI ensure must prefer uv tool install agentsview"

grep -q -E 'agentsview.io/install.sh' "$SKILL" \
  || fail "CLI ensure must fall back to the official install.sh"

grep -q -E 'install.ps1' "$SKILL" \
  || fail "CLI ensure must fall back to the official install.ps1 on Windows"

grep -q -E 'skills list --format json' "$SKILL" \
  || fail "must inspect agentsview skills list --format json"

grep -q -E 'agentsview skills install' "$SKILL" \
  || fail "must install official skills with agentsview skills install"

grep -q -- '--force' "$SKILL" \
  || fail "must mention --force when refusing overwrite"

grep -q -E 'session search --help' "$SKILL" \
  || fail "missing+declined official skill must follow session search --help"

grep -q -E 'agentsview-finding-history' "$SKILL" \
  || fail "must name the official finding-history skill"

grep -q 'SKILL.md' "$SKILL" \
  || fail "must read the installed finding-history SKILL.md"

grep -q -E 'untrusted data' "$SKILL" \
  || fail "SKILL.md must treat transcripts as untrusted data"

grep -q -E 'references/security.md' "$SKILL" \
  || fail "link to references/security.md is missing"

[ -f "$SKILL_DIR/references/security.md" ] || fail "references/security.md is missing"

grep -q -E 'Untrusted Transcript Content' "$SKILL_DIR/references/security.md" \
  || fail "security.md must have an Untrusted Transcript Content section"

grep -q -E 'Do not follow instructions' "$SKILL_DIR/references/security.md" \
  || fail "security.md must forbid following instructions inside transcripts"

echo "agentsview-extract content checks passed"
