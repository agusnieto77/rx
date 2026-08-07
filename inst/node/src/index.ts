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

// ── network capture state ────────────────────────────────────────────

interface NetworkEvent {
  requestId: string;
  url: string;
  method?: string;
  resourceType?: string;
  status?: number;
  fromDiskCache?: boolean;
  fromServiceWorker?: boolean;
  fromPrefetchCache?: boolean;
  timedOut?: boolean;
  protocol?: string;
  contentType?: string;
}

let networkEvents: NetworkEvent[] = [];
// Module-level references to the current handler closures, so that
// handleNetworkCaptureClear() can remove them without casting.
let _captureOnRequest: ((params: Record<string, unknown>) => void) | null = null;
let _captureOnResponse: ((params: Record<string, unknown>) => void) | null = null;

async function handleNetworkCaptureEnable(id: unknown): Promise<void> {
  if (cdpConnection === null || !cdpConnection.isConnected) {
    respondError(id, "CDP_ERROR", "Cannot enable network capture — CDP connection not active");
    return;
  }
  const conn = cdpConnection;
  networkEvents = [];

  // Remove stale listeners from a prior enable call to prevent duplicate
  // event pushes. This also fixes the race window: we register listeners
  // BEFORE sending Network.enable so no events are lost.
  if (_captureOnRequest !== null) {
    conn.removeListener("Network.request", _captureOnRequest);
    conn.removeListener("Network.requestWillBeSent", _captureOnRequest);
  }
  if (_captureOnResponse !== null) {
    conn.removeListener("Network.responseReceived", _captureOnResponse);
  }

  const onRequest = (params: Record<string, unknown>): void => {
    const request = params.request as Record<string, unknown> | undefined;
    networkEvents.push({
      requestId: String(params.requestId ?? ""),
      url: String((request?.url ?? params.url ?? "") as string),
      method: request?.method as string | undefined,
      resourceType: String(params.type ?? ""),
    });
  };

  const onResponse = (params: Record<string, unknown>): void => {
    const rid = String(params.requestId ?? "");
    const response = params.response as Record<string, unknown> | undefined;
    for (const ev of networkEvents) {
      if (ev.requestId === rid) {
        ev.status = typeof (response?.status as number | undefined) === "number" ? response!.status as number : undefined;
        ev.protocol = String((response?.protocol as string | undefined) ?? "");
        ev.fromDiskCache = Boolean(response?.fromDiskCache);
        ev.fromServiceWorker = Boolean(response?.fromServiceWorker);
        ev.fromPrefetchCache = Boolean(response?.fromPrefetchCache);
        ev.timedOut = Boolean(response?.timedOut);
        // Store the content type so the body getter knows whether to
        // attempt JSON parsing.  Only the media type (before ";") is kept
        // to ignore charset directives — the sidecar always decodes as
        // UTF-8 regardless of the declared encoding.
        const ct = (response?.contentType as string | undefined) ?? "";
        ev.contentType = ct.split(";")[0].trim();
        break;
      }
    }
  };

  // Register listeners BEFORE sending Network.enable to prevent the narrow
  // race window where CDP emits events before listeners are attached.
  _captureOnRequest = onRequest;
  _captureOnResponse = onResponse;

  conn.on("Network.request", onRequest as (params: Record<string, unknown>) => void);
  conn.on("Network.requestWillBeSent", onRequest as (params: Record<string, unknown>) => void);
  conn.on("Network.responseReceived", onResponse as (params: Record<string, unknown>) => void);

  // Now enable the CDP Network domain — await to serialize with any
  // concurrent clear/disable call so the domain is guaranteed enabled.
  try {
    await conn.sendCommand("Network.enable");
  } catch (err: unknown) {
    log("warn", "Network.enable failed", (err as Error).message);
  }

  log("info", "network capture enabled");
  respond(id, { enabled: true, eventsCaptured: networkEvents.length });
}

function handleNetworkCaptureGet(id: unknown): void {
  const events = networkEvents.slice();
  networkEvents = [];
  respond(id, { events });
}

