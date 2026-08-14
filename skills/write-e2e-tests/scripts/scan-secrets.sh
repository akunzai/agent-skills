#!/usr/bin/env bash
set -euo pipefail

# Scan a webwright script or Playwright spec for credential literals.
# Usage: scan-secrets.sh FILE
# Prints file:line:category (never the matched text). Exit 1 on hits, 2 on usage.

if [[ $# -ne 1 ]]; then
  echo "Usage: scan-secrets.sh FILE" >&2
  exit 2
fi

FILE=$1

if [[ ! -f $FILE ]]; then
  echo "Error: '$FILE' is not a file." >&2
  exit 2
fi

matches() {
  local text=$1
  local pattern=$2
  printf '%s\n' "$text" | grep -E -q -- "$pattern"
}

matches_i() {
  local text=$1
  local pattern=$2
  printf '%s\n' "$text" | grep -E -qi -- "$pattern"
}

# High-confidence shapes. Categories are the report vocabulary tests lock.
# Patterns live only here — references/security.md does not duplicate them.
declare -a SHAPE_NAMES=(
  openai_key
  github_token
  aws_access_key
  pem_private_key
  bearer_token
  connection_string
)
declare -a SHAPE_PATTERNS=(
  'sk-proj-[A-Za-z0-9_-]{32,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}'
  'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[ours]_[A-Za-z0-9]{20,}'
  'AKIA[0-9A-Z]{16}'
  '-----BEGIN [A-Z ]{0,}PRIVATE KEY-----'
  '[Bb]earer[[:space:]]+[A-Za-z0-9._~+/-]{20,}'
  '(postgres|postgresql|mongodb(\+srv)?|mysql)://[^[:space:]/:]+:[^@[:space:]]+@'
)

ASSIGNMENT_PATTERN='(^|[^A-Za-z0-9_])(password|token|secret|api[_-]?key|apikey)[[:space:]]*[:=][[:space:]]*['\''"][^'\''"]+['\''"]'
FIELD_NAME_PATTERN='password|token|secret'
TWO_ARG_LITERAL='(\.|[[:alnum:]_])(fill|type)\([[:space:]]*['\''"][^'\''"]+['\''"][[:space:]]*,[[:space:]]*['\''"][^'\''"]+['\''"]'
ONE_ARG_LITERAL='\.(fill|type)\([[:space:]]*['\''"][^'\''"]+['\''"][[:space:]]*\)'

hits=0
line_no=0

while IFS= read -r line || [[ -n $line ]]; do
  line_no=$((line_no + 1))

  idx=0
  while [[ $idx -lt ${#SHAPE_NAMES[@]} ]]; do
    if matches "$line" "${SHAPE_PATTERNS[$idx]}"; then
      printf '%s:%s:%s\n' "$FILE" "$line_no" "${SHAPE_NAMES[$idx]}"
      hits=$((hits + 1))
    fi
    idx=$((idx + 1))
  done

  if matches_i "$line" "$ASSIGNMENT_PATTERN"; then
    printf '%s:%s:%s\n' "$FILE" "$line_no" credential_assignment
    hits=$((hits + 1))
  fi

  if matches_i "$line" "$FIELD_NAME_PATTERN" \
    && { matches "$line" "$TWO_ARG_LITERAL" || matches "$line" "$ONE_ARG_LITERAL"; }; then
    printf '%s:%s:%s\n' "$FILE" "$line_no" password_field_literal
    hits=$((hits + 1))
  fi
done <"$FILE"

if [[ $hits -gt 0 ]]; then
  exit 1
fi
exit 0
