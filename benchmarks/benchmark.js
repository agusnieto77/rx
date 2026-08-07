#!/usr/bin/env node
// xtweetsR benchmark harness
// Measures: sidecar startup, Lightpanda connection, local fixture navigation,
//           local structured extraction.
//
// Usage:
//   node benchmark.js                  # Run all benchmarks
//   node benchmark.js --warmup 3       # Warmup iterations
//   node benchmark.js --iterations 5
//
// Output: JSON to stdout, progress to stderr.
//
// Requirements: Node.js 18+, TypeScript sidecar compiled at inst/node/dist/index.js
//   Lightpanda is NOT required for the startup benchmark.
//   Connection/navigation/extraction benchmarks will report SKIP if
//   no CDP endpoint is available (no Lightpanda running).

import { spawn } from "node:child_process";
import { resolve, dirname } from "node:path";
import { createInterface } from "node:readline";
import { randomUUID } from "node:crypto";
import { createServer } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// ── CLI parsing ────────────────────────────────────────────────────────

function parseArgs() {
  const args = process.argv.slice(2);
  let warmup = 1;
  let iterations = 3;
  let sidecarPath = resolve(__dirname, "..", "inst", "node", "dist", "index.js");

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--warmup" && args[i + 1]) {
      warmup = parseInt(args[i + 1], 10);
      i++;
    } else if (args[i] === "--iterations" && args[i + 1]) {
      iterations = parseInt(args[i + 1], 10);
      i++;
    } else if (args[i] === "--sidecar" && args[i + 1]) {
      sidecarPath = resolve(args[i + 1]);
      i++;
    } else if (args[i] === "--help" || args[i] === "-h") {
      console.error("Usage: node benchmark.js [--warmup N] [--iterations N] [--sidecar PATH]");
      process.exit(0);
    }
  }

  return { warmup, iterations, sidecarPath };
}

// ── Types (JS comments for documentation) ─────────────────────────────
// BenchmarkResult: { name, iterations[], warmup, avg, min, max, p50, p95, status, error?, metadata? }
// BenchmarkSuite: { timestamp, nodeVersion, sidecarPath, sidecarVersion, results[] }

// ── Helpers ────────────────────────────────────────────────────────────

function ms(now) {
  return performance.now() - now;
}

function percentile(sorted, p) {
  if (sorted.length === 0) return 0;
  if (sorted.length === 1) return sorted[0];
  const idx = (p / 100) * (sorted.length - 1);
  const lower = Math.floor(idx);
  const upper = Math.ceil(idx);
  if (lower === upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (idx - lower);
}

function log(level, ...args) {
  const ts = new Date().toISOString();
  process.stderr.write(
    JSON.stringify({ type: level, ts, args: args.map(String) }) + "\n"
  );
}

// ── Sidecar process management ────────────────────────────────────────

function startSidecar(sidecarPath) {
  return new Promise((resolve, reject) => {
    const child = spawn("node", [sidecarPath], {
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...process.env, LPD_ENDPOINT: "ws://127.0.0.1:21111" },
    });

    const stderrLines = [];
    const rl = createInterface({ input: child.stderr });

    rl.on("line", (line) => {
      stderrLines.push(line);
      try {
        const parsed = JSON.parse(line);
        if (parsed.type === "startup" && parsed.version) {
          rl.close();
          resolve({ child, version: parsed.version });
        }
      } catch {
        // Not JSON, ignore.
      }
    });

    child.on("error", (err) => {
      rl.close();
      reject(err);
    });

    child.on("exit", (code) => {
      if (code !== 0) {
        rl.close();
        const lastLines = stderrLines.slice(-5).join("\n");
        reject(new Error(`Sidecar exited with code ${code}: ${lastLines}`));
      }
    });

    // Timeout: if no startup message after 10s, fail.
    setTimeout(() => {
      if (!child.killed) {
        child.kill();
        rl.close();
        reject(new Error("Sidecar startup timeout after 10s"));
      }
    }, 10_000);
  });
}

function stopSidecar(child) {
  if (child.killed) return Promise.resolve();
  return new Promise((resolve) => {
    try {
      child.kill("SIGTERM");
      const timeout = setTimeout(() => {
        try { child.kill("SIGKILL"); } catch {}
        resolve();
      }, 3000);
      child.on("exit", () => {
        clearTimeout(timeout);
        resolve();
      });
    } catch {
      resolve();
    }
  });
}

// ── JSONL protocol client ─────────────────────────────────────────────

