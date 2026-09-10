#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUGGEST="$ROOT_DIR/skills/to-walkthrough-video/scripts/suggest-zooms.mjs"
RENDER="$ROOT_DIR/skills/to-walkthrough-video/scripts/render-auto-zoom.mjs"
RECORD="$ROOT_DIR/skills/to-walkthrough-video/scripts/record.mjs"
SERVE="$ROOT_DIR/skills/to-walkthrough-video/examples/site/serve.mjs"

fail() {
  echo "to-walkthrough-video test failed: $*" >&2
  exit 1
}

[ -f "$SUGGEST" ] || fail "scripts/suggest-zooms.mjs is missing"
[ -f "$RENDER" ] || fail "scripts/render-auto-zoom.mjs is missing"
[ -f "$RECORD" ] || fail "scripts/record.mjs is missing"
[ -f "$SERVE" ] || fail "examples/site/serve.mjs is missing"

command -v node >/dev/null || fail "node is not on PATH"
command -v curl >/dev/null || fail "curl is not on PATH"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

set +e
node "$SUGGEST" >/dev/null 2>"$TMP_DIR/stderr"
status=$?
set -e
[ "$status" -eq 2 ] || fail "suggest-zooms with no args should exit 2, got $status"

set +e
node "$RENDER" >/dev/null 2>"$TMP_DIR/stderr"
status=$?
set -e
[ "$status" -eq 2 ] || fail "render-auto-zoom with no args should exit 2, got $status"

set +e
node "$RECORD" >/dev/null 2>"$TMP_DIR/stderr"
status=$?
set -e
[ "$status" -eq 2 ] || fail "record with no args should exit 2, got $status"

node "$SUGGEST" --help >"$TMP_DIR/help"
grep -q -- "--clicks" "$TMP_DIR/help" || fail "suggest-zooms --help missing --clicks"

# Skills are installed as symlinks; invoking through one must still run main().
ln -s "$ROOT_DIR/skills/to-walkthrough-video" "$TMP_DIR/skill-link"
node "$TMP_DIR/skill-link/scripts/record.mjs" --help >"$TMP_DIR/symlink-help" \
  || fail "record.mjs through a symlink should exit 0"
grep -q -- "--scenario" "$TMP_DIR/symlink-help" \
  || fail "record.mjs through a symlink printed nothing: main() did not run"

node "$RECORD" --help >"$TMP_DIR/record-help"
grep -q -- "--width" "$TMP_DIR/record-help" || fail "record --help missing --width"
grep -q -- "--pause-ms" "$TMP_DIR/record-help" || fail "record --help missing --pause-ms"
grep -q -- "--storage-state" "$TMP_DIR/record-help" || fail "record --help missing --storage-state"

node --input-type=module <<EOF || fail "record helper exports"
import { parseArgs, resolveViewport, resolvePauseMs } from "file://${RECORD}";

const fail = (message) => {
  console.error(message);
  process.exit(1);
};

const args = parseArgs([
  "--scenario", "s.json",
  "--out", "o.webm",
  "--width", "1920",
  "--height", "1081",
  "--pause-ms", "3000",
]);
if (args.width !== 1920 || args.height !== 1081 || args.pauseMs !== 3000) {
  fail("parseArgs flags");
}

for (const flag of ["--headed", "--live-zoom", "--keep-raw", "--channel"]) {
  let threw = false;
  try {
    parseArgs(flag === "--channel" ? [flag, "chrome"] : [flag]);
  } catch {
    threw = true;
  }
  if (!threw) {
    fail("parseArgs should reject " + flag);
  }
}

const vp = resolveViewport({}, {});
if (vp.width !== 1280 || vp.height !== 720) {
  fail("default viewport");
}
const odd = resolveViewport({}, { width: 1919, height: 601 });
if (odd.width !== 1920 || odd.height !== 602) {
  fail("odd viewport rounding");
}

if (resolvePauseMs({}, {}) !== 2500) {
  fail("default pause");
}
if (resolvePauseMs({ pause: 800 }, { pauseMs: 2500 }) !== 800) {
  fail("step pause");
}
if (resolvePauseMs({}, { pauseMs: 3000 }) !== 3000) {
  fail("state pause");
}
EOF

# --- credential and storage-state guards -------------------------------------

GIT_REPO="$TMP_DIR/repo"
mkdir -p "$GIT_REPO"
git -C "$GIT_REPO" init -b main >/dev/null
printf '{"cookies":[],"origins":[]}\n' >"$GIT_REPO/auth.json"

