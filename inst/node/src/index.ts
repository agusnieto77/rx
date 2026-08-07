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
// Guard to prevent concurrent connect attempts that would leak connections.
let connecting = false;

// ── close handler ────────────────────────────────────────────────────

function handleClose(id: unknown): void {
  // Always bump generation and clear the connecting flag first, so that any
  // pending async connect() will see gen !== connectGen and clean itself up.
  // If we returned early here without bumping connectGen / clearing connecting,
  // a stale pending connect would resolve normally and leave connecting=true
  // forever, blocking all future connect() calls.
  connectGen++;
  connecting = false;

  if (cdpConnection === null || !cdpConnection.isConnected) {
    cdpConnection?.close();
    cdpConnection = null;
    cdpEndpointUrl = null;
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

function isValidWsUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    // Strip userinfo (username:password@) before validation to prevent
    // visual obfuscation — e.g. ws://localhost@evil.com parses as hostname
    // "evil.com" but a human glance at the URL string sees "localhost".
    if (parsed.username || parsed.password) {
      return false;
    }
    if (parsed.protocol !== "ws:" && parsed.protocol !== "wss:") {
      return false;
    }
    // SSRF guard — only allow loopback addresses.
    // Node.js URL.hostname strips brackets from IPv6, but we also handle
    // the case where brackets may be present in the raw hostname string.
    const host = parsed.hostname.toLowerCase();
    const hostUnbracketed = host.replace(/^\[/, "").replace(/\]$/, "");
    if (
      host === "localhost" ||
      hostUnbracketed === "localhost" ||
      host === "127.0.0.1" ||
      host === "::1" ||
      hostUnbracketed === "::1" ||
      hostUnbracketed === "127.0.0.1" ||
      /^127\./.test(hostUnbracketed) ||
      host.startsWith("[127.")
    ) {
      return true;
    }
    return false;
  } catch {
    return false;
  }
}

function handleConnect(id: unknown, params?: unknown): void {
  if (cdpConnection !== null && cdpConnection.isConnected) {
    respond(id, { connected: true, endpoint: cdpEndpointUrl ?? "unknown" });
    log("info", "already connected to CDP");
    return;
  }

  if (connecting) {
    respondError(id, "ALREADY_CONNECTING", "A connect operation is already in progress");
    return;
  }

  let endpointUrl: string | undefined;
  if (typeof params === "object" && params !== null) {
    const p = params as Record<string, unknown>;
    // Reject endpoint values that look like caller typos (e.g. {endpoint:{a:1}},
    // {endpoint:["ws://..."]}) — null, undefined, {}, and [] are valid "not
    // provided" values (R NULL serialises as {}).
    const ep = p.endpoint;
    if (
      typeof ep !== "string" &&
      ep !== null &&
      ep !== undefined &&
      !(typeof ep === "object" && Object.keys(ep).length === 0) &&
      !(Array.isArray(ep) && ep.length === 0)
    ) {
      respondError(id, "INVALID_REQUEST", "endpoint must be a string");
      return;
    }
    if (typeof p.endpoint === "string" && p.endpoint.length > 0) {
      endpointUrl = p.endpoint;
      // Validate endpoint to prevent SSRF — only allow ws: and wss: schemes.
      if (!isValidWsUrl(endpointUrl)) {
        respondError(id, "INVALID_REQUEST", "endpoint must be a ws: or wss: URL");
        return;
      }
    } else if ("endpoint" in p) {
      // endpoint key present but not a string.
      // null, undefined, {}, [] are all valid "not provided" (R NULL serialises as {}).
      // Reject non-null primitives like 123 or true — they mask caller typos.
      if (p.endpoint != null && typeof p.endpoint !== "object") {
        respondError(id, "INVALID_REQUEST", "endpoint must be a string");
        return;
      }
      // null, undefined, {}, [] → treat as "not provided", fall through to default.
    }
  }

  // Reject non-object, non-null params — they bypass all validation.
  if (params !== undefined && params !== null && typeof params !== "object") {
    respondError(id, "INVALID_REQUEST", "params must be a JSON object or omitted");
    return;
  }

  // Reject non-empty arrays — only plain objects (or null/undefined/empty) are valid.
  if (Array.isArray(params) && params.length > 0) {
    respondError(id, "INVALID_REQUEST", "params must be a JSON object or omitted");
    return;
  }

  if (!endpointUrl) {
    // Fall back to default Lightpanda endpoint.
    endpointUrl = process.env.LPD_ENDPOINT ?? "ws://127.0.0.1:21111";
    // Validate fallback URL to prevent SSRF via LPD_ENDPOINT env injection.
    if (!isValidWsUrl(endpointUrl)) {
      respondError(id, "INVALID_REQUEST", "endpoint must be a ws: or wss: URL");
      return;
    }
  }

  connecting = true;
  const gen = ++connectGen;
  const conn = new DefaultCdpConnection();
  cdpConnection = conn;

  conn
    .connect(endpointUrl)
    .then(() => {
      // Abort if handleClose was called while we were connecting.
      if (gen !== connectGen) {
        // Stale connection — close it regardless of whether it's still active
        // to prevent leaks when a new connect() already replaced it.
        if (cdpConnection === conn) {
          conn.close();
          cdpConnection = null;
          cdpEndpointUrl = null;
        } else {
          conn.close();
        }
        respondError(id, "ABORTED", "Connect aborted by close");
        log("debug", "connect aborted — stale gen", gen, "vs", connectGen);
        return;
      }
      connecting = false;
      cdpEndpointUrl = endpointUrl;
      respond(id, { connected: true, endpoint: endpointUrl });
      log("info", "CDP connected", endpointUrl);
    })
    .catch((err: Error) => {
      // Connection failed — clean up and always send a response so the
      // original R caller does not hang on a 30s timeout.
      // Only touch `connecting` if this promise is still the active one.
      if (gen === connectGen) {
        connecting = false;
        // Only null the globals if this connection is still the active one.
        if (cdpConnection === conn) {
          cdpConnection = null;
          cdpEndpointUrl = null;
        }
        respondError(id, "LPD_CONNECTION_ERROR", "Failed to connect to CDP endpoint");
        log("error", "CDP connection failed", endpointUrl, err.message);
      } else {
        // Stale connection — handleClose was called while we were connecting.
        // Clean up and send ABORTED so the R caller gets the correct reason.
        if (cdpConnection === conn) {
          cdpConnection = null;
          cdpEndpointUrl = null;
        }
        respondError(id, "ABORTED", "Connect aborted by close");
        log("debug", "connect aborted (catch) — stale gen", gen, "vs", connectGen);
      }
    });
}

