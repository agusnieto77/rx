// Integration tests for the R <-> TypeScript sidecar protocol.
// These tests verify the JSONL protocol without depending on R or processx.
// On platforms where R/processx works, the R-sidecar integration tests
// in tests/testthat/test-sidecar-protocol.R provide additional coverage.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SIDECAR_PATH = join(__dirname, "..", "dist", "index.js");

function startSidecar(): Promise<{
  proc: ReturnType<typeof spawn>;
  stderrBuf: string;
}> {
  return new Promise((resolve, reject) => {
    const proc = spawn("node", [SIDECAR_PATH]);
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
    const id = method;
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
  let proc: ReturnType<typeof spawn> | null = null;

  process.on("exit", () => {
    // Best-effort cleanup on process exit.
    if (proc && !proc.killed) proc.kill();
  });

  it("ping returns pong", async () => {
    const { proc: p } = await startSidecar();
    proc = p;
    const resp = await sendRequest(p, "ping");
    assert.strictEqual(resp.id, "ping");
    assert.strictEqual((resp.result as { pong: boolean }).pong, true);
    assert.strictEqual(typeof (resp.result as { version: string }).version, "string");
  });

  it("unknown method returns structured error", async () => {
    const { proc: p } = await startSidecar();
    const resp = await sendRequest(p, "nonexistent_method");
    assert.strictEqual(resp.id, "nonexistent_method");
    assert.strictEqual((resp.error as { code: string }).code, "UNKNOWN_METHOD");
    assert.strictEqual(typeof (resp.error as { message: string }).message, "string");
  });

  it("malformed JSON returns PARSE_ERROR", async () => {
    const { proc: p } = await startSidecar();
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
    const { proc: p } = await startSidecar();
    proc = p;
    p.kill();
    await new Promise<void>((resolve) => setTimeout(resolve, 200));
    assert.strictEqual(p.killed, true);
  });

  it("request with params echoes in result", async () => {
    const { proc: p } = await startSidecar();
    const resp = await sendRequest(p, "ping", { extra: "data" });
    assert.strictEqual(resp.id, "ping");
    assert.strictEqual((resp.result as { pong: boolean }).pong, true);
  });

  it("connect to unreachable endpoint returns LPD_CONNECTION_ERROR", async () => {
    const { proc: p } = await startSidecar();
    const resp = await sendRequest(p, "connect", { endpoint: "ws://127.0.0.1:1" });
    assert.strictEqual(resp.id, "connect");
    assert.strictEqual((resp.error as { code: string }).code, "LPD_CONNECTION_ERROR");
    assert.strictEqual(typeof (resp.error as { message: string }).message, "string");
    assert.ok((resp.error as { message: string }).message.includes("Failed to connect to CDP endpoint"));
  });

  it("connect with no endpoint falls back to default and returns LPD_CONNECTION_ERROR", async () => {
    const { proc: p } = await startSidecar();
    const resp = await sendRequest(p, "connect", {});
    assert.strictEqual(resp.id, "connect");
    assert.strictEqual((resp.error as { code: string }).code, "LPD_CONNECTION_ERROR");
  });

  it("connect with invalid endpoint format returns LPD_CONNECTION_ERROR", async () => {
    const { proc: p } = await startSidecar();
    const resp = await sendRequest(p, "connect", { endpoint: "not-a-url" });
    assert.strictEqual(resp.id, "connect");
    assert.strictEqual((resp.error as { code: string }).code, "LPD_CONNECTION_ERROR");
  });

  it("close when not connected returns not_connected", async () => {
    const { proc: p } = await startSidecar();
    const resp = await sendRequest(p, "close");
    assert.strictEqual(resp.id, "close");
    assert.strictEqual((resp.result as { closed: boolean }).closed, false);
    assert.strictEqual((resp.result as { reason: string }).reason, "not_connected");
  });

  it("close twice does not crash the sidecar", async () => {
    const { proc: p } = await startSidecar();
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
    const { proc: p } = await startSidecar();
    // Attempt connect to unreachable endpoint (will fail).
    const connectResp = await sendRequest(p, "connect", { endpoint: "ws://127.0.0.1:1" });
    assert.strictEqual((connectResp.error as { code: string }).code, "LPD_CONNECTION_ERROR");
    // Close after failed connect — should be safe (not_connected).
    const closeResp = await sendRequest(p, "close");
    assert.strictEqual(closeResp.id, "close");
    assert.strictEqual((closeResp.result as { closed: boolean }).closed, false);
  });
});
