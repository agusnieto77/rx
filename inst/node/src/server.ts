// Minimal static-file test server.
// Serves files from a given directory on a configurable port.
// Used only for local testing (Task 15+) — never shipped with the package.
//
// Usage:  node dist/server.js <directory> [port]
// Defaults: port 8765

import { createServer } from "node:http";
import { readFileSync, statSync } from "node:fs";
import { extname } from "node:path";

const EXT_CONTENT_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".htm":  "text/html; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".css":  "text/css; charset=utf-8",
  ".js":   "application/javascript; charset=utf-8",
  ".png":  "image/png",
  ".jpg":  "image/jpeg",
  ".gif":  "image/gif",
  ".svg":  "image/svg+xml",
  ".ico":  "image/x-icon",
  ".txt":  "text/plain; charset=utf-8",
};

function serveFile(dir: string, pathname: string): { status: number; body?: Buffer; contentType?: string } {
  // Prevent path traversal.
  const safe = pathname.replace(/\.\./g, "");
  if (safe !== pathname) {
    return { status: 403 };
  }

  const filePath = dir + safe;
  try {
    const stat = statSync(filePath);
    if (!stat.isFile()) {
      return { status: 404 };
    }
    const data = readFileSync(filePath);
    const ct = EXT_CONTENT_TYPES[extname(filePath).toLowerCase()] || "application/octet-stream";
    return { status: 200, body: data, contentType: ct };
  } catch {
    return { status: 404 };
  }
}

function main(): void {
  const dir = process.argv[2] ?? ".";
  const port = parseInt(process.argv[3] ?? "8765", 10);

  const server = createServer((req, res) => {
    const pathname = new URL(req.url!, `http://localhost:${port}`).pathname;
    const result = serveFile(dir, pathname);

    res.writeHead(result.status, {
      "Content-Type": result.contentType ?? "text/plain",
    });
    if (result.body) {
      res.end(result.body);
    } else {
      res.end("Not found");
    }
  });

  server.listen(port, () => {
    console.error("test-server listening on http://127.0.0.1:%d (root=%s)", port, dir);
  });
}

main();
