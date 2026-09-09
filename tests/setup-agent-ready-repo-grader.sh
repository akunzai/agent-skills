#!/usr/bin/env bash
set -euo pipefail

# The Waza `documents` grader decides whether a live Copilot run passed, so a
# defect in it reads as a flaky skill. These cases pin its contract offline: a
# compliant workspace passes, a document translated out of English fails and
# says so, and every failing assertion is reported in one run rather than the
# first one encountered.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADER="$ROOT_DIR/evals/setup-agent-ready-repo/graders/documents.sh"

fail() {
  echo "setup-agent-ready-repo-grader test failed: $*" >&2
  exit 1
}

[ -f "$GRADER" ] || fail "Grader $GRADER is missing"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- a workspace holding what the skill promises to write ---
WS="$TMP_DIR/pass"
mkdir -p "$WS/docs/agents"

cat > "$WS/AGENTS.md" <<'DOC'
# Fixture Storefront

## Pointers

- Issue tracker: @docs/agents/issue-tracker.md
- Pull requests: @docs/agents/pull-request.md
- Verification: @docs/agents/verification.md
DOC

cat > "$WS/docs/agents/issue-tracker.md" <<'DOC'
# Issue tracker: GitHub

Write issue titles and descriptions in **Traditional Chinese** (繁體中文).
This file is English throughout, sample blocks included.

Use the `gh` CLI: `gh issue create --title "..." --body "..."`.

## Description shape

Close with a collapsed technical section:

<details>
<summary>Technical details</summary>

repro commands, log excerpts

</details>

## Spec issues

## Acceptance criteria

- [ ] a checkable statement about observable behaviour

No personally identifiable information in any attachment.
DOC

cat > "$WS/docs/agents/pull-request.md" <<'DOC'
# Pull requests

Write pull request titles and descriptions in **Traditional Chinese**
(繁體中文). Git commit messages are English, imperative, subject under 72
characters. This file is English throughout.

Open the request with `gh pr create`.

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

## Not verified

- The Docker Compose stack: Docker is unavailable here, so it was not verified.
DOC

if ! WAZA_WORKSPACE_DIR="$WS" bash "$GRADER" 2>"$TMP_DIR/pass.err"; then
  fail "compliant workspace was rejected: $(cat "$TMP_DIR/pass.err")"
fi
[ ! -s "$TMP_DIR/pass.err" ] || fail "compliant workspace produced output: $(cat "$TMP_DIR/pass.err")"

# --- a document translated out of English is named as such ---
WS_ZH="$TMP_DIR/translated"
cp -R "$WS" "$WS_ZH"
cat > "$WS_ZH/docs/agents/pull-request.md" <<'DOC'
# Pull requests

PR 的標題與描述請使用繁體中文。Git commit message 仍然使用英文。

使用 `gh pr create` 開啟 PR，必要時先開 draft。

## 描述結構

流程或狀態轉換：Mermaid `flowchart`。任何附件都不得含有個資。

## 測試

例外：文件與 CI 設定。
DOC

if WAZA_WORKSPACE_DIR="$WS_ZH" bash "$GRADER" 2>"$TMP_DIR/zh.err"; then
  fail "a pull-request.md written in Chinese was accepted"
fi
grep -q "pull-request.md is not English throughout" "$TMP_DIR/zh.err" \
  || fail "translated document was rejected without naming the language rule: $(cat "$TMP_DIR/zh.err")"

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
for expected in 'does not say which diagram' 'does not name the paths exempt' \
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

echo "setup-agent-ready-repo-grader tests passed"
