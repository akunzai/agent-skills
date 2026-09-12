#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { renderAutoZoom, transcode } from "./render-auto-zoom.mjs";
import { parseSamples, suggestZooms } from "./suggest-zooms.mjs";

export const DEFAULT_VIEWPORT = { width: 1280, height: 720 };
const PRE_CLICK_MS = 520;
export const POST_CLICK_MS = 2500;
export const SIGN_IN_TIMEOUT_MS = 180_000;

// How this recording gets its session. One name rather than a pair of flags
// switched on at every site that cares.
export function resolveSessionMode(options = {}) {
  const saved = Boolean(options.storageState);
  const interactive = Boolean(options.signIn);
  if (saved && interactive) {
    return "conflict";
  }
  if (saved) {
    return "saved";
  }
  return interactive ? "interactive" : "none";
}
const AUTH_EXPECT_TIMEOUT_MS = 15_000;

function printUsage(stream) {
  stream.write(`Usage: record.mjs --scenario FILE --out FILE [--width PX] [--height PX] [--pause-ms MS]
                  [--storage-state FILE] [--sign-in]

Drive a Playwright walkthrough with a pointer and click echo.
WebM keeps those effects without ffmpeg. Auto-zoom (and MP4) needs ffmpeg.
`);
}

function evenPx(value) {
  const n = Math.round(Number(value));
  if (!Number.isFinite(n) || n < 2) {
    return null;
  }
  return n % 2 === 0 ? n : n + 1;
}

export function resolveViewport(scenario, options) {
  const width = evenPx(options.width ?? scenario.viewport?.width ?? DEFAULT_VIEWPORT.width);
  const height = evenPx(options.height ?? scenario.viewport?.height ?? DEFAULT_VIEWPORT.height);
  if (!width || !height) {
    throw new Error("viewport width and height must be numbers >= 2");
  }
  return { width, height };
}

export function parseArgs(argv) {
  const args = {
    scenario: null,
    out: null,
    width: null,
    height: null,
    pauseMs: null,
    storageState: null,
    signIn: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      args.help = true;
    } else if (arg === "--scenario" || arg === "--out") {
      args[arg.slice(2)] = argv[i + 1];
      i += 1;
    } else if (arg === "--storage-state") {
      args.storageState = argv[i + 1];
      i += 1;
    } else if (arg === "--sign-in") {
      args.signIn = true;
    } else if (arg === "--width" || arg === "--height" || arg === "--pause-ms") {
      const key = arg === "--pause-ms" ? "pauseMs" : arg.slice(2);
      args[key] = Number(argv[i + 1]);
      i += 1;
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }
  return args;
}

function hasFfmpeg() {
  try {
    const result = spawnSync("ffmpeg", ["-hide_banner", "-version"], {
      stdio: "ignore",
      timeout: 5000,
    });
    return result.status === 0;
  } catch {
    return false;
  }
}

export function describeLaunchFailure(error, headed) {
  const message = String(error?.message ?? error);
  if (headed && /Missing X server|cannot open display|\$DISPLAY/i.test(message)) {
    return `--sign-in needs a screen to put the browser on, and this session has no display (${message})`;
  }
  return null;
}

async function launchChromium(playwright, options = {}) {
  const headless = options.headless ?? true;
  try {
    return await playwright.chromium.launch({ headless });
  } catch (error) {
    const explained = describeLaunchFailure(error, !headless);
    if (explained) {
      throw new Error(explained, { cause: error });
    }
    if (!String(error.message ?? error).includes("Executable doesn't exist")) {
      throw error;
    }
    try {
      return await playwright.chromium.launch({ headless, channel: "chrome" });
    } catch (retryError) {
      const retryExplained = describeLaunchFailure(retryError, !headless);
      throw retryExplained ? new Error(retryExplained, { cause: retryError }) : retryError;
    }
  }
}

function tryRequire(fromDir, spec) {
  try {
    const require = createRequire(path.join(fromDir, "noop.js"));
    return require(spec);
  } catch {
    return null;
  }
}

