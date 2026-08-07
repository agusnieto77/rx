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
import { DefaultCdpConnection } from "./browser/connection.js";
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
// ── CDP connection state ─────────────────────────────────────────────
let cdpConnection = null;
let cdpEndpointUrl = null;
// ── close handler ────────────────────────────────────────────────────
function handleClose(id) {
    if (cdpConnection === null || !cdpConnection.isConnected) {
        respond(id, { closed: false, reason: "not_connected" });
        log("debug", "browser close — already not connected");
        return;
    }
    cdpConnection.close();
    cdpConnection = null;
    cdpEndpointUrl = null;
    respond(id, { closed: true });
    log("info", "browser closed");
}
// ── connect handler ──────────────────────────────────────────────────
function handleConnect(id, params) {
    if (cdpConnection !== null && cdpConnection.isConnected) {
        respond(id, { connected: true, endpoint: cdpEndpointUrl ?? "unknown" });
        log("info", "already connected to CDP");
        return;
    }
    let endpointUrl;
    if (typeof params === "object" && params !== null) {
        const p = params;
        if (typeof p.endpoint === "string") {
            endpointUrl = p.endpoint;
        }
    }
    if (!endpointUrl) {
        // Fall back to default Lightpanda endpoint.
        endpointUrl = process.env.LPD_ENDPOINT ?? "ws://127.0.0.1:21111";
    }
    cdpConnection = new DefaultCdpConnection();
    cdpConnection
        .connect(endpointUrl)
        .then(() => {
        cdpEndpointUrl = endpointUrl;
        respond(id, { connected: true, endpoint: endpointUrl });
        log("info", "CDP connected", endpointUrl);
    })
        .catch((err) => {
        // Connection failed — clean up and return structured error.
        cdpConnection = null;
        cdpEndpointUrl = null;
        respondError(id, "LPD_CONNECTION_ERROR", `Failed to connect to CDP endpoint: ${err.message}`);
        log("error", "CDP connection failed", endpointUrl, err.message);
    });
}
// ── navigate handler ─────────────────────────────────────────────────
const NAVIGATE_TIMEOUT_MS = 30_000;
function handleNavigate(id, params) {
    // Validate params first (before connection check).
    let url;
    if (typeof params === "object" && params !== null) {
        const p = params;
        if (typeof p.url === "string" && p.url.length > 0) {
            url = p.url;
        }
        else {
            respondError(id, "INVALID_REQUEST", "navigate requires a non-empty 'url' parameter");
            return;
        }
    }
    else {
        respondError(id, "INVALID_REQUEST", "navigate requires a 'url' parameter");
        return;
    }
    if (cdpConnection === null || !cdpConnection.isConnected) {
        respondError(id, "PAGE_LOAD_ERROR", "Cannot navigate — CDP connection not active");
        log("warn", "navigate failed — not connected");
        return;
    }
    // Wrap navigation in a promise that resolves on Page.loadEventFired or times out.
    const navPromise = new Promise((resolve, reject) => {
        let settled = false;
        const timeout = setTimeout(() => {
            if (!settled) {
                settled = true;
                cdpConnection.removeListener("Page.loadEventFired", onLoad);
                reject(new Error(`Navigation timeout after ${NAVIGATE_TIMEOUT_MS}ms to ${url}`));
            }
        }, NAVIGATE_TIMEOUT_MS);
        const onLoad = () => {
            if (!settled) {
                settled = true;
                clearTimeout(timeout);
                cdpConnection.removeListener("Page.loadEventFired", onLoad);
                cdpConnection.removeListener("Page.frameStoppedLoading", onFrameStopped);
                resolve({ loadEventFired: true });
            }
        };
        // Also listen for frameStoppedLoading as a fallback.
        const onFrameStopped = () => {
            // Do not settle here — loadEventFired is the stronger signal.
            log("debug", "Page.frameStoppedLoading received for", url);
        };
        cdpConnection.on("Page.loadEventFired", onLoad);
        cdpConnection.on("Page.frameStoppedLoading", onFrameStopped);
        // Enable the Page domain first.
        cdpConnection
            .sendCommand("Page.enable")
            .then(() => cdpConnection.sendCommand("Page.navigate", { url }))
            .then((result) => {
            // Navigation sent; waiting for loadEventFired.
            log("debug", "Page.navigate sent for", url, "loaderId=", result.loaderId);
        })
            .catch((err) => {
            // Page.enable or Page.navigate failed.
            cdpConnection.removeListener("Page.loadEventFired", onLoad);
            cdpConnection.removeListener("Page.frameStoppedLoading", onFrameStopped);
            clearTimeout(timeout);
            settled = true;
            reject(err);
        });
    });
    navPromise
        .then((result) => {
        respond(id, { url, navigated: true, result });
        log("info", "navigated to", url);
    })
        .catch((err) => {
        respondError(id, "PAGE_LOAD_ERROR", `Navigation failed: ${err.message}`);
        log("error", "navigation failed for", url, err.message);
    });
}
// ── evaluate handler ─────────────────────────────────────────────────
function handleEvaluate(id, params) {
    // Validate params first (before connection check).
    let expr;
    if (typeof params === "object" && params !== null) {
        const p = params;
        if (typeof p.expr === "string" && p.expr.length > 0) {
            expr = p.expr;
        }
        else {
            respondError(id, "INVALID_REQUEST", "evaluate requires a non-empty 'expr' parameter");
            return;
        }
    }
    else {
        respondError(id, "INVALID_REQUEST", "evaluate requires an 'expr' parameter");
        return;
    }
    if (cdpConnection === null || !cdpConnection.isConnected) {
        respondError(id, "CDP_ERROR", "Cannot evaluate — CDP connection not active");
        log("warn", "evaluate failed — not connected");
        return;
    }
    // Use Page.enable + Runtime.evaluate via CDP.
    cdpConnection
        .sendCommand("Runtime.enable")
        .then(() => cdpConnection.sendCommand("Page.enable"))
        .then(() => cdpConnection.sendCommand("Runtime.evaluate", { expression: expr, returnByValue: true }))
        .then((result) => {
        respond(id, { evaluated: true, result });
        log("debug", "evaluate succeeded for expression length", expr.length);
    })
        .catch((err) => {
        respondError(id, "CDP_ERROR", `JavaScript evaluation failed: ${err.message}`);
        log("error", "evaluate failed", expr.slice(0, 120), err.message);
    });
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
            case "connect":
                handleConnect(id, req.params);
                break;
            case "close":
                handleClose(id);
                break;
            case "navigate":
                handleNavigate(id, req.params);
                break;
            case "evaluate":
                handleEvaluate(id, req.params);
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