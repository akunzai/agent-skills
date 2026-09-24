#!/usr/bin/env bash
set -euo pipefail

# The Waza `documents` grader decides whether a live Copilot run passed, so a
# defect in it reads as a flaky skill. These cases pin its contract offline: a
# compliant workspace passes, a document mixing languages passes too, and every
# failing assertion is reported in one run rather than the first one
# encountered.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADER="$ROOT_DIR/evals/setup-agent-ready-repo/graders/documents.sh"

fail() {
  echo "setup-agent-ready-repo-grader test failed: $*" >&2
  exit 1
}

[ -f "$GRADER" ] || fail "Grader $GRADER is missing"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- the guarantee list is well formed, and true of the templates it cites ---
# Without this the list could promise something no template pins, and every
# document would read as behind on a guarantee that never existed.
GUARANTEES="$ROOT_DIR/skills/setup-agent-ready-repo/references/guarantees.tsv"
TEMPLATES="$ROOT_DIR/skills/setup-agent-ready-repo/references/templates"
[ -f "$GUARANTEES" ] || fail "guarantee list $GUARANTEES is missing"

rows=0
while IFS=$'\t' read -r doc name pattern origin; do
  case "$doc" in \#*|"") continue ;; esac
  rows=$((rows + 1))
  [ -n "$name" ] && [ -n "$pattern" ] && [ -n "$origin" ] \
    || fail "guarantee '$doc/$name' has an empty field"
  # The origin column already names the template file; reading it from there
  # keeps the document-to-template mapping in one place.
  template="$TEMPLATES/${origin%%,*}"
  [ -f "$template" ] || fail "guarantee '$name' cites a template that does not exist: $origin"
  grep -qiE "$pattern" "$template" \
    || fail "guarantee '$name' matches nothing in $(basename "$template")"
done < "$GUARANTEES"
[ "$rows" -gt 0 ] || fail "guarantee list has no rows"

# --- a workspace holding what the skill promises to write ---
WS="$TMP_DIR/pass"
mkdir -p "$WS/docs/agents"

cat > "$WS/AGENTS.md" <<'DOC'
# Fixture Storefront

## Pointers

- When filing or triaging an issue, read `docs/agents/issue-tracker.md`
- When opening a pull or merge request, read `docs/agents/pull-request.md`
- Before running or reporting verification, read `docs/agents/verification.md`
DOC

cat > "$WS/docs/agents/issue-tracker.md" <<'DOC'
# Issue tracker: GitHub

Write issue titles and descriptions in **Traditional Chinese** (`繁體中文`).

Use the `gh` CLI: `gh issue create --title "..." --body "..."`.

## Description shape

Close with a collapsed technical section:

<details>
<summary>Technical details</summary>

repro commands, log excerpts

</details>

## Labels

Read this repo's own labels with `gh label list --limit 100`; invent none.

## Spec issues

## Acceptance criteria

- [ ] a checkable statement about observable behaviour

No personally identifiable information in any attachment.
DOC

cat > "$WS/docs/agents/pull-request.md" <<'DOC'
# Pull requests

Write pull request titles and descriptions in **Traditional Chinese**
(`繁體中文`). Git commit messages are English, imperative, subject under 72
characters.

Open the request with `gh pr create`, and never without the developer asking.
Update it with `gh pr edit`.

## Description shape

| Change | Visual |
| --- | --- |
| Flow or state transition | Mermaid `flowchart` |

No personally identifiable information in any attachment.

## Tests land with the behaviour

- **Product logic**: `src/`.
- **Exempt**: documentation and CI configuration.

## Review readiness

Where only a deployed environment can verify, open the request as a draft
(`gh pr create --draft`), then mark it ready.
DOC

cat > "$WS/docs/agents/verification.md" <<'DOC'
# Verification

```sh
npm test
```

<!-- drift:forge github -->
<!-- drift:entrypoint-cmd npm test -->

**Proof it ran**: the command exits zero.

## Human prerequisites

- [ ] Install Node.

## Capturing evidence

This document is where the capture rules live.

- UI locale: **`zh-TW`**. Browser automation defaults to `en-US`, so set it on every capture.

## Not verified

- The Docker Compose stack: Docker is unavailable here, so it was not verified.