function asPlaywright(mod) {
  // Playwright's CJS export has `.chromium`; a file-URL import of index.js does not.
  if (mod?.chromium?.launch) {
    return mod;
  }
  if (mod?.default?.chromium?.launch) {
    return mod.default;
  }
  return null;
}

export async function loadPlaywright() {
  const dirs = [process.env.PLAYWRIGHT_DIR, process.cwd()].filter(Boolean);
  const specs = ["playwright", "playwright-core"];
  for (const dir of dirs) {
    for (const spec of specs) {
      const loaded = asPlaywright(tryRequire(dir, spec));
      if (loaded) {
        return loaded;
      }
    }
  }
  for (const spec of specs) {
    try {
      const loaded = asPlaywright(await import(spec));
      if (loaded) {
        return loaded;
      }
    } catch {
      // try the next specifier
    }
  }
  throw new Error(
    "Playwright is not installed. From the recording cwd: npm i -D playwright && npx playwright install chromium",
  );
}

function installCursor() {
  if (window.__tvrCursor?.mount) {
    window.__tvrCursor.mount();
    return;
  }

  const pageStyle = document.createElement("style");
  pageStyle.textContent =
    "html.__tvr-hide-cursor, html.__tvr-hide-cursor * { cursor: none !important; }";

  const host = document.createElement("div");
  host.setAttribute("data-tvr", "overlay");
  host.style.cssText =
    "position:fixed; inset:0; width:100vw; height:100vh; margin:0; padding:0;" +
    "border:none; background:transparent; overflow:hidden; pointer-events:none; z-index:2147483647;";

  const shadow = host.attachShadow({ mode: "open" });
  shadow.innerHTML = `
    <style>
      :host { pointer-events: none; }
      .cursor {
        position: absolute; left: 0; top: 0; width: 28px; height: 32px;
        transform-origin: 4px 3px;
        filter: drop-shadow(0 2px 3px rgba(0,0,0,.38));
      }
      .cursor svg { display: block; position: absolute; left: 0; top: 0; }
      .shape { opacity: 0; transition: opacity 130ms ease; }
      .shape-arrow { opacity: 1; }
      .cursor[data-icon="hand"] .shape-arrow { opacity: 0; }
      .cursor[data-icon="hand"] .shape-hand { opacity: 1; }
      .cursor[data-icon="text"] .shape-arrow { opacity: 0; }
      .cursor[data-icon="text"] .shape-text { opacity: 1; }
      .effects { position: absolute; inset: 0; }
      .ripple {
        position: absolute; width: 80px; height: 80px; margin: -40px 0 0 -40px;
        border-radius: 999px; border: 7px solid #2563EB; pointer-events: none;
        animation: tvr-ripple 400ms cubic-bezier(0.16, 1, 0.3, 1) forwards;
      }
      @keyframes tvr-ripple {
        0% { opacity: 0.85; transform: scale(1); }
        100% { opacity: 0; transform: scale(1.75); }
      }
    </style>
    <div class="effects"></div>
    <div class="cursor">
      <svg class="shape shape-arrow" width="28" height="32" viewBox="0 0 28 32" aria-hidden="true">
        <path fill="#111" stroke="#fff" stroke-width="1.55" stroke-linejoin="round"
          d="M3.8 2.6c-.18-.9.82-1.55 1.62-1.08L25.4 13.7c.82.48.62 1.68-.32 1.96l-10.1 3.05c-.24.07-.44.23-.54.46l-4.7 10.4c-.42.92-1.78.68-1.98-.34L3.8 2.6z"/>
      </svg>
      <svg class="shape shape-hand" width="26" height="28" viewBox="0 0 26 28" aria-hidden="true">
        <path fill="#111" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"
          d="M10 3.5a1.9 1.9 0 0 1 3.8 0v8.4l1.9.4V9.8a1.8 1.8 0 0 1 3.6 0v3.1l1.7.5a1.7 1.7 0 0 1 3.4.4v6.7c0 3.9-2.9 7-6.9 7h-3c-2.1 0-4-1-5.2-2.7l-4-5.6a1.9 1.9 0 0 1 2.9-2.4l1.8 1.7V3.5Z"/>
      </svg>
      <svg class="shape shape-text" width="16" height="28" viewBox="0 0 16 28" aria-hidden="true">
        <path fill="#111" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"
          d="M4 2h8v3.2H9.6v17.6H12V26H4v-3.2h2.4V5.2H4V2Z"/>
      </svg>
    </div>
  `;

  const cursorEl = shadow.querySelector(".cursor");
  const effectsEl = shadow.querySelector(".effects");

  const mount = () => {
    const root = document.documentElement;
    if (!root) {
      return;
    }
    root.classList.add("__tvr-hide-cursor");
    if (!pageStyle.isConnected) {
      root.appendChild(pageStyle);
    }
    if (!host.isConnected) {
      root.appendChild(host);
    }
  };
  const watch = () => {
    mount();
    new MutationObserver(mount).observe(document.documentElement, { childList: true, subtree: true });
  };
  if (document.documentElement) {
    watch();
  } else {
    document.addEventListener("DOMContentLoaded", watch, { once: true });
  }

  window.__tvrCursor = {
    mount,
    move(x, y) {
      mount();
      cursorEl.style.left = `${x}px`;
      cursorEl.style.top = `${y}px`;
    },
    setIcon(icon) {
      mount();
      if (icon === "hand" || icon === "text") {
        cursorEl.dataset.icon = icon;
      } else {
        delete cursorEl.dataset.icon;
      }
    },
    pulse(x, y) {
      mount();
      const el = document.createElement("div");
      el.className = "ripple";
      el.style.left = `${x}px`;
      el.style.top = `${y}px`;
      effectsEl.appendChild(el);
      el.addEventListener("animationend", () => el.remove());
    },
  };
}

