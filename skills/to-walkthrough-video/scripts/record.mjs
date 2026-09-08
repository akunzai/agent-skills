#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { renderAutoZoom } from "./render-auto-zoom.mjs";
import { parseSamples, suggestZooms } from "./suggest-zooms.mjs";

export const DEFAULT_VIEWPORT = { width: 1280, height: 720 };
const PRE_CLICK_MS = 520;
export const POST_CLICK_MS = 2500;

function printUsage(stream) {
  stream.write(`Usage: record.mjs --scenario FILE --out FILE [--width PX] [--height PX] [--pause-ms MS]

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
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      args.help = true;
    } else if (arg === "--scenario" || arg === "--out") {
      args[arg.slice(2)] = argv[i + 1];
      i += 1;
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

async function launchChromium(playwright) {
  try {
    return await playwright.chromium.launch({ headless: true });
  } catch (error) {
    if (!String(error.message ?? error).includes("Executable doesn't exist")) {
      throw error;
    }
    return playwright.chromium.launch({ headless: true, channel: "chrome" });
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
      .cursor svg { display: block; }
      .cursor.is-down { animation: tvr-bounce 350ms cubic-bezier(0.22, 1, 0.36, 1); }
      .effects { position: absolute; inset: 0; }
      .echo {
        position: absolute; width: 14px; height: 14px; border-radius: 999px;
        border: 2px solid #2563EB; pointer-events: none;
        animation: tvr-echo 600ms cubic-bezier(0.16, 1, 0.3, 1) forwards;
      }
      .echo.outer {
        border-width: 1.5px; animation-delay: 50ms;
      }
      .core {
        position: absolute; width: 7px; height: 7px; border-radius: 999px;
        background: rgba(37, 99, 235, 0.22); pointer-events: none;
        animation: tvr-core 600ms ease-out forwards;
      }
      @keyframes tvr-bounce {
        0% { transform: scale(1); }
        32% { transform: scale(0.84); }
        100% { transform: scale(1); }
      }
      @keyframes tvr-echo {
        0% { opacity: 0.78; transform: translate(-50%, -50%) scale(0.35); }
        100% { opacity: 0; transform: translate(-50%, -50%) scale(4.4); }
      }
      @keyframes tvr-core {
        0% { opacity: 0.35; transform: translate(-50%, -50%) scale(1); }
        100% { opacity: 0; transform: translate(-50%, -50%) scale(0.4); }
      }
    </style>
    <div class="effects"></div>
    <div class="cursor">
      <svg width="28" height="32" viewBox="0 0 28 32" aria-hidden="true">
        <path fill="#111" stroke="#fff" stroke-width="1.55" stroke-linejoin="round"
          d="M3.8 2.6c-.18-.9.82-1.55 1.62-1.08L25.4 13.7c.82.48.62 1.68-.32 1.96l-10.1 3.05c-.24.07-.44.23-.54.46l-4.7 10.4c-.42.92-1.78.68-1.98-.34L3.8 2.6z"/>
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
  mount();
  new MutationObserver(mount).observe(document.documentElement, { childList: true, subtree: true });

  window.__tvrCursor = {
    mount,
    move(x, y) {
      mount();
      cursorEl.style.left = `${x}px`;
      cursorEl.style.top = `${y}px`;
    },
    pulse(x, y) {
      mount();
      cursorEl.classList.remove("is-down");
      void cursorEl.offsetWidth;
      cursorEl.classList.add("is-down");
      const spawn = (className) => {
        const el = document.createElement("div");
        el.className = className;
        el.style.left = `${x}px`;
        el.style.top = `${y}px`;
        effectsEl.appendChild(el);
        el.addEventListener("animationend", () => el.remove());
      };
      spawn("core");
      spawn("echo");
      spawn("echo outer");
    },
  };
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
  for (let index = 0; index < steps.length; index += 1) {
    const step = steps[index];
    const action = step.action ?? (step.wait !== undefined ? "wait" : "click");
    if (action === "wait") {
      await sleep(Number(step.ms ?? step.wait ?? 0));
      continue;
    }
    if (action === "goto") {
      await page.goto(step.url, { waitUntil: "domcontentloaded" });
      await page.evaluate(installCursor).catch(() => {});
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
    await animateMove(page, state, x, y);
    await page.evaluate(installCursor).catch(() => {});
    await syncCursor(page, state);
    await sleep(PRE_CLICK_MS);
    const viewport = page.viewportSize() ?? DEFAULT_VIEWPORT;
    const button = step.button ?? "left";
    const interaction = action === "dblclick" || action === "double-click" ? "double-click" : "click";
    log({
      t: Date.now() - state.startedAt,
      action: interaction,
      button,
      cx: x / viewport.width,
      cy: y / viewport.height,
    });
    await page.evaluate(
      ([cx, cy]) => {
        window.__tvrCursor?.pulse(cx, cy);
      },
      [x, y],
    ).catch(() => {});
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
    await page.evaluate(installCursor).catch(() => {});
    await syncCursor(page, state);
  }
}

async function syncCursor(page, state) {
  await page.evaluate(
    ([x, y]) => {
      window.__tvrCursor?.move(x, y);
    },
    [state.x, state.y],
  ).catch(() => {});
}

export async function recordWalkthrough(options) {
  const scenario = options.scenario;
  const outPath = path.resolve(options.out);
  const viewport = resolveViewport(scenario, options);
  const wantWebm = /\.webm$/i.test(outPath);
  const ffmpeg = hasFfmpeg();
  if (!ffmpeg && !wantWebm) {
    throw new Error("ffmpeg is required for auto-zoom, and for any output that is not .webm");
  }
  const playwright = options.playwright ?? (await loadPlaywright());
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "to-walkthrough-video-"));
  const browser = await launchChromium(playwright);
  const context = await browser.newContext({
    viewport,
    deviceScaleFactor: 1,
    recordVideo: { dir: tmp, size: viewport },
  });
  await context.addInitScript(installCursor);
  const page = await context.newPage();
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
  };
  const video = page.video();
  const openedAt = Date.now();

  try {
    await page.goto(scenario.url, { waitUntil: "domcontentloaded" });
    await page.evaluate(installCursor).catch(() => {});
    await page.locator("h1").first().waitFor({ state: "visible", timeout: 15_000 }).catch(() => {});
    await sleep(500);
    state.startedAt = Date.now();
    await syncCursor(page, state);
    await runScenario(page, scenario, log, state);
    await sleep(600);
  } catch (error) {
    await context.close().catch(() => {});
    await browser.close().catch(() => {});
    fs.rmSync(tmp, { recursive: true, force: true });
    throw error;
  }

  await context.close();
  await browser.close();
  const rawPath = video ? await video.path() : null;
  const stem = outPath.replace(/\.(mp4|webm)$/i, "");
  const clicksPath = `${stem}.clicks.jsonl`;
  const zoomsPath = `${stem}.zooms.json`;
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(clicksPath, `${clicks.map((entry) => JSON.stringify(entry)).join("\n")}\n`);

  try {
    if (!rawPath || !fs.existsSync(rawPath)) {
      throw new Error("Playwright did not write a video");
    }

    let zoomDoc;
    if (ffmpeg) {
      const rendered = await renderAutoZoom({
        video: rawPath,
        out: outPath,
        clicks: clicksPath,
        trimStartMs: Math.max(0, state.startedAt - openedAt),
      });
      zoomDoc = { status: rendered.status, suggestions: rendered.suggestions };
    } else {
      fs.copyFileSync(rawPath, outPath);
      zoomDoc = suggestZooms(clicks, Math.max(1, Date.now() - state.startedAt));
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
    const scenario = JSON.parse(fs.readFileSync(path.resolve(args.scenario), "utf8"));
    if (!scenario.url) {
      throw new Error("scenario.json needs a url");
    }
    const result = await recordWalkthrough({
      scenario,
      out: args.out,
      width: args.width,
      height: args.height,
      pauseMs: args.pauseMs,
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

const invoked = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (invoked) {
  main().then((code) => {
    process.exit(code);
  });
}
