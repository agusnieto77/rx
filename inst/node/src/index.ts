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

// ── protocol types ───────────────────────────────────────────────────

interface Request {
  id: unknown;
  method: string;
  params?: unknown;
}

interface Response {
  id: unknown;
  result: unknown;
}

interface ErrorResponse {
  id: unknown;
  error: {
    code: string;
    message: string;
  };
}

type Message = Response | ErrorResponse;

// ── helpers ──────────────────────────────────────────────────────────

function respond(id: unknown, result: unknown): void {
  const msg: Response = { id, result };
  process.stdout.write(JSON.stringify(msg) + "\n");
}

function respondError(id: unknown, code: string, message: string): void {
  const msg: ErrorResponse = { id, error: { code, message } };
  process.stdout.write(JSON.stringify(msg) + "\n");
}

function log(level: string, ...args: unknown[]): void {
  process.stderr.write(
    JSON.stringify({ type: level, ts: new Date().toISOString(), args }) +
      "\n"
  );
}

// ── CDP connection state ─────────────────────────────────────────────

let cdpConnection: DefaultCdpConnection | null = null;
let cdpEndpointUrl: string | null = null;
// Generation counter to abort stale async operations when handleClose
// nullifies the connection while a prior connect() is still pending.
let connectGen = 0;

// ── close handler ────────────────────────────────────────────────────

function handleClose(id: unknown): void {
  if (cdpConnection === null || !cdpConnection.isConnected) {
    respond(id, { closed: false, reason: "not_connected" });
    log("debug", "browser close — already not connected");
    return;
  }

  // Increment generation to abort any pending async connect().
  connectGen++;
  cdpConnection.close();
  cdpConnection = null;
  cdpEndpointUrl = null;
  respond(id, { closed: true });
  log("info", "browser closed");
}

// ── connect handler ──────────────────────────────────────────────────

function handleConnect(id: unknown, params?: unknown): void {
  if (cdpConnection !== null && cdpConnection.isConnected) {
    respond(id, { connected: true, endpoint: cdpEndpointUrl ?? "unknown" });
    log("info", "already connected to CDP");
    return;
  }

  let endpointUrl: string | undefined;
  if (typeof params === "object" && params !== null) {
    const p = params as Record<string, unknown>;
    if (typeof p.endpoint === "string") {
      endpointUrl = p.endpoint;
    }
  }

  if (!endpointUrl) {
    // Fall back to default Lightpanda endpoint.
    endpointUrl = process.env.LPD_ENDPOINT ?? "ws://127.0.0.1:21111";
  }

  const gen = ++connectGen;
  cdpConnection = new DefaultCdpConnection();

  cdpConnection
    .connect(endpointUrl)
    .then(() => {
      // Abort if handleClose was called while we were connecting.
      if (gen !== connectGen) {
        cdpConnection!.close();
        cdpConnection = null;
        return;
      }
      cdpEndpointUrl = endpointUrl;
      respond(id, { connected: true, endpoint: endpointUrl });
      log("info", "CDP connected", endpointUrl);
    })
    .catch((err: Error) => {
      // Connection failed — clean up and return structured error.
      // Only respond if we are still the active connect generation.
      if (gen === connectGen) {
        cdpConnection = null;
        cdpEndpointUrl = null;
        respondError(id, "LPD_CONNECTION_ERROR", `Failed to connect to CDP endpoint: ${err.message}`);
        log("error", "CDP connection failed", endpointUrl, err.message);
      }
    });
}

// ── navigate handler ─────────────────────────────────────────────────

const NAVIGATE_TIMEOUT_MS = 30_000;

