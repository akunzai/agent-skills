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
                  [--check-prereqs]

Drive a Playwright walkthrough with a pointer, click echo, and auto-zoom.
Auto-zoom works on both WebM and MP4, but requires ffmpeg.
Without ffmpeg, output is raw WebM without zoom (pointer & click echo only).
`);
}

function evenPx(value) {
  const n = Math.round(Number(value));
  if (!Number.isFinite(n) || n < 2) {
    return null;
  }
  return n % 2 === 0 ? n : n + 1;
}

export function resolveViewport(scenario, options, device) {
  const width = evenPx(
    options.width ?? scenario.viewport?.width ?? device?.viewport?.width ?? DEFAULT_VIEWPORT.width,
  );
  const height = evenPx(
    options.height ?? scenario.viewport?.height ?? device?.viewport?.height ?? DEFAULT_VIEWPORT.height,
  );
  if (!width || !height) {
    throw new Error("viewport width and height must be numbers >= 2");
  }
  return { width, height };
}

// "phone" names a shape, not a model: the newest matching entry in this
// Playwright's own device list is picked at call time, so the default tracks
// whatever Playwright currently ships without this file naming a model that
// goes stale the moment Apple (or Playwright) ships another one.
const DEVICE_PRESET_PATTERNS = {
  phone: /^iPhone (\d+) Pro$/,
};

// "tablet" is pinned to iPad Mini rather than picked by the same generation
// pattern as "phone": Playwright ships one undated "iPad Mini" entry with no
// generation to pick among, and its narrower width also matters on its own
// merits — an iPad Pro's viewport is wide enough that plenty of real
// responsive sites already show their desktop nav on it, so a "tablet"
// recording would silently miss the mobile-style interaction (e.g. an
// expand-menu tap) it was asked to demonstrate.
const DEVICE_PRESET_ALIASES = {
  tablet: "iPad Mini",
};

export function pickLatestDevice(devices, pattern) {
  let bestName = null;
  let bestGen = -1;
  for (const name of Object.keys(devices ?? {})) {
    const match = name.match(pattern);
    if (!match) {
      continue;
    }
    const gen = Number(match[1]);
    if (gen > bestGen) {
      bestGen = gen;
      bestName = name;
    }
  }
  return bestName;
}

export function resolveDevice(playwright, scenario) {
  const requested = scenario.device;
  if (!requested) {
    return null;
  }
  const pattern = DEVICE_PRESET_PATTERNS[requested];
  const alias = DEVICE_PRESET_ALIASES[requested];
  const name = pattern ? pickLatestDevice(playwright.devices, pattern) : alias ?? requested;
  const descriptor = name ? playwright.devices[name] : null;
  if (!descriptor) {
    throw new Error(
      pattern || alias
        ? `no ${requested} device preset found in this Playwright's devices registry`
        : `unknown scenario.device: ${requested} (not "phone", "tablet", or a name in playwright.devices)`,
    );
  }
  return { name, ...descriptor };
}

function contextOptionsForDevice(device) {
  if (!device) {
    return {};
  }
  const { viewport, userAgent, deviceScaleFactor, isMobile, hasTouch } = device;
  return { viewport, userAgent, deviceScaleFactor, isMobile, hasTouch };
}