A gap you could have closed is not a gap. Run the check whose dependency
you have already seen running, and report a check you skipped as untried,
rather than recording it here as one this repo cannot run.
DOC

if ! WAZA_WORKSPACE_DIR="$WS" bash "$GRADER" 2>"$TMP_DIR/pass.err"; then
  fail "compliant workspace was rejected: $(cat "$TMP_DIR/pass.err")"
fi
[ ! -s "$TMP_DIR/pass.err" ] || fail "compliant workspace produced output: $(cat "$TMP_DIR/pass.err")"

# --- an @path pointer is a defect, even when the path is present ---
WS_AT="$TMP_DIR/at-pointer"
cp -R "$WS" "$WS_AT"
cat > "$WS_AT/AGENTS.md" <<'DOC'
# Fixture Storefront

## Pointers

- Issue tracker: @docs/agents/issue-tracker.md
- Pull requests: @docs/agents/pull-request.md
- Verification: @docs/agents/verification.md
DOC

if WAZA_WORKSPACE_DIR="$WS_AT" bash "$GRADER" 2>"$TMP_DIR/at.err"; then
  fail "an AGENTS.md with @path pointers was accepted"
fi
grep -q "still has an @docs/agents/issue-tracker.md pointer" "$TMP_DIR/at.err" \
  || fail "@path pointer was rejected without naming the pointer: $(cat "$TMP_DIR/at.err")"

# --- a localized UI captured in the automation's default en-US is named ---
WS_LOCALE="$TMP_DIR/locale"
cp -R "$WS" "$WS_LOCALE"
sed -i.bak 's/^- UI locale: .*/- UI locale: not applicable, the UI has one language./' \
  "$WS_LOCALE/docs/agents/verification.md"
if WAZA_WORKSPACE_DIR="$WS_LOCALE" bash "$GRADER" 2>"$TMP_DIR/locale.err"; then
  fail "a verification.md with no capture locale for a localized UI was accepted"
fi
grep -q "does not record zh-TW as the UI locale" "$TMP_DIR/locale.err" \
  || fail "missing capture locale was rejected without naming it: $(cat "$TMP_DIR/locale.err")"

# --- the ticket language beside the template's English sentences is accepted ---
WS_MIXED="$TMP_DIR/mixed"
cp -R "$WS" "$WS_MIXED"
cat >> "$WS_MIXED/docs/agents/issue-tracker.md" <<'DOC'

標籤：個資與資安議題。
DOC
if ! WAZA_WORKSPACE_DIR="$WS_MIXED" bash "$GRADER" 2>"$TMP_DIR/mixed.err"; then
  fail "a document mixing English and Chinese was rejected: $(cat "$TMP_DIR/mixed.err")"
fi

# --- the request CLI survives deleting the optional sections, and a document
# that loses it anyway is named by the grader and --check alike ---
# The attach line and the deployed-only draft are both sections a repo may
# delete; the Preparing line naming the CLI is not.
WS_CLI="$TMP_DIR/cli"
cp -R "$WS" "$WS_CLI"
grep -v -e 'draft' "$WS/docs/agents/pull-request.md" \
  > "$WS_CLI/docs/agents/pull-request.md"
if ! WAZA_WORKSPACE_DIR="$WS_CLI" bash "$GRADER" 2>"$TMP_DIR/cli.err"; then
  fail "deleting the deployed-only draft section lost the gh CLI: $(cat "$TMP_DIR/cli.err")"
fi
grep -v 'gh pr' "$WS/docs/agents/pull-request.md" > "$WS_CLI/docs/agents/pull-request.md"
if WAZA_WORKSPACE_DIR="$WS_CLI" bash "$GRADER" 2>"$TMP_DIR/cli.err"; then
  fail "a pull-request.md naming no CLI command was accepted"
fi
grep -q "does not use the gh CLI" "$TMP_DIR/cli.err" \
  || fail "a missing gh CLI was rejected without naming it: $(cat "$TMP_DIR/cli.err")"
"$ROOT_DIR/skills/setup-agent-ready-repo/scripts/install-templates.sh" --check "$WS_CLI" \
  >"$TMP_DIR/cli-check.out" 2>&1 || true
