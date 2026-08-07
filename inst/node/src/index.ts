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

  cdpConnection = new DefaultCdpConnection();

  cdpConnection
    .connect(endpointUrl)
    .then(() => {
      cdpEndpointUrl = endpointUrl;
      respond(id, { connected: true, endpoint: endpointUrl });
      log("info", "CDP connected", endpointUrl);
    })
    .catch((err: Error) => {
      // Connection failed — clean up and return structured error.
      cdpConnection = null;
      cdpEndpointUrl = null;
      respondError(id, "LPD_CONNECTION_ERROR", `Failed to connect to CDP endpoint: ${err.message}`);
      log("error", "CDP connection failed", endpointUrl, err.message);
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