// ── navigate handler ─────────────────────────────────────────────────

const NAVIGATE_TIMEOUT_MS = 30_000;

function isValidHttpUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    // Strip userinfo (username:password@) before validation to prevent
    // visual obfuscation of SSRF bypass.
    if (parsed.username || parsed.password) {
      return false;
    }
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return false;
    }
    // SSRF guard — reject private, link-local, and reserved IP ranges.
    if (isPrivateHost(parsed.hostname)) {
      return false;
    }
    return true;
  } catch {
    return false;
  }
}

function isPrivateHost(host: string): boolean {
  // Node.js URL.hostname includes brackets for IPv6 addresses (e.g. "[::1]").
  // Strip them so the pattern checks below work on the bare address.
  const h = host.replace(/^\[/, "").replace(/\]$/, "").toLowerCase();
  // Detect numeric IP obfuscation — browsers may parse these as loopback IPs.
  if (/^0x[0-9a-f]/i.test(h)) return true;
  if (/^0\d/.test(h) && /\d+\.\d+\.\d+$/.test(h)) return true;
  if (/^\d{7,}$/.test(h)) return true;
  if (/%\w/i.test(h)) return true;
  // Private ranges (RFC 1918).
  if (/^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(h)) return true;
  if (/^172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}$/.test(h)) return true;
  if (/^192\.168\.\d{1,3}\.\d{1,3}$/.test(h)) return true;
  // Link-local / API metadata (RFC 3927, RFC 6598, AWS/GCP/Azure metadata).
  if (/^169\.254\.\d{1,3}\.\d{1,3}$/.test(h)) return true;
  // Carrier-grade NAT (RFC 6598, 100.64/10 only).
  if (/^100\.(6[4-9]|7\d|8[0-9]|9\d|[12]\d|3[01])\.\d{1,3}\.\d{1,3}$/.test(h)) return true;
  // 0.0.0.0 / 0.0.0.0/8.
  if (h === "0.0.0.0" || /^0\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(h)) return true;
  // Documentation / reserved (RFC 5737).
  if (/^192\.0\.2\.\d{1,3}$/.test(h)) return true;
  if (/^198\.51\.100\.\d{1,3}$/.test(h)) return true;
  if (/^203\.0\.113\.\d{1,3}$/.test(h)) return true;
  // IPv6 loopback and private ranges.
  if (h === "::1" || h === "0:0:0:0:0:0:0:1" || h === "::ffff:127.0.0.1" || h === "::ffff:7f00:1") return true;
  if (/^fc\d\d:/i.test(h) || /^fc[0-9a-f]{2}:/i.test(h)) return true;
  if (/^fd..:/i.test(h)) return true;
  if (/^fe80:/i.test(h)) return true;
  return false;
}

