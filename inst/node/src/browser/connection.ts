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
  private commandTimeoutMs = 15_000;

  constructor() {
    // No options parameter — the timeout is a fixed default.
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
      try {
        const ws = new WebSocket(endpointUrl);
        this.ws = ws;

        const timeout = setTimeout(() => {
          if (this.ws !== null) {
            this.ws.close();
          }
          reject(new Error(`CDP connection timeout after 30s to ${endpointUrl}`));
        }, 30_000);

        ws.on("open", () => {
          clearTimeout(timeout);
          this._isConnected = true;
          log("info", "CDP connected to", endpointUrl);
          resolve();
        });

        ws.on("message", (data: WebSocket.Data) => {
          this.handleMessage(data.toString());
        });

        ws.on("error", (err: Error) => {
          // Only reject if we haven't already resolved.
          if (this.ws !== null && !this._isConnected) {
            reject(new Error(`CDP WebSocket error: ${err.message}`));
          }
        });

        ws.on("close", (code: number, reason: Buffer) => {
          this._isConnected = false;
          const msg = `CDP connection closed (code=${code}, reason=${reason.toString()})`;
          log("warn", msg);
          // Reject all pending commands.
          for (const [id, { reject, timer }] of this.pending) {
            clearTimeout(timer);
            reject(new Error(msg));
          }
          this.pending.clear();
        });
      } catch (err) {
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
      // Reject all pending commands.
      for (const [, { reject, timer }] of this.pending) {
        clearTimeout(timer);
        reject(new Error("Connection closed"));
      }
      this.pending.clear();
      this.ws.close();
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
