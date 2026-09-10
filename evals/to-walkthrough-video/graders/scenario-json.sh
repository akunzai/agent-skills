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

const problems = [];
const fail = (message) => {
  problems.push(message);
};

let doc;
try {
  doc = JSON.parse(fs.readFileSync("scenario.json", "utf8"));
} catch (error) {
  console.error(`scenario.json is not JSON: ${error.message}`);
  process.exit(1);
}

if (!doc || typeof doc !== "object" || Array.isArray(doc)) {
  console.error("scenario.json must be an object");
  process.exit(1);
}
if (typeof doc.url !== "string" || !doc.url.includes("example.com")) {
  fail("scenario.json needs url pointing at example.com");
}
if (!Array.isArray(doc.steps) || doc.steps.length < 5) {
  fail("scenario.json needs at least 5 steps");
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

// A keyboard shortcut acts on the page, so it is the one step with no locator.
const pressed = doc.steps.find((step) => (step.action ?? "") === "press");
if (!pressed) {
  fail("missing press step for the Ctrl+K shortcut");
} else if (!/control\+k/i.test(String(pressed.keys ?? ""))) {
  fail(
    "press keys must use Playwright syntax as the skill's example shows " +
      `(Control+k), not the human spelling: got ${JSON.stringify(pressed.keys ?? null)}`,
  );
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

// The brief says the site needs a sign-in, so the scenario must carry the
// assertion that proves the saved session is still alive.
const expect = doc.auth?.expect;
if (!expect || typeof expect !== "object") {
  fail("scenario.json needs auth.expect for a site that requires signing in");
} else if (!String(expect.name ?? expect.text ?? expect.label ?? expect.selector ?? "").includes("Account")) {
  fail("auth.expect must locate the Account control that only a signed-in user sees");
}

if (problems.length > 0) {
  console.error(problems.join("\n"));
  process.exit(1);
}
EOF
