#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT="$ROOT_DIR/evals/fixtures/api"

fail() {
  echo "api fixture check failed: $*" >&2
  exit 1
}

sha256_file() {
  local path="$1"
  printf 'sha256:%s' "$(shasum -a 256 "$path" | awk '{print $1}')"
}

is_repo_relative_path() {
  case "$1" in
    ""|/*|../*|*/../*|*/..|./*|*/./*) return 1 ;;
  esac
}

[ -d "$FIXTURE_ROOT" ] || fail "API fixture root is missing"

mapfile -t manifests < <(find "$FIXTURE_ROOT" -mindepth 3 -maxdepth 3 -type f -name fixture.json -print | sort)
[ "${#manifests[@]}" -gt 0 ] || fail "no API fixture manifests found"

for manifest in "${manifests[@]}"; do
  fixture_dir="$(dirname "$manifest")"
  fixture_id="$(jq -r '.fixture_id // empty' "$manifest")"
  expected_fixture_id="${fixture_dir#"$FIXTURE_ROOT"/}"
  [ -n "$fixture_id" ] || fail "$manifest must define fixture_id"
  [ "$fixture_id" = "$expected_fixture_id" ] \
    || fail "$manifest fixture_id must match its directory"

  jq -e '
    .schema_version == 1
    and (.fixture_revision | type == "string" and length > 0)
    and (.task.revision | type == "string" and length > 0)
    and (.skill.name | type == "string" and test("^[a-z0-9][a-z0-9-]*$"))
    and (.skill.revision | type == "string" and length > 0)
    and (.rubric.revision | type == "string" and length > 0)
    and (.conditions.treatment | type == "object")
    and (.conditions.control | type == "object")
    and (.deterministic_checks | type == "array" and length > 0)
    and ([.deterministic_checks[] | type == "string" and length > 0] | all)
  ' "$manifest" >/dev/null || fail "$manifest metadata is incomplete"

  task_path="$(jq -r '.task.path' "$manifest")"
  skill_path="$(jq -r '.skill.path' "$manifest")"
  rubric_path="$(jq -r '.rubric.path' "$manifest")"
  for input_path in "$task_path" "$skill_path" "$rubric_path"; do
    is_repo_relative_path "$input_path" || fail "$manifest contains an unsafe path: $input_path"
    [ -f "$ROOT_DIR/$input_path" ] || fail "$manifest points to a missing file: $input_path"
    [ -s "$ROOT_DIR/$input_path" ] || fail "$manifest points to an empty file: $input_path"
  done

  [ "$(jq -r '.task.sha256' "$manifest")" = "$(sha256_file "$ROOT_DIR/$task_path")" ] \
    || fail "$manifest task hash is stale"
  [ "$(jq -r '.skill.sha256' "$manifest")" = "$(sha256_file "$ROOT_DIR/$skill_path")" ] \
    || fail "$manifest skill hash is stale"
  [ "$(jq -r '.rubric.sha256' "$manifest")" = "$(sha256_file "$ROOT_DIR/$rubric_path")" ] \
    || fail "$manifest rubric hash is stale"

  jq -e \
    --arg task_path "$task_path" \
    --arg skill_path "$skill_path" \
    --arg rubric_revision "$(jq -r '.rubric.revision' "$manifest")" '
      .conditions.treatment.task_path == $task_path
      and .conditions.control.task_path == $task_path
      and .conditions.treatment.skill_path == $skill_path
      and .conditions.control.skill_path == null
      and .conditions.treatment.rubric_revision == $rubric_revision
      and .conditions.control.rubric_revision == $rubric_revision
    ' "$manifest" >/dev/null || fail "$manifest treatment/control inputs are not paired"

  grep -Eq '(^|[[:space:]])/[[:alnum:]_.-]+' "$ROOT_DIR/$task_path" \
    && fail "$manifest task must not use slash invocation"
  grep -Eqi 'SKILL-CONTEXT|slash invocation|harness-specific activation' "$ROOT_DIR/$task_path" \
    && fail "$manifest task must be an ordinary natural-language input"

  jq -e \
    --arg rubric_path "$rubric_path" \
    --arg rubric_revision "$(jq -r '.rubric.revision' "$manifest")" '
      .rubric.path == $rubric_path
      and .rubric.revision == $rubric_revision
    ' "$manifest" >/dev/null || fail "$manifest rubric metadata is inconsistent"

  jq -e '
    .schema_version == 1
    and (.revision | type == "string" and length > 0)
    and (.checks | type == "array" and length > 0)
    and ([.checks[] |
      (.id | type == "string" and length > 0)
      and (.kind | type == "string" and length > 0)
      and (.bounded == true)
    ] | all)
    and ([.checks[].id] | length == (unique | length))
  ' "$ROOT_DIR/$rubric_path" >/dev/null || fail "$manifest rubric checks are invalid"

  jq -e \
    --slurpfile rubric "$ROOT_DIR/$rubric_path" '
      ([.deterministic_checks[] as $id |
        ($rubric[0].checks | map(select(.id == $id)) | length == 1)] | all)
    ' "$manifest" >/dev/null || fail "$manifest references a missing deterministic check"

  jq -e '
    ([.checks[] | select(.id == "required-response-structure")
      | .kind == "required_headings"
      and ([.headings[]] | index("Micromanagement Audit") != null)] | any)
    and ([.checks[] | select(.id == "grounded-findings")
      | .kind == "minimum_context_references"
      and (.minimum as $minimum
        | ($minimum | type == "number" and . >= 1)
        and (.terms | type == "array" and length >= $minimum))] | any)
    and ([.checks[] | select(.id == "no-invented-actions-or-state")
      | .kind == "forbid_regex"
      and (.patterns | type == "array" and length > 0)] | any)
  ' "$ROOT_DIR/$rubric_path" >/dev/null || fail "$manifest rubric misses required response checks"

  jq -e '
    (.artifact_policy.allowed_fields | type == "array" and length > 0)
    and (.artifact_policy.forbidden_fields | type == "array" and length > 0)
    and ([.artifact_policy.allowed_fields[] | type == "string" and length > 0] | all)
    and ([.artifact_policy.forbidden_fields[] | type == "string" and length > 0] | all)
    and (.artifact_policy.max_field_bytes | type == "number" and . > 0)
    and (.artifact_policy.max_artifact_bytes | type == "number" and . > 0)
    and ([.artifact_policy.allowed_fields[]
      | select(test("raw|transcript|request|stderr|authorization|credential|workspace"; "i"))]
      | length == 0)
    and ([.artifact_policy.forbidden_fields[]
      | select(test("raw_response|raw_transcript|authorization|credential|workspace"; "i"))]
      | length >= 3)
  ' "$manifest" >/dev/null || fail "$manifest artifact policy is missing bounds or redaction guards"
done

echo "API response-level fixture checks passed"