OUTSIDE_STATE="$TMP_DIR/auth-outside.json"
printf '{"cookies":[],"origins":[]}\n' >"$OUTSIDE_STATE"

IGNORED_REPO="$TMP_DIR/repo-ignored"
mkdir -p "$IGNORED_REPO"
git -C "$IGNORED_REPO" init -b main >/dev/null
printf 'auth.json\n' >"$IGNORED_REPO/.gitignore"
printf '{"cookies":[],"origins":[]}\n' >"$IGNORED_REPO/auth.json"

node --input-type=module <<EOF || fail "record guard behaviour"
import { parseArgs, storageStateProblems, validateScenario } from "file://${RECORD}";

const fail = (message) => {
  console.error(message);
  process.exit(1);
};

const args = parseArgs(["--scenario", "s.json", "--out", "o.webm", "--storage-state", "auth.json"]);
if (args.storageState !== "auth.json") {
  fail("parseArgs --storage-state");
}

// What a walkthrough types on camera is the author's call: a scenario that
// fills a login form is recorded, not refused.
const typesAPassword = {
  steps: [{ action: "type", label: "Password", text: "whatever-the-author-wants" }],
};
if (validateScenario(typesAPassword, {}).length !== 0) {
  fail("a demo scenario may type into a password field");
}
if (validateScenario({ password: "x", steps: [] }, {}).length !== 0) {
  fail("scenario fields are the author's business");
}

// auth mode still needs the assertion that proves the session survived.
const missingExpect = validateScenario({ steps: [] }, { authMode: true });
if (!missingExpect.some((p) => p.includes("auth.expect"))) {
  fail("auth mode should require auth.expect");
}
const wellFormed = { auth: { expect: { role: "button", name: "Account" } }, steps: [] };
if (validateScenario(wellFormed, { authMode: true }).length !== 0) {
  fail("a well-formed auth scenario should pass");
}

// A storage state that cannot be read is a refusal; where it lives is not.
if (storageStateProblems("${OUTSIDE_STATE}").length !== 0) {
  fail("a readable storage state should pass");
}
if (storageStateProblems("${GIT_REPO}/auth.json").length !== 0) {
  fail("a storage state inside a repository should not be refused");
}
if (!storageStateProblems("${TMP_DIR}/missing.json")[0].includes("--save-storage")) {
  fail("a missing storage state should point at the save command");
}
EOF

node --input-type=module <<EOF || fail "storage state warnings"
import { storageStateWarnings } from "file://${RECORD}";

const fail = (message) => {
  console.error(message);
  process.exit(1);
};

// A committable storage state is worth saying out loud, without blocking.
if (!storageStateWarnings("${GIT_REPO}/auth.json").some((w) => w.includes(".gitignore"))) {
  fail("a committable storage state should warn");
}
if (storageStateWarnings("${IGNORED_REPO}/auth.json").length !== 0) {
  fail("an ignored storage state should not warn");
}
if (storageStateWarnings("${OUTSIDE_STATE}").length !== 0) {
  fail("a storage state outside any repository should not warn");
}
EOF

node --input-type=module <<EOF || fail "effects and captions"
import {
  DEFAULT_CAPTION_LOCALE,
  EFFECT_DEFAULTS,
  captionFor,
  captionHtml,
  captionPosition,
  formatKeys,
  resolveCaptionLocale,
  resolveEffects,
  validateScenario,
} from "file://${RECORD}";

const fail = (message) => {
  console.error(message);
  process.exit(1);
};
const same = (a, b, what) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    fail(what + ": got " + JSON.stringify(a) + ", wanted " + JSON.stringify(b));
  }
};

// Every effect is on unless the scenario says otherwise, and an unlisted key
// keeps its default rather than switching off.
same(EFFECT_DEFAULTS, { zoom: true, cursor: true, captions: true }, "effect defaults");
same(resolveEffects({}), EFFECT_DEFAULTS, "no effects field");
same(resolveEffects({ effects: { zoom: false } }), { zoom: false, cursor: true, captions: true }, "partial effects");