function createClient(child, version) {
  let nextId = 0;
  const responses = new Map();
  const stdoutRl = createInterface({ input: child.stdout });

  stdoutRl.on("line", (line) => {
    try {
      const parsed = JSON.parse(line);
      if (parsed.id !== null && parsed.id !== undefined) {
        responses.set(String(parsed.id), {
          result: parsed.result,
          error: parsed.error,
        });
      }
    } catch {
      // Ignore malformed lines.
    }
  });

  return {
    child,
    version,
    requestCount: 0,
    responses,
    async request(method, params) {
      const id = nextId++;
      const req = JSON.stringify({ id, method, ...(params !== undefined ? { params } : {}) });
      child.stdin.write(req + "\n");

      // Wait for response with timeout.
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          const err = new Error(`Sidecar request timeout: ${method}`);
          responses.delete(String(id));
          reject(err);
        }, 30_000);

        const check = setInterval(() => {
          const resp = responses.get(String(id));
          if (resp) {
            clearInterval(check);
            clearTimeout(timeout);
            responses.delete(String(id));
            if (resp.error) {
              reject(new Error(JSON.stringify(resp.error)));
            } else {
              resolve(resp.result);
            }
          }
        }, 50);
      });
    },
    async close() {
      try {
        await this.request("close");
      } catch {
        // Ignore close errors.
      }
      await stopSidecar(this.child);
    },
  };
}

// ── Benchmark: Sidecar Startup ─────────────────────────────────────────

async function benchStartup(iterations, warmup, sidecarPath) {
  const times = [];

  // Warmup runs.
  for (let i = 0; i < warmup; i++) {
    const { child, version } = await startSidecar(sidecarPath);
    await stopSidecar(child);
    log("info", `startup warmup ${i + 1}/${warmup}`);
  }

  // Measured runs.
  for (let i = 0; i < iterations; i++) {
    const start = ms(0);
    try {
      const { child } = await startSidecar(sidecarPath);
      await stopSidecar(child);
      times.push(ms(start));
    } catch {
      times.push(-1); // Mark failure.
    }
  }

  const validTimes = times.filter((t) => t >= 0);
  const sorted = [...validTimes].sort((a, b) => a - b);

  if (sorted.length === 0) {
    return {
      name: "sidecar_startup",
      iterations: times,
      warmup,
      avg: 0, min: 0, max: 0, p50: 0, p95: 0,
      status: "fail",
      error: "All iterations failed",
    };
  }

  return {
    name: "sidecar_startup",
    iterations: times,
    warmup,
    avg: validTimes.reduce((a, b) => a + b, 0) / validTimes.length,
    min: sorted[0],
    max: sorted[sorted.length - 1],
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    status: "ok",
    metadata: { iterations: validTimes.length },
  };
}

// ── Benchmark: Lightpanda Connection ───────────────────────────────────

async function benchConnection(client, iterations, warmup, endpoint) {
  const times = [];

  // Warmup.
  for (let i = 0; i < warmup; i++) {
    try {
      const start = ms(0);
      await client.request("connect", { endpoint });
      times.push(ms(start));
      // Close and reconnect for next warmup.
      await client.request("close");
    } catch {
      times.push(-1);
    }
  }

  // Measured runs.
  for (let i = 0; i < iterations; i++) {
    try {
      const start = ms(0);
      await client.request("connect", { endpoint });
      times.push(ms(start));
      await client.request("close");
    } catch {
      times.push(-1);
    }
  }

  const validTimes = times.filter((t) => t >= 0);
  const sorted = [...validTimes].sort((a, b) => a - b);

  if (sorted.length === 0) {
    const allFailed = times.every((t) => t < 0);
    return {
      name: "lpd_connection",
      iterations: times,
      warmup,
      avg: 0, min: 0, max: 0, p50: 0, p95: 0,
      status: allFailed ? "skip" : "fail",
      error: allFailed ? "No CDP endpoint reachable — Lightpanda not running" : undefined,
      metadata: { endpoint: endpoint || process.env.LPD_ENDPOINT || "ws://127.0.0.1:21111" },
    };
  }

  return {
    name: "lpd_connection",
    iterations: times,
    warmup,
    avg: validTimes.reduce((a, b) => a + b, 0) / validTimes.length,
    min: sorted[0],
    max: sorted[sorted.length - 1],
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    status: "ok",
    metadata: { endpoint: endpoint || process.env.LPD_ENDPOINT || "ws://127.0.0.1:21111" },
  };
}

// ── Benchmark: Local Fixture Navigation ────────────────────────────────