async function handleNavigate(id: unknown, params?: unknown): Promise<void> {
  // Validate params first (before connection check).
  let url: string;
  if (typeof params === "object" && params !== null) {
    const p = params as Record<string, unknown>;
    if (typeof p.url === "string" && p.url.length > 0) {
      url = p.url;
      if (!isValidHttpUrl(url)) {
        respondError(id, "INVALID_REQUEST", "navigate only supports http: and https: URLs");
        return;
      }
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

  // Capture local reference to prevent race with handleClose nullifying cdpConnection.
  const conn = cdpConnection;

  // Wrap navigation in a promise that resolves on Page.loadEventFired or times out.
  const navPromise = new Promise<Record<string, unknown>>((resolve, reject) => {
    let settled = false;
    let timeout: ReturnType<typeof setTimeout>;

    // Declare listeners before timeout so the variables are in scope.
    // `let` TDZ does not apply here because CDP events are always async
    // — `onLoad`/`onFrameStopped`/`onConnClosed` are never invoked before
    // `timeout` is assigned by setTimeout's timer callback.
    const onLoad = (): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        conn!.removeListener("Page.loadEventFired", onLoad);
        conn!.removeListener("Page.frameStoppedLoading", onFrameStopped);
        conn!.removeListener("close", onConnClosed);
        resolve({ loadEventFired: true });
      }
    };

    // Also listen for frameStoppedLoading as a fallback settle signal.
    const onFrameStopped = (): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        conn!.removeListener("Page.loadEventFired", onLoad);
        conn!.removeListener("Page.frameStoppedLoading", onFrameStopped);
        conn!.removeListener("close", onConnClosed);
        resolve({ frameStoppedLoading: true });
      }
    };

    // If the connection closes during navigation (e.g. handleClose called after
    // Page.navigate was sent but before load events fire), reject immediately
    // instead of waiting for the full 30s timeout.
    const onConnClosed = (): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        conn!.removeListener("Page.loadEventFired", onLoad);
        conn!.removeListener("Page.frameStoppedLoading", onFrameStopped);
        conn!.removeListener("close", onConnClosed);
        reject(new Error("Connection closed during navigation"));
      }
    };

    timeout = setTimeout(() => {
      if (!settled) {
        settled = true;
        conn!.removeListener("Page.loadEventFired", onLoad);
        conn!.removeListener("Page.frameStoppedLoading", onFrameStopped);
        conn!.removeListener("close", onConnClosed);
        reject(new Error(`Navigation timeout after ${NAVIGATE_TIMEOUT_MS}ms to ${url}`));
      }
    }, NAVIGATE_TIMEOUT_MS);

    conn!.on("Page.loadEventFired", onLoad);
    conn!.on("Page.frameStoppedLoading", onFrameStopped);
    conn!.on("close", onConnClosed);

    // Enable the Page domain first.
    conn!
      .sendCommand("Page.enable")
      .then(() => conn!.sendCommand("Page.navigate", { url }))
      .then((result) => {
        // Navigation sent; waiting for loadEventFired.
        log("debug", "Page.navigate sent for", url, "loaderId=", (result as Record<string, unknown>).loaderId);
      })
      .catch((err: Error) => {
        // Page.enable or Page.navigate failed.
        conn!.removeListener("Page.loadEventFired", onLoad);
        conn!.removeListener("Page.frameStoppedLoading", onFrameStopped);
        conn!.removeListener("close", onConnClosed);
        clearTimeout(timeout);
        settled = true;
        reject(err);
      });
  });

  try {
    const result = await navPromise;
    respond(id, { url, navigated: true, result });
    log("info", "navigated to", url);
  } catch (err) {
    respondError(id, "PAGE_LOAD_ERROR", `Navigation failed: ${(err as Error).message}`);
    log("error", "navigation failed for", url, (err as Error).message);
  }
}

// ── evaluate handler ─────────────────────────────────────────────────

async function handleEvaluate(id: unknown, params?: unknown): Promise<void> {
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

  // Capture local reference to prevent race with handleClose nullifying cdpConnection.
  const conn = cdpConnection;

  try {
    // Use Runtime.evaluate via CDP.
    await conn.sendCommand("Runtime.enable");
    const result = await conn.sendCommand("Runtime.evaluate", { expression: expr, returnByValue: true });
    // CDP includes exceptionDetails when JS throws — treat as evaluation error.
    if (result && typeof result === "object" && "exceptionDetails" in result) {
      const details = (result as Record<string, unknown>).exceptionDetails as Record<string, unknown>;
      const message = typeof details === "object" && details !== null && "text" in details
        ? String(details.text)
        : "JavaScript exception";
      respondError(id, "JS_EXCEPTION", `JavaScript evaluation failed: ${message}`);
      log("error", "evaluate threw exception, expression length", expr.length);
      return;
    }
    respond(id, { evaluated: true, result });
    log("debug", "evaluate succeeded for expression length", expr.length);
  } catch (err) {
    respondError(id, "CDP_ERROR", `JavaScript evaluation failed: ${(err as Error).message}`);
    log("error", "evaluate failed, expression length", expr.length, (err as Error).message);
  }
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

    // Validate id before method so malformed requests that omit id get a
    // matching error response instead of R waiting 30s for a timeout.
    if (id === undefined || id === null) {
      respondError(null, "INVALID_REQUEST", "Missing 'id' field");
      log("warn", "missing id");
      continue;
    }

    if (typeof method !== "string") {
      // Echo id when present so the R sidecar can match the error to its request.
      // Without this, R waits 30s for a matching id and times out instead of failing fast.
      respondError(id, "INVALID_REQUEST", "Missing 'method' field");
      log("warn", "missing method");
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
        await handleNavigate(id, req.params);
        break;
      case "evaluate":
        await handleEvaluate(id, req.params);
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
