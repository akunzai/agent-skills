#!/usr/bin/env bash
set -euo pipefail

# Offline contract check for scripts/bump-pinned-tools.sh. Copies the files
# it rewrites into a temp dir, stubs the GitHub release/commit lookups with
# fixture files (BUMP_TOOLS_RELEASES_CMD / BUMP_TOOLS_SHA_CMD), and asserts
# real file content changed, not just that the script exited 0 -- a gutted
# --apply that prints "changed=true" without touching a file must fail this.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/bump-pinned-tools.sh"

fail() {
  echo "bump-pinned-tools test failed: $*" >&2
  exit 1
}

if [ ! -x "$SCRIPT" ]; then
  fail "Script $SCRIPT is missing or not executable"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO="$TMP_DIR/repo"
FIXTURES="$TMP_DIR/fixtures"
mkdir -p "$REPO/scripts" "$REPO/.github/workflows" \
  "$REPO/skills/agentsview-extract" "$REPO/skills/agentsview-resume" \
  "$FIXTURES"

cp "$SCRIPT" "$REPO/scripts/bump-pinned-tools.sh"
chmod +x "$REPO/scripts/bump-pinned-tools.sh"
cp "$ROOT_DIR/mise.toml" "$REPO/mise.toml"
cp "$ROOT_DIR/.github/workflows/waza-eval.yml" "$REPO/.github/workflows/waza-eval.yml"
cp "$ROOT_DIR/skills/agentsview-extract/SKILL.md" "$REPO/skills/agentsview-extract/SKILL.md"
cp "$ROOT_DIR/skills/agentsview-resume/SKILL.md" "$REPO/skills/agentsview-resume/SKILL.md"

MISE_TOML="$REPO/mise.toml"
WAZA_EVAL="$REPO/.github/workflows/waza-eval.yml"
AGENTSVIEW_EXTRACT="$REPO/skills/agentsview-extract/SKILL.md"
AGENTSVIEW_RESUME="$REPO/skills/agentsview-resume/SKILL.md"

# --- stubs: read release tags / commit shas from fixture files, never the
# network -----------------------------------------------------------------
cat >"$TMP_DIR/stub-releases.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
repo="$1"
file="$FIXTURES_DIR/${repo//\//_}.tags"
[ -f "$file" ] && cat "$file"
exit 0
EOF
cat >"$TMP_DIR/stub-sha.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
repo="$1"
file="$FIXTURES_DIR/${repo//\//_}.sha"
if [ -f "$file" ]; then
  cat "$file"
else
  echo "0000000000000000000000000000000000000000"
fi
EOF
chmod +x "$TMP_DIR/stub-releases.sh" "$TMP_DIR/stub-sha.sh"

export FIXTURES_DIR="$FIXTURES"
export BUMP_TOOLS_RELEASES_CMD="$TMP_DIR/stub-releases.sh"
export BUMP_TOOLS_SHA_CMD="$TMP_DIR/stub-sha.sh"

run_script() {
  (cd "$REPO" && bash scripts/bump-pinned-tools.sh "$@")
}

field() {
  # field <key> <apply-output> -- pulls "key=value" from --apply's output
  local key="$1" output="$2"
  printf '%s\n' "$output" | sed -nE "s/^${key}=(.*)\$/\1/p"
}

# --- fixtures ----------------------------------------------------------------
# zizmor: fixture top tag equals the repo's current pin, so --apply must be
# a no-op that leaves the file untouched (the "already current" case).
printf 'v1.30.1\n' >"$FIXTURES/zizmorcore_zizmor.tags"

# gitleaks: not pinned in mise.toml yet (a separate, unmerged slice adds it).
# No fixture needed for the first (absent) assertion below.
printf 'v8.30.1\nv8.31.0\n' >"$FIXTURES/gitleaks_gitleaks.tags"

# waza: includes a non-semver release tag (the azd extension release the
# repo's own mise.toml comment warns about) that must be filtered out
# rather than picked as "latest".
printf 'v0.38.7\nv0.39.0\nazd-ext-microsoft-azd-waza_0.39.0\n' >"$FIXTURES/microsoft_waza.tags"

printf 'v0.44.0\nv0.45.0\n' >"$FIXTURES/kenn-io_agentsview.tags"

printf 'v2.12.0\nv2.13.0\n' >"$FIXTURES/NVIDIA_SkillSpector.tags"
printf 'abc123def456abc123def456abc123def456abcd\n' >"$FIXTURES/NVIDIA_SkillSpector.sha"

# --- baseline: capture what must never change --------------------------------
BEFORE_MISE="$(cat "$MISE_TOML")"
LATEST_LINES_BEFORE="$(grep -cE '"latest"' "$MISE_TOML")"

# --- 1. zizmor already at latest: no-op, file untouched ----------------------
OUT="$(run_script --apply zizmor)"
[ "$(field changed "$OUT")" = "false" ] \
  || fail "zizmor already-current apply reported changed=true: $OUT"
[ "$(cat "$MISE_TOML")" = "$BEFORE_MISE" ] \
  || fail "zizmor already-current apply modified mise.toml"

# --- 2. gitleaks absent from mise.toml: no-op, no crash ----------------------
OUT="$(run_script --apply gitleaks)"
[ "$(field changed "$OUT")" = "false" ] \
  || fail "gitleaks apply on an absent pin reported changed=true: $OUT"