async function benchNavigate(client, iterations, warmup, fixtureUrl) {
  const times = [];

  // Warmup.
  for (let i = 0; i < warmup; i++) {
    try {
      const start = ms(0);
      await client.request("navigate", { url: fixtureUrl });
      await client.request("navigate", { url: "data:text/html,<p>reset</p>" });
      times.push(ms(start));
    } catch {
      times.push(-1);
    }
  }

  // Measured runs.
  for (let i = 0; i < iterations; i++) {
    try {
      // Reset first.
      try { await client.request("navigate", { url: "data:text/html,<p>reset</p>" }); } catch {}
      const start = ms(0);
      await client.request("navigate", { url: fixtureUrl });
      times.push(ms(start));
    } catch {
      times.push(-1);
    }
  }

  const validTimes = times.filter((t) => t >= 0);
  const sorted = [...validTimes].sort((a, b) => a - b);

  if (sorted.length === 0) {
    return {
      name: "local_fixture_navigation",
      iterations: times,
      warmup,
      avg: 0, min: 0, max: 0, p50: 0, p95: 0,
      status: times.every((t) => t < 0) ? "skip" : "fail",
      error: times.every((t) => t < 0) ? "Navigation not available (CDP not connected)" : undefined,
      metadata: { url: fixtureUrl },
    };
  }

  return {
    name: "local_fixture_navigation",
    iterations: times,
    warmup,
    avg: validTimes.reduce((a, b) => a + b, 0) / validTimes.length,
    min: sorted[0],
    max: sorted[sorted.length - 1],
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    status: "ok",
    metadata: { url: fixtureUrl },
  };
}

// ── Benchmark: Local Structured Extraction ─────────────────────────────

async function benchExtraction(client, iterations, warmup, fixtureUrl) {
  const times = [];

  // Warmup.
  for (let i = 0; i < warmup; i++) {
    try {
      const start = ms(0);
      await client.request("networkCaptureEnable");
      await client.request("navigate", { url: fixtureUrl });
      // Wait briefly for network events.
      await new Promise((r) => setTimeout(r, 500));
      const events = await client.request("networkCaptureGet");
      await client.request("networkCaptureClear");
      times.push(ms(start));
    } catch {
      times.push(-1);
    }
  }

  // Measured runs.
  for (let i = 0; i < iterations; i++) {
    try {
      const start = ms(0);
      await client.request("networkCaptureEnable");
      // Reset page.
      try { await client.request("navigate", { url: "data:text/html,<p>reset</p>" }); } catch {}
      await client.request("navigate", { url: fixtureUrl });
      // Wait for XHR responses.
      await new Promise((r) => setTimeout(r, 500));
      const events = await client.request("networkCaptureGet");
      await client.request("networkCaptureClear");
      times.push(ms(start));
    } catch {
      times.push(-1);
    }
  }

  const validTimes = times.filter((t) => t >= 0);
  const sorted = [...validTimes].sort((a, b) => a - b);

  if (sorted.length === 0) {
    return {
      name: "local_structured_extraction",
      iterations: times,
      warmup,
      avg: 0, min: 0, max: 0, p50: 0, p95: 0,
      status: times.every((t) => t < 0) ? "skip" : "fail",
      error: times.every((t) => t < 0) ? "Extraction not available (CDP not connected)" : undefined,
      metadata: { url: fixtureUrl },
    };
  }

  return {
    name: "local_structured_extraction",
    iterations: times,
    warmup,
    avg: validTimes.reduce((a, b) => a + b, 0) / validTimes.length,
    min: sorted[0],
    max: sorted[sorted.length - 1],
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    status: "ok",
    metadata: { url: fixtureUrl },
  };
}

// ── Ping benchmark (lightweight health check) ──────────────────────────

async function benchPing(client, iterations, warmup) {
  const times = [];

  // Warmup.
  for (let i = 0; i < warmup; i++) {
    await client.request("ping");
  }

  // Measured runs.
  for (let i = 0; i < iterations; i++) {
    const start = ms(0);
    await client.request("ping");
    times.push(ms(start));
  }

  const sorted = [...times].sort((a, b) => a - b);
  return {
    name: "sidecar_ping",
    iterations: times,
    warmup,
    avg: times.reduce((a, b) => a + b, 0) / times.length,
    min: sorted[0],
    max: sorted[sorted.length - 1],
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    status: "ok",
  };
}

// ── Local test server ──────────────────────────────────────────────────

function startLocalServer(fixtureDir) {
  return new Promise((resolve) => {
    const PORT = 18765; // Arbitrary port.

    const server = createServer((req, res) => {
      let filePath = resolve(fixtureDir, req.url === "/" ? "index.html" : req.url.split("?")[0]);

      // Security: prevent path traversal.
      if (!filePath.startsWith(resolve(fixtureDir))) {
        res.writeHead(403);
        res.end("Forbidden");
        return;
      }

      if (!existsSync(filePath)) {
        res.writeHead(404);
        res.end("Not found");
        return;
      }

      const ext = filePath.split(".").pop();
      const types = {
        html: "text/html",
        json: "application/json",
        css: "text/css",
        js: "application/javascript",
      };

      res.writeHead(200, { "Content-Type": types[ext] || "application/octet-stream" });
      res.end(readFileSync(filePath));
    });

    server.listen(PORT, "127.0.0.1", () => {
      log("info", `Local fixture server on http://127.0.0.1:${PORT}`);
      resolve({
        url: `http://127.0.0.1:${PORT}`,
        port: PORT,
        stop: () => server.close(),
      });
    });
  });
}