export function resolveContextOptions(scenario, device, viewport, storageState) {
  return {
    ...contextOptionsForDevice(device),
    viewport,
    ...(device ? {} : { deviceScaleFactor: 1 }),
    ...(storageState ? { storageState: path.resolve(storageState) } : {}),
    ...(scenario.locale ? { locale: scenario.locale } : {}),
    ...(scenario.ignoreHTTPSErrors ? { ignoreHTTPSErrors: true } : {}),
  };
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
    checkPrereqs: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      args.help = true;
    } else if (arg === "--check-prereqs") {
      args.checkPrereqs = true;
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
    try {
      const direct = path.join(fromDir, spec);
      if (fs.existsSync(direct)) {
        const require = createRequire(path.join(direct, "package.json"));
        return require(direct);
      }
    } catch {
      // ignore
    }
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

// Where each package manager's global install puts playwright. Bun's global
// root is a fixed path, not something `bun pm` prints; `yarn global dir` exists
// only in Yarn Classic and fails harmlessly under Berry.
export function getGlobalNodeDirs(options = {}) {
  const env = options.env ?? process.env;
  const spawnOpts = {
    encoding: "utf8",
    timeout: 3000,
    stdio: ["ignore", "pipe", "ignore"],
    shell: process.platform === "win32",
  };
  const run = options.run ?? ((cmd, argv) => spawnSync(cmd, argv, spawnOpts));
  const dirs = [];
  const add = (p) => {
    if (p && !dirs.includes(p)) {
      dirs.push(p);
    }
  };
  if (env.NODE_PATH) {
    env.NODE_PATH.split(path.delimiter).filter(Boolean).forEach(add);
  }
  const probes = [
    ["npm", ["root", "-g"], ""],
    ["pnpm", ["root", "-g"], ""],
    ["yarn", ["global", "dir"], "node_modules"],
  ];
  for (const [cmd, argv, suffix] of probes) {
    try {
      const res = run(cmd, argv);
      const out = res?.status === 0 && typeof res.stdout === "string" ? res.stdout.trim() : "";
      if (out) {
        add(path.join(out, suffix));
      }
    } catch {
      // package manager not on PATH or failed
    }
  }
  const bunRoot = env.BUN_INSTALL_GLOBAL_DIR ?? path.join(env.BUN_INSTALL ?? path.join(os.homedir(), ".bun"), "install", "global");
  add(path.join(bunRoot, "node_modules"));
  return dirs;
}

export async function loadPlaywright(options = {}) {
  const globalDirs = options.globalDirs ?? getGlobalNodeDirs();
  const dirs = [process.env.PLAYWRIGHT_DIR, process.cwd(), ...globalDirs].filter(Boolean);
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
    "Playwright is not installed. To avoid repo pollution, ask user authorization to install globally (npm i -g playwright && npx playwright install chromium) or in recording cwd (npm i -D playwright && npx playwright install chromium)",
  );
}

export function getFfmpegInstallAdvice(options = {}) {
  const checkMise = options.hasMise ?? (() => {
    try {
      const res = spawnSync("mise", ["--version"], { stdio: "ignore", timeout: 2000 });
      return res.status === 0;
    } catch {
      return false;
    }
  });
  const platform = options.platform ?? process.platform;
  let sysCmd = "see https://ffmpeg.org/download.html";
  if (platform === "darwin") {
    sysCmd = "brew install ffmpeg";
  } else if (platform === "linux") {
    sysCmd = "sudo apt install ffmpeg";
  } else if (platform === "win32") {
    sysCmd = "winget install Gyan.FFmpeg";
  }

  if (checkMise()) {
    return `To install ffmpeg, ask user authorization to run: mise use -g ffmpeg (or system package manager: ${sysCmd})`;
  }
  return `To install ffmpeg, ask user authorization to install via mise (curl https://mise.run | sh && mise use -g ffmpeg) or system package manager (${sysCmd})`;
}

export async function checkPrereqs(options = {}) {
  const result = {
    ok: true,
    playwright: false,
    browser: false,
    browserType: null,
    ffmpeg: false,
    messages: [],
  };

  const ffmpegChecker = options.hasFfmpeg ?? hasFfmpeg;
  if (ffmpegChecker()) {
    result.ffmpeg = true;
    result.messages.push("ffmpeg: available");
  } else {
    const advice = getFfmpegInstallAdvice(options);
    result.messages.push(
      `ffmpeg: not found on PATH (raw WebM recording works, but auto-zoom and MP4 conversion require ffmpeg. ${advice})`,
    );
  }

  let playwright;
  try {
    const loader = options.loadPlaywright ?? loadPlaywright;
    playwright = options.playwright ?? (await loader());
    result.playwright = true;
    result.messages.push("Playwright: available");
  } catch (error) {
    result.ok = false;
    result.messages.push(`Playwright: missing (${error.message})`);
    return result;
  }

  try {
    const launcher = options.launchChromium ?? launchChromium;
    const browser = await launcher(playwright, { headless: true });
    result.browser = true;
    result.browserType = browser.browserType?.()?.name?.() ?? "chromium";
    await browser.close?.();
    result.messages.push(`Browser: ${result.browserType} launched successfully`);
  } catch (error) {
    result.ok = false;
    result.messages.push(
      `Browser: launch failed (${error.message}). Run: npx playwright install chromium`,
    );
  }

  return result;
}

export function findTopLayerHost(doc = globalThis.document) {
  if (!doc) {
    return null;
  }
  try {
    const modals = Array.from(
      doc.querySelectorAll("dialog:modal, [popover]:popover-open"),
    ).filter((el) => !el.tagName?.toLowerCase().startsWith("x-pw") && !el.hasAttribute?.("data-tvr"));
    if (modals.length > 0) {
      return modals[modals.length - 1];
    }
  } catch {
    const dialogs = Array.from(doc.querySelectorAll("dialog[open]")).filter(
      (el) => !el.tagName?.toLowerCase().startsWith("x-pw") && !el.hasAttribute?.("data-tvr"),
    );
    if (dialogs.length > 0) {
      return dialogs[dialogs.length - 1];
    }
  }
  return doc.fullscreenElement || doc.documentElement;
}

