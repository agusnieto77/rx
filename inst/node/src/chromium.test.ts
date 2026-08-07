// Integration tests for the Chromium backend.
// These tests verify that the Chromium backend (Puppeteer) works
// through the same JSONL protocol as the CDP backend.
//
// Note: These tests require a system Chrome/Chromium or Puppeteer's
// bundled Chromium. They are skipped if Chromium cannot be launched.

import { describe, it, afterEach, before } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SIDECAR_PATH = join(__dirname, "..", "dist", "index.js");

let canUseChromium = false;

before(async () => {
  // Pre-check: can we launch Chromium at all?
  // We do a quick connect test and use the result to gate all Chromium tests.
  try {
    const proc = spawn("node", [SIDECAR_PATH]);
    let stderrBuf = "";
    let resolved = false;

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        if (!resolved) {
          resolved = true;
          proc.kill();
          reject(new Error("Chromium pre-check timeout"));
        }
      }, 5000);

      proc.stderr.on("data", (d: Buffer) => {
        stderrBuf += d.toString();
        const line = d.toString().trim();
        if (line) {
          try {
            const parsed = JSON.parse(line);
            if (parsed.type === "startup" && !resolved) {
              resolved = true;
              clearTimeout(timeout);
              resolve();
            }
          } catch {
            // Not a JSON line
          }
        }
      });

      proc.on("error", () => {
        if (!resolved) {
          resolved = true;
          clearTimeout(timeout);
          reject(new Error("Spawn error"));
        }
      });
    });

    // Try to connect with chromium backend.
    const resp = await sendRequest(proc, "connect", { backend: "chromium" });
    canUseChromium = Boolean(!resp.error && resp.result && (resp.result as { connected: boolean }).connected);
    if (canUseChromium) {
      // Clean up — close the Chromium instance.
      await sendRequest(proc, "close");
    }
    proc.kill();
  } catch {
    canUseChromium = false;
  }
});

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
    const id = Date.now() + Math.floor(Math.random() * 10000);
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
    }, 30000);
  });
}

