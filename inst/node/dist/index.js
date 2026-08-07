// xtweetsR TypeScript sidecar — entry point
// Reads JSONL requests from stdin, writes JSONL responses to stdout.
// Logs go to stderr.
//
// Protocol shape (JSON Lines over stdin/stdout):
//
// Request:  { "id": <any>, "method": string, "params": <any>? }
// Response: { "id": <same>, "result": <any> }
// Error:    { "id": <same>, "error": { "code": string, "message": string } }
// Log:      written to stderr, never to stdout.
import { createInterface } from "readline";
const VERSION = "0.1.0";
// ── helpers ──────────────────────────────────────────────────────────
function respond(id, result) {
    const msg = { id, result };
    process.stdout.write(JSON.stringify(msg) + "\n");
}
function respondError(id, code, message) {
    const msg = { id, error: { code, message } };
    process.stdout.write(JSON.stringify(msg) + "\n");
}
function log(level, ...args) {
    process.stderr.write(JSON.stringify({ type: level, ts: new Date().toISOString(), args }) +
        "\n");
}
// ── ping handler ─────────────────────────────────────────────────────
function handlePing(id) {
    respond(id, { pong: true, version: VERSION });
    log("debug", "ping handled");
}
// ── main loop ────────────────────────────────────────────────────────
async function main() {
    // Deterministic startup message on stderr.
    process.stderr.write(JSON.stringify({ type: "startup", version: VERSION }) + "\n");
    const rl = createInterface({ input: process.stdin });
    for await (const line of rl) {
        const trimmed = line.trim();
        if (!trimmed)
            continue;
        let parsed;
        try {
            parsed = JSON.parse(trimmed);
        }
        catch {
            // Malformed JSON → structured error.
            respondError(null, "PARSE_ERROR", "Invalid JSON input");
            log("warn", "parse error on line:", trimmed.slice(0, 120));
            continue;
        }
        if (typeof parsed !== "object" || parsed === null) {
            respondError(null, "INVALID_REQUEST", "Request must be a JSON object");
            log("warn", "non-object input:", trimmed.slice(0, 120));
            continue;
        }
        const req = parsed;
        const id = req.id;
        const method = req.method;
        if (typeof method !== "string") {
            respondError(id, "INVALID_REQUEST", "Missing 'method' field");
            continue;
        }
        log("debug", "method=", method, "id=", id);
        // Route to the handler.
        switch (method) {
            case "ping":
                handlePing(id);
                break;
            default:
                respondError(id, "UNKNOWN_METHOD", `Method "${method}" is not implemented`);
                break;
        }
    }
}
main().catch((err) => {
    process.stderr.write(JSON.stringify({ type: "fatal", error: err.message }) + "\n");
    process.exit(1);
});
//# sourceMappingURL=index.js.map