grep -q "the CLI that opens and updates requests" "$TMP_DIR/cli-check.out" \
  || fail "--check did not report the lost request CLI the grader rejects: $(cat "$TMP_DIR/cli-check.out")"

# --- "the `gh` CLI" names the CLI as well as a full command does ---
# shellcheck disable=SC2016  # backticks are literal, not command substitution
printf '%s\n' 'Use the `gh` CLI for every request.' >>"$WS_CLI/docs/agents/pull-request.md"
if WAZA_WORKSPACE_DIR="$WS_CLI" bash "$GRADER" 2>"$TMP_DIR/cli.err"; then
  :
elif grep -q "does not use the gh CLI" "$TMP_DIR/cli.err"; then
  fail "the gh CLI named in backticks was not recognised: $(cat "$TMP_DIR/cli.err")"
fi

# --- every failing assertion is reported, not just the first ---
WS_MULTI="$TMP_DIR/multi"
cp -R "$WS" "$WS_MULTI"
# Drop the diagram table, the exempt paths, and the drift:forge marker.
grep -v -e 'Mermaid' -e 'Exempt' "$WS/docs/agents/pull-request.md" \
  > "$WS_MULTI/docs/agents/pull-request.md"
grep -v 'drift:forge' "$WS/docs/agents/verification.md" \
  > "$WS_MULTI/docs/agents/verification.md"

if WAZA_WORKSPACE_DIR="$WS_MULTI" bash "$GRADER" 2>"$TMP_DIR/multi.err"; then
  fail "a workspace missing three guarantees was accepted"
fi
# Two of the three now come from the shared guarantee list and are reported by
# the name a developer reads there; the forge value stays the grader's own.
for expected in 'which diagram belongs to which change' \
  'the paths exempt from landing with tests' \
  'does not record GitHub as the forge'; do
  grep -q "$expected" "$TMP_DIR/multi.err" \
    || fail "grader stopped early; '$expected' never reported: $(cat "$TMP_DIR/multi.err")"
done

# --- an unresolved template placeholder is caught ---
WS_PLACEHOLDER="$TMP_DIR/placeholder"
cp -R "$WS" "$WS_PLACEHOLDER"
cat >> "$WS_PLACEHOLDER/docs/agents/pull-request.md" <<'DOC'

Write titles in **<language>**, and read them back with
`<gh | glab> pr view <number>`.
DOC

if WAZA_WORKSPACE_DIR="$WS_PLACEHOLDER" bash "$GRADER" 2>"$TMP_DIR/placeholder.err"; then
  fail "a document shipping <language> and <gh | glab> was accepted"
fi
grep -q "unresolved template placeholder" "$TMP_DIR/placeholder.err" \
  || fail "placeholder leak not reported: $(cat "$TMP_DIR/placeholder.err")"

# `gh issue view <number>` is a sample command, not a leaked placeholder.
WS_SAMPLE="$TMP_DIR/sample"
cp -R "$WS" "$WS_SAMPLE"
cat >> "$WS_SAMPLE/docs/agents/pull-request.md" <<'DOC'

Read it with `gh pr view <number> --comments`.
DOC
if ! WAZA_WORKSPACE_DIR="$WS_SAMPLE" bash "$GRADER" 2>"$TMP_DIR/sample.err"; then
  fail "an angle placeholder inside a sample command was rejected: $(cat "$TMP_DIR/sample.err")"
fi

# --- an inline `placeholder:name` span is an unresolved placeholder too ---
WS_PH="$TMP_DIR/placeholder-marker"
cp -R "$WS" "$WS_PH"
# shellcheck disable=SC2016  # backticks are literal, not command substitution
cat >> "$WS_PH/docs/agents/issue-tracker.md" <<'DOC'

Issues live as `placeholder:forge` issues.
DOC
if WAZA_WORKSPACE_DIR="$WS_PH" bash "$GRADER" 2>"$TMP_DIR/ph.err"; then
  fail "an unresolved \`placeholder:name\` span was accepted"
fi
grep -q "unresolved template placeholder" "$TMP_DIR/ph.err" \
  || fail "placeholder span leak not reported: $(cat "$TMP_DIR/ph.err")"

