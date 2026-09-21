#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

// The zoom (and any pan to a later click) lands exactly on the click.
export const ZOOM_IN_MS = 500;
export const ZOOM_OUT_MS = 400;
// Held until the step's action (typing, choosing) ends, plus this long.
export const HOLD_AFTER_MS = 800;
export const MIN_HOLD_MS = 1500;
// Below this, zooming out and straight back in would read as a flicker, so the
// camera stays in and pans instead. Kept under the gap that the default
// 2500ms step pause leaves, so ordinary steps still zoom out between them.
export const MERGE_GAP_MS = 800;
export const DOUBLE_CLICK_MS = 350;
export const DOUBLE_CLICK_DIST = 0.04;
export const ZOOM_SCALE = 1.5;

const CLICK_TYPES = new Set(["click", "double-click", "right-click", "middle-click"]);

export function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

export function parseSamples(text) {
  const trimmed = text.trim();
  if (!trimmed) {
    return [];
  }
  if (trimmed.startsWith("[")) {
    const parsed = JSON.parse(trimmed);
    if (!Array.isArray(parsed)) {
      throw new Error("JSON click log must be an array");
    }
    return parsed;
  }
  return trimmed
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch {
        throw new Error(`invalid JSONL on line ${index + 1}`);
      }
    });
}

function buttonToType(button) {
  if (button === "right") {
    return "right-click";
  }
  if (button === "middle") {
    return "middle-click";
  }
  return "click";
}

export function normalizeSamples(rawSamples) {
  return rawSamples
    .filter((sample) => sample && typeof sample === "object")
    .map((sample) => {
      const timeMs = Number(sample.timeMs ?? sample.t ?? 0);
      const endMs = Number(sample.endTimeMs ?? sample.endT);
      let cx = Number(sample.cx);
      let cy = Number(sample.cy);
      if (!Number.isFinite(cx) || !Number.isFinite(cy)) {
        const vx = Number(sample.vx);
        const vy = Number(sample.vy);
        const width = Number(sample.viewportWidth ?? sample.innerW ?? 0);
        const height = Number(sample.viewportHeight ?? sample.innerH ?? 0);
        if (Number.isFinite(vx) && Number.isFinite(vy) && width > 0 && height > 0) {
          cx = vx / width;
          cy = vy / height;
        }
      }
      const action = sample.interactionType ?? sample.action;
      let interactionType;
      if (action === "dblclick" || action === "doubleclick") {
        interactionType = "double-click";
      } else if (action === "click" && sample.button) {
        interactionType = buttonToType(sample.button);
      } else if (CLICK_TYPES.has(action) || action === "move" || action === "mouseup") {
        interactionType = action;
      } else if (sample.button) {
        interactionType = buttonToType(sample.button);
      }
      const start = Number.isFinite(timeMs) ? Math.max(0, timeMs) : 0;
      return {
        timeMs: start,
        endMs: Number.isFinite(endMs) ? Math.max(start, endMs) : start,
        cx: Number.isFinite(cx) ? clamp(cx, 0, 1) : 0.5,
        cy: Number.isFinite(cy) ? clamp(cy, 0, 1) : 0.5,
        interactionType,
      };
    })
    .sort((a, b) => a.timeMs - b.timeMs);
}

export function classifyDoubleClicks(samples) {
  let lastLeft = null;
  return samples.map((sample) => {
    if (sample.interactionType !== "click") {
      return sample;
    }
    if (
      lastLeft &&
      sample.timeMs - lastLeft.timeMs <= DOUBLE_CLICK_MS &&
      Math.hypot(sample.cx - lastLeft.cx, sample.cy - lastLeft.cy) <= DOUBLE_CLICK_DIST
    ) {
      lastLeft = { ...sample, interactionType: "double-click" };
      return lastLeft;
    }
    lastLeft = sample;
    return sample;
  });
}

function isExplicitClick(interactionType) {
  return typeof interactionType === "string" && CLICK_TYPES.has(interactionType);
}