export const EFFECT_DEFAULTS = { zoom: true, cursor: true, captions: true };

export function resolveEffects(scenario) {
  const given = scenario?.effects;
  if (given === undefined) {
    return { ...EFFECT_DEFAULTS };
  }
  if (given === null || typeof given !== "object" || Array.isArray(given)) {
    throw new Error("scenario.effects must be an object of booleans");
  }
  const effects = { ...EFFECT_DEFAULTS };
  for (const [key, value] of Object.entries(given)) {
    if (!(key in EFFECT_DEFAULTS)) {
      throw new Error(`unknown effect: ${key}; known effects are ${Object.keys(EFFECT_DEFAULTS).join(", ")}`);
    }
    if (typeof value !== "boolean") {
      throw new Error(`effects.${key} must be true or false`);
    }
    effects[key] = value;
  }
  return effects;
}

// A viewer reads their own keyboard, not Playwright's key syntax.
const KEYCAPS = {
  Meta: "\u2318",
  Control: "Ctrl",
  Shift: "\u21e7",
  Alt: "\u2325",
  Enter: "\u21b5",
  Escape: "Esc",
  Tab: "\u21e5",
  Backspace: "\u232b",
  ArrowUp: "\u2191",
  ArrowDown: "\u2193",
  ArrowLeft: "\u2190",
  ArrowRight: "\u2192",
};

export function formatKeys(keys) {
  return String(keys ?? "")
    .split("+")
    .map((part) => KEYCAPS[part] ?? (part.length === 1 ? part.toUpperCase() : part))
    .join(" + ");
}

const CAPTION_TEMPLATES = {
  en: {
    click: "Click {}",
    "double-click": "Double-click {}",
    type: "Type {}",
    select: "Select {}",
    press: "Press {}",
  },
  "zh-tw": {
    click: "\u9ede\u64ca {}",
    "double-click": "\u9023\u64ca {}",
    type: "\u8f38\u5165 {}",
    select: "\u9078\u64c7 {}",
    press: "\u6309\u4e0b {}",
  },
  ja: {
    click: "{} \u3092\u30af\u30ea\u30c3\u30af",
    "double-click": "{} \u3092\u30c0\u30d6\u30eb\u30af\u30ea\u30c3\u30af",
    type: "{} \u3068\u5165\u529b",
    select: "{} \u3092\u9078\u629e",
    press: "{} \u3092\u62bc\u3059",
  },
};

