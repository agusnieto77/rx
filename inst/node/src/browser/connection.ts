// xtweetsR — CDP WebSocket connection manager
//
// Connects the sidecar to a Lightpanda (or Chrome-compatible) CDP endpoint
// over WebSocket.  Commands are dispatched with incremental IDs and responses
// are matched back via a pending-map.
//
// CDP protocol over WebSocket:
//   Send: { "id": <number>, "method": "<CDP method>", "params": <object>? }
//   Receive: { "id": <number>, "result": <object>? }  (response)
//            { "method": "<CDP event>", "params": <object>? }  (event)
//
// This module is intentionally minimal — no CDP helper abstractions,
// just raw command dispatch and response correlation.

import { WebSocket } from "ws";

// ── public types ─────────────────────────────────────────────────────

/** CDP response shape: either a result or an error. */
interface CdpResult {
  id: number;
  result?: Record<string, unknown>;
  error?: { code: number; message: string };
}

/** CDP event shape (no id, only method + params). */
interface CdpEvent {
  method: string;
  params?: Record<string, unknown>;
}

type CdpMessage = CdpResult | CdpEvent;

// ── DefaultCdpConnection implementation ──────────────────────────────

export class DefaultCdpConnection {
  private ws: WebSocket | null = null;
  private nextId = 1;
  private pending = new Map<number, { resolve: (v: Record<string, unknown>) => void; reject: (e: Error) => void; timer: ReturnType<typeof setTimeout> }>();
  private eventListeners = new Map<string, Set<(params: Record<string, unknown>) => void>>();
  private _isConnected = false;
  private commandTimeoutMs = 30_000;
  // Rejected when close() is called while connect() is still pending.
  private connectReject: ((e: Error) => void) | null = null;
  // Guard to prevent double-dispatch of "close" events (close() dispatches
  // listeners, then ws.close() triggers the same "close" event).
  private dispatchingClose = false;

  constructor() {
    // Timeout is fixed at 30 seconds to match NAVIGATE_TIMEOUT_MS in index.ts.
  }

  get isConnected(): boolean {
    return this._isConnected && this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }

  // -- connect ----------------------------------------------------------

  async connect(endpointUrl: string): Promise<void> {
    if (this.ws !== null) {
      this.close();
    }

    return new Promise((resolve, reject) => {
      // Track this reject so close() can abort a pending connect() immediately.
      this.connectReject = reject;

      try {
        const ws = new WebSocket(endpointUrl);
        this.ws = ws;

        const timeout = setTimeout(() => {
          // Null connectReject so close() / ws.on("close") know connect has
          // already been resolved (one way or another).
          this.connectReject = null;
          if (this.ws !== null) {
            try {
              this.ws.close();
            } catch {
              // WebSocket may already be closing/closed — safe to ignore.
            }
          }
          reject(new Error(`CDP connection timeout after 30s to ${endpointUrl}`));
        }, 30_000);

        ws.on("open", () => {
          clearTimeout(timeout);
          this.connectReject = null;
          this._isConnected = true;
          log("info", "CDP connected to", endpointUrl);
          resolve();
        });

        ws.on("message", (data: WebSocket.Data) => {
          this.handleMessage(data.toString());
        });

        ws.on("error", (err: Error) => {
          clearTimeout(timeout);
          this.connectReject = null;
          // Only reject if we haven't already resolved.
          if (this.ws !== null && !this._isConnected) {
            try {
              this.ws.close();
            } catch {
              // WebSocket may already be closing/closed — safe to ignore.
            }
            reject(new Error(`CDP WebSocket error: ${err.message}`));
          }
        });

        ws.on("close", (code: number, reason: Buffer) => {
          this._isConnected = false;
          const msg = `CDP connection closed (code=${code}, reason=${reason.toString()})`;
          log("warn", msg);
          // If connect() is still pending (no open/error yet), reject it now
          // so callers don't wait for the full 30s timeout.
          if (this.ws === ws && this.connectReject !== null) {
            clearTimeout(timeout);
            this.connectReject(new Error("Connection closed before handshake completed"));
            this.connectReject = null;
          }
          // Reject all pending commands.
          for (const [id, { reject, timer }] of this.pending) {
            clearTimeout(timer);
            reject(new Error(msg));
          }
          this.pending.clear();
          // Dispatch "close" event listeners so callers (e.g. navPromise)
          // that registered conn.on("close", ...) are notified immediately.
          // Guard prevents double dispatch when close() already dispatched
          // and ws.close() triggers the same "close" event.
          if (this.dispatchingClose) return;
          this.dispatchingClose = true;
          for (const fn of this.eventListeners.get("close") ?? []) {
            try {
              fn({});
            } catch {
              // Listener errors should not kill the connection.
            }
          }
          this.dispatchingClose = false;
        });
      } catch (err) {
        this.connectReject = null;
        reject(new Error(`Failed to create CDP WebSocket: ${(err as Error).message}`));
      }
    });
  }

