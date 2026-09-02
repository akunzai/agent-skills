#!/usr/bin/env bash
set -euo pipefail

# Fail only on Agent Skills spec, eval schema, and broken links.
# waza check always exits 0; its compliance score and advisory
# checks are Waza style guidance, not the agentskills.io spec.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "waza spec check failed: $*" >&2
  exit 1
}

command -v waza >/dev/null || fail "waza is not on PATH (run mise install)"
command -v jq >/dev/null || fail "jq is not on PATH (run mise install)"

json=$(waza check --format json) || fail "waza check failed to run"

printf '%s\n' "$json" | jq -e '.skills | type == "array" and length > 0' >/dev/null \
  || fail "waza check returned no skills"

# agentskills.io only allows name/description/license/allowed-tools/
# metadata/compatibility, so waza flags `disable-model-invocation` as
# unknown. Claude Code honors it directly and it pairs with each such
# skill's agents/openai.yaml (policy.allow_implicit_invocation: false)
# for Codex, per openai/codex#29989 — treat it as a deliberate,
# documented extension rather than a spec violation.
problems=$(printf '%s\n' "$json" | jq -r '
  def unknown_fields: capture("Unknown frontmatter fields: (?<f>.*)").f | split(", ");
  def waived: . as $c
    | $c.name == "spec-allowed-fields"
      and (($c.summary // "" | unknown_fields) - ["disable-model-invocation"] | length) == 0;

  .skills[]
  | . as $s
  | (
      (.specCompliance // [])[]
      | select(.passed == false)
      | select(waived | not)
      | "\($s.name): spec \(.name): \(.summary)"
    ),
    (
      select((.links.passed // true) == false)
      | "\($s.name): broken links (\(.links.valid)/\(.links.total))"
    ),
    (
      select((.schema.valid // true) == false)
      | "\($s.name): eval schema invalid"
    )
')

if [[ -n $problems ]]; then
  printf '%s\n' "$problems" >&2
  fail "one or more skills failed spec, schema, or link checks"
fi

count=$(printf '%s\n' "$json" | jq '.skills | length')
printf 'waza spec checks passed for %s skill(s)\n' "$count"
