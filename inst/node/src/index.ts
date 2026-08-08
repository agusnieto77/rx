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
import { ChromiumBackend } from "./browser/chromium.js";

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

// ── Backend abstraction ──────────────────────────────────────────────
//
// The sidecar now supports two backend types:
//   - "cdp" (default): connects to a CDP endpoint via WebSocket
//     (Lightpanda, Chrome DevTools Protocol).
//   - "chromium": launches a local Chromium instance via Puppeteer.
//
// Both implement the same methods (navigate, evaluate, close) so that
// the public R API is unchanged regardless of the backend.
//
// State is unified — `currentBackend` holds whichever backend was
// connected.  This avoids duplicating handlers for two separate backends.

type BackendType = "cdp" | "chromium";

let currentBackend: DefaultCdpConnection | ChromiumBackend | null = null;
let backendType: BackendType | null = null;
let cdpEndpointUrl: string | null = null;
// Generation counter to abort stale async operations when handleClose
// nullifies the connection while a prior connect() is still pending.
let connectGen = 0;
// Guard to prevent concurrent connect attempts that would leak connections.
let connecting = false;

function getCDP(): DefaultCdpConnection | null {
  return currentBackend instanceof DefaultCdpConnection ? currentBackend : null;
}

function getChromium(): ChromiumBackend | null {
  return currentBackend instanceof ChromiumBackend ? currentBackend : null;
}

function isChromium(): boolean {
  return backendType === "chromium";
}

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
// Secondary map keyed by requestId that persists until Clear, so
// handleNetworkCaptureGetBody can look up events after a prior Get
// has returned a snapshot and cleared the main buffer.
let networkEventsById = new Map<string, NetworkEvent>();
// TODO: size cap / LRU eviction — a page with 10k resources after 5 Get()
// cycles holds 10k entries. Consider a max-size or TTL-based cleanup.
// Module-level references to the current handler closures, so that
// handleNetworkCaptureClear() can remove them without casting.
let _captureOnRequest: ((params: Record<string, unknown>) => void) | null = null;
let _captureOnResponse: ((params: Record<string, unknown>) => void) | null = null;

async function handleNetworkCaptureEnable(id: unknown): Promise<void> {
  if (isChromium()) {
    respondError(id, "CDP_ERROR", "Network capture requires CDP backend, not Chromium");
    return;
  }
  const conn = getCDP();
  if (conn === null || !conn.isConnected) {
    respondError(id, "CDP_ERROR", "Cannot enable network capture — CDP connection not active");
    return;
  }
  // Guard against stale backend reference.
  if (currentBackend !== conn) {
    respondError(id, "CDP_ERROR", "CDP connection not active");
    return;
  }
  networkEvents = [];
  networkEventsById.clear();

  // Remove stale listeners from a prior enable call to prevent duplicate
  // event pushes. This also fixes the race window: we register listeners
  // BEFORE sending Network.enable so no events are lost.
  if (_captureOnRequest !== null) {
    conn.removeListener("Network.requestWillBeSent", _captureOnRequest);
  }
  if (_captureOnResponse !== null) {
    conn.removeListener("Network.responseReceived", _captureOnResponse);
  }

  const onRequest = (params: Record<string, unknown>): void => {
    const request = params.request as Record<string, unknown> | undefined;
    const entry: NetworkEvent = {
      requestId: String(params.requestId ?? ""),
      url: String((request?.url ?? params.url ?? "") as string),
      method: request?.method as string | undefined,
      resourceType: String(params.type ?? ""),
    };
    networkEvents.push(entry);
    // Keep a secondary index so GetBody can find events after Get
    // has returned a snapshot and cleared the main buffer.
    networkEventsById.set(entry.requestId, entry);
  };

  const onResponse = (params: Record<string, unknown>): void => {
    const rid = String(params.requestId ?? "");
    const response = params.response as Record<string, unknown> | undefined;
    // Update the main array (for events still being captured).
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
    // Also update the map directly so events already returned by Get()
    // still get their status/contentType updated by interleaved responses.
    // The map entry is the same object reference as the array entry.
    const mapped = networkEventsById.get(rid);
    if (mapped) {
      mapped.status = typeof (response?.status as number | undefined) === "number" ? response!.status as number : undefined;
      mapped.protocol = String((response?.protocol as string | undefined) ?? "");
      mapped.fromDiskCache = Boolean(response?.fromDiskCache);
      mapped.fromServiceWorker = Boolean(response?.fromServiceWorker);
      mapped.fromPrefetchCache = Boolean(response?.fromPrefetchCache);
      mapped.timedOut = Boolean(response?.timedOut);
      const ct = (response?.contentType as string | undefined) ?? "";
      mapped.contentType = ct.split(";")[0].trim();
    }
  };

  // Register listeners BEFORE sending Network.enable to prevent the narrow
  // race window where CDP emits events before listeners are attached.
  _captureOnRequest = onRequest;
  _captureOnResponse = onResponse;

  // Only register Network.requestWillBeSent — Network.request is not a
  // standard CDP event and likely never fires; registering it would cause
  // duplicate calls if a custom runtime emits both.
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
  if (isChromium()) {
    respond(id, { events: [] });
    return;
  }
  // Return a snapshot and clear the array, but keep the secondary map
  // so handleNetworkCaptureGetBody can still look up events by requestId.
  // Note: networkEventsById accumulates entries until handleNetworkCaptureClear
  // is called. This is a known limitation (see TODO at line 117).
  const events = networkEvents.slice();
  networkEvents = [];
  respond(id, { events });
}