for (const bad of [{ effects: [] }, { effects: null }, { effects: "none" }]) {
  let threw = false;
  try { resolveEffects(bad); } catch { threw = true; }
  if (!threw) {
    fail("effects must be an object of booleans: " + JSON.stringify(bad));
  }
}
if (!validateScenario({ effects: { bogus: true }, steps: [] })[0].includes("unknown effect")) {
  fail("an unknown effect should be refused before recording");
}
if (!validateScenario({ effects: { zoom: "yes" }, steps: [] })[0].includes("true or false")) {
  fail("a non-boolean effect should be refused");
}

// A press step carries no locator, so its keys are the only thing to check.
if (!validateScenario({ steps: [{ action: "press" }] })[0].includes("without keys")) {
  fail("a press step without keys should be refused before recording");
}
same(validateScenario({ steps: [{ action: "press", keys: "Enter" }] }), [], "a well-formed press step");

// A viewer reads their own keyboard, not Playwright's key syntax.
if (formatKeys("Meta+Shift+p") !== "\u2318 + \u21e7 + P") {
  fail("keycaps: " + formatKeys("Meta+Shift+p"));
}
if (formatKeys("Control+k") !== "Ctrl + K") {
  fail("keycaps: " + formatKeys("Control+k"));
}

// Generated wording follows the locale; anything unknown falls back to English.
if (resolveCaptionLocale({ captionLocale: "zh-TW" }) !== "zh-tw") {
  fail("zh-TW should resolve");
}
if (resolveCaptionLocale({ captionLocale: "fr" }) !== DEFAULT_CAPTION_LOCALE) {
  fail("an unknown locale should fall back");
}
if (resolveCaptionLocale({}) !== DEFAULT_CAPTION_LOCALE) {
  fail("no locale should fall back");
}

const click = { action: "click", role: "link", name: "More information" };
if (captionFor(click, "en") !== "Click More information") {
  fail("en click caption: " + captionFor(click, "en"));
}
if (captionFor(click, "zh-tw") !== "\u9ede\u64ca More information") {
  fail("zh-tw click caption: " + captionFor(click, "zh-tw"));
}
if (captionFor({ action: "type", text: "SSH" }, "en") !== "Type SSH") {
  fail("type caption");
}
if (captionFor({ action: "select", value: "English" }, "en") !== "Select English") {
  fail("select caption");
}
if (captionFor({ action: "press", keys: "Control+k" }, "en") !== "Press Ctrl + K") {
  fail("press caption: " + captionFor({ action: "press", keys: "Control+k" }, "en"));
}
if (captionFor({ action: "wait", ms: 100 }, "en") !== null) {
  fail("a wait step is not captioned");
}
if (captionFor({ ...click, caption: "anything at all" }, "zh-tw") !== "anything at all") {
  fail("a step caption overrides the generated one");
}

// Word order is not universal: Japanese puts the verb last.
if (captionFor(click, "ja") !== "More information \u3092\u30af\u30ea\u30c3\u30af") {
  fail("ja click caption: " + captionFor(click, "ja"));
}
if (captionFor({ action: "press", keys: "Control+k" }, "ja") !== "Ctrl + K \u3092\u62bc\u3059") {
  fail("ja press caption: " + captionFor({ action: "press", keys: "Control+k" }, "ja"));
}
if (resolveCaptionLocale({ captionLocale: "JA" }) !== "ja") {
  fail("a locale should resolve case-insensitively");
}

// The caption is page HTML, so what a scenario supplies has to be escaped.
if (!captionHtml('<img src=x onerror="boom">').includes("&lt;img")) {
  fail("caption html must escape markup");
}

// Auto-zoom crops around the click, so the caption has to travel with it.
const vp = { width: 1280, height: 720 };
same(captionPosition({ x: 350, y: 175 }, vp), { left: 350, top: 219 }, "caption under the target");
const low = captionPosition({ x: 350, y: 700 }, vp);
if (low.top >= 700) {
  fail("a target near the bottom should put the caption above it: " + JSON.stringify(low));
}
if (captionPosition({ x: 10, y: 300 }, vp).left !== 140) {
  fail("a target near the edge should keep the caption on screen");
}
if (captionPosition(null, vp).left !== 640) {
  fail("a step with no anchor should centre the caption");
}
EOF

# --- fixture site ------------------------------------------------------------

node "$SERVE" --port 0 >"$TMP_DIR/serve.log" 2>&1 &
SERVE_PID=$!
trap 'kill "$SERVE_PID" 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT

BASE=""
for _ in $(seq 1 50); do
  BASE="$(sed -n 's|.*listening on \(http://[^ ]*\)/|\1|p' "$TMP_DIR/serve.log")"
  [ -n "$BASE" ] && break
  sleep 0.1
