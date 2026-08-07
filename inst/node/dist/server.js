// Minimal static-file test server.
// Serves files from a given directory on a configurable port.
// Used only for local testing (Task 15+) — never shipped with the package.
//
// Usage:  node dist/server.js <directory> [port]
// Defaults: port 8765
import { createServer } from "node:http";
import { readFileSync, statSync } from "node:fs";
import { extname, join } from "node:path";
const EXT_CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".htm": "text/html; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".txt": "text/plain; charset=utf-8",
};
function serveFile(dir, pathname) {
    // Prevent path traversal: resolve the canonical absolute path and
    // verify it is inside the serving directory (or equals it).
    const resolved = join(dir, pathname);
    const normalized = resolved.replace(/\\/g, "/").replace(/\/+/g, "/");
    const baseNormalized = dir.replace(/\\/g, "/").replace(/\/+/g, "/");
    if (!normalized.startsWith(baseNormalized + "/") && normalized !== baseNormalized) {
        return { status: 403 };
    }
    try {
        const stat = statSync(resolved);
        if (!stat.isFile()) {
            return { status: 404 };
        }
        const data = readFileSync(resolved);
        const ct = EXT_CONTENT_TYPES[extname(resolved).toLowerCase()] || "application/octet-stream";
        return { status: 200, body: data, contentType: ct };
    }
    catch {
        return { status: 404 };
    }
}
function main() {
    const dir = process.argv[2] ?? ".";
    const port = parseInt(process.argv[3] ?? "8765", 10);
    const server = createServer((req, res) => {
        const pathname = new URL(req.url, `http://localhost:${port}`).pathname;
        const result = serveFile(dir, pathname);
        res.writeHead(result.status, {
            "Content-Type": result.contentType ?? "text/plain",
        });
        if (result.body) {
            res.end(result.body);
        }
        else {
            res.end("Not found");
        }
    });
    server.listen(port, () => {
        console.error("test-server listening on http://127.0.0.1:%d (root=%s)", port, dir);
    });
}
main();
//# sourceMappingURL=server.js.map