# Credential handling

`scripts/scan-secrets.sh` is the only matcher. Run it on `final_script.py`
before converting, and on the drafted Playwright spec before writing the
file. A non-zero exit is a hard stop.

## On a hit

The script prints `file:line:category` and never prints secret values. For
each row, propose mapping that literal to `process.env.E2E_<ROLE>_<KIND>`
(for example `E2E_USER_PASSWORD`). Wait for explicit confirmation. Then
convert using those env names. Leaving a matched literal in the spec is
not a valid path; abort if the user declines the mapping.

## Writing rules

Put credential values in `process.env`. Keep selectors, labels, and
non-credential fixtures as literals. The output scan must exit 0 before
the spec is written.
