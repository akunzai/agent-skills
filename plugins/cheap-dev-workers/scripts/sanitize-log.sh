#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: sanitize-log.sh INPUT OUTPUT" >&2
  exit 64
fi

input="$1"
output="$2"
if [[ ! -f "$input" || -L "$input" || "$input" == "$output" ]]; then
  echo "Refusing unsupported input" >&2
  exit 65
fi

size="$(wc -c <"$input")"
if ((size > 10 * 1024 * 1024)); then
  echo "Refusing input above 10 MiB; split it at job or test-suite boundaries" >&2
  exit 65
fi
if ! iconv -f UTF-8 -t UTF-8 "$input" >/dev/null 2>&1; then
  echo "Refusing non-UTF-8 input" >&2
  exit 65
fi
without_nuls="$(tr -d '\000' <"$input" | wc -c)"
if [[ "$size" != "$without_nuls" ]]; then
  echo "Refusing binary input" >&2
  exit 65
fi
for tool in redact betterleaks; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Required hardening tool is unavailable: $tool" >&2
    exit 69
  }
done

output_dir="$(dirname "$output")"
[[ -d "$output_dir" ]] || {
  echo "Output directory does not exist" >&2
  exit 73
}
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/sanitized-log.XXXXXX")"
temporary="$temporary_dir/artifact.log"
cleanup() {
  rm -f "$temporary"
  rmdir "$temporary_dir"
}
trap cleanup EXIT

if ! redact --format text anonymize --strategy replace \
  <"$input" >"$temporary" 2>/dev/null; then
  echo "Log sanitization failed" >&2
  exit 70
fi
if ! env -u BETTERLEAKS_CONFIG betterleaks dir "$temporary" >/dev/null 2>&1; then
  echo "Residual-secret gate failed closed" >&2
  exit 70
fi

chmod 600 "$temporary"
mv "$temporary" "$output"
rmdir "$temporary_dir"
trap - EXIT
echo "Sanitized artifact ready: $output"