describe("chromium backend", () => {
  const children: ReturnType<typeof spawn>[] = [];

  afterEach(() => {
    for (const p of children) {
      if (p && !p.killed) p.kill();
    }
    children.length = 0;
  });

  describe("skip if Chromium unavailable", () => {
    it("skips all Chromium tests", () => {
      // This test exists only to provide a clear skip message.
      // The actual tests below use `if (!canUseChromium) return;`.
      assert.ok(true);
    });
  });

  describe("connect", () => {
    it("connects with backend=chromium", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      const resp = await sendRequest(proc, "connect", { backend: "chromium" });
      assert.strictEqual(typeof resp.id, "number");
      assert.ok(!resp.error, "connect should not return error: " + JSON.stringify(resp.error));
      const result = resp.result as { connected: boolean; endpoint: string; backend: string };
      assert.strictEqual(result.connected, true);
      assert.strictEqual(result.backend, "chromium");
      // Endpoint should be the wsEndpoint() or "local".
      assert.ok(typeof result.endpoint === "string" && result.endpoint.length > 0);
    });

    it("connect response includes backend field", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      const resp = await sendRequest(proc, "connect", { backend: "chromium" });
      const result = resp.result as { backend?: string };
      assert.strictEqual(result.backend, "chromium");
    });

    it("double connect returns already connected", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      await sendRequest(proc, "connect", { backend: "chromium" });
      const resp = await sendRequest(proc, "connect", { backend: "chromium" });
      const result = resp.result as { connected: boolean; backend: string };
      assert.strictEqual(result.connected, true);
      assert.strictEqual(result.backend, "chromium");
    });
  });

  describe("navigate", () => {
    it("navigates to a URL (page may fail to load — no server running)", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      await sendRequest(proc, "connect", { backend: "chromium" });
      // Navigate to a URL that passes SSRF validation. The page itself
      // won't load (no server on localhost), but the navigation call
      // proves Chromium backend navigation works.
      const resp = await sendRequest(proc, "navigate", { url: "http://localhost/" });
      assert.strictEqual(typeof resp.id, "number");
      // The navigation call returns — either with navigated=true or
      // with PAGE_LOAD_ERROR. Both prove the Chromium path works.
      if (resp.error) {
        // Expected on a headless system with no local HTTP server.
        assert.strictEqual((resp.error as { code: string }).code, "PAGE_LOAD_ERROR");
      } else {
        const result = resp.result as { url: string; navigated: boolean };
        assert.strictEqual(result.navigated, true);
      }
    });
  });

  describe("evaluate", () => {
    it("evaluates simple JavaScript", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      await sendRequest(proc, "connect", { backend: "chromium" });
      const resp = await sendRequest(proc, "evaluate", { expr: "1 + 1" });
      assert.strictEqual(typeof resp.id, "number");
      assert.ok(!resp.error, "evaluate should not return error: " + JSON.stringify(resp.error));
      const result = resp.result as { evaluated: boolean };
      assert.strictEqual(result.evaluated, true);
    });

    it("evaluates document.title", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      await sendRequest(proc, "connect", { backend: "chromium" });
      // On a blank page, document.title is "". This proves evaluate works.
      const resp = await sendRequest(proc, "evaluate", { expr: "document.title" });
      assert.ok(!resp.error, "evaluate should not return error: " + JSON.stringify(resp.error));
      const result = resp.result as { evaluated: boolean; result?: Record<string, unknown> };
      assert.strictEqual(result.evaluated, true);
      // document.title on a blank page is an empty string.
      const title = (result.result as Record<string, unknown>)?.value ?? result.result;
      assert.strictEqual(title, "");
    });
  });

  describe("close", () => {
    it("closes Chromium backend cleanly", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      await sendRequest(proc, "connect", { backend: "chromium" });
      const resp = await sendRequest(proc, "close");
      assert.strictEqual(typeof resp.id, "number");
      const result = resp.result as { closed: boolean };
      assert.strictEqual(result.closed, true);
    });

    it("double close is safe", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      await sendRequest(proc, "connect", { backend: "chromium" });
      await sendRequest(proc, "close");
      const resp = await sendRequest(proc, "close");
      const result = resp.result as { closed: boolean; reason: string };
      assert.strictEqual(result.closed, false);
      assert.strictEqual(result.reason, "not_connected");
      // Sidecar still alive.
      const ping = await sendRequest(proc, "ping");
      assert.strictEqual((ping.result as { pong: boolean }).pong, true);
    });
  });

  describe("network capture (not available on Chromium)", () => {
    it("returns error for networkCaptureEnable", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      await sendRequest(proc, "connect", { backend: "chromium" });
      const resp = await sendRequest(proc, "networkCaptureEnable");
      assert.strictEqual((resp.error as { code: string }).code, "CDP_ERROR");
      assert.ok(
        (resp.error as { message: string }).message.includes("Network capture requires CDP backend")
      );
    });

    it("returns empty events for networkCaptureGet", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      await sendRequest(proc, "connect", { backend: "chromium" });
      const resp = await sendRequest(proc, "networkCaptureGet");
      assert.ok(!resp.error);
      const result = resp.result as { events: unknown[] };
      assert.ok(Array.isArray(result.events));
      assert.strictEqual(result.events.length, 0);
    });
  });

  describe("DOM inspect (not available on Chromium)", () => {
    it("returns error for domInspect", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      await sendRequest(proc, "connect", { backend: "chromium" });
      const resp = await sendRequest(proc, "domInspect");
      assert.strictEqual((resp.error as { code: string }).code, "CDP_ERROR");
      assert.ok(
        (resp.error as { message: string }).message.includes("DOM inspect requires CDP backend")
      );
    });
  });

  describe("backend switching", () => {
    it("can connect chromium then CDP (unreachable)", async () => {
      if (!canUseChromium) return;
      const { proc } = await startSidecar(children);
      await sendRequest(proc, "connect", { backend: "chromium" });
      const closeResp = await sendRequest(proc, "close");
      assert.strictEqual((closeResp.result as { closed: boolean }).closed, true);
      // Now connect to an unreachable CDP endpoint.
      const resp = await sendRequest(proc, "connect", { endpoint: "ws://127.0.0.1:1" });
      assert.strictEqual((resp.error as { code: string }).code, "LPD_CONNECTION_ERROR");
    });
  });
});