export const DEFAULT_CAPTION_LOCALE = "en";

export function resolveCaptionLocale(scenario) {
  const asked = String(scenario?.captionLocale ?? DEFAULT_CAPTION_LOCALE).toLowerCase();
  return asked in CAPTION_TEMPLATES ? asked : DEFAULT_CAPTION_LOCALE;
}

function captionSubject(step, action) {
  if (action === "type") {
    return String(step.text ?? "");
  }
  if (action === "select") {
    return String(step.value ?? step.option ?? step.label ?? "");
  }
  if (action === "press") {
    return formatKeys(step.keys);
  }
  return String(step.name ?? step.label ?? step.text ?? step.selector ?? "");
}

function captionAction(step) {
  const action = resolveAction(step);
  return action === "dblclick" ? "double-click" : action;
}

export function captionFor(step, locale = DEFAULT_CAPTION_LOCALE) {
  if (typeof step.caption === "string") {
    return step.caption;
  }
  const action = captionAction(step);
  const templates = CAPTION_TEMPLATES[locale] ?? CAPTION_TEMPLATES[DEFAULT_CAPTION_LOCALE];
  const template = templates[action];
  if (!template) {
    return null;
  }
  const subject = captionSubject(step, action);
  return subject ? template.replace("{}", subject) : null;
}

const HTML_ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (c) => HTML_ESCAPES[c]);
}

export function captionPosition(anchor, viewport = DEFAULT_VIEWPORT) {
  if (!anchor) {
    return { left: viewport.width / 2, top: viewport.height - 72 };
  }
  const below = anchor.y + 44;
  const top = below > viewport.height - 56 ? Math.max(24, anchor.y - 56) : below;
  const left = Math.min(Math.max(anchor.x, 140), Math.max(140, viewport.width - 140));
  return { left, top };
}

export function captionHtml(text, anchor, viewport = DEFAULT_VIEWPORT) {
  const { left, top } = captionPosition(anchor, viewport);
  return `<style>
    .tvr-caption {
      position: absolute; left: ${left}px; top: ${top}px; transform: translateX(-50%);
      font: 600 20px/1.4 system-ui, -apple-system, "Segoe UI", sans-serif;
      color: #fff; background: rgba(17,18,22,.82); padding: 10px 18px;
      border-radius: 999px; backdrop-filter: blur(6px); white-space: nowrap;
      box-shadow: 0 6px 24px rgba(0,0,0,.28);
    }
  </style>
  <div class="tvr-caption">${escapeHtml(text)}</div>`;
}

async function showCaption(page, state, step, anchor) {
  if (!state.effects?.captions) {
    return null;
  }
  const text = captionFor(step, state.captionLocale);
  if (!text) {
    return null;
  }
  const viewport = page.viewportSize() ?? DEFAULT_VIEWPORT;
  return page.screencast.showOverlay(captionHtml(text, anchor, viewport)).catch(() => null);
}

async function hideCaption(overlay) {
  await overlay?.[Symbol.asyncDispose]?.().catch(() => {});
}

export function resolveAction(step) {
  return step.action ?? (step.wait !== undefined ? "wait" : "click");
}

// A step's own action already says what kind of target it acts on, so the
// icon is read off that rather than inspected live from the page.
export function resolvePointerIcon(step) {
  const action = resolveAction(step);
  if (action === "click" || action === "dblclick" || action === "double-click" || action === "select") {
    return "hand";
  }
  if (action === "type") {
    return "text";
  }
  return null;
}

function locatorFor(page, step) {
  if (step.selector) {
    return page.locator(step.selector);
  }
  if (step.role) {
    const options = {};
    if (step.name !== undefined) {
      options.name = step.name;
    }
    if (step.exact) {
      options.exact = true;
    }
    return page.getByRole(step.role, options);
  }
  if (step.text) {
    return page.getByText(step.text, { exact: Boolean(step.exact) });
  }
  if (step.label) {
    return page.getByLabel(step.label);
  }
  throw new Error(`step needs selector, role, text, or label: ${JSON.stringify(step)}`);
}

