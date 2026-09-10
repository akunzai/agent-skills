#!/usr/bin/env node
// Offline fixture for to-walkthrough-video: a public page, a sign-in form, and
// a cookie-gated page. Static files cannot carry a session cookie, so the
// signed-in half of the skill needs a real origin rather than file://.
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const COOKIE = "walkthrough_session";
const TYPES = { ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8" };

export function parseArgs(argv) {
  const args = { port: 4173 };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--port") {
      args.port = Number(argv[i + 1]);
      i += 1;
    } else if (argv[i] === "--help" || argv[i] === "-h") {
      args.help = true;
    } else {
      throw new Error(`unknown option: ${argv[i]}`);
    }
  }
  return args;
}

export function hasSession(cookieHeader) {
  return String(cookieHeader ?? "")
    .split(";")
    .some((pair) => pair.trim().startsWith(`${COOKIE}=`));
}

function sendFile(res, name, status = 200) {
  const body = fs.readFileSync(path.join(HERE, name));
  res.writeHead(status, { "content-type": TYPES[path.extname(name)] ?? "text/plain" });
  res.end(body);
}

function redirect(res, location, headers = {}) {
  res.writeHead(302, { location, ...headers });
  res.end();
}

export function createServer() {
  return http.createServer((req, res) => {
    const url = new URL(req.url, "http://localhost");
    if (req.method === "POST" && url.pathname === "/login") {
      req.resume();
      req.on("end", () => {
        redirect(res, "/app", {
          "set-cookie": `${COOKIE}=1; Path=/; HttpOnly; SameSite=Lax`,
        });
      });
      return;
    }
    if (req.method !== "GET") {
      res.writeHead(405).end();
      return;
    }
    if (url.pathname === "/" || url.pathname === "/index.html") {
      sendFile(res, "public.html");
    } else if (url.pathname === "/login") {
      sendFile(res, "login.html");
    } else if (url.pathname === "/app") {
      if (hasSession(req.headers.cookie)) {
        sendFile(res, "app.html");
      } else {
        redirect(res, "/login");
      }
    } else if (url.pathname === "/style.css") {
      sendFile(res, "style.css");
    } else {
      res.writeHead(404, { "content-type": "text/plain" }).end("not found\n");
    }
  });
}

export function main(argv = process.argv.slice(2), io = process) {
  let args;
  try {
    args = parseArgs(argv);
  } catch (error) {
    io.stderr.write(`${error.message}\nUsage: serve.mjs [--port PORT]\n`);
    return 2;
  }
  if (args.help) {
    io.stdout.write("Usage: serve.mjs [--port PORT]\n");
    return 0;
  }
  const server = createServer();
  server.listen(args.port, () => {
    // Print what was bound, not what was asked for: --port 0 lets a test take
    // any free port and read it back from this line.
    io.stdout.write(`fixture listening on http://localhost:${server.address().port}/\n`);
  });
  return 0;
}

const invoked = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (invoked) {
  const code = main();
  if (code !== 0) {
    process.exit(code);
  }
}