done
[ -n "$BASE" ] || fail "fixture server did not report a port: $(cat "$TMP_DIR/serve.log")"

http_status() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@"
}

[ "$(http_status "$BASE/")" = "200" ] || fail "fixture public page should be served"
[ "$(http_status "$BASE/app")" = "302" ] || fail "fixture protected page should redirect without a cookie"
[ "$(http_status -H 'Cookie: walkthrough_session=1' "$BASE/app")" = "200" ] \
  || fail "fixture protected page should be served with a session cookie"
[ "$(http_status -d 'username=a&password=b' "$BASE/login")" = "302" ] || fail "fixture login should redirect"
curl -s -D- -o /dev/null --max-time 5 -d 'username=a&password=b' "$BASE/login" \
  | grep -qi '^set-cookie: walkthrough_session=' || fail "fixture login should set the session cookie"

kill "$SERVE_PID" 2>/dev/null || true
trap 'rm -rf "$TMP_DIR"' EXIT

jq_field() {
  node -e "const fs=require('fs'); const j=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); const path=process.argv[2].split('.'); let v=j; for (const k of path) v=v[k]; if (v===undefined||v===null) process.exit(1); process.stdout.write(String(v));" "$@"
}

# single isolated click → one region padded ±500ms
cat >"$TMP_DIR/one.jsonl" <<'EOF'
{"t": 5000, "action": "click", "button": "left", "cx": 0.4, "cy": 0.3}
EOF
node "$SUGGEST" --clicks "$TMP_DIR/one.jsonl" --duration-ms 30000 --out "$TMP_DIR/one.zooms.json"
[ "$(jq_field "$TMP_DIR/one.zooms.json" status)" = "ok" ] || fail "single click status"
[ "$(jq_field "$TMP_DIR/one.zooms.json" suggestions.0.start)" = "4500" ] || fail "single click start"
[ "$(jq_field "$TMP_DIR/one.zooms.json" suggestions.0.end)" = "5500" ] || fail "single click end"
[ "$(jq_field "$TMP_DIR/one.zooms.json" suggestions.0.scale)" = "1.5" ] || fail "single click scale"

# clicks 2499ms apart merge; 2501ms apart split
cat >"$TMP_DIR/merge.jsonl" <<'EOF'
{"t": 4000, "action": "click", "cx": 0.5, "cy": 0.5}
{"t": 6499, "action": "click", "cx": 0.5, "cy": 0.5}
EOF
node "$SUGGEST" --clicks "$TMP_DIR/merge.jsonl" --duration-ms 30000 --out "$TMP_DIR/merge.zooms.json"
[ "$(jq_field "$TMP_DIR/merge.zooms.json" suggestions.0.start)" = "3500" ] || fail "merged start"
[ "$(jq_field "$TMP_DIR/merge.zooms.json" suggestions.0.end)" = "6999" ] || fail "merged end"
COUNT="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).suggestions.length)" "$TMP_DIR/merge.zooms.json")"
[ "$COUNT" = "1" ] || fail "expected 1 merged region, got $COUNT"

cat >"$TMP_DIR/split.jsonl" <<'EOF'
{"t": 3000, "action": "click", "cx": 0.5, "cy": 0.5}
{"t": 5501, "action": "click", "cx": 0.5, "cy": 0.5}
EOF
node "$SUGGEST" --clicks "$TMP_DIR/split.jsonl" --duration-ms 30000 --out "$TMP_DIR/split.zooms.json"
COUNT="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).suggestions.length)" "$TMP_DIR/split.zooms.json")"
[ "$COUNT" = "2" ] || fail "expected 2 split regions, got $COUNT"

# chained clicks 2000ms apart become one region, start clamped to 0
cat >"$TMP_DIR/chain.jsonl" <<'EOF'
{"t": 0, "action": "click", "cx": 0.2, "cy": 0.2}
{"t": 2000, "action": "click", "cx": 0.2, "cy": 0.2}
{"t": 4000, "action": "click", "cx": 0.2, "cy": 0.2}
EOF
node "$SUGGEST" --clicks "$TMP_DIR/chain.jsonl" --duration-ms 30000 --out "$TMP_DIR/chain.zooms.json"
[ "$(jq_field "$TMP_DIR/chain.zooms.json" suggestions.0.start)" = "0" ] || fail "chained start clamp"
[ "$(jq_field "$TMP_DIR/chain.zooms.json" suggestions.0.end)" = "4500" ] || fail "chained end"