async function handleNetworkCaptureClear(id: unknown): Promise<void> {
  if (isChromium()) {
    respond(id, { cleared: true });
    return;
  }
  // Disable the CDP Network domain so the browser stops sending network
  // events. Await to serialize with any concurrent enable call.
  const conn = getCDP();
  if (conn !== null && conn.isConnected) {
    try {
      await conn.sendCommand("Network.disable");
    } catch {
      // Best-effort — logging is enough.
    }
  }
  networkEvents = [];
  networkEventsById.clear();
  // Remove event listeners from the connection.
  const c = getCDP();
  if (c !== null && _captureOnRequest !== null) {
    c.removeListener("Network.requestWillBeSent", _captureOnRequest);
  }
  if (c !== null && _captureOnResponse !== null) {
    c.removeListener("Network.responseReceived", _captureOnResponse);
  }
  _captureOnRequest = null;
  _captureOnResponse = null;
  respond(id, { cleared: true });
}

// ── response body retrieval ──────────────────────────────────────────

/** Fetch the response body for a captured requestId via CDP. */
async function handleNetworkCaptureGetBody(id: unknown, params?: unknown): Promise<void> {
  if (isChromium()) {
    respondError(id, "CDP_ERROR", "Network body capture requires CDP backend, not Chromium");
    return;
  }
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

  const conn = getCDP();
  if (conn === null || !conn.isConnected) {
    respondError(id, "CDP_ERROR", "Cannot get body — CDP connection not active");
    return;
  }

  // Validate that the requestId exists in our captured events.
  // Use the secondary map (networkEventsById) so GetBody works even after
  // Get() has returned a snapshot and cleared the main array.
  const event = networkEventsById.get(requestId)
    ?? networkEvents.find((e) => e.requestId === requestId);
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

async function handleClose(id: unknown): Promise<void> {
  // Always bump generation and clear the connecting flag first, so that any
  // pending async connect() will see gen !== connectGen and clean itself up.
  // If we returned early here without bumping connectGen / clearing connecting,
  // a stale pending connect would resolve normally and leave connecting=true
  // forever, blocking all future connect() calls.
  connectGen++;
  connecting = false;

  if (currentBackend === null || !currentBackend.isConnected) {
    currentBackend = null;
    backendType = null;
    cdpEndpointUrl = null;
    respond(id, { closed: false, reason: "not_connected" });
    log("debug", "browser close — already not connected");
    return;
  }

  if (isChromium()) {
    await getChromium()!.close();
  } else {
    getCDP()!.close();
  }
  currentBackend = null;
  backendType = null;
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

async function handleConnect(id: unknown, params?: unknown): Promise<void> {
  if (currentBackend !== null && currentBackend.isConnected) {
    respond(id, { connected: true, endpoint: cdpEndpointUrl ?? "unknown", backend: backendType ?? "cdp" });
    log("info", "already connected to", backendType ?? "CDP");
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

  let endpointUrl: string | null = null;
  let backendTypeParam: string | undefined;
  let chromiumOptions: Record<string, unknown> | undefined;

  if (typeof params === "object" && params !== null) {
    const p = params as Record<string, unknown>;

    // backend — which backend to use: "cdp" (default) or "chromium"
    if (p.backend !== undefined && p.backend !== null) {
      if (typeof p.backend === "string") {
        backendTypeParam = p.backend;
      } else {
        respondError(id, "INVALID_REQUEST", "backend must be a string");
        return;
      }
    }

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
      respondError(id, "INVALID_REQUEST", "endpoint must be a string");
      return;
    }

    // chromiumOptions — passed through to Puppeteer when backend="chromium"
    if (p.chromiumOptions !== undefined && p.chromiumOptions !== null) {
      if (typeof p.chromiumOptions === "object" && !Array.isArray(p.chromiumOptions)) {
        chromiumOptions = p.chromiumOptions as Record<string, unknown>;
      }
    }
  }

  const resolvedBackend = backendTypeParam ?? "cdp";

  if (resolvedBackend === "chromium") {
    // Launch a local Chromium instance via Puppeteer.
    connecting = true;
    const gen = ++connectGen;
    const chromium = new ChromiumBackend();
    currentBackend = chromium;
    backendType = "chromium";

    const launchOpts: Record<string, unknown> = {};
    if (endpointUrl) {
      // When endpoint is provided with chromium backend, treat it as a CDP
      // attachment target (e.g. for testing with Lightpanda).
      launchOpts.type = "cdp";
      launchOpts.endpoint = endpointUrl;
    }
    if (chromiumOptions) {
      Object.assign(launchOpts, chromiumOptions);
    }
    if (!launchOpts.type) {
      launchOpts.type = "chromium";
    }

    chromium
      .connect(launchOpts as Parameters<ChromiumBackend["connect"]>[0])
      .then((result) => {
        if (gen !== connectGen) {
          chromium.close();
          respondError(id, "ABORTED", "Connect aborted by close");
          connecting = false;
          return;
        }
        connecting = false;
        cdpEndpointUrl = result.endpoint;
        respond(id, { connected: true, endpoint: result.endpoint, backend: "chromium" });
        log("info", "Chromium backend connected");
      })
      .catch((err: Error) => {
        if (gen === connectGen) {
          connecting = false;
          currentBackend = null;
          backendType = null;
        }
        respondError(id, "LPD_CONNECTION_ERROR", "Failed to connect Chromium: " + err.message);
        log("error", "Chromium connection failed", err.message);
      });
  } else {
    // Default CDP backend — existing behavior unchanged.
    if (!endpointUrl) {
      endpointUrl = process.env.LPD_ENDPOINT ?? "ws://127.0.0.1:21111";
      if (!isValidWsUrl(endpointUrl)) {
        respondError(id, "INVALID_REQUEST", "endpoint must be a ws: or wss: URL");
        return;
      }
    }

    connecting = true;
    const gen = ++connectGen;
    const conn = new DefaultCdpConnection();
    currentBackend = conn;
    backendType = "cdp";

    conn
      .connect(endpointUrl)
      .then(() => {
        if (gen !== connectGen) {
          if (currentBackend === conn) {
            conn.close();
            currentBackend = null;
            backendType = null;
            cdpEndpointUrl = null;
          } else {
            conn.close();
          }
          respondError(id, "ABORTED", "Connect aborted by close");
          connecting = false;
          return;
        }
        connecting = false;
        cdpEndpointUrl = endpointUrl;
        respond(id, { connected: true, endpoint: endpointUrl, backend: "cdp" });
        log("info", "CDP connected", endpointUrl);
      })
      .catch((err: Error) => {
        if (gen === connectGen) {
          connecting = false;
          if (currentBackend === conn) {
            currentBackend = null;
            backendType = null;
            cdpEndpointUrl = null;
          }
        }
        respondError(id, "LPD_CONNECTION_ERROR", "Failed to connect to CDP endpoint: " + err.message);
        log("error", "CDP connection failed", endpointUrl, err.message);
      });
  }
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

  // Detect IPv4-mapped IPv6 (e.g. ::ffff:10.0.0.1) — extract the embedded
  // IPv4 address and check it, since the raw IPv6 string would not match
  // the IPv4-only patterns below.
  // NOTE: hex-encoded IPv4 form (e.g. ::ffff:c0a8:101 → 192.168.1.1) is
  // not handled here. A production system should normalize this via
  // ipaddr.js or similar. See: https://github.com/whitequark/ipaddr.js
  const ipv6Mapped = /^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/i.exec(h);
  if (ipv6Mapped !== null) {
    return isPrivateHost(ipv6Mapped[1]);
  }

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

async function handleNavigateCdp(id: unknown, url: string, conn: DefaultCdpConnection): Promise<void> {
  // Wrap navigation in a promise that resolves on Page.loadEventFired or times out.
  const navPromise = new Promise<Record<string, unknown>>((resolve, reject) => {
    let settled = false;
    let timeout: ReturnType<typeof setTimeout>;

    const onLoad = (): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        conn.removeListener("Page.loadEventFired", onLoad);
        conn.removeListener("Page.frameStoppedLoading", onFrameStopped);
        conn.removeListener("close", onConnClosed);
        resolve({ loadEventFired: true });
      }
    };

    const onFrameStopped = (): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        conn.removeListener("Page.loadEventFired", onLoad);
        conn.removeListener("Page.frameStoppedLoading", onFrameStopped);
        conn.removeListener("close", onConnClosed);
        resolve({ frameStoppedLoading: true });
      }
    };

    const onConnClosed = (): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        conn.removeListener("Page.loadEventFired", onLoad);
        conn.removeListener("Page.frameStoppedLoading", onFrameStopped);
        conn.removeListener("close", onConnClosed);
        reject(new Error("Connection closed during navigation"));
      }
    };

    timeout = setTimeout(() => {
      if (!settled) {
        settled = true;
        conn.removeListener("Page.loadEventFired", onLoad);
        conn.removeListener("Page.frameStoppedLoading", onFrameStopped);
        conn.removeListener("close", onConnClosed);
        reject(new Error(`Navigation timeout after ${NAVIGATE_TIMEOUT_MS}ms to ${url}`));
      }
    }, NAVIGATE_TIMEOUT_MS);

    conn.on("Page.loadEventFired", onLoad);
    conn.on("Page.frameStoppedLoading", onFrameStopped);
    conn.on("close", onConnClosed);

    conn
      .sendCommand("Page.enable")
      .then(() => conn.sendCommand("Page.navigate", { url }))
      .then((result) => {
        log("debug", "Page.navigate sent for", url, "loaderId=", (result as Record<string, unknown>).loaderId);
      })
      .catch((err: Error) => {
        conn.removeListener("Page.loadEventFired", onLoad);
        conn.removeListener("Page.frameStoppedLoading", onFrameStopped);
        conn.removeListener("close", onConnClosed);
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

async function handleNavigateChromium(id: unknown, url: string, chromium: ChromiumBackend): Promise<void> {
  try {
    const result = await chromium.navigate(url);
    respond(id, { url, navigated: result.navigated, result: { status: result.status } });
    log("info", "chromium navigated to", url);
  } catch (err) {
    respondError(id, "PAGE_LOAD_ERROR", `Navigation failed: ${(err as Error).message}`);
    log("error", "chromium navigation failed for", url, (err as Error).message);
  }
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

  if (currentBackend === null || !currentBackend.isConnected) {
    respondError(id, "PAGE_LOAD_ERROR", "Cannot navigate — backend connection not active");
    log("warn", "navigate failed — not connected");
    return;
  }

  if (isChromium()) {
    const chromium = getChromium();
    if (chromium === null) {
      respondError(id, "PAGE_LOAD_ERROR", "Chromium backend not available");
      return;
    }
    await handleNavigateChromium(id, url, chromium);
  } else {
    const conn = getCDP();
    if (conn === null) {
      respondError(id, "PAGE_LOAD_ERROR", "CDP connection not active");
      return;
    }
    await handleNavigateCdp(id, url, conn);
  }
}

// ── evaluate handler ─────────────────────────────────────────────────

async function handleEvaluateCdp(id: unknown, expr: string, conn: DefaultCdpConnection): Promise<void> {
  try {
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

async function handleEvaluateChromium(id: unknown, expr: string, chromium: ChromiumBackend): Promise<void> {
  try {
    const result = await chromium.evaluate(expr);
    respond(id, result);
    log("debug", "chromium evaluate succeeded for expression length", expr.length);
  } catch (err) {
    respondError(id, "CDP_ERROR", `JavaScript evaluation failed: ${(err as Error).message}`);
    log("error", "chromium evaluate failed, expression length", expr.length, (err as Error).message);
  }
}

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

  if (currentBackend === null || !currentBackend.isConnected) {
    respondError(id, "CDP_ERROR", "Cannot evaluate — backend connection not active");
    log("warn", "evaluate failed — not connected");
    return;
  }

  if (isChromium()) {
    const chromium = getChromium();
    if (chromium === null) {
      respondError(id, "CDP_ERROR", "Chromium backend not available");
      return;
    }
    await handleEvaluateChromium(id, expr, chromium);
  } else {
    const conn = getCDP();
    if (conn === null) {
      respondError(id, "CDP_ERROR", "CDP connection not active");
      return;
    }
    await handleEvaluateCdp(id, expr, conn);
  }
}

// ── domInspect handler ────────────────────────────────────────────────

async function handleDomInspect(id: unknown, params?: unknown): Promise<void> {
  // Validate params — selector must be a single non-empty string, or absent.
  let selector: string | null = null;
  if (typeof params === "object" && params !== null) {
    const p = params as Record<string, unknown>;
    if (typeof p.selector === "string" && p.selector.length > 0) {
      selector = p.selector;
    } else if (p.selector !== undefined && p.selector !== null) {
      // Non-string, empty, or multi-element selector — reject instead of
      // silently falling back to full HTML, which confuses debug users.
      respondError(id, "INVALID_REQUEST", "selector must be a single non-empty string or omitted");
      return;
    }
    // selector === undefined or null → full HTML mode (null default)
  }

  if (currentBackend === null || !currentBackend.isConnected) {
    respondError(id, "CDP_ERROR", "Cannot inspect DOM — backend connection not active");
    log("warn", "domInspect failed — not connected");
    return;
  }

  // DOM inspect is only implemented for CDP backend in this spike.
  if (isChromium()) {
    respondError(id, "CDP_ERROR", "DOM inspect requires CDP backend, not Chromium");
    return;
  }

  const conn = getCDP()!;

  try {
    await conn.sendCommand("Runtime.enable");

    let result: Record<string, unknown>;

    if (selector !== null) {
      // Query a specific selector and return outer HTML of matches.
      // Use Function to safely pass the selector string without template-literal escaping issues.
      const js = `
        (function(sel) {
          const nodes = Array.from(document.querySelectorAll(sel));
          return nodes.map(n => ({
            tagName: n.tagName.toLowerCase(),
            id: n.id || null,
            className: n.className || null,
            outerHTML: n.outerHTML
          }));
        })(${JSON.stringify(selector)})`;
      const evalResult = await conn.sendCommand("Runtime.evaluate", { expression: js, returnByValue: true });
      if (evalResult && typeof evalResult === "object" && "exceptionDetails" in evalResult) {
        const details = (evalResult as Record<string, unknown>).exceptionDetails as Record<string, unknown>;
        const message = typeof details === "object" && details !== null && "text" in details
          ? String(details.text)
          : "DOM query exception";
        respondError(id, "JS_EXCEPTION", `DOM query failed: ${message}`);
        return;
      }
      result = { selector, found: (evalResult as Record<string, unknown>).value };
    } else {
      // Return the full document HTML.
      const js = "document.documentElement.outerHTML";
      const evalResult = await conn.sendCommand("Runtime.evaluate", { expression: js, returnByValue: true });
      if (evalResult && typeof evalResult === "object" && "exceptionDetails" in evalResult) {
        const details = (evalResult as Record<string, unknown>).exceptionDetails as Record<string, unknown>;
        const message = typeof details === "object" && details !== null && "text" in details
          ? String(details.text)
          : "DOM read exception";
        respondError(id, "JS_EXCEPTION", `DOM inspection failed: ${message}`);
        return;
      }
      result = { html: String((evalResult as Record<string, unknown>).value ?? "") };
    }

    respond(id, result);
    log("debug", "domInspect succeeded", selector ? `selector=${selector}` : "full html");
  } catch (err) {
    respondError(id, "CDP_ERROR", `DOM inspection failed: ${(err as Error).message}`);
    log("error", "domInspect failed", (err as Error).message);
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
        await handleConnect(id, req.params);
        break;
      case "close":
        await handleClose(id);
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
      case "domInspect":
        await handleDomInspect(id, req.params);
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
