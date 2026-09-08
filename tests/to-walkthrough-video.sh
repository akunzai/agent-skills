#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUGGEST="$ROOT_DIR/skills/to-walkthrough-video/scripts/suggest-zooms.mjs"
RENDER="$ROOT_DIR/skills/to-walkthrough-video/scripts/render-auto-zoom.mjs"
RECORD="$ROOT_DIR/skills/to-walkthrough-video/scripts/record.mjs"

fail() {
  echo "to-walkthrough-video test failed: $*" >&2
  exit 1
}

[ -f "$SUGGEST" ] || fail "scripts/suggest-zooms.mjs is missing"
[ -f "$RENDER" ] || fail "scripts/render-auto-zoom.mjs is missing"
[ -f "$RECORD" ] || fail "scripts/record.mjs is missing"

command -v node >/dev/null || fail "node is not on PATH"

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

node "$RECORD" --help >"$TMP_DIR/record-help"
grep -q -- "--width" "$TMP_DIR/record-help" || fail "record --help missing --width"
grep -q -- "--pause-ms" "$TMP_DIR/record-help" || fail "record --help missing --pause-ms"

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