# --- the template's own author-facing mention of the convention is not a
# leaked placeholder itself ---
WS_PH_COMMENT="$TMP_DIR/placeholder-comment"
cp -R "$WS" "$WS_PH_COMMENT"
# shellcheck disable=SC2016  # backticks are literal, not command substitution
{
  printf '<!-- Replace every inline `placeholder` span. -->\n'
  cat "$WS/docs/agents/issue-tracker.md"
} > "$WS_PH_COMMENT/docs/agents/issue-tracker.md"
if ! WAZA_WORKSPACE_DIR="$WS_PH_COMMENT" bash "$GRADER" 2>"$TMP_DIR/ph-comment.err"; then
  fail "the template's own author instructions were flagged as an unresolved placeholder: $(cat "$TMP_DIR/ph-comment.err")"
fi

# --- a missing document is reported alone, without cascading ---
WS_GONE="$TMP_DIR/missing"
cp -R "$WS" "$WS_GONE"
rm "$WS_GONE/docs/agents/pull-request.md"

if WAZA_WORKSPACE_DIR="$WS_GONE" bash "$GRADER" 2>"$TMP_DIR/gone.err"; then
  fail "a workspace missing pull-request.md was accepted"
fi
grep -q "docs/agents/pull-request.md is missing" "$TMP_DIR/gone.err" \
  || fail "missing document was not reported: $(cat "$TMP_DIR/gone.err")"
[ "$(wc -l < "$TMP_DIR/gone.err")" -eq 1 ] \
  || fail "missing document cascaded into other assertions: $(cat "$TMP_DIR/gone.err")"

# --- a markdown link is not the pinned shape ---
WS_MD="$TMP_DIR/md-link"
cp -R "$WS" "$WS_MD"
cat > "$WS_MD/AGENTS.md" <<'DOC'
# Fixture Storefront

## Pointers

- When filing or triaging an issue, read [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md)
- When opening a pull or merge request, read [`docs/agents/pull-request.md`](docs/agents/pull-request.md)
- Before running or reporting verification, read [`docs/agents/verification.md`](docs/agents/verification.md)
DOC

if WAZA_WORKSPACE_DIR="$WS_MD" bash "$GRADER" 2>"$TMP_DIR/md.err"; then
  fail "an AGENTS.md with markdown-link pointers was accepted"
fi
grep -q "has a markdown link to docs/agents/issue-tracker.md" "$TMP_DIR/md.err" \
  || fail "markdown-link pointer was rejected without naming it: $(cat "$TMP_DIR/md.err")"

# --- a backtick path without read is not the pinned shape ---
WS_NO_READ="$TMP_DIR/no-read"
cp -R "$WS" "$WS_NO_READ"
cat > "$WS_NO_READ/AGENTS.md" <<'DOC'
# Fixture Storefront

## Pointers

- Issue tracker: `docs/agents/issue-tracker.md`
- Pull requests: `docs/agents/pull-request.md`
- Verification: `docs/agents/verification.md`
DOC

if WAZA_WORKSPACE_DIR="$WS_NO_READ" bash "$GRADER" 2>"$TMP_DIR/noread.err"; then
  fail "an AGENTS.md with backtick paths but no read trigger was accepted"
fi
grep -q "has no read \`docs/agents/issue-tracker.md\` pointer" "$TMP_DIR/noread.err" \
  || fail "missing read trigger was rejected without naming it: $(cat "$TMP_DIR/noread.err")"

# --- a nested docs/agents/AGENTS.md is a defect ---
WS_NESTED="$TMP_DIR/nested"
cp -R "$WS" "$WS_NESTED"
cat > "$WS_NESTED/docs/agents/AGENTS.md" <<'DOC'
# Nested
DOC

if WAZA_WORKSPACE_DIR="$WS_NESTED" bash "$GRADER" 2>"$TMP_DIR/nested.err"; then
  fail "a nested docs/agents/AGENTS.md was accepted"
fi
grep -q "wrote nested docs/agents/AGENTS.md" "$TMP_DIR/nested.err" \
  || fail "nested AGENTS.md was rejected without naming it: $(cat "$TMP_DIR/nested.err")"

echo "setup-agent-ready-repo-grader tests passed"
