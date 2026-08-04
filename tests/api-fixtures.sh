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

assert_manifest_hash() {
  local manifest="$1"
  local manifest_key="$2"
  local path="$3"
  local label="$4"
  local expected_hash
  local actual_hash

  expected_hash="$(jq -r "$manifest_key" "$manifest")"
  actual_hash="$(sha256_file "$ROOT_DIR/$path")"
  [ "$expected_hash" = "$actual_hash" ] || fail "$manifest $label hash is stale"
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
    and (.conditions.treatment | type == "object"
      and has("task_path") and has("task_revision")
      and has("skill_path") and has("rubric_revision"))
    and (.conditions.control | type == "object"
      and has("task_path") and has("task_revision")
      and has("skill_path") and has("rubric_revision"))
    and (.deterministic_checks | type == "array" and length > 0)
    and ([.deterministic_checks[] | type == "string" and length > 0] | all)
  ' "$manifest" >/dev/null || fail "$manifest metadata is incomplete"

  skill_name="$(jq -r '.skill.name' "$manifest")"
  expected_skill_name="${expected_fixture_id%%/*}"
  [ "$skill_name" = "$expected_skill_name" ] \
    || fail "$manifest skill name must match its fixture directory"

  task_path="$(jq -r '.task.path' "$manifest")"
  skill_path="$(jq -r '.skill.path' "$manifest")"
  rubric_path="$(jq -r '.rubric.path' "$manifest")"
  for input_path in "$task_path" "$skill_path" "$rubric_path"; do
    is_repo_relative_path "$input_path" || fail "$manifest contains an unsafe path: $input_path"
    [ -f "$ROOT_DIR/$input_path" ] || fail "$manifest points to a missing file: $input_path"
    [ -s "$ROOT_DIR/$input_path" ] || fail "$manifest points to an empty file: $input_path"
  done
  [ "$task_path" != "$skill_path" ] || fail "$manifest must separate task and skill inputs"

  assert_manifest_hash "$manifest" '.task.sha256' "$task_path" task
  assert_manifest_hash "$manifest" '.skill.sha256' "$skill_path" skill
  assert_manifest_hash "$manifest" '.rubric.sha256' "$rubric_path" rubric

  jq -e \
    --arg task_path "$task_path" \
    --arg skill_path "$skill_path" \
    --arg task_revision "$(jq -r '.task.revision' "$manifest")" \
    --arg rubric_revision "$(jq -r '.rubric.revision' "$manifest")" '
      .conditions.treatment.task_path == $task_path
      and .conditions.control.task_path == $task_path
      and .conditions.treatment.task_revision == $task_revision
      and .conditions.control.task_revision == $task_revision
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
    --arg fixture_id "$fixture_id" \
    --arg rubric_revision "$(jq -r '.rubric.revision' "$manifest")" '
      .rubric.path == $rubric_path
      and .rubric.revision == $rubric_revision
    ' "$manifest" >/dev/null || fail "$manifest rubric metadata is inconsistent"

  jq -e '
    .schema_version == 1
    and (.rubric_id | type == "string" and length > 0)
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
    --arg fixture_id "$fixture_id" \
    --arg rubric_revision "$(jq -r '.rubric.revision' "$manifest")" \
    ' .rubric_id == $fixture_id and .revision == $rubric_revision ' \
    "$ROOT_DIR/$rubric_path" >/dev/null \
    || fail "$manifest rubric identity or revision does not match its manifest"

  jq -e \
    --slurpfile rubric "$ROOT_DIR/$rubric_path" '
      ([.deterministic_checks[] as $id |
        ($rubric[0].checks | map(select(.id == $id)) | length == 1)] | all)
    ' "$manifest" >/dev/null || fail "$manifest references a missing deterministic check"

  jq -e \
    --slurpfile rubric "$ROOT_DIR/$rubric_path" '
      def nonempty_strings:
        type == "array"
        and length > 0
        and all(.[]; type == "string" and length > 0);

      [
        .deterministic_checks[] as $id
        | ($rubric[0].checks[] | select(.id == $id))
        | if (.bounded != true or .field != "response_text") then
            false
          elif .kind == "required_headings" then
            (.headings | nonempty_strings)
          elif .kind == "minimum_context_references" then
            (.minimum as $minimum
              | ($minimum | type == "number" and . >= 1)
              and (.terms | nonempty_strings and length >= $minimum))
          elif .kind == "minimum_grounded_findings" then
            (.minimum | type == "number" and . >= 1)
            and (.per_item == true)
            and (.required_components | nonempty_strings)
            and (.required_components | index("context_reference") != null)
            and (.required_components | index("rationale") != null)
            and (.required_components | index("alternative") != null)
          elif .kind == "forbid_regex" then
            (.patterns | nonempty_strings)
            and (.regression_phrases | nonempty_strings)
          else
            false
          end
      ] | all
    ' "$manifest" >/dev/null \
    || fail "$manifest references an incomplete deterministic check"

  jq -e '
    any(.checks[];
      .kind == "required_headings"
      and (.headings | type == "array" and length > 0))
    and any(.checks[];
      .kind == "minimum_context_references"
      and (.minimum as $minimum
        | ($minimum | type == "number" and . >= 1)
        and (.terms | type == "array" and length >= $minimum)
        and ([.terms[] | type == "string" and length > 0] | all)))
    and any(.checks[];
      .kind == "minimum_grounded_findings"
      and (.minimum | type == "number" and . >= 1)
      and (.per_item == true)
      and (.required_components | type == "array" and length >= 1)
      and (.required_components | index("context_reference") != null)
      and (.required_components | index("rationale") != null)
      and (.required_components | index("alternative") != null))
    and any(.checks[];
      .kind == "forbid_regex"
      and (.patterns | type == "array" and length > 0)
      and ([.patterns[] | type == "string" and length > 0] | all)
      and (.regression_phrases | type == "array" and length > 0)
      and ([.regression_phrases[] | type == "string" and length > 0] | all))
    and any(.checks[];
      .kind == "required_headings"
      and ([.headings[] | type == "string" and length > 0] | all))
  ' "$ROOT_DIR/$rubric_path" >/dev/null || fail "$manifest rubric misses required response checks"

  jq -e '
    ([.checks[] | keys_unsorted[]
      | select(. != "id" and . != "kind" and . != "field"
        and . != "headings" and . != "terms" and . != "minimum"
        and . != "per_item" and . != "required_components"
        and . != "patterns" and . != "regression_phrases"
        and . != "bounded")]
      | length == 0)
    and ([.checks[].kind
      | select(. != "required_headings"
        and . != "minimum_context_references"
        and . != "minimum_grounded_findings"
        and . != "forbid_regex")]
      | length == 0)
    and ([.checks[] | .field] | all(. == "response_text"))
  ' "$ROOT_DIR/$rubric_path" >/dev/null \
    || fail "$manifest rubric must remain response-level and native-state free"

  jq -e '
    (.artifact_policy.allowed_fields | type == "array" and length > 0)
    and (.artifact_policy.forbidden_fields | type == "array" and length > 0)
    and ([.artifact_policy.allowed_fields[] | type == "string" and length > 0] | all)
    and ([.artifact_policy.forbidden_fields[] | type == "string" and length > 0] | all)
    and (.artifact_policy.max_field_bytes | type == "number" and . > 0)
    and (.artifact_policy.max_artifact_bytes | type == "number" and . > 0)
    and (.artifact_policy.max_field_bytes <= 4096)
    and (.artifact_policy.max_artifact_bytes <= 65536)
    and (.artifact_policy.allowed_fields - .artifact_policy.forbidden_fields
      == .artifact_policy.allowed_fields)
    and ([.artifact_policy.allowed_fields[]
      | select(test("raw|transcript|request|stderr|authorization|credential|workspace"; "i"))]
      | length == 0)
    and ([.artifact_policy.forbidden_fields[]
      | select(test("raw_response|raw_transcript|authorization|credential|workspace"; "i"))]
      | length >= 3)
  ' "$manifest" >/dev/null || fail "$manifest artifact policy is missing bounds or redaction guards"

  jq -e '
    [
      .checks[]
      | select(.kind == "forbid_regex")
      | . as $check
      | $check.regression_phrases[]
      | ([$check.patterns[] as $pattern | test($pattern)] | any)
    ] | (length > 0 and all)
  ' "$ROOT_DIR/$rubric_path" >/dev/null \
    || fail "$manifest invention guard regression phrases are not covered by their own patterns"
done

echo "API response-level fixture checks passed"