async function animateMove(page, state, x, y) {
  const steps = 14;
  const fromX = state.x;
  const fromY = state.y;
  for (let i = 1; i <= steps; i += 1) {
    const t = i / steps;
    const eased = 0.5 - 0.5 * Math.cos(Math.PI * t);
    const nx = fromX + (x - fromX) * eased;
    const ny = fromY + (y - fromY) * eased;
    await page.mouse.move(nx, ny);
    await page.evaluate(
      ([cx, cy]) => {
        window.__tvrCursor?.move(cx, cy);
      },
      [nx, ny],
    ).catch(() => {});
    state.x = nx;
    state.y = ny;
  }
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function setPointerIcon(page, state, icon) {
  if (!state.effects?.cursor) {
    return;
  }
  await page.evaluate(
    (ic) => {
      window.__tvrCursor?.setIcon(ic);
    },
    icon,
  ).catch(() => {});
}

async function firePulses(page, x, y, times) {
  for (let i = 0; i < times; i += 1) {
    if (i > 0) {
      await sleep(150);
    }
    await page.evaluate(
      ([cx, cy]) => {
        window.__tvrCursor?.pulse(cx, cy);
      },
      [x, y],
    ).catch(() => {});
  }
}

export function resolvePauseMs(step, state) {
  if (Number.isFinite(step.pause) && step.pause >= 0) {
    return step.pause;
  }
  if (Number.isFinite(state.pauseMs) && state.pauseMs >= 0) {
    return state.pauseMs;
  }
  return POST_CLICK_MS;
}

export async function runScenario(page, scenario, log, state) {
  const steps = scenario.steps ?? [];
  const effects = state.effects ?? EFFECT_DEFAULTS;
  for (let index = 0; index < steps.length; index += 1) {
    const step = steps[index];
    const action = resolveAction(step);
    if (action === "wait") {
      await sleep(Number(step.ms ?? step.wait ?? 0));
      continue;
    }
    if (action === "goto") {
      await page.goto(step.url, { waitUntil: "domcontentloaded" });
      await installOverlay(page, state);
      continue;
    }
    if (action === "press") {
      // The keypress itself is instantaneous, so the caption has to hold for
      // the step's pause or nobody reads it.
      const pressCaption = await showCaption(page, state, step);
      await page.keyboard.press(String(step.keys));
      await sleep(resolvePauseMs(step, state));
      await hideCaption(pressCaption);
      continue;
    }
    const locator = locatorFor(page, step);
    await locator.first().waitFor({ state: "visible", timeout: 15_000 });
    const box = await locator.first().boundingBox();
    if (!box) {
      throw new Error(`no bounding box for ${JSON.stringify(step)}`);
    }
    const x = box.x + box.width / 2;
    const y = box.y + box.height / 2;
    if (effects.cursor) {
      await animateMove(page, state, x, y);
      await installOverlay(page, state);
      await syncCursor(page, state);
      await setPointerIcon(page, state, resolvePointerIcon(step));
    } else {
      await page.mouse.move(x, y);
      state.x = x;
      state.y = y;
    }
    await sleep(PRE_CLICK_MS);
    const viewport = page.viewportSize() ?? DEFAULT_VIEWPORT;
    const button = step.button ?? "left";
    const isDouble = action === "dblclick" || action === "double-click";
    const interaction = isDouble ? "double-click" : "click";
    log({
      t: Date.now() - state.startedAt,
      action: interaction,
      button,
      cx: x / viewport.width,
      cy: y / viewport.height,
    });
    if (effects.cursor && (action === "click" || isDouble)) {
      await firePulses(page, x, y, isDouble ? 2 : 1);
    }
    const caption = await showCaption(page, state, step, { x, y });
    if (action === "dblclick" || action === "double-click") {
      await page.mouse.dblclick(x, y);
    } else {
      await page.mouse.click(x, y, { button });
      if (action === "type") {
        const typed = String(step.text ?? "");
        if (typed) {
          await locator.first().pressSequentially(typed, { delay: 90 });
        }
      } else if (action === "select") {
        const value = step.value ?? step.option ?? step.label;
        if (value === undefined) {
          throw new Error(`select step needs value: ${JSON.stringify(step)}`);
        }
        await locator.first().selectOption({ label: String(value) }).catch(async () => {
          await locator.first().selectOption(String(value));
        });
      }
    }
    await sleep(resolvePauseMs(step, state));
    await hideCaption(caption);
    await installOverlay(page, state);
    await syncCursor(page, state);
    await setPointerIcon(page, state, null);
  }
}

// A navigation or a framework re-render can drop the host, so the overlay is
// re-evaluated rather than trusted to survive.
async function installOverlay(page, state) {
  if (!state.effects?.cursor) {
    return;
  }
  await page.evaluate(installCursor).catch(() => {});
}

async function syncCursor(page, state) {
  if (!state.effects?.cursor) {
    return;
  }
  await page.evaluate(
    ([x, y]) => {
      window.__tvrCursor?.move(x, y);
    },
    [state.x, state.y],
  ).catch(() => {});
}

export async function recordWalkthrough(options) {
  const scenario = options.scenario;
  const sessionMode = resolveSessionMode(options);
  const signIn = sessionMode === "interactive";
  const authMode = sessionMode === "saved";
  const problems = [
    ...(authMode ? storageStateProblems(options.storageState) : []),
    ...validateScenario(scenario, { sessionMode }),
  ];
  if (problems.length > 0) {
    throw new Error(`refusing to record:\n- ${problems.join("\n- ")}`);
  }
  const effects = resolveEffects(scenario);
  if (authMode) {
    for (const warning of storageStateWarnings(options.storageState)) {
      process.stderr.write(`warning: ${warning}\n`);
    }
  }
  const outPath = path.resolve(options.out);
  const viewport = resolveViewport(scenario, options);
  const wantWebm = /\.webm$/i.test(outPath);
  const ffmpeg = hasFfmpeg();
  if (!ffmpeg && !wantWebm) {
    throw new Error("ffmpeg is required for auto-zoom, and for any output that is not .webm");
  }
  const playwright = options.playwright ?? (await loadPlaywright());
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "to-walkthrough-video-"));
  const browser = await launchChromium(playwright, { headless: !signIn });
  const context = await browser.newContext({
    viewport,
    deviceScaleFactor: 1,
    ...(authMode ? { storageState: path.resolve(options.storageState) } : {}),
  });
  if (effects.cursor && !signIn) {
    await context.addInitScript(installCursor);
  }
  const page = await context.newPage();
  if (typeof page.screencast?.start !== "function") {
    await context.close().catch(() => {});
    await browser.close().catch(() => {});
    fs.rmSync(tmp, { recursive: true, force: true });
    throw new Error("page.screencast is missing: this skill needs Playwright 1.59 or newer");
  }
  const clicks = [];
  const log = (entry) => {
    clicks.push(entry);
  };
  const state = {
    x: viewport.width / 2,
    y: viewport.height / 2,
    startedAt: Date.now(),
    pauseMs: Number.isFinite(options.pauseMs)
      ? options.pauseMs
      : Number.isFinite(scenario.pauseMs)
        ? scenario.pauseMs
        : POST_CLICK_MS,
    effects,
    captionLocale: resolveCaptionLocale(scenario),
  };
  const rawPath = path.join(tmp, "raw.webm");

  try {
    await page.goto(scenario.url, { waitUntil: "domcontentloaded" });
    if (!signIn) {
      await installOverlay(page, state);
    }
    await ensureSignedIn(page, scenario, { signIn });
    if (signIn) {
      if (!samePage(page.url(), scenario.url)) {
        // Signing in usually lands somewhere of the system's choosing.
        await page.goto(scenario.url, { waitUntil: "domcontentloaded" });
        // That navigation can bounce straight back to the login screen, which
        // is the one frame this mode exists to keep out of the file.
        await ensureSignedIn(page, scenario);
      }
      if (effects.cursor) {
        await context.addInitScript(installCursor);
      }
      await installOverlay(page, state);
    }
    await page.locator("h1").first().waitFor({ state: "visible", timeout: 15_000 }).catch(() => {});
    await sleep(500);
    // Capture starts where the click timeline starts, so nothing has to be
    // trimmed back off later.
    await page.screencast.start({ path: rawPath, size: viewport });
    state.startedAt = Date.now();
    await syncCursor(page, state);
    await runScenario(page, scenario, log, state);
    await sleep(600);
  } catch (error) {
    await page.screencast.stop().catch(() => {});
    await context.close().catch(() => {});
    await browser.close().catch(() => {});
    fs.rmSync(tmp, { recursive: true, force: true });
    throw error;
  }

  const stoppedAt = Date.now();
  await page.screencast.stop();
  await context.close();
  await browser.close();
  const stem = outPath.replace(/\.(mp4|webm)$/i, "");
  const clicksPath = `${stem}.clicks.jsonl`;
  const zoomsPath = `${stem}.zooms.json`;
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(clicksPath, `${clicks.map((entry) => JSON.stringify(entry)).join("\n")}\n`);

  try {
    if (!fs.existsSync(rawPath)) {
      throw new Error("Playwright did not write a video");
    }

    let zoomDoc;
    if (ffmpeg && effects.zoom) {
      const rendered = await renderAutoZoom({
        video: rawPath,
        out: outPath,
        clicks: clicksPath,
      });
      zoomDoc = { status: rendered.status, suggestions: rendered.suggestions };
    } else {
      if (ffmpeg && !wantWebm) {
        await transcode({ video: rawPath, out: outPath });
      } else {
        fs.copyFileSync(rawPath, outPath);
      }
      zoomDoc = suggestZooms(clicks, Math.max(1, stoppedAt - state.startedAt));
    }
    fs.writeFileSync(zoomsPath, `${JSON.stringify(zoomDoc, null, 2)}\n`);

    return {
      out: outPath,
      clicks: clicksPath,
      zooms: zoomsPath,
      status: zoomDoc.status,
      samples: parseSamples(fs.readFileSync(clicksPath, "utf8")),
      suggestions: zoomDoc.suggestions,
      preview: zoomDoc,
    };
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

// What the scenario itself must carry. What a walkthrough types on camera is
// the author's call, so nothing here inspects step text.
export function validateScenario(scenario, options = {}) {
  const problems = [];
  const steps = scenario.steps ?? [];
  for (let index = 0; index < steps.length; index += 1) {
    if (resolveAction(steps[index]) === "press" && !steps[index].keys) {
      problems.push(`steps[${index}] is a press step without keys`);
    }
  }
  try {
    resolveEffects(scenario);
  } catch (error) {
    problems.push(error.message);
  }
  if (options.sessionMode === "conflict") {
    problems.push(
      "--sign-in and --storage-state do the same job from opposite ends: one makes a session, the other loads one. Pick one.",
    );
  } else if (options.sessionMode === "saved" && !scenario.auth?.expect) {
    problems.push(
      "--storage-state needs scenario.auth.expect: a locator visible only once signed in",
    );
  } else if (options.sessionMode === "interactive" && !scenario.auth?.expect) {
    problems.push(
      "--sign-in needs scenario.auth.expect: a locator visible only once signed in",
    );
  }
  return problems;
}

export function storageStateProblems(file) {
  const abs = path.resolve(file);
  if (!fs.existsSync(abs)) {
    return [`${abs} does not exist; create it with: npx playwright open --save-storage=${file} <url>`];
  }
  try {
    JSON.parse(fs.readFileSync(abs, "utf8"));
  } catch {
    return [`${abs} is not a Playwright storage state file`];
  }
  return [];
}

// A storage state impersonates the account that made it for as long as the
// session lives, so a committable one is worth saying out loud. Playwright says
// the same: https://playwright.dev/docs/auth. It is a warning, not a refusal —
// where the file lives is the author's call.
export function storageStateWarnings(file) {
  const abs = path.resolve(file);
  const dir = path.dirname(abs);
  const inWorkTree = spawnSync("git", ["-C", dir, "rev-parse", "--is-inside-work-tree"], {
    encoding: "utf8",
  });
  if (inWorkTree.status !== 0 || inWorkTree.stdout.trim() !== "true") {
    return [];
  }
  const ignored = spawnSync("git", ["-C", dir, "check-ignore", "--quiet", abs], { stdio: "ignore" });
  if (ignored.status === 0) {
    return [];
  }
  return [`${abs} sits in a git work tree and is not ignored; consider adding it to .gitignore`];
}

// auth.expect invisible means two different things. With a saved state it is a
// dead session; with --sign-in it is simply nobody having signed in yet, which
// is exactly what this is waiting for.
export function samePage(a, b) {
  try {
    const left = new URL(a);
    const right = new URL(b);
    return left.origin === right.origin && left.pathname === right.pathname;
  } catch {
    return a === b;
  }
}

export async function ensureSignedIn(page, scenario, options = {}) {
  const expect = scenario.auth?.expect;
  if (!expect) {
    return;
  }
  const signIn = Boolean(options.signIn);
  const timeout = signIn ? SIGN_IN_TIMEOUT_MS : AUTH_EXPECT_TIMEOUT_MS;
  if (signIn) {
    process.stderr.write(
      `Sign in yourself in the browser window now, at ${page.url()}. ` +
        `Recording starts once you are in, and waits up to ${Math.round(timeout / 60_000)} minutes.\n`,
    );
  }
  try {
    await locatorFor(page, expect).first().waitFor({ state: "visible", timeout });
  } catch {
    if (signIn) {
      throw new Error(
        "nobody signed in before the wait ran out, so there is nothing to record",
      );
    }
    throw new Error(
      "auth.expect never became visible: the saved storage state has most likely expired. " +
        "Sign in again with: npx playwright open --save-storage=<file> <url>. " +
        "A session held only in sessionStorage cannot be reused this way.",
    );
  }
}

export async function main(argv = process.argv.slice(2), io = process) {
  let args;
  try {
    args = parseArgs(argv);
  } catch (error) {
    printUsage(io.stderr);
    io.stderr.write(`${error.message}\n`);
    return 2;
  }

  if (args.help) {
    printUsage(io.stdout);
    return 0;
  }

  if (!args.scenario || !args.out) {
    printUsage(io.stderr);
    return 2;
  }

  try {
    const scenarioPath = path.resolve(args.scenario);
    let scenario;
    try {
      scenario = JSON.parse(fs.readFileSync(scenarioPath, "utf8"));
    } catch {
      throw new Error(`${scenarioPath} is not readable JSON`);
    }
    if (!scenario.url) {
      throw new Error("scenario.json needs a url");
    }
    const result = await recordWalkthrough({
      scenario,
      out: args.out,
      width: args.width,
      height: args.height,
      pauseMs: args.pauseMs,
      storageState: args.storageState,
      signIn: args.signIn,
    });
    io.stdout.write(
      `${JSON.stringify({ out: result.out, clicks: result.clicks, zooms: result.zooms, status: result.status }, null, 2)}\n`,
    );
    return 0;
  } catch (error) {
    io.stderr.write(`${error.message}\n`);
    return 1;
  }
}

// Skills are installed as symlinks, so argv[1] is the link while import.meta.url
// is always the real path. Comparing them unresolved makes main() never run, and
// the command exits 0 having done nothing.
function isMainModule(arg) {
  if (!arg) {
    return false;
  }
  try {
    return import.meta.url === pathToFileURL(fs.realpathSync(path.resolve(arg))).href;
  } catch {
    return false;
  }
}

if (isMainModule(process.argv[1])) {
  main().then((code) => {
    process.exit(code);
  });
}
