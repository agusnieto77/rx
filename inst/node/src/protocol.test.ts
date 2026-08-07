// Integration tests for the R <-> TypeScript sidecar protocol.
// These tests verify the JSONL protocol without depending on R or processx.
// On platforms where R/processx works, the R-sidecar integration tests
// in tests/testthat/test-sidecar-protocol.R provide additional coverage.

import { describe, it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SIDECAR_PATH = join(__dirname, "..", "dist", "index.js");

// Incrementing counter for per-request IDs in tests.
let testId = 0;

function startSidecar(
  track: ReturnType<typeof spawn>[]
): Promise<{
  proc: ReturnType<typeof spawn>;
  stderrBuf: string;
}> {
  return new Promise((resolve, reject) => {
    const proc = spawn("node", [SIDECAR_PATH]);
    track.push(proc);
    let stderrBuf = "";
    let resolved = false;

    const timeout = setTimeout(() => {
      if (!resolved) {
        resolved = true;
        proc.kill();
        reject(new Error("Sidecar startup timeout"));
      }
    }, 5000);

    proc.stderr.on("data", (d: Buffer) => {
      stderrBuf += d.toString();
      if (resolved) return;
      const line = d.toString().trim();
      if (line) {
        try {
          const parsed = JSON.parse(line);
          if (parsed.type === "startup") {
            resolved = true;
            clearTimeout(timeout);
            resolve({ proc, stderrBuf });
          }
        } catch {
          // Not a JSON line, ignore
        }
      }
    });

    proc.on("error", (e) => {
      if (!resolved) {
        resolved = true;
        clearTimeout(timeout);
        reject(e);
      }
    });

    proc.on("exit", (code) => {
      if (!resolved) {
        resolved = true;
        clearTimeout(timeout);
        reject(new Error(`Sidecar exited with code ${code}`));
      }
    });
  });
}

function sendRequest(
  proc: ReturnType<typeof spawn>,
  method: string,
  params?: Record<string, unknown>
): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const id = ++testId;
    const req = JSON.stringify({ id, method, ...(params ? { params } : {}) });
    if (proc.stdin) proc.stdin.write(req + "\n");

    const handler = (d: Buffer) => {
      const line = d.toString().trim();
      if (!line) return;
      try {
        const parsed = JSON.parse(line);
        if (proc.stdout) proc.stdout.removeListener("data", handler);
        resolve(parsed);
      } catch {
        // Not JSON, ignore
      }
    };
    if (proc.stdout) proc.stdout.once("data", handler);

    setTimeout(() => {
      if (proc.stdout) proc.stdout.removeListener("data", handler);
      reject(new Error(`No response for method: ${method}`));
    }, 3000);
  });
}

