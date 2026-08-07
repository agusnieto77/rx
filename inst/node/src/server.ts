// Minimal static-file test server.
// Serves files from a given directory on a configurable port.
// Used only for local testing (Task 15+) — never shipped with the package.
//
// Usage:  node dist/server.js <directory> [port]
// Defaults: port 8765

import { createServer } from "node:http";
import { readFileSync, statSync, realpathSync } from "node:fs";
import { extname, relative, resolve, isAbsolute, sep } from "node:path";

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
  // Prevent path traversal: resolve to an absolute canonical path and
  // verify it is inside the serving directory (or equals it).
  const resolved = resolve(dir, "." + pathname);
  const baseResolved = resolve(dir);
  const relativePath = relative(baseResolved, resolved);
  if (relativePath === ".." || relativePath.startsWith(".." + sep) || isAbsolute(relativePath)) {
    return { status: 403 };
  }

  try {
    const stat = statSync(resolved);
    if (!stat.isFile()) {
      return { status: 404 };
    }
    // Verify symlinks do not escape the base directory.
    const realPath = realpathSync(resolved);
    const realBase = realpathSync(baseResolved);
    const realRelative = relative(realBase, realPath);
    if (realRelative === ".." || realRelative.startsWith(".." + sep) || isAbsolute(realRelative)) {
      return { status: 403 };
    }
    const data = readFileSync(realPath);
    const ct = EXT_CONTENT_TYPES[extname(realPath).toLowerCase()] || "application/octet-stream";
    return { status: 200, body: data, contentType: ct };
  } catch {
    return { status: 404 };
  }
}

function main(): void {
  const dir = process.argv[2] ?? ".";
  const port = parseInt(process.argv[3] ?? "8765", 10);

  if (Number.isNaN(port) || port < 1 || port > 65535) {
    process.stderr.write("Error: invalid port. Must be 1-65535.\n");
    process.exit(1);
  }

  const server = createServer((req, res) => {
    let pathname: string;
    try {
      pathname = decodeURIComponent(
        new URL(req.url!, `http://localhost:${port}`).pathname
      );
    } catch {
      res.writeHead(400, { "Content-Type": "text/plain" });
      res.end("Bad Request");
      return;
    }
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