async function handleNetworkCaptureClear(id: unknown): Promise<void> {
  // Disable the CDP Network domain so the browser stops sending network
  // events. Await to serialize with any concurrent enable call.
  if (cdpConnection !== null && cdpConnection.isConnected) {
    try {
      await cdpConnection.sendCommand("Network.disable");
    } catch {
      // Best-effort — logging is enough.
    }
  }
  networkEvents = [];
  // Remove event listeners from the connection.
  if (cdpConnection !== null && _captureOnRequest !== null) {
    cdpConnection.removeListener("Network.request", _captureOnRequest);
    cdpConnection.removeListener("Network.requestWillBeSent", _captureOnRequest);
  }
  if (cdpConnection !== null && _captureOnResponse !== null) {
    cdpConnection.removeListener("Network.responseReceived", _captureOnResponse);
  }
  _captureOnRequest = null;
  _captureOnResponse = null;
  respond(id, { cleared: true });
}

// ── response body retrieval ──────────────────────────────────────────

/** Fetch the response body for a captured requestId via CDP. */
async function handleNetworkCaptureGetBody(id: unknown, params?: unknown): Promise<void> {
  let requestId: string;
  if (typeof params === "object" && params !== null) {
    const p = params as Record<string, unknown>;
    if (typeof p.requestId === "string" && p.requestId.length > 0) {
      requestId = p.requestId;
    } else {
      respondError(id, "INVALID_REQUEST", "requestBody requires a non-empty 'requestId' parameter");
      return;
    }
  } else {
    respondError(id, "INVALID_REQUEST", "requestBody requires a 'requestId' parameter");
    return;
  }

  if (cdpConnection === null || !cdpConnection.isConnected) {
    respondError(id, "CDP_ERROR", "Cannot get body — CDP connection not active");
    return;
  }

  const conn = cdpConnection;

  // Validate that the requestId exists in our captured events.
  const event = networkEvents.find((e) => e.requestId === requestId);
  if (!event) {
    respondError(id, "REQUEST_ID_NOT_FOUND", `No captured event with requestId="${requestId}"`);
    return;
  }

  // Find the content-type from the matching event.
  const contentType = (event.contentType ?? "").split(";")[0].trim();

  try {
    const result = await conn.sendCommand("Network.getResponseBody", { requestId });
    const body = (result as Record<string, unknown>).body as string | undefined;
    const base64Encoded = Boolean((result as Record<string, unknown>).base64Encoded);

    if (!body) {
      respond(id, { requestId, body: null, contentType: contentType || undefined, error: "no_body_available" });
      return;
    }

    const decoded = base64Encoded ? Buffer.from(body, "base64").toString("utf-8") : body;

    // Attempt JSON parsing for application/json content types.
    if (contentType === "application/json") {
      try {
        const parsed = JSON.parse(decoded);
        respond(id, { requestId, body: parsed, contentType, error: null });
        return;
      } catch {
        // Fall through to raw body if JSON parsing fails.
      }
    }

    respond(id, { requestId, body: decoded, contentType: contentType || undefined, error: null });
  } catch (err) {
    respondError(
      id,
      "NETWORK_ERROR",
      `Failed to retrieve response body for requestId="${requestId}": ${(err as Error).message}`
    );
  }
}

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

  // Validate params: must be null, undefined, or an object (not a non-empty array).
  // R NULL serialises as {}, so allow both null and empty objects.
  const isInvalidParams = params === undefined || params === null
    ? false
    : typeof params !== "object"
      || (Array.isArray(params) && params.length > 0);
  if (isInvalidParams) {
    respondError(id, "INVALID_REQUEST", "params must be a JSON object or omitted");
    return;
  }

  let endpointUrl: string | undefined;
  if (typeof params === "object" && params !== null) {
    const p = params as Record<string, unknown>;
    const ep = p.endpoint;

    // endpoint must be a non-empty string, or absent/nullish.
    if (typeof ep === "string" && ep.length > 0) {
      // Validate endpoint to prevent SSRF — only allow ws: and wss: schemes.
      if (!isValidWsUrl(ep)) {
        respondError(id, "INVALID_REQUEST", "endpoint must be a ws: or wss: URL");
        return;
      }
      endpointUrl = ep;
    } else if (ep !== undefined && ep !== null) {
      // Non-string, non-nullish endpoint value — caller typo.
      respondError(id, "INVALID_REQUEST", "endpoint must be a string");
      return;
    }
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
      case "networkCaptureEnable":
        await handleNetworkCaptureEnable(id);
        break;
      case "networkCaptureGet":
        handleNetworkCaptureGet(id);
        break;
      case "networkCaptureClear":
        await handleNetworkCaptureClear(id);
        break;
      case "networkCaptureGetBody":
        await handleNetworkCaptureGetBody(id, req.params);
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