export function bringOverlayToFront(doc = globalThis.document) {
  if (!doc) {
    return;
  }
  const glass = doc.querySelector?.("x-pw-glass");
  if (glass && typeof glass.showPopover === "function") {
    try {
      glass.hidePopover();
      glass.showPopover();
    } catch {
      // ignore
    }
  }
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
        transform: scale(var(--tvr-k, 1)); transform-origin: 4px 3px;
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
        position: absolute; width: calc(80px * var(--tvr-k, 1)); height: calc(80px * var(--tvr-k, 1));
        margin: calc(-40px * var(--tvr-k, 1)) 0 0 calc(-40px * var(--tvr-k, 1));
        border-radius: 999px; border: calc(7px * var(--tvr-k, 1)) solid #2563EB; pointer-events: none;
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

  const findTopLayerHost = () => {
    try {
      const modals = Array.from(
        document.querySelectorAll("dialog:modal, [popover]:popover-open"),
      ).filter((el) => !el.tagName.toLowerCase().startsWith("x-pw") && !el.hasAttribute("data-tvr"));
      if (modals.length > 0) {
        return modals[modals.length - 1];
      }
    } catch {
      const dialogs = Array.from(document.querySelectorAll("dialog[open]")).filter(
        (el) => !el.tagName.toLowerCase().startsWith("x-pw") && !el.hasAttribute("data-tvr"),
      );
      if (dialogs.length > 0) {
        return dialogs[dialogs.length - 1];
      }
    }
    return document.fullscreenElement || document.documentElement;
  };

  const mount = () => {
    const root = document.documentElement;
    if (!root) {
      return;
    }
    root.classList.add("__tvr-hide-cursor");
    if (!pageStyle.isConnected) {
      root.appendChild(pageStyle);
    }
    const container = findTopLayerHost();
    if (host.parentElement !== container) {
      container.appendChild(host);
    }
    // A zoomed-out page shrinks whatever is drawn into it, so the pointer and
    // its ring are scaled back up to their size on screen.
    host.style.setProperty("--tvr-k", String(1 / (window.visualViewport?.scale || 1)));
  };
  const syncGlass = () => {
    try {
      const glass = document.querySelector("x-pw-glass");
      if (glass && typeof glass.showPopover === "function" && glass.matches?.(":popover-open")) {
        glass.hidePopover();
        glass.showPopover();
      }
    } catch {
      // ignore
    }
  };
  const onTopLayerChange = (event) => {
    if (event?.target?.tagName?.toLowerCase().startsWith("x-pw")) {
      return;
    }
    mount();
    syncGlass();
  };
  const watch = () => {
    mount();
    new MutationObserver(onTopLayerChange).observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["open", "popover"],
    });
    document.addEventListener("toggle", onTopLayerChange, true);
    document.addEventListener("close", onTopLayerChange, true);
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
      const rect = host.getBoundingClientRect();
      cursorEl.style.left = `${x - rect.left}px`;
      cursorEl.style.top = `${y - rect.top}px`;
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
      const rect = host.getBoundingClientRect();
      const el = document.createElement("div");
      el.className = "ripple";
      el.style.left = `${x - rect.left}px`;
      el.style.top = `${y - rect.top}px`;
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

const CAPTION_GUTTER = 16;
const CAPTION_MAX_WIDTH = 720;
const NARROW_VIEWPORT = 640;

// Where a step's click opens something, a menu below its toggle say, only the
// scenario author knows, so "auto" can be overridden per step.
export const CAPTION_PLACEMENTS = ["auto", "above", "below", "bottom"];

// A caption wraps at a known width instead of running on in one line, so it
// can be centred where its widest line still stays inside a phone's viewport.
export function captionPosition(anchor, viewport = DEFAULT_VIEWPORT, placement = "auto") {
  const maxWidth = Math.min(CAPTION_MAX_WIDTH, viewport.width - 2 * CAPTION_GUTTER);
  if (!anchor || placement === "bottom") {
    return { left: viewport.width / 2, bottom: 24, maxWidth };
  }
  const half = maxWidth / 2 + CAPTION_GUTTER;
  const left = Math.min(Math.max(anchor.x, half), viewport.width - half);
  const below = anchor.y + 44;
  if (placement === "above" || (placement !== "below" && below > viewport.height - 56)) {
    // Held by its bottom edge, so a wrapped line grows away from the target.
    return { left, bottom: viewport.height - anchor.y + 12, maxWidth };
  }
  return { left, top: below, maxWidth };
}

