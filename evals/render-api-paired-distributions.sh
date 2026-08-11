#!/usr/bin/env bash
set -euo pipefail

RESULTS_PATH="${1:?usage: render-api-paired-distributions.sh RESULTS_PATH}"

jq -e '(.lift_distributions | type) == "array"' "$RESULTS_PATH" >/dev/null

echo
echo "| Target | Samples | Scored | Not scored | Median | Min | Max | Sign consistent |"
echo "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |"
jq -r '
  def shown: if . == null then "-" else tostring end;
  .lift_distributions[]
  | "| `" + .target_model + "` | "
    + (.sample_count | shown) + " | "
    + (.scored_sample_count | shown) + " | "
    + (.not_scored_sample_count | shown) + " | "
    + (.median | shown) + " | "
    + (.min | shown) + " | "
    + (.max | shown) + " | "
    + (.sign_consistent | shown) + " |"
' "$RESULTS_PATH"

echo
echo "| Target | Replicate | Status | Treatment | Control | Lift |"
echo "| --- | ---: | --- | ---: | ---: | ---: |"
jq -r '
  def shown: if . == null then "-" else tostring end;
  .lift_distributions[] as $distribution
  | $distribution.samples[]
  | "| `" + $distribution.target_model + "` | "
    + (.replicate_index | shown) + " | "
    + (.status | shown) + " | "
    + (.treatment_score | shown) + " | "
    + (.control_score | shown) + " | "
    + (.treatment_minus_control | shown) + " |"
' "$RESULTS_PATH"
