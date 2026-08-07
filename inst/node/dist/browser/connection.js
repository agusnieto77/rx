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
// ── CdpConnection implementation ─────────────────────────────────────
export class DefaultCdpConnection {
    ws = null;
    nextId = 1;
    pending = new Map();
    eventListeners = new Map();
    _isConnected = false;
    commandTimeoutMs;
    constructor(options = {}) {
        this.commandTimeoutMs = options.commandTimeoutMs ?? 15_000;
    }
    get isConnected() {
        return this._isConnected && this.ws !== null && this.ws.readyState === WebSocket.OPEN;
    }
    // -- connect ----------------------------------------------------------
    async connect(endpointUrl) {
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
                ws.on("message", (data) => {
                    this.handleMessage(data.toString());
                });
                ws.on("error", (err) => {
                    // Only reject if we haven't already resolved.
                    if (this.ws !== null && !this._isConnected) {
                        reject(new Error(`CDP WebSocket error: ${err.message}`));
                    }
                });
                ws.on("close", (code, reason) => {
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
            }
            catch (err) {
                reject(new Error(`Failed to create CDP WebSocket: ${err.message}`));
            }
        });
    }
    // -- sendCommand ------------------------------------------------------
    async sendCommand(method, params) {
        if (!this.isConnected) {
            throw new Error(`CDP not connected — cannot send ${method}`);
        }
        const id = this.nextId++;
        const payload = { id, method };
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
            }
            else {
                clearTimeout(timer);
                this.pending.delete(id);
                reject(new Error("CDP WebSocket not ready"));
            }
        });
    }
    // -- events -----------------------------------------------------------
    on(event, listener) {
        if (!this.eventListeners.has(event)) {
            this.eventListeners.set(event, new Set());
        }
        this.eventListeners.get(event).add(listener);
    }
    removeListener(event, listener) {
        const set = this.eventListeners.get(event);
        if (set) {
            set.delete(listener);
        }
    }
    // -- close ------------------------------------------------------------
    close() {
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
    handleMessage(raw) {
        let msg;
        try {
            msg = JSON.parse(raw);
        }
        catch {
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
                }
                else {
                    pending.resolve(msg.result ?? {});
                }
            }
            else {
                log("debug", "unexpected CDP response id=", id, JSON.stringify(msg));
            }
        }
        else if ("method" in msg) {
            // Event — dispatch to listeners.
            const event = msg;
            const listeners = this.eventListeners.get(event.method);
            if (listeners) {
                for (const fn of listeners) {
                    try {
                        fn(event.params ?? {});
                    }
                    catch {
                        // Listener errors should not kill the connection.
                    }
                }
            }
        }
        else {
            log("debug", "unexpected CDP message:", JSON.stringify(msg));
        }
    }
}
// ── helpers (reuse same pattern as index.ts) ─────────────────────────
function log(level, ...args) {
    process.stderr.write(JSON.stringify({ type: level, ts: new Date().toISOString(), args }) + "\n");
}
//# sourceMappingURL=connection.js.map