function clampFocus(focus, scale) {
  const margin = 1 / (2 * scale);
  return {
    cx: clamp(focus.cx, margin, 1 - margin),
    cy: clamp(focus.cy, margin, 1 - margin),
  };
}

function holdEnd(click) {
  return Math.max(click.timeMs + MIN_HOLD_MS, click.endMs + HOLD_AFTER_MS);
}

// One cluster per stretch of clicks the camera stays zoomed through. Each click
// keeps its own keyframe, so the camera pans to it rather than sitting on one
// focus that an earlier click in the cluster may lie outside of.
function buildClusters(clicks, mergeGapMs) {
  const clusters = [];
  let current = null;
  for (const click of clicks) {
    if (current && click.timeMs - ZOOM_IN_MS - current.holdEndMs < mergeGapMs) {
      current.clicks.push(click);
      current.holdEndMs = Math.max(current.holdEndMs, holdEnd(click));
    } else {
      current = { clicks: [click], holdEndMs: holdEnd(click) };
      clusters.push(current);
    }
  }
  return clusters;
}

function keyframesFor(clicks, scale) {
  const keyframes = [];
  for (const click of clicks) {
    const { cx, cy } = clampFocus(click, scale);
    const last = keyframes[keyframes.length - 1];
    if (last && Math.hypot(cx - last.cx, cy - last.cy) < 0.005) {
      continue;
    }
    keyframes.push({ t: click.timeMs, cx, cy });
  }
  return keyframes;
}

export function suggestZooms(rawSamples, totalMs, options = {}) {
  const mergeGapMs = options.mergeGapMs ?? MERGE_GAP_MS;
  const scale = options.scale ?? ZOOM_SCALE;

  if (!Number.isFinite(totalMs) || totalMs <= 0) {
    return { status: "no-slots", suggestions: [] };
  }

  const samples = classifyDoubleClicks(normalizeSamples(rawSamples));
  const clicks = samples.filter((sample) => isExplicitClick(sample.interactionType));

  if (clicks.length === 0) {
    return { status: samples.length === 0 ? "no-telemetry" : "no-interactions", suggestions: [] };
  }

  const suggestions = [];
  for (const cluster of buildClusters(clicks, mergeGapMs)) {
    const start = Math.max(0, cluster.clicks[0].timeMs - ZOOM_IN_MS);
    const end = Math.min(totalMs, cluster.holdEndMs + ZOOM_OUT_MS);
    if (end <= start) {
      continue;
    }
    const keyframes = keyframesFor(cluster.clicks, scale);
    suggestions.push({
      start,
      end,
      focus: { cx: keyframes[0].cx, cy: keyframes[0].cy },
      keyframes,
      scale,
    });
  }

  if (suggestions.length === 0) {
    return { status: "no-slots", suggestions: [] };
  }

  return { status: "ok", suggestions };
}

function printUsage(stream) {
  stream.write(`Usage: suggest-zooms.mjs --clicks FILE --duration-ms MS [--out FILE]

Cluster explicit clicks into auto-zoom regions (JSON on stdout).
FILE is JSONL or a JSON array. Each click needs t/timeMs and cx, cy;
an optional endT holds the zoom until that step's action ended.
`);
}

function parseArgs(argv) {
  const args = { clicks: null, durationMs: null, out: null };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      args.help = true;
    } else if (arg === "--clicks") {
      args.clicks = argv[i + 1];
      i += 1;
    } else if (arg === "--duration-ms") {
      args.durationMs = Number(argv[i + 1]);
      i += 1;
    } else if (arg === "--out") {
      args.out = argv[i + 1];
      i += 1;
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }
  return args;
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

  if (!args.clicks || !Number.isFinite(args.durationMs)) {
    printUsage(io.stderr);
    return 2;
  }

  const text = fs.readFileSync(path.resolve(args.clicks), "utf8");
  const result = suggestZooms(parseSamples(text), args.durationMs);
  const json = `${JSON.stringify(result, null, 2)}\n`;
  if (args.out) {
    fs.writeFileSync(path.resolve(args.out), json);
  } else {
    io.stdout.write(json);
  }
  return 0;
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
