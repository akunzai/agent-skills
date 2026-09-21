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

node "$TMP_DIR/skill-link/scripts/suggest-zooms.mjs" --help >"$TMP_DIR/suggest-symlink-help" \
  || fail "suggest-zooms.mjs through a symlink should exit 0"
grep -q -- "--clicks" "$TMP_DIR/suggest-symlink-help" \
  || fail "suggest-zooms.mjs through a symlink printed nothing: main() did not run"

node "$TMP_DIR/skill-link/scripts/render-auto-zoom.mjs" --help >"$TMP_DIR/render-symlink-help" \
  || fail "render-auto-zoom.mjs through a symlink should exit 0"
grep -q -- "--video" "$TMP_DIR/render-symlink-help" \
  || fail "render-auto-zoom.mjs through a symlink printed nothing: main() did not run"

node "$RECORD" --help >"$TMP_DIR/record-help"
grep -q -- "--width" "$TMP_DIR/record-help" || fail "record --help missing --width"
grep -q -- "--pause-ms" "$TMP_DIR/record-help" || fail "record --help missing --pause-ms"
grep -q -- "--storage-state" "$TMP_DIR/record-help" || fail "record --help missing --storage-state"
grep -q -- "--sign-in" "$TMP_DIR/record-help" || fail "record --help missing --sign-in"
grep -q -- "--connect" "$TMP_DIR/record-help" || fail "record --help missing --connect"
grep -q -- "--check-prereqs" "$TMP_DIR/record-help" || fail "record --help missing --check-prereqs"

set +e
node "$RECORD" --check-prereqs >"$TMP_DIR/check-prereqs-out" 2>"$TMP_DIR/check-prereqs-err"
check_status=$?
set -e
if [ "$check_status" -eq 0 ]; then
  grep -q -- "Playwright: available" "$TMP_DIR/check-prereqs-out" \
    || fail "record --check-prereqs stdout missing 'Playwright: available'"
else
  [ "$check_status" -eq 1 ] || fail "record --check-prereqs in unprovisioned cwd should exit 1, got $check_status"
  grep -q -- "Playwright: missing" "$TMP_DIR/check-prereqs-err" \
    || fail "record --check-prereqs stderr missing 'Playwright: missing'"
  grep -qi -- "ask user" "$TMP_DIR/check-prereqs-err" \
    || fail "record --check-prereqs stderr missing 'ask user' guidance"
fi

node --input-type=module <<EOF || fail "record helper exports"
import fs from "node:fs";
import path from "node:path";
import { bringOverlayToFront, findTopLayerHost, parseArgs, resolveContextOptions, resolveViewport, resolvePauseMs, checkPrereqs, getGlobalNodeDirs, loadPlaywright, getFfmpegInstallAdvice, pickLatestDevice, resolveDevice, targetPoint } from "file://${RECORD}";

const fail = (message) => {
  console.error(message);
  process.exit(1);
};
const same = (a, b, what) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    fail(what + ": got " + JSON.stringify(a) + ", wanted " + JSON.stringify(b));
  }
};

if (!Array.isArray(getGlobalNodeDirs())) {
  fail("getGlobalNodeDirs should return an array");
}

const fakeRoots = { npm: "/g/npm", pnpm: "/g/pnpm", yarn: "/g/yarn" };
const fakeRun = (cmd) => (fakeRoots[cmd] ? { status: 0, stdout: fakeRoots[cmd] + "\n" } : { status: 1, stdout: "" });
same(
  getGlobalNodeDirs({ env: { NODE_PATH: "/g/node-path", BUN_INSTALL: "/g/bun" }, run: fakeRun }),
  ["/g/node-path", "/g/npm", "/g/pnpm", path.join("/g/yarn", "node_modules"), path.join("/g/bun", "install", "global", "node_modules")],
  "getGlobalNodeDirs probes npm, pnpm, Yarn Classic and Bun global roots",
);
same(
  getGlobalNodeDirs({ env: { BUN_INSTALL_GLOBAL_DIR: "/g/bun-global" }, run: () => { throw new Error("ENOENT"); } }),
  [path.join("/g/bun-global", "node_modules")],
  "getGlobalNodeDirs honours BUN_INSTALL_GLOBAL_DIR and survives a missing package manager",
);

const mockGlobalDir = "${TMP_DIR}/global-modules";
const mockPwDir = path.join(mockGlobalDir, "playwright");
fs.mkdirSync(mockPwDir, { recursive: true });
fs.writeFileSync(
  path.join(mockPwDir, "package.json"),
  JSON.stringify({ name: "playwright", main: "index.js" }),
);
fs.writeFileSync(
  path.join(mockPwDir, "index.js"),
  "module.exports = { chromium: { launch: async () => ({}) } };",
);

const loadedFromGlobal = await loadPlaywright({
  globalDirs: [mockGlobalDir],
});
if (!loadedFromGlobal?.chromium?.launch) {
  fail("loadPlaywright should resolve playwright from globalDirs");
}

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

const checkArgs = parseArgs(["--check-prereqs"]);
if (!checkArgs.checkPrereqs) {
  fail("parseArgs should set checkPrereqs");
}

const mockPrereqsOk = await checkPrereqs({
  hasFfmpeg: () => true,
  playwright: {},
  launchChromium: async () => ({
    browserType: () => ({ name: () => "mock-chromium" }),
    close: async () => {},
  }),
});
if (!mockPrereqsOk.ok || !mockPrereqsOk.playwright || !mockPrereqsOk.browser || !mockPrereqsOk.ffmpeg) {
  fail("checkPrereqs mock success failed");
}

const mockPrereqsNoFfmpeg = await checkPrereqs({
  hasFfmpeg: () => false,
  playwright: {},
  launchChromium: async () => ({
    browserType: () => ({ name: () => "mock-chromium" }),
    close: async () => {},
  }),
});
if (!mockPrereqsNoFfmpeg.ok || mockPrereqsNoFfmpeg.ffmpeg) {
  fail("checkPrereqs should still pass without ffmpeg (raw webm supported)");
}
if (!mockPrereqsNoFfmpeg.messages.some((m) => m.includes("mise use -g ffmpeg") && m.includes("ask user authorization"))) {
  fail("checkPrereqs with missing ffmpeg should include installation advice asking user authorization");
}

