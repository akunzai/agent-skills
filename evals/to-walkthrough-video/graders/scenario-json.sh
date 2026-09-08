#!/usr/bin/env bash
set -euo pipefail

ws="${WAZA_WORKSPACE_DIR:?WAZA_WORKSPACE_DIR is unset}"
cd "$ws"

if [[ ! -f scenario.json ]]; then
  echo "scenario.json is missing" >&2
  exit 1
fi

node --input-type=module <<'EOF'
import fs from "node:fs";

const fail = (message) => {
  console.error(message);
  process.exit(1);
};

let doc;
try {
  doc = JSON.parse(fs.readFileSync("scenario.json", "utf8"));
} catch (error) {
  fail(`scenario.json is not JSON: ${error.message}`);
}

if (!doc || typeof doc !== "object" || Array.isArray(doc)) {
  fail("scenario.json must be an object");
}
if (typeof doc.url !== "string" || !doc.url.includes("example.com")) {
  fail("scenario.json needs url pointing at example.com");
}
if (!Array.isArray(doc.steps) || doc.steps.length < 4) {
  fail("scenario.json needs at least 4 steps");
}

const actions = doc.steps.map((step) => step.action ?? (step.wait !== undefined ? "wait" : "click"));
if (!actions.includes("wait")) {
  fail("missing wait step");
}
if (!actions.includes("click")) {
  fail("missing click step");
}
if (!actions.includes("type")) {
  fail("missing type step");
}
if (!actions.includes("select")) {
  fail("missing select step");
}

const typed = doc.steps.find((step) => (step.action ?? "") === "type");
if (!typed || String(typed.text ?? "") !== "SSH") {
  fail("type step must type SSH");
}

const selected = doc.steps.find((step) => (step.action ?? "") === "select");
const value = selected?.value ?? selected?.option ?? selected?.label;
if (String(value ?? "") !== "English") {
  fail("select step must choose English");
}

const more = doc.steps.find((step) => String(step.name ?? step.text ?? "").includes("More information"));
if (!more) {
  fail("missing More information locator");
}
EOF