// anchor and viewport are in screen pixels; scale is pageScale(), and the
// caption is emitted in the page's CSS pixels so it reads the same size either way.
export function captionHtml(text, anchor, viewport = DEFAULT_VIEWPORT, placement = "auto", scale = 1) {
  const { left, top, bottom, maxWidth } = captionPosition(anchor, viewport, placement);
  const css = (px) => `${px / scale}px`;
  const vertical = top === undefined ? `bottom: ${css(bottom)}` : `top: ${css(top)}`;
  const origin = top === undefined ? "50% 100%" : "50% 0";
  const fontSize = viewport.width < NARROW_VIEWPORT ? 16 : 20;
  return `<style>
    .tvr-caption {
      position: absolute; left: ${css(left)}; ${vertical};
      transform: translateX(-50%) scale(${1 / scale}); transform-origin: ${origin};
      box-sizing: border-box; width: max-content; max-width: ${maxWidth}px;
      font: 600 ${fontSize}px/1.4 system-ui, -apple-system, "Segoe UI", sans-serif;
      color: #fff; background: rgba(17,18,22,.82); padding: 10px 18px;
      border-radius: 24px; backdrop-filter: blur(6px); text-align: center;
      overflow-wrap: anywhere; box-shadow: 0 6px 24px rgba(0,0,0,.28);
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
  // A page an earlier step loaded can still be short of DOMContentLoaded
  // while its content is already usable; waiting here leaves only this step's
  // own navigation to take the caption down below.
  await page.waitForLoadState("domcontentloaded").catch(() => {});
  // The overlay is drawn into the page, so it is placed in CSS pixels and
  // zoomed with the page; it is laid out in screen pixels and scaled back.
  const screen = page.viewportSize() ?? DEFAULT_VIEWPORT;
  const scale = pageScale(screen, await cssViewport(page, screen));
  const onScreen = anchor ? { x: anchor.x * scale, y: anchor.y * scale } : undefined;
  const html = captionHtml(text, onScreen, screen, step.captionPlacement, scale);
  const overlay = await page.screencast.showOverlay(html).catch(() => null);
  if (!overlay) {
    return null;
  }
  await page.evaluate(bringOverlayToFront).catch(() => {});
  // The overlay belongs to the page, not the document, so a step that
  // navigates would otherwise go on captioning the page it lands on.
  const dispose = () => overlay[Symbol.asyncDispose]?.().catch(() => {});
  page.once("domcontentloaded", dispose);
  return { page, dispose };
}

async function hideCaption(caption) {
  if (!caption) {
    return;
  }
  caption.page.off("domcontentloaded", caption.dispose);
  await caption.dispose();
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

// A touch device taps, and a tap is where touchstart and pointerType "touch"
// come from; a site can behave differently for it, which may be the very thing
// the recording is for. Touch has no double-click or secondary button, so
// those still go through the mouse.
export function resolveInput(step, state) {
  const action = resolveAction(step);
  const tappable = action === "click" || action === "type" || action === "select";
  return state.touch && tappable && (step.button ?? "left") === "left" ? "tap" : "mouse";
}

async function animateMove(page, state, x, y, options = {}) {
  const hover = options.hover ?? true;
  const steps = 14;
  const fromX = state.x;
  const fromY = state.y;
  for (let i = 1; i <= steps; i += 1) {
    const t = i / steps;
    const eased = 0.5 - 0.5 * Math.cos(Math.PI * t);
    const nx = fromX + (x - fromX) * eased;
    const ny = fromY + (y - fromY) * eased;
    if (hover) {
      await page.mouse.move(nx, ny);
    }
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

// The centre of the part of the box on screen, or null when none of it is: an
// element taller than the viewport still gets a point the viewer can see, and
// a point off screen would hit whatever else sits there, or nothing.
export function targetPoint(box, viewport = DEFAULT_VIEWPORT) {
  const left = Math.max(box.x, 0);
  const top = Math.max(box.y, 0);
  const right = Math.min(box.x + box.width, viewport.width);
  const bottom = Math.min(box.y + box.height, viewport.height);
  if (right <= left || bottom <= top) {
    return null;
  }
  return { x: (left + right) / 2, y: (top + bottom) / 2 };
}

// Boxes, the pointer, and anything drawn into the page are in the page's own
// CSS pixels. A phone page without a viewport meta tag lays out wider than
// the screen and is zoomed out to fit, so innerWidth/innerHeight, not
// page.viewportSize(), is what they are measured against; Playwright's own
// clickable point is clipped against the same.
async function cssViewport(page, fallback) {
  return page.evaluate(() => ({ width: innerWidth, height: innerHeight })).catch(() => fallback);
}

// How many screen pixels one CSS pixel covers: 1 unless the page is zoomed out.
export function pageScale(screen, css) {
  return css?.width > 0 ? screen.width / css.width : 1;
}

// The pointer acts at viewport coordinates so it can be drawn getting there,
// which skips the scroll a locator action would do for itself. It scrolls
// with the DOM rather than scrollIntoViewIfNeeded(), which also waits for the
// box to stop moving and so never returns for a pulsing or sliding target.
async function scrollToTarget(page, target) {
  const box = await target.boundingBox();
  if (!box) {
    return null;
  }
  const viewport = await cssViewport(page, page.viewportSize() ?? DEFAULT_VIEWPORT);
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;
  if (cx >= 0 && cx <= viewport.width && cy >= 0 && cy <= viewport.height) {
    return box;
  }
  await target.evaluate((el) => {
    el.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
  });
  return target.boundingBox();
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
    const box = await scrollToTarget(page, locator.first());
    if (!box) {
      throw new Error(`no bounding box for ${JSON.stringify(step)}`);
    }
    const viewport = await cssViewport(page, page.viewportSize() ?? DEFAULT_VIEWPORT);
    const target = targetPoint(box, viewport);
    if (!target) {
      throw new Error(`target is outside the viewport even after scrolling: ${JSON.stringify(step)}`);
    }
    const { x, y } = target;
    const input = resolveInput(step, state);
    // A finger does not hover on its way to the target, so a tap moves only
    // the drawn pointer and leaves hover-only UI closed.
    const hover = input === "mouse";
    if (effects.cursor) {
      await animateMove(page, state, x, y, { hover });
      await installOverlay(page, state);
      await syncCursor(page, state);
      await setPointerIcon(page, state, resolvePointerIcon(step));
    } else {
      if (hover) {
        await page.mouse.move(x, y);
      }
      state.x = x;
      state.y = y;
    }
    // Shown while the pointer rests rather than at the click, so a step that
    // navigates, and so takes its caption with it, is still read first.
    const caption = await showCaption(page, state, step, { x, y });
    await sleep(PRE_CLICK_MS);
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
    if (action === "dblclick" || action === "double-click") {
      await page.mouse.dblclick(x, y);
    } else {
      if (input === "tap") {
        await page.touchscreen.tap(x, y);
      } else {
        await page.mouse.click(x, y, { button });
      }
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
  const wantWebm = /\.webm$/i.test(outPath);
  const ffmpeg = hasFfmpeg();
  if (!ffmpeg && !wantWebm) {
    const advice = getFfmpegInstallAdvice();
    throw new Error(`ffmpeg is required for auto-zoom, and for any output that is not .webm. ${advice}`);
  }
  const playwright = options.playwright ?? (await loadPlaywright());
  const device = resolveDevice(playwright, scenario);
  const viewport = resolveViewport(scenario, options, device);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "to-walkthrough-video-"));
  const browser = await launchChromium(playwright, { headless: !signIn });
  const contextOptions = resolveContextOptions(
    scenario,
    device,
    viewport,
    authMode ? options.storageState : null,
  );
  const context = await browser.newContext(contextOptions);
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
    touch: Boolean(contextOptions.hasTouch),
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
    const placement = steps[index].captionPlacement;
    if (placement !== undefined && !CAPTION_PLACEMENTS.includes(placement)) {
      problems.push(`steps[${index}].captionPlacement must be one of ${CAPTION_PLACEMENTS.join(", ")}`);
    }
  }
  try {
    resolveEffects(scenario);
  } catch (error) {
    problems.push(error.message);
  }
  if (scenario.device !== undefined && typeof scenario.device !== "string") {
    problems.push('scenario.device must be a string: "phone", "tablet", or an exact Playwright device name');
  }
  if (scenario.locale !== undefined && typeof scenario.locale !== "string") {
    problems.push('scenario.locale must be a BCP 47 string such as "zh-TW"');
  }
  if (scenario.ignoreHTTPSErrors !== undefined && typeof scenario.ignoreHTTPSErrors !== "boolean") {
    problems.push("scenario.ignoreHTTPSErrors must be true or false");
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

  if (args.checkPrereqs) {
    const prereqs = await checkPrereqs();
    const stream = prereqs.ok ? io.stdout : io.stderr;
    stream.write(
      `${prereqs.ok ? "Prerequisites satisfied" : "Prerequisites check failed"}:\n${prereqs.messages.map((m) => `  - ${m}`).join("\n")}\n`,
    );
    return prereqs.ok ? 0 : 1;
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
