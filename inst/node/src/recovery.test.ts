// Recovery tests for sidecar crash and backend disconnect scenarios.
// These tests verify that the sidecar handles unexpected failures gracefully.
//
// Covers:
// - Sidecar process restart after crash (SIGKILL)
// - Fresh sidecar starts in clean state
// - Backend disconnect is handled gracefully
// - Repeated connect/disconnect cycles are safe

import { describe, it, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SIDECAR_PATH = join(__dirname, "..", "dist", "index.js");

// ── helpers ──────────────────────────────────────────────────────────

interface SidecarInstance {
  proc: ReturnType<typeof spawn>;
}

/**
 * Spawn a sidecar process.
 * Resolves when the sidecar logs a "startup" message to stderr.
 */
async function spawnSidecar(): Promise<SidecarInstance> {
  const proc = spawn("node", [SIDECAR_PATH]);

  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => {
      proc.kill();
      reject(new Error("Sidecar startup timeout"));
    }, 5000);

    proc.stderr.on("data", (d: Buffer) => {
      const line = d.toString().trim();
      if (line) {
        try {
          const parsed = JSON.parse(line);
          if (parsed.type === "startup" || parsed.type === "ready") {
            clearTimeout(timeout);
            resolve();
          }
        } catch {
          // Not a JSON log line
        }
      }
    });

    proc.on("error", (err) => {
      clearTimeout(timeout);
      reject(err);
    });

    proc.on("exit", (code) => {
      if (code !== 0) {
        clearTimeout(timeout);
        reject(new Error(`Sidecar exited with code ${code}`));
      }
    });
  });

  return { proc };
}

/**
 * Send a JSONL request and return the parsed response.
 * Times out after 3 seconds.
 */
async function sendRequest(
  proc: ReturnType<typeof spawn>,
  request: unknown
): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error("Request timeout"));
    }, 3000);

    const stdout = proc.stdout;
    const stdin = proc.stdin;

    if (!stdout || !stdin) {
      clearTimeout(timeout);
      reject(new Error("proc stdout/stdin is null"));
      return;
    }

    const handler = (data: Buffer) => {
      const line = data.toString().trim();
      if (line) {
        try {
          const parsed = JSON.parse(line);
          clearTimeout(timeout);
          stdout.off("data", handler);
          resolve(parsed as Record<string, unknown>);
        } catch {
          // Not JSON, ignore
        }
      }
    };

    stdout.on("data", handler);
    stdin.write(JSON.stringify(request) + "\n");
  });
}

// ── Tests ────────────────────────────────────────────────────────────

describe("sidecar crash recovery", () => {
  // Test 1: Sidecar restarts cleanly after SIGKILL (simulating a crash)
  it("restarts cleanly after crash (SIGKILL)", async () => {
    // First instance: start, ping, verify, crash
    const { proc: proc1 } = await spawnSidecar();

    const resp1 = (await sendRequest(proc1, {
      id: "crash-test-1",
      method: "ping",
    })) as Record<string, unknown>;

    assert.strictEqual(
      (resp1.result as Record<string, unknown>)?.pong,
      true,
      "first instance should respond to ping"
    );

    // Simulate crash: SIGKILL the process
    proc1.kill("SIGKILL");
    await new Promise<void>((resolve) => {
      proc1.on("exit", resolve);
      setTimeout(resolve, 2000);
    });

    // Second instance: start fresh and verify clean state
    const { proc: proc2 } = await spawnSidecar();

    const resp2 = (await sendRequest(proc2, {
      id: "crash-test-2",
      method: "ping",
    })) as Record<string, unknown>;

    assert.strictEqual(
      (resp2.result as Record<string, unknown>)?.pong,
      true,
      "restarted instance should respond to ping"
    );

    proc2.kill();
  });

  // Test 2: Fresh sidecar starts in a clean/disconnected state
  it("starts in a clean disconnected state", async () => {
    const { proc } = await spawnSidecar();

    // Navigate should fail because no connection is active
    const resp = (await sendRequest(proc, {
      id: "clean-state-test",
      method: "navigate",
      params: { url: "https://x.com" },
    })) as Record<string, unknown>;

    assert.ok(resp.error, "navigate should fail on fresh sidecar");
    assert.strictEqual(
      (resp.error as Record<string, unknown>)?.code,
      "PAGE_LOAD_ERROR",
      "error code should be PAGE_LOAD_ERROR"
    );

    proc.kill();
  });

  // Test 3: Multiple crash-restart cycles are safe
  it("survives multiple crash-restart cycles", async () => {
    for (let i = 0; i < 3; i++) {
      const { proc } = await spawnSidecar();

      const resp = (await sendRequest(proc, {
        id: `cycle-${i}`,
        method: "ping",
      })) as Record<string, unknown>;

      assert.strictEqual(
        (resp.result as Record<string, unknown>)?.pong,
        true,
        `cycle ${i}: should respond to ping`
      );

      // Crash
      proc.kill("SIGKILL");
      await new Promise<void>((resolve) => {
        proc.on("exit", resolve);
        setTimeout(resolve, 2000);
      });
    }
  });
});

describe("backend disconnect handling", () => {
  // Test 4: connect to unreachable endpoint returns structured error
  it("returns LPD_CONNECTION_ERROR for unreachable CDP endpoint", async () => {
    const { proc } = await spawnSidecar();

    const resp = (await sendRequest(proc, {
      id: "disconnect-test",
      method: "connect",
      params: {
        endpoint: "ws://127.0.0.1:1", // unreachable
        token: null,
      },
    })) as Record<string, unknown>;

    assert.ok(resp.error, "connect to unreachable endpoint should error");
    assert.strictEqual(
      (resp.error as Record<string, unknown>)?.code,
      "LPD_CONNECTION_ERROR",
      "should return LPD_CONNECTION_ERROR"
    );

    proc.kill();
  });

  // Test 5: Operations after failed connect return appropriate errors
  it("returns errors for operations after failed connect", async () => {
    const { proc } = await spawnSidecar();

    // Failed connect first
    await sendRequest(proc, {
      id: "fail-connect",
      method: "connect",
      params: {
        endpoint: "ws://127.0.0.1:1",
        token: null,
      },
    });

    // Now try navigate — should fail with PAGE_LOAD_ERROR
    const navigateResp = (await sendRequest(proc, {
      id: "after-fail-nav",
      method: "navigate",
      params: { url: "https://x.com" },
    })) as Record<string, unknown>;

    assert.ok(
      navigateResp.error,
      "navigate after failed connect should error"
    );
    assert.strictEqual(
      (navigateResp.error as Record<string, unknown>)?.code,
      "PAGE_LOAD_ERROR",
      "should return PAGE_LOAD_ERROR"
    );

    proc.kill();
  });

  // Test 6: Double close is safe after connect failure
  it("double close after failed connect is safe", async () => {
    const { proc } = await spawnSidecar();

    // Failed connect
    await sendRequest(proc, {
      id: "fail",
      method: "connect",
      params: { endpoint: "ws://127.0.0.1:1", token: null },
    });

    // Close twice — should not crash
    const close1 = (await sendRequest(proc, {
      id: "close-1",
      method: "close",
    })) as Record<string, unknown>;

    const close2 = (await sendRequest(proc, {
      id: "close-2",
      method: "close",
    })) as Record<string, unknown>;

    // Both should succeed (not error)
    assert.ok(close1.result, "first close should not error");
    assert.ok(close2.result, "second close should not error");

    proc.kill();
  });
});