grep -q '^gitleaks = ' "$MISE_TOML" \
  && fail "gitleaks apply on an absent pin should not have added a pin"

# --- 3. simulate the other slice landing: add the pin, then re-apply --------
# Proves the table-driven design: covering gitleaks took one row in
# scripts/bump-pinned-tools.sh's repo_for(), no other code path changed.
printf 'gitleaks = "8.30.1"\n' >>"$MISE_TOML"
OUT="$(run_script --apply gitleaks)"
[ "$(field changed "$OUT")" = "true" ] || fail "gitleaks apply did not bump once pinned: $OUT"
[ "$(field new_version "$OUT")" = "8.31.0" ] || fail "gitleaks resolved wrong version: $OUT"
grep -qF 'gitleaks = "8.31.0"' "$MISE_TOML" || fail "mise.toml gitleaks pin was not rewritten"
grep -qF 'gitleaks = "8.30.1"' "$MISE_TOML" && fail "old gitleaks pin still present in mise.toml"

# --- 4. waza: two files, and the azd-ext tag must be ignored -----------------
OUT="$(run_script --apply waza)"
[ "$(field changed "$OUT")" = "true" ] || fail "waza apply did not report a change: $OUT"
[ "$(field new_version "$OUT")" = "0.39.0" ] \
  || fail "waza picked the wrong 'latest' (want 0.39.0, azd-ext tag must be excluded): $OUT"
grep -qF 'version = "0.39.0"' "$MISE_TOML" || fail "mise.toml waza version was not rewritten"
grep -qF 'install_args: github:microsoft/waza@0.39.0' "$WAZA_EVAL" \
  || fail "waza-eval.yml install_args was not rewritten"
grep -qF '0.38.7' "$MISE_TOML" && fail "old waza version still present in mise.toml"
grep -qF '0.38.7' "$WAZA_EVAL" && fail "old waza version still present in waza-eval.yml"

# --- 5. agentsview: mise.toml task + both SKILL.md files ---------------------
OUT="$(run_script --apply agentsview)"
[ "$(field changed "$OUT")" = "true" ] || fail "agentsview apply did not report a change: $OUT"
[ "$(field new_version "$OUT")" = "0.45.0" ] || fail "agentsview resolved wrong version: $OUT"
grep -qF '"github:kenn-io/agentsview" = "v0.45.0"' "$MISE_TOML" \
  || fail "mise.toml agentsview task pin was not rewritten"
for f in "$AGENTSVIEW_EXTRACT" "$AGENTSVIEW_RESUME"; do
  grep -qF 'agentsview==0.45.0' "$f" || fail "$f uv install pin was not rewritten"
  grep -qF 'agentsview@v0.45.0' "$f" || fail "$f mise use pin was not rewritten"
  grep -qF '0.44.0' "$f" && fail "$f still cites the old agentsview version"
done

# --- 6. skillspector: sha + version comment together ------------------------
OUT="$(run_script --apply skillspector)"
[ "$(field changed "$OUT")" = "true" ] || fail "skillspector apply did not report a change: $OUT"
[ "$(field new_version "$OUT")" = "2.13.0" ] || fail "skillspector resolved wrong version: $OUT"
[ "$(field commit_sha "$OUT")" = "abc123def456abc123def456abc123def456abcd" ] \
  || fail "skillspector apply did not report the resolved commit sha: $OUT"
grep -qF 'SKILLSPECTOR_REF="abc123def456abc123def456abc123def456abcd" # v2.13.0' "$MISE_TOML" \
  || fail "mise.toml SKILLSPECTOR_REF sha+comment were not rewritten together"
grep -qF 'c7958a3268d9498644b22edb75d0f051bbc8cbfc' "$MISE_TOML" \
  && fail "old SkillSpector commit sha still present in mise.toml"

# --- 7. "latest" (unpinned) tools are never touched -------------------------
for entry in 'shellcheck = "latest"' 'actionlint = "latest"' 'uv = "latest"' 'jq = "latest"'; do
  grep -qF "$entry" "$MISE_TOML" || fail "mise.toml '$entry' was modified or removed"
done
LATEST_LINES_AFTER="$(grep -cE '"latest"' "$MISE_TOML")"
[ "$LATEST_LINES_AFTER" = "$LATEST_LINES_BEFORE" ] \
  || fail "count of \"latest\" pins changed ($LATEST_LINES_BEFORE -> $LATEST_LINES_AFTER)"

# --- 8. --list reflects every rewrite, end to end ---------------------------
LIST_OUT="$(run_script --list)"
for row in 'zizmor	1.30.1	1.30.1	up-to-date' \
  'gitleaks	8.31.0	8.31.0	up-to-date' \
  'waza	0.39.0	0.39.0	up-to-date' \
  'agentsview	0.45.0	0.45.0	up-to-date' \
  'skillspector	2.13.0	2.13.0	up-to-date'; do
  printf '%s\n' "$LIST_OUT" | grep -qF "$row" \
    || fail "--list is missing expected row '$row' after applying every tool. Got:\n$LIST_OUT"
done

# --- 9. usage errors ----------------------------------------------------------
if run_script --apply not-a-real-tool >/dev/null 2>&1; then
  fail "--apply with an unknown tool name should fail"
fi
if run_script --apply >/dev/null 2>&1; then
  fail "--apply without a tool name should fail"
fi
if run_script >/dev/null 2>&1; then
  fail "running with no arguments should fail"
fi

echo "bump-pinned-tools tests passed"