if (!mockPrereqsNoFfmpeg.messages.some((m) => m.includes("command -v ffmpeg") && m.includes("mise ls ffmpeg"))) {
  fail("checkPrereqs with missing ffmpeg should first point at an installed-but-off-PATH ffmpeg");
}

const macMiseAdvice = getFfmpegInstallAdvice({ hasMise: () => true, platform: "darwin" });
if (!macMiseAdvice.includes("mise use -g ffmpeg") || !macMiseAdvice.includes("brew install ffmpeg")) {
  fail("getFfmpegInstallAdvice with mise on mac should mention mise and brew");
}
const linuxNoMiseAdvice = getFfmpegInstallAdvice({ hasMise: () => false, platform: "linux" });
if (!linuxNoMiseAdvice.includes("mise.run") || !linuxNoMiseAdvice.includes("sudo apt install ffmpeg")) {
  fail("getFfmpegInstallAdvice without mise on linux should mention mise.run and apt");
}
const winAdvice = getFfmpegInstallAdvice({ hasMise: () => false, platform: "win32" });
if (!winAdvice.includes("winget install Gyan.FFmpeg")) {
  fail("getFfmpegInstallAdvice without mise on win32 should mention winget");
}

const mockPrereqsMissingPw = await checkPrereqs({
  hasFfmpeg: () => true,
  loadPlaywright: async () => {
    throw new Error("not installed");
  },
});
if (mockPrereqsMissingPw.ok || mockPrereqsMissingPw.playwright) {
  fail("checkPrereqs should fail when playwright is missing");
}