function handleNavigate(id: unknown, params?: unknown): void {
  // Validate params first (before connection check).
  let url: string;
  if (typeof params === "object" && params !== null) {
    const p = params as Record<string, unknown>;
    if (typeof p.url === "string" && p.url.length > 0) {
      url = p.url;
    } else {
      respondError(id, "INVALID_REQUEST", "navigate requires a non-empty 'url' parameter");
      return;
    }
  } else {
    respondError(id, "INVALID_REQUEST", "navigate requires a 'url' parameter");
    return;
  }

  if (cdpConnection === null || !cdpConnection.isConnected) {
    respondError(id, "PAGE_LOAD_ERROR", "Cannot navigate — CDP connection not active");
    log("warn", "navigate failed — not connected");
    return;
  }

  // Wrap navigation in a promise that resolves on Page.loadEventFired or times out.
  const navPromise = new Promise<Record<string, unknown>>((resolve, reject) => {
    let settled = false;

    const timeout = setTimeout(() => {
      if (!settled) {
        settled = true;
        cdpConnection!.removeListener("Page.loadEventFired", onLoad);
        cdpConnection!.removeListener("Page.frameStoppedLoading", onFrameStopped);
        reject(new Error(`Navigation timeout after ${NAVIGATE_TIMEOUT_MS}ms to ${url}`));
      }
    }, NAVIGATE_TIMEOUT_MS);

    const onLoad = (): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        cdpConnection!.removeListener("Page.loadEventFired", onLoad);
        cdpConnection!.removeListener("Page.frameStoppedLoading", onFrameStopped);
        resolve({ loadEventFired: true });
      }
    };

    // Also listen for frameStoppedLoading as a fallback settle signal.
    const onFrameStopped = (): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        cdpConnection!.removeListener("Page.loadEventFired", onLoad);
        cdpConnection!.removeListener("Page.frameStoppedLoading", onFrameStopped);
        resolve({ frameStoppedLoading: true });
      }
    };

    cdpConnection!.on("Page.loadEventFired", onLoad);
    cdpConnection!.on("Page.frameStoppedLoading", onFrameStopped);

    // Enable the Page domain first.
    cdpConnection!
      .sendCommand("Page.enable")
      .then(() => cdpConnection!.sendCommand("Page.navigate", { url }))
      .then((result) => {
        // Navigation sent; waiting for loadEventFired.
        log("debug", "Page.navigate sent for", url, "loaderId=", (result as Record<string, unknown>).loaderId);
      })
      .catch((err: Error) => {
        // Page.enable or Page.navigate failed.
        cdpConnection!.removeListener("Page.loadEventFired", onLoad);
        cdpConnection!.removeListener("Page.frameStoppedLoading", onFrameStopped);
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
    .catch((err: Error) => {
      respondError(id, "PAGE_LOAD_ERROR", `Navigation failed: ${err.message}`);
      log("error", "navigation failed for", url, err.message);
    });
}

// ── evaluate handler ─────────────────────────────────────────────────

function handleEvaluate(id: unknown, params?: unknown): void {
  // Validate params first (before connection check).
  let expr: string;
  if (typeof params === "object" && params !== null) {
    const p = params as Record<string, unknown>;
    if (typeof p.expr === "string" && p.expr.length > 0) {
      expr = p.expr;
    } else {
      respondError(id, "INVALID_REQUEST", "evaluate requires a non-empty 'expr' parameter");
      return;
    }
  } else {
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
    .then(() => cdpConnection!.sendCommand("Page.enable"))
    .then(() => cdpConnection!.sendCommand("Runtime.evaluate", { expression: expr, returnByValue: true }))
    .then((result) => {
      respond(id, { evaluated: true, result });
      log("debug", "evaluate succeeded for expression length", expr.length);
    })
    .catch((err: Error) => {
      respondError(id, "CDP_ERROR", `JavaScript evaluation failed: ${err.message}`);
      log("error", "evaluate failed", expr.slice(0, 120), err.message);
    });
}

// ── ping handler ─────────────────────────────────────────────────────

function handlePing(id: unknown): void {
  respond(id, { pong: true, version: VERSION });
  log("debug", "ping handled");
}

// ── main loop ────────────────────────────────────────────────────────

async function main(): Promise<void> {
  // Deterministic startup message on stderr.
  process.stderr.write(
    JSON.stringify({ type: "startup", version: VERSION }) + "\n"
  );

  const rl = createInterface({ input: process.stdin });

  for await (const line of rl) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    let parsed: unknown;
    try {
      parsed = JSON.parse(trimmed);
    } catch {
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

    const req = parsed as Record<string, unknown>;
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
  process.stderr.write(
    JSON.stringify({ type: "fatal", error: (err as Error).message }) + "\n"
  );
  process.exit(1);
});