  // -- sendCommand ------------------------------------------------------

  async sendCommand(method: string, params?: Record<string, unknown>): Promise<Record<string, unknown>> {
    if (!this.isConnected) {
      throw new Error(`CDP not connected — cannot send ${method}`);
    }

    const id = this.nextId++;
    const payload: Record<string, unknown> = { id, method };
    if (params) {
      payload.params = params;
    }

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP command timeout: ${method} (id=${id})`));
      }, this.commandTimeoutMs);

      this.pending.set(id, { resolve, reject, timer });

      if (this.ws !== null && this.ws.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify(payload));
      } else {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(new Error("CDP WebSocket not ready"));
      }
    });
  }

  // -- events -----------------------------------------------------------

  on(event: string, listener: (params: Record<string, unknown>) => void): void {
    if (!this.eventListeners.has(event)) {
      this.eventListeners.set(event, new Set());
    }
    this.eventListeners.get(event)!.add(listener);
  }

  removeListener(event: string, listener: (params: Record<string, unknown>) => void): void {
    const set = this.eventListeners.get(event);
    if (set) {
      set.delete(listener);
    }
  }

  // -- close ------------------------------------------------------------

  close(): void {
    if (this.ws !== null) {
      const wasConnected = this._isConnected;
      // Reject the connect promise if a connect() is still pending.
      if (this.connectReject !== null) {
        this.connectReject(new Error("Connection closed before handshake completed"));
        this.connectReject = null;
      }
      // Reject all pending commands.
      for (const [, { reject, timer }] of this.pending) {
        clearTimeout(timer);
        reject(new Error("Connection closed"));
      }
      this.pending.clear();
      // Dispatch "close" event listeners so callers (e.g. navPromise)
      // that registered conn.on("close", ...) are notified immediately.
      // Set guard before dispatch to prevent double-dispatch: close() dispatches,
      // then ws.close() triggers the same "close" event.
      this.dispatchingClose = true;
      for (const fn of this.eventListeners.get("close") ?? []) {
        try {
          fn({});
        } catch {
          // Listener errors should not kill the connection.
        }
      }
      this.dispatchingClose = false;
      try {
        this.ws.close();
      } catch {
        // WebSocket may already be closing/closed — safe to ignore.
      }
      this.ws = null;
      this._isConnected = false;
      if (wasConnected) {
        log("info", "CDP connection closed");
      }
    }
  }

  // -- internal: message handling ---------------------------------------

  private handleMessage(raw: string): void {
    let msg: CdpMessage;
    try {
      msg = JSON.parse(raw);
    } catch {
      log("warn", "invalid CDP message:", raw.slice(0, 200));
      return;
    }

    // Guard against primitives (42, "str", null, []) — the "in" operator
    // throws TypeError on non-objects, which would kill the event handler.
    if (typeof msg !== "object" || msg === null || Array.isArray(msg)) {
      log("debug", "non-object CDP message:", JSON.stringify(msg));
      return;
    }

    if ("id" in msg && msg.id !== undefined) {
      // Response — match to pending command.
      const id = typeof msg.id === "number" ? msg.id : -1;
      const pending = this.pending.get(id);
      if (pending) {
        this.pending.delete(id);
        clearTimeout(pending.timer);
        if (msg.error) {
          pending.reject(new Error(`CDP error ${msg.error.code}: ${msg.error.message}`));
        } else {
          pending.resolve((msg as CdpResult).result ?? {});
        }
      } else {
        log("debug", "unexpected CDP response id=", id, JSON.stringify(msg));
      }
    } else if ("method" in msg) {
      // Event — dispatch to listeners.
      const event = msg as CdpEvent;
      const listeners = this.eventListeners.get(event.method);
      if (listeners) {
        for (const fn of listeners) {
          try {
            fn(event.params ?? {});
          } catch {
            // Listener errors should not kill the connection.
          }
        }
      }
    } else {
      log("debug", "unexpected CDP message:", JSON.stringify(msg));
    }
  }
}

// ── helpers (reuse same pattern as index.ts) ─────────────────────────

function log(level: string, ...args: unknown[]): void {
  process.stderr.write(
    JSON.stringify({ type: level, ts: new Date().toISOString(), args }) + "\n"
  );
}