// ── Main ───────────────────────────────────────────────────────────────

async function main() {
  const { warmup, iterations, sidecarPath } = parseArgs();

  log("info", "=== xtweetsR Benchmark Harness ===");
  log("info", `Node ${process.version}`);
  log("info", `Warmup: ${warmup}, Iterations: ${iterations}`);
  log("info", `Sidecar: ${sidecarPath}`);
  log("info", "");

  const suite = {
    timestamp: new Date().toISOString(),
    nodeVersion: process.version,
    sidecarPath,
    sidecarVersion: "0.1.0", // Will be updated after startup benchmark.
    results: [],
  };

  // ── 1. Sidecar Startup ────────────────────────────────────────────
  log("info", "--- Benchmark 1/4: Sidecar Startup ---");
  const startupResult = await benchStartup(iterations, warmup, sidecarPath);
  suite.results.push(startupResult);
  log("info", `  avg=${startupResult.avg.toFixed(1)}ms  p50=${startupResult.p50.toFixed(1)}ms  p95=${startupResult.p95.toFixed(1)}ms  status=${startupResult.status}`);

  // ── 2. Ping (lightweight, requires running sidecar) ──────────────
  log("info", "--- Benchmark 2/4: Sidecar Ping ---");
  let client = null;
  try {
    const { child, version } = await startSidecar(sidecarPath);
    client = createClient(child, version);
    suite.sidecarVersion = version;
    const pingResult = await benchPing(client, iterations, warmup);
    suite.results.push(pingResult);
    log("info", `  avg=${pingResult.avg.toFixed(1)}ms  p50=${pingResult.p50.toFixed(1)}ms  p95=${pingResult.p95.toFixed(1)}ms`);

    // ── 3. Lightpanda Connection ──────────────────────────────────
    log("info", "--- Benchmark 3/4: Lightpanda Connection ---");
    const lpdEndpoint = process.env.LPD_ENDPOINT || "ws://127.0.0.1:21111";
    const connResult = await benchConnection(client, iterations, warmup, lpdEndpoint);
    suite.results.push(connResult);
    log("info", `  status=${connResult.status}${connResult.error ? ` (${connResult.error})` : ""}`);

    if (connResult.status === "ok") {
      // ── 4. Local Fixture Navigation & Extraction ────────────────
      // Start a local server first.
      log("info", "Starting local fixture server...");
      const server = await startLocalServer(resolve(__dirname, "..", "inst", "tests", "fixtures"));
      const baseUrl = server.url;

      try {
        // Navigation.
        log("info", "--- Benchmark 4a/4: Local Fixture Navigation ---");
        const navResult = await benchNavigate(client, iterations, warmup, `${baseUrl}/dynamic-page.html`);
        suite.results.push(navResult);
        log("info", `  avg=${navResult.avg.toFixed(1)}ms  p50=${navResult.p50.toFixed(1)}ms  p95=${navResult.p95.toFixed(1)}ms  status=${navResult.status}`);

        // Extraction.
        log("info", "--- Benchmark 4b/4: Local Structured Extraction ---");
        const extResult = await benchExtraction(client, iterations, warmup, `${baseUrl}/dynamic-page.html`);
        suite.results.push(extResult);
        log("info", `  avg=${extResult.avg.toFixed(1)}ms  p50=${extResult.p50.toFixed(1)}ms  p95=${extResult.p95.toFixed(1)}ms  status=${extResult.status}`);
      } finally {
        server.stop();
      }
    }

    await client.close();
  } catch (err) {
    log("error", "Benchmark error:", err.message);
    if (client) {
      try { await client.close(); } catch {}
    }
  }

  // ── Output JSON ───────────────────────────────────────────────────
  console.log(JSON.stringify(suite, null, 2));

  // ── Summary ───────────────────────────────────────────────────────
  log("info", "");
  log("info", "=== Benchmark Summary ===");
  for (const r of suite.results) {
    const icon = r.status === "ok" ? "OK" : r.status === "skip" ? "SKIP" : "FAIL";
    if (r.status === "ok") {
      log("info", `[${icon}] ${r.name}: avg=${r.avg.toFixed(1)}ms  min=${r.min.toFixed(1)}ms  max=${r.max.toFixed(1)}ms  p50=${r.p50.toFixed(1)}ms  p95=${r.p95.toFixed(1)}ms`);
    } else {
      log("info", `[${icon}] ${r.name}${r.error ? `: ${r.error}` : ""}`);
    }
  }

  // Exit with non-zero if any benchmark failed (not skipped).
  const failures = suite.results.filter((r) => r.status === "fail");
  if (failures.length > 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  log("error", "Fatal error:", err.message);
  console.error(err);
  process.exit(1);
});
