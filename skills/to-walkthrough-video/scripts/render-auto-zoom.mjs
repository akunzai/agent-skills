#!/usr/bin/env node
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { parseSamples, suggestZooms, ZOOM_SCALE } from "./suggest-zooms.mjs";

export const ZOOM_IN_MS = 500;
export const ZOOM_OUT_MS = 400;

function printUsage(stream) {
  stream.write(`Usage: render-auto-zoom.mjs --video FILE --out FILE [--zooms FILE | --clicks FILE]

Apply auto-zoom regions to a recorded viewport video. Needs ffmpeg on PATH.
Pass --zooms from suggest-zooms.mjs, or --clicks plus optional --duration-ms.
`);
}

function parseArgs(argv) {
  const args = {
    video: null,
    out: null,
    zooms: null,
    clicks: null,
    durationMs: null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      args.help = true;
    } else if (arg === "--video" || arg === "--out" || arg === "--zooms" || arg === "--clicks") {
      args[arg.slice(2)] = argv[i + 1];
      i += 1;
    } else if (arg === "--duration-ms" || arg === "--trim-start-ms") {
      args[arg === "--duration-ms" ? "durationMs" : "trimStartMs"] = Number(argv[i + 1]);
      i += 1;
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }
  return args;
}

function run(command, argv, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, argv, {
      stdio: ["ignore", options.stdout ?? "pipe", options.stderr ?? "pipe"],
    });
    let stdout = "";
    let stderr = "";
    if (child.stdout) {
      child.stdout.on("data", (chunk) => {
        stdout += chunk;
      });
    }
    if (child.stderr) {
      child.stderr.on("data", (chunk) => {
        stderr += chunk;
      });
    }
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }
      const error = new Error(`${command} exited ${code}${stderr ? `: ${stderr.trim()}` : ""}`);
      error.stdout = stdout;
      error.stderr = stderr;
      reject(error);
    });
  });
}

function parseFrameRate(rate) {
  if (!rate || typeof rate !== "string") {
    return 30;
  }
  if (rate.includes("/")) {
    const [num, den] = rate.split("/").map(Number);
    if (Number.isFinite(num) && Number.isFinite(den) && den !== 0) {
      return num / den;
    }
  }
  const value = Number(rate);
  return Number.isFinite(value) && value > 0 ? value : 30;
}

export async function probeVideo(videoPath) {
  const { stdout } = await run("ffprobe", [
    "-v",
    "error",
    "-print_format",
    "json",
    "-show_format",
    "-show_streams",
    videoPath,
  ]);
  const info = JSON.parse(stdout);
  const video = (info.streams ?? []).find((stream) => stream.codec_type === "video");
  if (!video) {
    throw new Error(`no video stream in ${videoPath}`);
  }
  const duration = Number(info.format?.duration ?? video.duration);
  const fps = parseFrameRate(video.avg_frame_rate) || parseFrameRate(video.r_frame_rate);
  return {
    durationMs: Math.round(duration * 1000),
    width: Number(video.width),
    height: Number(video.height),
    fps,
  };
}

function even(value) {
  const rounded = Math.round(value);
  return rounded % 2 === 0 ? rounded : rounded + 1;
}

function loadZooms(args, durationMs) {
  if (args.zooms) {
    const parsed = JSON.parse(fs.readFileSync(path.resolve(args.zooms), "utf8"));
    if (Array.isArray(parsed)) {
      return { status: parsed.length ? "ok" : "no-interactions", suggestions: parsed };
    }
    return parsed;
  }
  if (args.clicks) {
    const samples = parseSamples(fs.readFileSync(path.resolve(args.clicks), "utf8"));
    return suggestZooms(samples, durationMs);
  }
  throw new Error("need --zooms or --clicks");
}

function buildSegments(suggestions, durationMs) {
  const segments = [];
  let cursor = 0;
  for (const region of suggestions) {
    const start = clampTime(region.start, durationMs);
    const end = clampTime(region.end, durationMs);
    if (end <= start) {
      continue;
    }
    if (start > cursor) {
      segments.push({ kind: "plain", start: cursor, end: start });
    }
    segments.push({
      kind: "zoom",
      start,
      end,
      cx: Number(region.focus?.cx ?? 0.5),
      cy: Number(region.focus?.cy ?? 0.5),
      scale: Number(region.scale ?? ZOOM_SCALE),
    });
    cursor = end;
  }
  if (cursor < durationMs) {
    segments.push({ kind: "plain", start: cursor, end: durationMs });
  }
  return segments.filter((segment) => segment.end - segment.start >= 1);
}

function clampTime(value, durationMs) {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.min(durationMs, Math.max(0, value));
}

function sec(ms) {
  return (ms / 1000).toFixed(3);
}