const mockPrereqsLaunchFail = await checkPrereqs({
  hasFfmpeg: () => true,
  playwright: {},
  launchChromium: async () => {
    throw new Error("launch failed");
  },
});
if (mockPrereqsLaunchFail.ok || !mockPrereqsLaunchFail.playwright || mockPrereqsLaunchFail.browser) {
  fail("checkPrereqs should fail when browser launch fails");
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

// "phone" picks the newest matching entry rather than naming one, so the
// default tracks whatever this Playwright's device list currently has.
// "tablet" is pinned to iPad Mini instead: an iPad Pro's viewport is wide
// enough that plenty of real sites keep their desktop nav at that width.
const mockDevices = {
  "iPhone 13": { viewport: { width: 390, height: 844 } },
  "iPhone 15 Pro": { viewport: { width: 393, height: 852 }, isMobile: true },
  "iPhone 15 Pro Max": { viewport: { width: 430, height: 932 }, isMobile: true },
  "iPhone 15 Pro landscape": { viewport: { width: 852, height: 393 }, isMobile: true },
  "iPad Pro 11": { viewport: { width: 834, height: 1194 }, isMobile: true },
  "iPad Mini": { viewport: { width: 768, height: 1024 }, isMobile: true },
};
if (pickLatestDevice(mockDevices, /^iPhone (\d+) Pro$/) !== "iPhone 15 Pro") {
  fail("pickLatestDevice should skip Max/landscape variants and pick the highest generation");
}
if (pickLatestDevice(mockDevices, /^iPad Pro (\d+)$/) !== "iPad Pro 11") {
  fail("pickLatestDevice should still match a generation pattern");
}
if (pickLatestDevice(mockDevices, /^Pixel (\d+)$/) !== null) {
  fail("pickLatestDevice should return null when nothing matches");
}

const mockPlaywright = { devices: mockDevices };
const phoneDevice = resolveDevice(mockPlaywright, { device: "phone" });
if (phoneDevice.name !== "iPhone 15 Pro" || phoneDevice.viewport.width !== 393) {
  fail("resolveDevice phone: " + JSON.stringify(phoneDevice));
}
const tabletDevice = resolveDevice(mockPlaywright, { device: "tablet" });
if (tabletDevice.name !== "iPad Mini" || tabletDevice.viewport.width !== 768) {
  fail("resolveDevice tablet should be pinned to iPad Mini, not the newest iPad Pro: " + JSON.stringify(tabletDevice));
}
if (resolveDevice(mockPlaywright, {}) !== null) {
  fail("resolveDevice with no scenario.device should return null");
}
const exactDevice = resolveDevice(mockPlaywright, { device: "iPad Pro 11" });
if (exactDevice.name !== "iPad Pro 11") {
  fail("resolveDevice should pass an exact device name through");
}
let deviceThrew = false;
try {
  resolveDevice(mockPlaywright, { device: "bogus" });
} catch {
  deviceThrew = true;
}
if (!deviceThrew) {
  fail("resolveDevice should refuse an unknown device name");
}
let tabletMissingThrew = false;
try {
  resolveDevice({ devices: {} }, { device: "tablet" });
} catch {
  tabletMissingThrew = true;
}
if (!tabletMissingThrew) {
  fail("resolveDevice should refuse tablet when iPad Mini is absent from the registry");
}

const viewportFromDevice = resolveViewport({}, {}, phoneDevice);
if (viewportFromDevice.width !== 394 || viewportFromDevice.height !== 852) {
  fail("resolveViewport should fall back to the device's own viewport: " + JSON.stringify(viewportFromDevice));
}
const explicitOverridesDevice = resolveViewport({ viewport: { width: 800, height: 600 } }, {}, phoneDevice);
if (explicitOverridesDevice.width !== 800 || explicitOverridesDevice.height !== 600) {
  fail("scenario.viewport should override the device's viewport");
}

// A local stack on a self-signed certificate, or a page whose content follows
// Accept-Language, needs the context configured before the first request.
const phoneContext = resolveContextOptions({ locale: "zh-TW", ignoreHTTPSErrors: true }, phoneDevice, explicitOverridesDevice, null);
if (phoneContext.locale !== "zh-TW" || phoneContext.ignoreHTTPSErrors !== true) {
  fail("resolveContextOptions should pass locale and ignoreHTTPSErrors through: " + JSON.stringify(phoneContext));
}
if (phoneContext.isMobile !== true || phoneContext.viewport.width !== 800) {
  fail("resolveContextOptions should keep the device's own options and the resolved viewport: " + JSON.stringify(phoneContext));
}
const desktopContext = resolveContextOptions({}, null, vp, null);
if ("locale" in desktopContext || "ignoreHTTPSErrors" in desktopContext || desktopContext.deviceScaleFactor !== 1) {
  fail("resolveContextOptions should leave Playwright's defaults alone when the scenario says nothing: " + JSON.stringify(desktopContext));
}

// The pointer aims at what is actually on screen, and refuses a target that
// is not rather than clicking whatever else sits at those coordinates.
same(targetPoint({ x: 100, y: 200, width: 40, height: 20 }, { width: 390, height: 844 }), { x: 120, y: 210 }, "target centre");
same(targetPoint({ x: 0, y: -500, width: 390, height: 2000 }, { width: 390, height: 844 }), { x: 195, y: 422 }, "a target taller than the viewport aims at its visible part");
if (targetPoint({ x: 10, y: 2000, width: 40, height: 20 }, { width: 390, height: 844 }) !== null) {
  fail("a target below the fold has no point to aim at");
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

const mockDoc = {
  documentElement: { tagName: "HTML" },
  querySelectorAll(sel) {
    if (sel.includes(":modal")) {
      return [
        { tagName: "DIALOG", hasAttribute: () => false },
        { tagName: "X-PW-GLASS", hasAttribute: () => false },
      ];
    }
    return [];
  },
};
if (findTopLayerHost(mockDoc)?.tagName !== "DIALOG") {
  fail("findTopLayerHost should filter out internal x-pw overlays");
}
if (findTopLayerHost({ documentElement: { tagName: "HTML" }, querySelectorAll: () => [] })?.tagName !== "HTML") {
  fail("findTopLayerHost fallback to documentElement");
}

let popoverActions = [];
const mockGlass = {
  tagName: "X-PW-GLASS",
  showPopover: () => { popoverActions.push("show"); },
  hidePopover: () => { popoverActions.push("hide"); },
};
const mockGlassDoc = {
  querySelector: (sel) => (sel === "x-pw-glass" ? mockGlass : null),
};
bringOverlayToFront(mockGlassDoc);
if (popoverActions.join(",") !== "hide,show") {
  fail("bringOverlayToFront should hide and re-show popover to bring to front");
}
bringOverlayToFront({ querySelector: () => null });
bringOverlayToFront(null);
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
import {
  describeLaunchFailure,
  parseArgs,
  resolveSessionMode,
  samePage,
  storageStateProblems,
  validateScenario,
} from "file://${RECORD}";

const fail = (message) => {
  console.error(message);
  process.exit(1);
};

const args = parseArgs([
  "--scenario", "s.json", "--out", "o.webm", "--storage-state", "auth.json", "--sign-in",
]);
if (args.storageState !== "auth.json") {
  fail("parseArgs --storage-state");
}
if (args.signIn !== true) {
  fail("parseArgs --sign-in");
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

// A secret can come from the environment instead, so it never sits in a
// scenario file that gets committed or pasted into a pull request.
const fromEnv = { steps: [{ action: "type", label: "Password", textEnv: "DEMO_PASSWORD" }] };
if (validateScenario(fromEnv, { env: { DEMO_PASSWORD: "set" } }).length !== 0) {
  fail("a type step may read its text from the environment");
}
if (!validateScenario(fromEnv, { env: {} }).some((p) => p.includes("DEMO_PASSWORD"))) {
  fail("an unset textEnv should be refused before a browser opens");
}
const both = { steps: [{ action: "type", label: "Password", text: "x", textEnv: "DEMO_PASSWORD" }] };
if (!validateScenario(both, { env: { DEMO_PASSWORD: "set" } }).some((p) => p.includes("textEnv"))) {
  fail("text and textEnv together should be refused");
}
if (!validateScenario({ steps: [{ action: "click", text: "Go", textEnv: "DEMO_PASSWORD" }] }, { env: { DEMO_PASSWORD: "set" } }).some((p) => p.includes("textEnv"))) {
  fail("textEnv outside a type step should be refused");
}
if (!validateScenario({ steps: [{ action: "type", label: "Key", text: "x", sensitive: "yes" }] }, {}).some((p) => p.includes("sensitive"))) {
  fail("a non-boolean sensitive should be refused");
}

// auth mode still needs the assertion that proves the session survived.
const missingExpect = validateScenario({ steps: [] }, { sessionMode: "saved" });
if (!missingExpect.some((p) => p.includes("auth.expect"))) {
  fail("auth mode should require auth.expect");
}
const wellFormed = { auth: { expect: { role: "button", name: "Account" } }, steps: [] };
if (validateScenario(wellFormed, { sessionMode: "saved" }).length !== 0) {
  fail("a well-formed auth scenario should pass");
}

// One name for how the session is obtained, derived from the flags once.
for (const [given, wanted] of [
  [{}, "none"],
  [{ storageState: "auth.json" }, "saved"],
  [{ signIn: true }, "interactive"],
  [{ storageState: "auth.json", signIn: true }, "conflict"],
  [{ connect: "http://127.0.0.1:9222" }, "attached"],
  [{ connect: "http://127.0.0.1:9222", signIn: true }, "conflict"],
  [{ connect: "http://127.0.0.1:9222", storageState: "auth.json" }, "conflict"],
]) {
  const got = resolveSessionMode(given);
  if (got !== wanted) {
    fail("session mode for " + JSON.stringify(given) + ": got " + got + ", wanted " + wanted);
  }
}

// A shared prefix is not the same page.
if (!samePage("http://x/app", "http://x/app?q=1")) {
  fail("a query string is still the same page");
}
if (samePage("http://x/application", "http://x/app")) {
  fail("a longer path is a different page");
}

// Signing in by hand needs the same assertion a saved state does, and the two
// modes cannot both be asked for.
const signedIn = { auth: { expect: { role: "button", name: "Account" } }, steps: [] };
if (!validateScenario({ steps: [] }, { sessionMode: "interactive" })[0].includes("--sign-in needs scenario.auth.expect")) {
  fail("--sign-in should require auth.expect");
}
if (validateScenario(signedIn, { sessionMode: "interactive" }).length !== 0) {
  fail("--sign-in with auth.expect should pass");
}
const bothModes = validateScenario(signedIn, { sessionMode: "conflict" });
if (!bothModes.some((p) => p.includes("Pick one"))) {
  fail("--sign-in with --storage-state should be refused: " + JSON.stringify(bothModes));
}

// Attaching to a window somebody already signed in on still needs a locator
// that proves the page is the signed-in one, and parses its endpoint.
if (parseArgs(["--connect", "http://127.0.0.1:9222"]).connect !== "http://127.0.0.1:9222") {
  fail("parseArgs --connect");
}
if (!validateScenario({ steps: [] }, { sessionMode: "attached" })[0].includes("--connect needs scenario.auth.expect")) {
  fail("--connect should require auth.expect");
}
if (validateScenario(signedIn, { sessionMode: "attached" }).length !== 0) {
  fail("--connect with auth.expect should pass");
}

// An expect step only waits, so its state and any step timeout are checked up front.
if (validateScenario({ steps: [{ action: "expect", text: "x", state: "gone" }] })[0] !== 'steps[0].state must be "visible" or "hidden"') {
  fail("expect state should be validated");
}
if (validateScenario({ steps: [{ action: "click", text: "x", timeout: -1 }] })[0] !== "steps[0].timeout must be a positive number of milliseconds") {
  fail("step timeout should be validated");
}
if (validateScenario({ steps: [{ action: "expect", text: "x", state: "hidden", timeout: 500 }] }).length !== 0) {
  fail("a well-formed expect step should pass");
}

// A headed launch with nowhere to draw is worth naming as such.
if (!describeLaunchFailure(new Error("Missing X server or \$DISPLAY"), true).includes("no display")) {
  fail("a headed launch without a display should be explained");
}
if (describeLaunchFailure(new Error("Missing X server or \$DISPLAY"), false) !== null) {
  fail("a headless launch failure is not a display problem");
}
if (describeLaunchFailure(new Error("Executable doesn't exist"), true) !== null) {
  fail("a missing browser is not a display problem");
}
if (describeLaunchFailure(new Error("failed to display the page"), true) !== null) {
  fail("the word display alone is not a display problem");
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
  CAPTION_PLACEMENTS,
  DEFAULT_CAPTION_LOCALE,
  EFFECT_DEFAULTS,
  captionFor,
  captionHtml,
  captionPosition,
  formatKeys,
  pageScale,
  resolveCaptionLocale,
  resolveEffects,
  resolveInput,
  resolvePointerIcon,
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

// scenario.device is checked for shape here; whether the name actually
// resolves is Playwright's own device registry, checked at record time.
if (!validateScenario({ device: 42, steps: [] })[0].includes("scenario.device must be a string")) {
  fail("a non-string scenario.device should be refused before recording");
}
same(validateScenario({ device: "phone", steps: [] }), [], "a string scenario.device should pass validation");
if (!validateScenario({ locale: 7, steps: [] })[0].includes("scenario.locale")) {
  fail("a non-string scenario.locale should be refused before recording");
}
if (!validateScenario({ ignoreHTTPSErrors: "yes", steps: [] })[0].includes("ignoreHTTPSErrors")) {
  fail("a non-boolean scenario.ignoreHTTPSErrors should be refused before recording");
}
same(validateScenario({ locale: "zh-TW", ignoreHTTPSErrors: true, steps: [] }), [], "well-formed context settings");

// The pointer icon is read off the step's own action, not the live page.
if (resolvePointerIcon({ action: "click" }) !== "hand") {
  fail("click should show the hand icon");
}
if (resolvePointerIcon({ action: "dblclick" }) !== "hand") {
  fail("dblclick should show the hand icon");
}
if (resolvePointerIcon({ action: "select" }) !== "hand") {
  fail("select should show the hand icon");
}
if (resolvePointerIcon({ action: "type" }) !== "text") {
  fail("type should show the text icon");
}
if (resolvePointerIcon({ action: "press", keys: "Control+k" }) !== null) {
  fail("press should leave the arrow alone");
}
if (resolvePointerIcon({ action: "wait", ms: 100 }) !== null) {
  fail("wait should leave the arrow alone");
}

// A touch device taps wherever a finger could; touch has no double-click or
// secondary button, so those stay on the mouse.
const touch = { touch: true };
same(
  ["click", "type", "select"].map((action) => resolveInput({ action }, touch)),
  ["tap", "tap", "tap"],
  "a touch device taps to click, focus, and open",
);
if (resolveInput({ action: "dblclick" }, touch) !== "mouse") {
  fail("a double-click has no tap equivalent");
}
if (resolveInput({ action: "click", button: "right" }, touch) !== "mouse") {
  fail("a right click has no tap equivalent");
}
if (resolveInput({ action: "click" }, {}) !== "mouse") {
  fail("a context without touch clicks with the mouse");
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
// A secret is captioned as a fixed row of dots, which gives away neither the
// value nor its length. A caption the author wrote is still theirs.
const dots = "Type \u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022";
if (captionFor({ action: "type", text: "hunter2" }, "en", { masked: true }) !== dots) {
  fail("a masked type caption: " + captionFor({ action: "type", text: "hunter2" }, "en", { masked: true }));
}
if (captionFor({ action: "type", text: "hunter2", sensitive: true }, "en") !== dots) {
  fail("a sensitive step should be masked");
}
if (captionFor({ action: "type", textEnv: "DEMO_PASSWORD" }, "en") !== dots) {
  fail("text from the environment should be masked");
}
if (captionFor({ action: "type", text: "hunter2", caption: "Sign in" }, "en", { masked: true }) !== "Sign in") {
  fail("an author's caption should not be replaced");
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
same(captionPosition({ x: 350, y: 175 }, vp), { left: 376, top: 219, maxWidth: 720 }, "caption under the target");
const low = captionPosition({ x: 350, y: 700 }, vp);
if (!(vp.height - low.bottom < 700)) {
  fail("a target near the bottom should put the caption above it: " + JSON.stringify(low));
}
const onScreen = (position, viewport) =>
  position.left - position.maxWidth / 2 >= 0 && position.left + position.maxWidth / 2 <= viewport.width;
const phoneVp = { width: 390, height: 844 };
for (const [anchor, viewport, what] of [
  [{ x: 10, y: 300 }, vp, "a target near the left edge"],
  [{ x: 1270, y: 300 }, vp, "a target near the right edge"],
  [{ x: 30, y: 300 }, phoneVp, "a target on a phone"],
  [{ x: 380, y: 830 }, phoneVp, "a target in a phone's corner"],
  [null, phoneVp, "a step with no target on a phone"],
]) {
  const position = captionPosition(anchor, viewport);
  if (!onScreen(position, viewport)) {
    fail(what + " should keep the widest caption on screen: " + JSON.stringify(position));
  }
}
if (captionPosition(null, vp).left !== 640) {
  fail("a step with no anchor should centre the caption");
}
// A menu opening under its toggle is something only the author knows about,
// so a step can move its caption out of the way.
same(captionPosition({ x: 350, y: 175 }, vp, "above"), { left: 376, bottom: 557, maxWidth: 720 }, "caption above the target");
same(captionPosition({ x: 350, y: 700 }, vp, "below"), { left: 376, top: 744, maxWidth: 720 }, "an explicit below does not flip");
same(captionPosition({ x: 350, y: 175 }, vp, "bottom"), captionPosition(null, vp), "caption at the bottom centre");
same(captionPosition({ x: 350, y: 175 }, vp, "auto"), captionPosition({ x: 350, y: 175 }, vp), "auto is the default");
// On a page zoomed out to half size, positions are halved into CSS pixels
// and the caption is scaled back up around the edge that holds it.
same(pageScale({ width: 390 }, { width: 975 }), 0.4, "page scale of a zoomed-out page");
same(pageScale({ width: 390 }, { width: 390 }), 1, "page scale of a page that fits");
const halved = captionHtml("Menu", { x: 350, y: 175 }, vp, "above", 0.5);
if (!halved.includes("left: 752px") || !halved.includes("bottom: 1114px") || !halved.includes("scale(2)") || !halved.includes("transform-origin: 50% 100%")) {
  fail("a caption on a zoomed-out page should be placed in CSS pixels and scaled back up: " + halved);
}
if (!captionHtml("Menu", { x: 350, y: 175 }, vp, "above").includes("bottom: 557px")) {
  fail("captionHtml should honour the placement");
}
if (!validateScenario({ steps: [{ action: "click", text: "Menu", captionPlacement: "left" }] })[0].includes("captionPlacement must be one of")) {
  fail("an unknown captionPlacement should be refused before recording");
}
same(
  validateScenario({ steps: CAPTION_PLACEMENTS.map((captionPlacement) => ({ action: "click", text: "Menu", captionPlacement })) }),
  [],
  "every known captionPlacement",
);

const phoneCaption = captionHtml("Check the agreement before you continue to the identity provider", { x: 30, y: 300 }, phoneVp);
if (!phoneCaption.includes("max-width: 358px") || phoneCaption.includes("nowrap")) {
  fail("a caption on a phone should wrap inside the viewport: " + phoneCaption);
}
EOF

# --- real browser --------------------------------------------------------------
# The pointer drives page.mouse at viewport coordinates, so what it actually hits
# only shows in a browser. Skipped where --check-prereqs found no Playwright.

if [ "$check_status" -eq 0 ]; then
  node --input-type=module <<EOF || fail "real browser steps"
import { loadPlaywright, runScenario } from "file://${RECORD}";

const fail = (message) => {
  console.error(message);
  process.exit(1);
};

const playwright = await loadPlaywright();
const browser = await playwright.chromium.launch();
const quiet = { zoom: false, cursor: false, captions: false };
const stateFor = (viewport, extra = {}) => ({
  x: viewport.width / 2, y: viewport.height / 2, startedAt: Date.now(), pauseMs: 0, effects: quiet, ...extra,
});

try {
  // A target below the fold is scrolled to, not clicked at off-screen
  // coordinates, and one that never stops pulsing is not waited on to settle.
  const viewport = { width: 390, height: 844 };
  const page = await browser.newPage({ viewport });
  await page.setContent(
    '<style>@keyframes pulse { 50% { transform: scale(1.2); } } button { animation: pulse .4s infinite; }</style>' +
    '<div style="height:2000px"></div><button onclick="window.hit = true">Far</button><div style="height:400px"></div>',
  );
  await runScenario(page, { steps: [{ action: "click", role: "button", name: "Far" }] }, () => {}, stateFor(viewport));
  if (!(await page.evaluate(() => window.hit === true))) {
    fail("a click on a target below the fold should reach it");
  }
  await page.close();

  // expect waits for an element to appear without touching the page, and a
  // failing step names itself and leaves a screenshot and an aria snapshot.
  const waited = await browser.newPage({ viewport: { width: 640, height: 480 } });
  await waited.setContent(
    '<button onclick="window.clicks = (window.clicks || 0) + 1">Add</button>' +
    '<script>setTimeout(() => { document.body.insertAdjacentHTML("beforeend", "<p>Saved item</p>"); }, 600);</script>',
  );
  await runScenario(waited, { steps: [{ action: "expect", text: "Saved item" }] }, () => {}, stateFor({ width: 640, height: 480 }));
  if (!(await waited.getByText("Saved item").isVisible())) {
    fail("expect should wait until the element is visible");
  }
  if ((await waited.evaluate(() => window.clicks ?? 0)) !== 0) {
    fail("expect must not click anything");
  }
  await runScenario(waited, { steps: [{ action: "expect", text: "Saved item", state: "hidden", timeout: 200 }] }, () => {}, stateFor({ width: 640, height: 480 }))
    .then(() => fail("expect hidden on a visible element should time out"), () => {});
  const failStem = "${TMP_DIR}/failing";
  let failure = "";
  try {
    await runScenario(
      waited,
      { steps: [{ action: "expect", text: "Saved item" }, { action: "click", role: "button", name: "Missing", timeout: 300 }] },
      () => {},
      stateFor({ width: 640, height: 480 }, { failureStem: failStem }),
    );
  } catch (error) {
    failure = error.message;
  }
  if (!failure.includes("step 2 of 2") || !failure.includes("Missing")) {
    fail("a failing step should name itself: " + failure);
  }
  const fs = await import("node:fs");
  if (!fs.existsSync(failStem + ".failure.png") || !fs.readFileSync(failStem + ".failure.aria.txt", "utf8").includes("Add")) {
    fail("a failing step should leave a screenshot and an aria snapshot");
  }
  await waited.close();

  // A phone page without a viewport meta tag lays out 980px wide and zooms
  // out, so a target past the device's own width is still on screen.
  const zoomedOut = await browser.newContext({ viewport, isMobile: true });
  const unscaled = await zoomedOut.newPage();
  await unscaled.setContent('<button style="position:absolute; left:700px; top:100px" onclick="window.hit = true">Wide</button>');
  const zoomedLog = [];
  const zoomedDrawn = [];
  const showZoomedOverlay = unscaled.screencast.showOverlay.bind(unscaled.screencast);
  unscaled.screencast.showOverlay = async (html) => {
    zoomedDrawn.push(html);
    return showZoomedOverlay(html);
  };
  await runScenario(
    unscaled,
    { steps: [{ action: "click", role: "button", name: "Wide", pause: 0 }] },
    (entry) => zoomedLog.push(entry),
    stateFor(viewport, { effects: { zoom: false, cursor: true, captions: true }, captionLocale: "en" }),
  );
  if (!(await unscaled.evaluate(() => window.hit === true))) {
    fail("a click on a zoomed-out phone page should reach a target past the device width");
  }
  // The page is zoomed to fit 980 CSS pixels into 390 screen pixels, and the
  // video frame is the screen: the click is logged where the viewer sees it.
  const zoomed = await unscaled.evaluate(() => ({ width: innerWidth, box: document.querySelector("button").getBoundingClientRect() }));
  const seenAt = (zoomed.box.left + zoomed.box.width / 2) / zoomed.width;
  if (zoomedLog.length !== 1 || Math.abs(zoomedLog[0].cx - seenAt) > 0.01 || zoomedLog[0].cx > 1) {
    fail("a click on a zoomed-out page should be logged as a fraction of the screen: " + JSON.stringify({ zoomedLog, seenAt }));
  }
  // What is drawn into the page is zoomed out with it, so it is scaled back up.
  const zoomFactor = zoomed.width / viewport.width;
  const drawnScale = Number(zoomedDrawn[0]?.match(/scale\(([\d.]+)\)/)?.[1]);
  if (Math.abs(drawnScale - zoomFactor) > 0.01) {
    fail("a caption on a zoomed-out page should be scaled back to screen size: " + JSON.stringify({ zoomFactor, zoomedDrawn }));
  }
  const pointerScale = Number(await unscaled.evaluate(() => document.querySelector("[data-tvr]")?.style.getPropertyValue("--tvr-k")));
  if (Math.abs(pointerScale - zoomFactor) > 0.01) {
    fail("the pointer on a zoomed-out page should be scaled back to screen size: " + JSON.stringify({ zoomFactor, pointerScale }));
  }
  await zoomedOut.close();

  // A step's captionPlacement reaches the overlay the recording draws.
  const placed = await browser.newPage({ viewport });
  await placed.setContent("<button>Menu</button>");
  const drawn = [];
  const showPlacedOverlay = placed.screencast.showOverlay.bind(placed.screencast);
  placed.screencast.showOverlay = async (html) => {
    drawn.push(html);
    return showPlacedOverlay(html);
  };
  await runScenario(placed, {
    steps: [{ action: "click", role: "button", name: "Menu", captionPlacement: "bottom", pause: 0 }],
  }, () => {}, stateFor(viewport, { effects: { ...quiet, captions: true }, captionLocale: "en" }));
  if (drawn.length !== 1 || !drawn[0].includes("bottom: 24px")) {
    fail("a step's captionPlacement should place its caption: " + JSON.stringify(drawn));
  }
  await placed.close();

  // A password or one-time-code field is recognised on the page, so its
  // caption shows dots however the scenario wrote the step; an ordinary field
  // still shows what is typed.
  const secret = await browser.newPage({ viewport });
  await secret.setContent(
    '<label>Password <input id="pw" type="password"></label>' +
    '<label>Code <input id="otp" autocomplete="one-time-code"></label>' +
    '<label>Env <input id="env" type="password"></label>' +
    '<label>Search <input id="q"></label>',
  );
  const secretDrawn = [];
  const showSecretOverlay = secret.screencast.showOverlay.bind(secret.screencast);
  secret.screencast.showOverlay = async (html) => {
    secretDrawn.push(html);
    return showSecretOverlay(html);
  };
  process.env.TVR_TEST_SECRET = "from-env-secret";
  await runScenario(secret, {
    steps: [
      { action: "type", label: "Password", text: "hunter2", pause: 0 },
      { action: "type", label: "Code", text: "424242", pause: 0 },
      { action: "type", label: "Env", textEnv: "TVR_TEST_SECRET", pause: 0 },
      { action: "type", label: "Search", text: "SSH", pause: 0 },
    ],
  }, () => {}, stateFor(viewport, { effects: { ...quiet, captions: true }, captionLocale: "en" }));
  const leaked = secretDrawn.filter((html) => /hunter2|424242|from-env-secret/.test(html));
  if (secretDrawn.length !== 4 || leaked.length !== 0 || !secretDrawn[3].includes("Type SSH")) {
    fail("a secret should never reach a caption: " + JSON.stringify(secretDrawn));
  }
  const secretValues = await secret.evaluate(() => ["pw", "otp", "env"].map((id) => document.getElementById(id).value));
  if (secretValues.join() !== "hunter2,424242,from-env-secret") {
    fail("a masked step should still type its text: " + JSON.stringify(secretValues));
  }
  // Error text lands in terminals and CI logs, so a type step's text is left out.
  let redacted = "";
  try {
    await runScenario(secret, {
      steps: [{ action: "type", label: "Missing", text: "hunter2", timeout: 200 }],
    }, () => {}, stateFor(viewport));
  } catch (error) {
    redacted = error.message;
  }
  if (!redacted.includes("Missing") || redacted.includes("hunter2")) {
    fail("a failing type step should not print its text: " + redacted);
  }
  await secret.close();

  // A touch device taps, so touch-only handlers fire, and the cursor's sweep
  // does not hover anything on the way. Double-click still works there.
  const phone = await browser.newContext({ viewport, isMobile: true, hasTouch: true });
  const tapped = await phone.newPage();
  await tapped.setContent(\`
    <button id="menu">Menu</button>
    <p><button id="details">Details</button></p>
    <p><label>Search <input id="q"></label></p>
    <p><label>Language <select id="lang"><option>English</option><option>Japanese</option></select></label></p>
    <script>
      window.seen = [];
      for (const type of ["touchstart", "mouseover", "click", "dblclick"]) {
        document.addEventListener(type, (event) => {
          seen.push(type + ":" + event.target.id + (event.pointerType ? ":" + event.pointerType : ""));
        }, true);
      }
    </script>\`);
  await runScenario(tapped, {
    steps: [
      { action: "click", role: "button", name: "Menu" },
      { action: "dblclick", role: "button", name: "Details" },
      { action: "type", role: "textbox", name: "Search", text: "SSH" },
      { action: "select", role: "combobox", name: "Language", value: "Japanese" },
    ],
  }, () => {}, stateFor(viewport, { touch: true, effects: { ...quiet, cursor: true } }));
  const seen = await tapped.evaluate(() => window.seen);
  if (!seen.includes("touchstart:menu") || !seen.includes("click:menu:touch")) {
    fail("a click on a touch device should arrive as a tap: " + JSON.stringify(seen));
  }
  // A real tap is followed by compatibility mouse events, so only a hover
  // before the touch would mean the pointer's sweep dispatched it.
  if (seen.indexOf("mouseover:menu") < seen.indexOf("touchstart:menu")) {
    fail("a tap should not hover its target on the way: " + JSON.stringify(seen));
  }
  if (!seen.includes("dblclick:details")) {
    fail("a double-click should still land on a touch device: " + JSON.stringify(seen));
  }
  const typed = await tapped.evaluate(() => [document.getElementById("q").value, document.getElementById("lang").value]);
  if (typed[0] !== "SSH" || typed[1] !== "Japanese") {
    fail("type and select should still work after a tap: " + JSON.stringify(typed));
  }
  await phone.close();

  // A caption ends with its page: one whose step navigates is gone by the time
  // the next document loads, not held over it for the rest of the pause.
  const server = (await import("node:http")).createServer((req, res) => {
    if (req.url === "/slow.js") {
      setTimeout(() => res.end(""), 2000);
      return;
    }
    res.writeHead(200, { "content-type": "text/html" });
    const pages = {
      "/next": "<h1>Next page</h1>",
      "/slow": '<button>Stay</button><script defer src="/slow.js"></script>',
    };
    res.end(pages[req.url] ?? '<a href="/next">Continue</a> <a href="/slow">Slow</a>');
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const navigating = await browser.newPage({ viewport });
    await navigating.goto("http://127.0.0.1:" + server.address().port + "/");
    let loadedAt = 0;
    let disposedAt = 0;
    navigating.on("domcontentloaded", () => { loadedAt ||= Date.now(); });
    const showOverlay = navigating.screencast.showOverlay.bind(navigating.screencast);
    navigating.screencast.showOverlay = async (html) => {
      const overlay = await showOverlay(html);
      return {
        async [Symbol.asyncDispose]() {
          disposedAt ||= Date.now();
          await overlay[Symbol.asyncDispose]();
        },
      };
    };
    await runScenario(navigating, {
      steps: [{ action: "click", role: "link", name: "Continue", pause: 2500 }],
    }, () => {}, stateFor(viewport, { effects: { ...quiet, captions: true }, captionLocale: "en" }));
    if (!loadedAt || !disposedAt || disposedAt - loadedAt > 1000) {
      fail("a caption should be removed once its step navigates: loaded " + loadedAt + ", removed " + disposedAt);
    }
    await navigating.close();

    // A page an earlier step loaded can be usable long before DOMContentLoaded;
    // that late event is not the next step's navigation and leaves its caption.
    const slow = await browser.newPage({ viewport });
    await slow.goto("http://127.0.0.1:" + server.address().port + "/");
    const lifetimes = [];
    const showSlowOverlay = slow.screencast.showOverlay.bind(slow.screencast);
    slow.screencast.showOverlay = async (html) => {
      const overlay = await showSlowOverlay(html);
      const shownAt = Date.now();
      let removed = false;
      return {
        async [Symbol.asyncDispose]() {
          // Only the first removal ends what a viewer sees; later ones are no-ops.
          if (!removed) {
            removed = true;
            lifetimes.push(Date.now() - shownAt);
          }
          await overlay[Symbol.asyncDispose]();
        },
      };
    };
    await runScenario(slow, {
      steps: [
        { action: "click", role: "link", name: "Slow", pause: 100 },
        { action: "click", role: "button", name: "Stay", pause: 3000 },
      ],
    }, () => {}, stateFor(viewport, { effects: { ...quiet, captions: true }, captionLocale: "en" }));
    if (!(lifetimes[lifetimes.length - 1] >= 3000)) {
      fail("an earlier step's late page load should not remove this step's caption: " + JSON.stringify(lifetimes));
    }
    await slow.close();
  } finally {
    server.close();
  }
} finally {
  await browser.close();
}
EOF
fi

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
curl -s "$BASE/" | grep -q 'id="search-modal"' || fail "fixture public page should contain search modal"
curl -s "$BASE/" | grep -q 'id="menu-toggle"' || fail "fixture public page should have an RWD menu toggle"
[ "$(http_status "$BASE/app")" = "302" ] || fail "fixture protected page should redirect without a cookie"
[ "$(http_status -H 'Cookie: walkthrough_session=1' "$BASE/app")" = "200" ] \
  || fail "fixture protected page should be served with a session cookie"
curl -s -H 'Cookie: walkthrough_session=1' "$BASE/app" | grep -q 'id="menu-toggle"' \
  || fail "fixture dashboard page should have an RWD menu toggle"
[ "$(http_status -d 'username=a&password=b' "$BASE/login")" = "302" ] || fail "fixture login should redirect"
curl -s -D- -o /dev/null --max-time 5 -d 'username=a&password=b' "$BASE/login" \
  | grep -qi '^set-cookie: walkthrough_session=' || fail "fixture login should set the session cookie"

# The sign-in example types a password on camera: it reaches the form and signs
# in, and neither the password nor any caption drawn on the way carries it.
if [ "$check_status" -eq 0 ]; then
  DEMO_PASSWORD="fixture-secret-9f3" node --input-type=module <<EOF || fail "sign-in example"
import fs from "node:fs";
import { loadPlaywright, runScenario, validateScenario } from "file://${RECORD}";

const fail = (message) => {
  console.error(message);
  process.exit(1);
};

const scenario = JSON.parse(fs.readFileSync("${ROOT_DIR}/skills/to-walkthrough-video/examples/scenario-login.json", "utf8"));
const problems = validateScenario(scenario);
if (problems.length !== 0) {
  fail("the sign-in example should validate: " + problems.join("; "));
}
const playwright = await loadPlaywright();
const browser = await playwright.chromium.launch();
try {
  const page = await browser.newPage({ viewport: scenario.viewport });
  const drawn = [];
  const showOverlay = page.screencast.showOverlay.bind(page.screencast);
  page.screencast.showOverlay = async (html) => {
    drawn.push(html);
    return showOverlay(html);
  };
  await page.goto(scenario.url.replace("http://localhost:4173", "${BASE}"));
  const steps = scenario.steps.map((step) => ({ ...step, pause: 0, ms: 0 }));
  await runScenario(page, { ...scenario, steps }, () => {}, {
    x: 0, y: 0, startedAt: Date.now(), pauseMs: 0, captionLocale: scenario.captionLocale,
    effects: { zoom: false, cursor: false, captions: true },
  });
  if (!page.url().endsWith("/app")) {
    fail("the sign-in example should land on the dashboard: " + page.url());
  }
  const typed = drawn.filter((html) => html.includes("Type "));
  if (typed.length !== 2 || !typed[0].includes("Type demo") || !typed[1].includes("\u2022".repeat(8))) {
    fail("the sign-in example should caption the username and dots: " + JSON.stringify(typed));
  }
  if (drawn.some((html) => html.includes(process.env.DEMO_PASSWORD))) {
    fail("the sign-in example leaked its password into a caption");
  }
} finally {
  await browser.close();
}
EOF
fi

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

# clicks within the merge gap but far apart on screen (e.g. a corner click
# right after a center click) split too, so the zoom keeps following the
# cursor instead of freezing on the earlier click
cat >"$TMP_DIR/spatial.jsonl" <<'EOF'
{"t": 1000, "action": "click", "cx": 0.1, "cy": 0.1}
{"t": 2000, "action": "click", "cx": 0.9, "cy": 0.9}
EOF
node "$SUGGEST" --clicks "$TMP_DIR/spatial.jsonl" --duration-ms 30000 --out "$TMP_DIR/spatial.zooms.json"
COUNT="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).suggestions.length)" "$TMP_DIR/spatial.zooms.json")"
[ "$COUNT" = "2" ] || fail "expected 2 regions for a corner-to-corner jump, got $COUNT"
[ "$(jq_field "$TMP_DIR/spatial.zooms.json" suggestions.1.focus.cx)" = "0.6666666666666667" ] \
  || fail "second region should track the later click, not the first"

# clicks close in both time and space still merge, but the shared focus
# tracks the most recent click rather than sticking to the first
cat >"$TMP_DIR/recency.jsonl" <<'EOF'
{"t": 1000, "action": "click", "cx": 0.5, "cy": 0.5}
{"t": 2000, "action": "click", "cx": 0.55, "cy": 0.5}
EOF
node "$SUGGEST" --clicks "$TMP_DIR/recency.jsonl" --duration-ms 30000 --out "$TMP_DIR/recency.zooms.json"
COUNT="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).suggestions.length)" "$TMP_DIR/recency.zooms.json")"
[ "$COUNT" = "1" ] || fail "expected 1 merged region for a nearby jump, got $COUNT"
[ "$(jq_field "$TMP_DIR/recency.zooms.json" suggestions.0.focus.cx)" = "0.55" ] \
  || fail "merged focus should track the latest click"

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

node "$RENDER" --video "$TMP_DIR/src.mp4" --clicks "$TMP_DIR/render.clicks.jsonl" --out "$TMP_DIR/out.webm" \
  >/dev/null || fail "render-auto-zoom to webm failed"
CODEC="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$TMP_DIR/out.webm")"
[ "$CODEC" = "vp9" ] || fail "webm output should be VP9 (constant quality), got $CODEC"

echo "to-walkthrough-video tests passed"