# moves only → no-interactions
cat >"$TMP_DIR/moves.jsonl" <<'EOF'
{"t": 0, "action": "move", "cx": 0.5, "cy": 0.5}
{"t": 1000, "action": "move", "cx": 0.6, "cy": 0.6}
EOF
node "$SUGGEST" --clicks "$TMP_DIR/moves.jsonl" --duration-ms 30000 --out "$TMP_DIR/moves.zooms.json"
[ "$(jq_field "$TMP_DIR/moves.zooms.json" status)" = "no-interactions" ] || fail "moves-only should be no-interactions"

# right-click is explicit; double-click pair within 350ms stays one cluster
cat >"$TMP_DIR/right.jsonl" <<'EOF'
{"t": 5000, "action": "click", "button": "right", "cx": 0.5, "cy": 0.5}
EOF
node "$SUGGEST" --clicks "$TMP_DIR/right.jsonl" --duration-ms 30000 --out "$TMP_DIR/right.zooms.json"
[ "$(jq_field "$TMP_DIR/right.zooms.json" status)" = "ok" ] || fail "right-click should zoom"

cat >"$TMP_DIR/dbl.jsonl" <<'EOF'
{"t": 5000, "action": "click", "cx": 0.5, "cy": 0.5}
{"t": 5200, "action": "click", "cx": 0.51, "cy": 0.5}
EOF
node "$SUGGEST" --clicks "$TMP_DIR/dbl.jsonl" --duration-ms 30000 --out "$TMP_DIR/dbl.zooms.json"
COUNT="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).suggestions.length)" "$TMP_DIR/dbl.zooms.json")"
[ "$COUNT" = "1" ] || fail "double-click pair should be one region, got $COUNT"

# bounding-box fields on a click are ignored by clustering
cat >"$TMP_DIR/boxed.jsonl" <<'EOF'
{"t": 5000, "action": "click", "cx": 0.4, "cy": 0.3, "x": 100, "y": 80, "w": 160, "h": 40}
EOF
node "$SUGGEST" --clicks "$TMP_DIR/boxed.jsonl" --duration-ms 30000 --out "$TMP_DIR/boxed.zooms.json"
[ "$(jq_field "$TMP_DIR/boxed.zooms.json" suggestions.0.start)" = "4500" ] || fail "boxed click start"

# JSON array input
printf '%s\n' '[{"timeMs":8000,"interactionType":"click","cx":0.5,"cy":0.5}]' >"$TMP_DIR/array.json"
node "$SUGGEST" --clicks "$TMP_DIR/array.json" --duration-ms 20000 --out "$TMP_DIR/array.zooms.json"
[ "$(jq_field "$TMP_DIR/array.zooms.json" suggestions.0.start)" = "7500" ] || fail "JSON array start"

if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  echo "to-walkthrough-video tests passed (suggest-zooms; ffmpeg not on PATH, render skipped)"
  exit 0
fi

ffmpeg -hide_banner -loglevel error -y -f lavfi -i "color=c=blue:s=1280x720:d=3:r=30" \
  -c:v libx264 -pix_fmt yuv420p "$TMP_DIR/src.mp4" \
  || fail "failed to create synthetic source video"

cat >"$TMP_DIR/render.clicks.jsonl" <<'EOF'
{"t": 1000, "action": "click", "cx": 0.35, "cy": 0.4}
EOF

node "$RENDER" --video "$TMP_DIR/src.mp4" --clicks "$TMP_DIR/render.clicks.jsonl" --out "$TMP_DIR/out.mp4" \
  >"$TMP_DIR/render.json" || fail "render-auto-zoom failed: $(cat "$TMP_DIR/render.json" 2>/dev/null || true)"

[ -s "$TMP_DIR/out.mp4" ] || fail "render-auto-zoom wrote an empty file"

PROBE="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -show_entries format=duration -of csv=p=0 "$TMP_DIR/out.mp4")"
echo "$PROBE" | grep -q '1280,720' || fail "rendered video is not 1280x720: $PROBE"
DUR="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$TMP_DIR/out.mp4")"
node -e "const d=Number(process.argv[1]); if (!(d>=2.5 && d<=3.5)) process.exit(1)" "$DUR" \
  || fail "rendered duration $DUR not ~3s"

echo "to-walkthrough-video tests passed"