function zoomFilter(segment, width, height, fps) {
  const durationMs = segment.end - segment.start;
  const inMs = Math.max(1, Math.min(ZOOM_IN_MS, Math.floor(durationMs / 3)));
  const outMs = Math.max(1, Math.min(ZOOM_OUT_MS, Math.floor(durationMs / 3)));
  const inFrames = Math.max(1, Math.round((inMs / 1000) * fps));
  const outFrames = Math.max(1, Math.round((outMs / 1000) * fps));
  const totalFrames = Math.max(inFrames + outFrames, Math.round((durationMs / 1000) * fps));
  const holdUntil = Math.max(inFrames, totalFrames - outFrames);
  const scale = segment.scale;
  const delta = (scale - 1).toFixed(4);
  const cx = segment.cx.toFixed(4);
  const cy = segment.cy.toFixed(4);
  const z =
    `if(lt(on,${inFrames}),` +
    `1+${delta}*(0.5-0.5*cos(PI*on/${inFrames})),` +
    `if(lt(on,${holdUntil}),${scale},` +
    `1+${delta}*(0.5-0.5*cos(PI*(${totalFrames}-on)/${outFrames}))))`;
  const x = `max(0,min(iw-iw/zoom,${cx}*iw-iw/zoom/2))`;
  const y = `max(0,min(ih-ih/zoom,${cy}*ih-ih/zoom/2))`;
  return (
    `trim=${sec(segment.start)}:${sec(segment.end)},setpts=PTS-STARTPTS,` +
    `setsar=1,format=yuv420p,` +
    `zoompan=z='${z}':x='${x}':y='${y}':d=1:s=${width}x${height}:fps=${fps}`
  );
}

function plainFilter(segment) {
  return `trim=${sec(segment.start)}:${sec(segment.end)},setpts=PTS-STARTPTS,setsar=1,format=yuv420p`;
}

export function buildFilterComplex(suggestions, probe) {
  const width = even(probe.width);
  const height = even(probe.height);
  const fps = Math.round(probe.fps * 1000) / 1000;
  const segments = buildSegments(suggestions, probe.durationMs);
  if (segments.length === 0) {
    return {
      filter: `setsar=1,format=yuv420p,scale=${width}:${height}:flags=lanczos`,
      map: "0:v",
      segments,
    };
  }
  if (segments.length === 1 && segments[0].kind === "plain") {
    return {
      filter: `[0:v]${plainFilter(segments[0])},scale=${width}:${height}:flags=lanczos[out]`,
      map: "[out]",
      segments,
    };
  }

  const parts = [];
  const labels = [];
  segments.forEach((segment, index) => {
    const label = `v${index}`;
    const body = segment.kind === "zoom" ? zoomFilter(segment, width, height, fps) : plainFilter(segment);
    parts.push(`[0:v]${body}[${label}]`);
    labels.push(`[${label}]`);
  });
  parts.push(`${labels.join("")}concat=n=${segments.length}:v=1:a=0[out]`);
  return { filter: parts.join(";"), map: "[out]", segments };
}

export async function renderAutoZoom(options) {
  const videoPath = path.resolve(options.video);
  const outPath = path.resolve(options.out);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });

  const probe = await probeVideo(videoPath);
  const trimStartMs = Math.max(0, Number(options.trimStartMs) || 0);
  const durationMs = Math.max(1, (options.durationMs ?? probe.durationMs) - trimStartMs);
  const zoomDoc = options.suggestions
    ? { status: "ok", suggestions: options.suggestions }
    : loadZooms(options, durationMs);
  const suggestions = zoomDoc.suggestions ?? [];
  const { filter, map } = buildFilterComplex(suggestions, { ...probe, durationMs });

  const ffmpegArgs = ["-y"];
  if (trimStartMs > 0) {
    ffmpegArgs.push("-ss", (trimStartMs / 1000).toFixed(3));
  }
  const webm = outPath.toLowerCase().endsWith(".webm");
  ffmpegArgs.push("-i", videoPath, "-filter_complex", filter, "-map", map, "-an");
  if (webm) {
    ffmpegArgs.push("-c:v", "libvpx", "-b:v", "1.5M", "-pix_fmt", "yuv420p", "-deadline", "realtime");
  } else {
    ffmpegArgs.push(
      "-c:v",
      "libx264",
      "-pix_fmt",
      "yuv420p",
      "-preset",
      "veryfast",
      "-crf",
      "20",
      "-movflags",
      "+faststart",
    );
  }
  ffmpegArgs.push(outPath);
  await run("ffmpeg", ffmpegArgs);

  return { outPath, probe, suggestions, status: zoomDoc.status ?? "ok" };
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

  if (!args.video || !args.out || (!args.zooms && !args.clicks)) {
    printUsage(io.stderr);
    return 2;
  }

  try {
    const result = await renderAutoZoom(args);
    io.stdout.write(
      `${JSON.stringify({ out: result.outPath, status: result.status, zooms: result.suggestions.length }, null, 2)}\n`,
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