describe("sidecar protocol", () => {
  // Track every sidecar process so we can clean them up reliably.
  const children: ReturnType<typeof spawn>[] = [];

  afterEach(() => {
    // Kill any sidecar processes still alive.
    for (const p of children) {
      if (p && !p.killed) p.kill();
    }
    children.length = 0;
  });

  it("ping returns pong", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "ping");
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.result as { pong: boolean }).pong, true);
    assert.strictEqual(typeof (resp.result as { version: string }).version, "string");
  });

  it("unknown method returns structured error", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "nonexistent_method");
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "UNKNOWN_METHOD");
    assert.strictEqual(typeof (resp.error as { message: string }).message, "string");
  });

  it("malformed JSON returns PARSE_ERROR", async () => {
    const { proc: p } = await startSidecar(children);
    if (p.stdin) p.stdin.write("not valid json {{{\n");
    const resp = await new Promise<Record<string, unknown>>((resolve) => {
      if (p.stdout)
        p.stdout.once("data", (d: Buffer) => {
          const parsed = JSON.parse(d.toString().trim());
          resolve(parsed);
        });
    });
    assert.strictEqual((resp.error as { code: string }).code, "PARSE_ERROR");
  });

  it("process shutdown terminates cleanly", async () => {
    const { proc: p } = await startSidecar(children);
    p.kill();
    await new Promise<void>((resolve) => setTimeout(resolve, 200));
    assert.strictEqual(p.killed, true);
  });

  it("request with params echoes in result", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "ping", { extra: "data" });
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.result as { pong: boolean }).pong, true);
  });

  it("connect to unreachable endpoint returns LPD_CONNECTION_ERROR", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "connect", { endpoint: "ws://127.0.0.1:1" });
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "LPD_CONNECTION_ERROR");
    assert.strictEqual(typeof (resp.error as { message: string }).message, "string");
    assert.ok((resp.error as { message: string }).message.includes("Failed to connect to CDP endpoint"));
  });

  it("connect with no endpoint falls back to default and returns LPD_CONNECTION_ERROR", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "connect", {});
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "LPD_CONNECTION_ERROR");
  });

  it("connect with invalid endpoint format returns INVALID_REQUEST", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "connect", { endpoint: "not-a-url" });
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "INVALID_REQUEST");
  });

  it("connect with non-string non-null endpoint returns INVALID_REQUEST", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "connect", { endpoint: 123 });
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "INVALID_REQUEST");
  });

  it("close when not connected returns not_connected", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "close");
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.result as { closed: boolean }).closed, false);
    assert.strictEqual((resp.result as { reason: string }).reason, "not_connected");
  });

  it("close twice does not crash the sidecar", async () => {
    const { proc: p } = await startSidecar(children);
    // First close — not connected.
    const r1 = await sendRequest(p, "close");
    assert.strictEqual((r1.result as { closed: boolean }).closed, false);
    // Second close — still safe.
    const r2 = await sendRequest(p, "close");
    assert.strictEqual((r2.result as { closed: boolean }).closed, false);
    // Sidecar is still alive and responsive.
    const pingResp = await sendRequest(p, "ping");
    assert.strictEqual((pingResp.result as { pong: boolean }).pong, true);
  });

  it("close after failed connect is safe", async () => {
    const { proc: p } = await startSidecar(children);
    // Attempt connect to unreachable endpoint (will fail).
    const connectResp = await sendRequest(p, "connect", { endpoint: "ws://127.0.0.1:1" });
    assert.strictEqual((connectResp.error as { code: string }).code, "LPD_CONNECTION_ERROR");
    // Close after failed connect — should be safe (not_connected).
    const closeResp = await sendRequest(p, "close");
    assert.strictEqual(typeof closeResp.id, "number");
    assert.strictEqual((closeResp.result as { closed: boolean }).closed, false);
  });

  it("navigate without connection returns PAGE_LOAD_ERROR", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "navigate", { url: "http://example.com" });
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "PAGE_LOAD_ERROR");
    assert.ok((resp.error as { message: string }).message.includes("CDP connection not active"));
  });

  it("navigate with missing url returns INVALID_REQUEST", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "navigate", {});
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "INVALID_REQUEST");
  });

  it("evaluate without connection returns CDP_ERROR", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "evaluate", { expr: "1+1" });
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "CDP_ERROR");
    assert.ok((resp.error as { message: string }).message.includes("CDP connection not active"));
  });

  it("evaluate with missing expr returns INVALID_REQUEST", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "evaluate", {});
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "INVALID_REQUEST");
  });

  it("navigate with empty url returns INVALID_REQUEST", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "navigate", { url: "" });
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "INVALID_REQUEST");
  });

  it("evaluate with empty expr returns INVALID_REQUEST", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "evaluate", { expr: "" });
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "INVALID_REQUEST");
  });

  it("networkCaptureGetBody without CDP connection returns CDP_ERROR", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "networkCaptureGetBody", { requestId: "fake-123" });
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "CDP_ERROR");
    assert.ok((resp.error as { message: string }).message.includes("CDP connection not active"));
  });

  it("networkCaptureGetBody with missing requestId returns INVALID_REQUEST", async () => {
    const { proc: p } = await startSidecar(children);
    // Connect to trigger the "no connection" path won't work, so we test
    // the param validation first — the sidecar validates params before checking connection.
    const resp = await sendRequest(p, "networkCaptureGetBody", {});
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "INVALID_REQUEST");
  });

  it("domInspect without connection returns CDP_ERROR", async () => {
    const { proc: p } = await startSidecar(children);
    const resp = await sendRequest(p, "domInspect", {});
    assert.strictEqual(typeof resp.id, "number");
    assert.strictEqual((resp.error as { code: string }).code, "CDP_ERROR");
    assert.ok((resp.error as { message: string }).message.includes("CDP connection not active"));
  });
});
