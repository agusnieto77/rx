#!/usr/bin/env node
// xtweetsR — Backend comparison: Lightpanda (CDP) vs Chromium
//
// Runs the same benchmark suite on both backends and produces a
// side-by-side comparison. Measures:
//   - startup (sidecar process spawn only; backend launch excluded)
//   - navigation to local fixture
//   - JavaScript evaluation (structured extraction proxy)
//
// Network capture is NOT compared because the Chromium backend
// does not implement it (by design in this spike).
//
// Usage:
//   node compare-backends.js [--warmup N] [--iterations N] [--sidecar PATH]
//
// Output: JSON to stdout, progress to stderr.
//
// Requirements: Node.js 18+, TypeScript sidecar compiled at inst/node/dist/index.js

import { spawn } from "node:child_process";
import { resolve, dirname } from "node:path";
import { createInterface } from "node:readline";
import { createServer } from "node:http";
import { readFileSync, existsSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// ── CLI parsing ────────────────────────────────────────────────────────

function parseArgs() {
  const args = process.argv.slice(2);
  let warmup = 1;
  let iterations = 5;
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
      console.error(
        "Usage: node compare-backends.js [--warmup N] [--iterations N] [--sidecar PATH]"
      );
      process.exit(0);
    }
  }

  return { warmup, iterations, sidecarPath };
}

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
      env: { ...process.env },
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

// ── Benchmark: Navigation ──────────────────────────────────────────────

async function benchNavigate(client, iterations, warmup, fixtureUrl) {
  const times = [];
  const errors = [];

  // Warmup.
  for (let i = 0; i < warmup; i++) {
    try {
      const start = ms(0);
      await client.request("navigate", { url: fixtureUrl });
      times.push(ms(start));
      // Reset.
      try { await client.request("navigate", { url: "data:text/html,<p>reset</p>" }); } catch {}
    } catch (err) {
      times.push(-1);
      errors.push(`warmup ${i + 1}: ${err.message}`);
    }
  }

  // Measured runs.
  for (let i = 0; i < iterations; i++) {
    try {
      try { await client.request("navigate", { url: "data:text/html,<p>reset</p>" }); } catch {}
      const start = ms(0);
      await client.request("navigate", { url: fixtureUrl });
      times.push(ms(start));
    } catch (err) {
      times.push(-1);
      errors.push(`iter ${i + 1}: ${err.message}`);
    }
  }

  const validTimes = times.filter((t) => t >= 0);
  const sorted = [...validTimes].sort((a, b) => a - b);

  if (sorted.length === 0) {
    return {
      name: "navigation",
      status: "fail",
      avg: 0, min: 0, max: 0, p50: 0, p95: 0,
      errors: errors.slice(0, 3),
      metadata: { url: fixtureUrl, validRuns: 0, totalRuns: times.length },
    };
  }

  return {
    name: "navigation",
    status: "ok",
    avg: validTimes.reduce((a, b) => a + b, 0) / validTimes.length,
    min: sorted[0],
    max: sorted[sorted.length - 1],
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    errors: errors.slice(0, 3),
    metadata: { url: fixtureUrl, validRuns: validTimes.length, totalRuns: times.length },
  };
}

// ── Benchmark: JavaScript Evaluation (structured extraction proxy) ────

async function benchEvaluate(client, iterations, warmup, fixtureUrl) {
  const times = [];
  const errors = [];
  const results = [];

  // Warmup: navigate to the fixture first.
  try {
    await client.request("navigate", { url: fixtureUrl });
  } catch {
    errors.push("warmup: navigation failed");
  }

  for (let i = 0; i < warmup; i++) {
    try {
      await new Promise((r) => setTimeout(r, 1500));
      const start = ms(0);
      const result = await client.request("evaluate", {
        expr: "({ url: location.href, title: document.title, postCount: document.querySelectorAll('.post').length, bodyLength: document.body.innerHTML.length })",
      });
      log("debug", `  warmup eval result: ${JSON.stringify(result).slice(0, 200)}`);
      times.push(ms(start));
      results.push(result);
    } catch (err) {
      times.push(-1);
      errors.push(`warmup ${i + 1}: ${err.message}`);
    }
  }

  // Measured runs.
  for (let i = 0; i < iterations; i++) {
    try {
      // Use cache-busting query param to force reload.
      const reloadUrl = fixtureUrl + "?_t=" + Date.now();
      const navResult = await client.request("navigate", { url: reloadUrl });
      // Wait for dynamic content (setTimeout is 50ms + generous buffer).
      await new Promise((r) => setTimeout(r, 1500));
      const start = ms(0);
      // Evaluate page state: URL, title, content, and dynamic elements.
      const result = await client.request("evaluate", {
        expr: "({ url: location.href, title: document.title, postCount: document.querySelectorAll('.post').length, postIds: Array.from(document.querySelectorAll('.post')).map(el => el.getAttribute('data-post-id')), bodyLength: document.body.innerHTML.length })",
      });
      times.push(ms(start));
      results.push(result);
    } catch (err) {
      times.push(-1);
      errors.push(`iter ${i + 1}: ${err.message}`);
    }
  }

  const validTimes = times.filter((t) => t >= 0);
  const sorted = [...validTimes].sort((a, b) => a - b);

  if (sorted.length === 0) {
    return {
      name: "javascript_evaluation",
      status: "fail",
      avg: 0, min: 0, max: 0, p50: 0, p95: 0,
      errors: errors.slice(0, 3),
      metadata: { validRuns: 0, totalRuns: times.length },
    };
  }

  // Summarize evaluation results.
  const postCounts = results.map((r) => {
    if (r && r.result !== undefined) {
      return typeof r.result.value !== "undefined" ? r.result.value : r.result;
    }
    return null;
  });

  return {
    name: "javascript_evaluation",
    status: "ok",
    avg: validTimes.reduce((a, b) => a + b, 0) / validTimes.length,
    min: sorted[0],
    max: sorted[sorted.length - 1],
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    errors: errors.slice(0, 3),
    metadata: {
      validRuns: validTimes.length,
      totalRuns: times.length,
      postCounts: [...new Set(postCounts.filter((c) => c !== null))],
    },
  };
}

// ── Benchmark: DOM Inspection (CDP only) ──────────────────────────────

async function benchDomInspect(client, iterations, warmup, fixtureUrl) {
  const times = [];
  const errors = [];
  const results = [];

  // Navigate first.
  try {
    await client.request("navigate", { url: fixtureUrl });
  } catch (err) {
    return {
      name: "dom_inspect",
      status: "fail",
      avg: 0, min: 0, max: 0, p50: 0, p95: 0,
      errors: [`navigation failed: ${err.message}`],
      metadata: { available: false, reason: "Navigation prerequisite failed" },
    };
  }

  // Wait for dynamic content.
  await new Promise((r) => setTimeout(r, 200));

  // Warmup.
  for (let i = 0; i < warmup; i++) {
    try {
      const start = ms(0);
      const result = await client.request("domInspect", { selector: ".post" });
      times.push(ms(start));
      results.push(result);
    } catch (err) {
      times.push(-1);
      errors.push(`warmup ${i + 1}: ${err.message}`);
    }
  }

  // Measured runs.
  for (let i = 0; i < iterations; i++) {
    try {
      const start = ms(0);
      const result = await client.request("domInspect", { selector: ".post" });
      times.push(ms(start));
      results.push(result);
    } catch (err) {
      times.push(-1);
      errors.push(`iter ${i + 1}: ${err.message}`);
    }
  }

  const validTimes = times.filter((t) => t >= 0);
  const sorted = [...validTimes].sort((a, b) => a - b);

  if (sorted.length === 0) {
    // Check if this is a "not available" error (Chromium backend).
    const isNotAvailable = errors.some((e) =>
      e.includes("CDP backend") || e.includes("not available") || e.includes("not supported")
    );
    return {
      name: "dom_inspect",
      status: isNotAvailable ? "skip" : "fail",
      avg: 0, min: 0, max: 0, p50: 0, p95: 0,
      errors: errors.slice(0, 3),
      metadata: {
        available: false,
        reason: isNotAvailable ? "DOM inspect only implemented for CDP backend" : "All runs failed",
      },
    };
  }

  const foundCounts = results.map((r) => {
    if (r && r.found && Array.isArray(r.found)) return r.found.length;
    return null;
  });

  return {
    name: "dom_inspect",
    status: "ok",
    avg: validTimes.reduce((a, b) => a + b, 0) / validTimes.length,
    min: sorted[0],
    max: sorted[sorted.length - 1],
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    errors: errors.slice(0, 3),
    metadata: {
      validRuns: validTimes.length,
      totalRuns: times.length,
      foundCounts: [...new Set(foundCounts.filter((c) => c !== null))],
    },
  };
}

// ── Benchmark: Network Capture (CDP only) ─────────────────────────────

async function benchNetworkCapture(client, iterations, warmup, fixtureUrl) {
  const times = [];
  const errors = [];

  // Warmup.
  for (let i = 0; i < warmup; i++) {
    try {
      const start = ms(0);
      await client.request("networkCaptureEnable");
      try { await client.request("navigate", { url: "data:text/html,<p>reset</p>" }); } catch {}
      await client.request("navigate", { url: fixtureUrl });
      await new Promise((r) => setTimeout(r, 500));
      const events = await client.request("networkCaptureGet");
      await client.request("networkCaptureClear");
      times.push(ms(start));
    } catch (err) {
      times.push(-1);
      errors.push(`warmup ${i + 1}: ${err.message}`);
    }
  }

  // Measured runs.
  for (let i = 0; i < iterations; i++) {
    try {
      const start = ms(0);
      await client.request("networkCaptureEnable");
      try { await client.request("navigate", { url: "data:text/html,<p>reset</p>" }); } catch {}
      await client.request("navigate", { url: fixtureUrl });
      await new Promise((r) => setTimeout(r, 500));
      const events = await client.request("networkCaptureGet");
      await client.request("networkCaptureClear");
      times.push(ms(start));
    } catch (err) {
      times.push(-1);
      errors.push(`iter ${i + 1}: ${err.message}`);
    }
  }

  const validTimes = times.filter((t) => t >= 0);
  const sorted = [...validTimes].sort((a, b) => a - b);

  if (sorted.length === 0) {
    const isNotAvailable = errors.some((e) =>
      e.includes("CDP backend") || e.includes("not available") || e.includes("not supported")
    );
    return {
      name: "network_capture",
      status: isNotAvailable ? "skip" : "fail",
      avg: 0, min: 0, max: 0, p50: 0, p95: 0,
      errors: errors.slice(0, 3),
      metadata: {
        available: false,
        reason: isNotAvailable
          ? "Network capture only implemented for CDP backend"
          : "All runs failed",
      },
    };
  }

  return {
    name: "network_capture",
    status: "ok",
    avg: validTimes.reduce((a, b) => a + b, 0) / validTimes.length,
    min: sorted[0],
    max: sorted[sorted.length - 1],
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    errors: errors.slice(0, 3),
    metadata: { validRuns: validTimes.length, totalRuns: times.length },
  };
}

// ── Local test server ──────────────────────────────────────────────────

function startLocalServer(fixtureDir) {
  return new Promise((serverResolve) => {
    const PORT = 18766;

    const server = createServer((req, res) => {
      const rawUrl = typeof req.url === "string" ? req.url.replace(/^\/+/, "") : "";
      const cleanPath = rawUrl === "" ? "index.html" : rawUrl.split("?")[0];
      const filePath = resolve(fixtureDir, cleanPath);
      const baseDir = resolve(fixtureDir);

      if (typeof filePath !== "string" || !filePath.startsWith(baseDir)) {
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
      serverResolve({
        url: `http://127.0.0.1:${PORT}`,
        port: PORT,
        stop: () => server.close(),
      });
    });
  });
}

// ── Run benchmarks for one backend ─────────────────────────────────────

async function runBackendBenchmarks(sidecarPath, backendName, warmup, iterations, connectParams, fixtureUrl) {
  const results = {};

  log("info", "");
  log("info", `=== Running ${backendName} benchmarks ===`);

  const { child, version } = await startSidecar(sidecarPath);
  const client = createClient(child, version);

  try {
    // Connect.
    log("info", `Connecting ${backendName}...`);
    const connStart = ms(0);
    try {
      const connResult = await client.request("connect", connectParams);
      const connTime = ms(connStart);
      log("info", `  Connected in ${connTime.toFixed(1)}ms (backend=${connResult.backend})`);
      results.connection = { status: "ok", time_ms: connTime, backend: connResult.backend, endpoint: connResult.endpoint };
    } catch (err) {
      log("info", `  Connect failed: ${err.message}`);
      results.connection = { status: "fail", error: err.message };
    }

    // Only run navigation/extraction if connection succeeded.
    if (results.connection.status === "ok") {
      // Navigation.
      log("info", "  Benchmarking navigation...");
      results.navigation = await benchNavigate(client, iterations, warmup, fixtureUrl);
      log("info", `    avg=${results.navigation.avg.toFixed(1)}ms  p50=${results.navigation.p50.toFixed(1)}ms  status=${results.navigation.status}`);

      // JavaScript evaluation.
      log("info", "  Benchmarking JS evaluation...");
      results.js_evaluation = await benchEvaluate(client, iterations, warmup, fixtureUrl);
      log("info", `    avg=${results.js_evaluation.avg.toFixed(1)}ms  status=${results.js_evaluation.status}`);

      // DOM inspection (CDP only).
      log("info", "  Benchmarking DOM inspection...");
      results.dom_inspect = await benchDomInspect(client, iterations, warmup, fixtureUrl);
      log("info", `    avg=${results.dom_inspect.avg.toFixed(1)}ms  status=${results.dom_inspect.status}`);

      // Network capture (CDP only).
      log("info", "  Benchmarking network capture...");
      results.network_capture = await benchNetworkCapture(client, iterations, warmup, fixtureUrl);
      log("info", `    avg=${results.network_capture.avg.toFixed(1)}ms  status=${results.network_capture.status}`);
    }
  } finally {
    await client.close();
  }

  return { backend: backendName, version, results };
}

// ── Main ───────────────────────────────────────────────────────────────

async function main() {
  const { warmup, iterations, sidecarPath } = parseArgs();

  log("info", "=== xtweetsR Backend Comparison ===");
  log("info", `Node ${process.version}`);
  log("info", `Warmup: ${warmup}, Iterations: ${iterations}`);
  log("info", `Sidecar: ${sidecarPath}`);
  log("info", "");

  const suite = {
    timestamp: new Date().toISOString(),
    nodeVersion: process.version,
    sidecarPath,
    backends: [],
  };

  // Start local fixture server.
  const fixtureDir = resolve(__dirname, "..", "inst", "tests", "fixtures");
  const server = await startLocalServer(fixtureDir);
  const fixtureUrl = `${server.url}/dynamic-page.html`;

  try {
    // ── 1. CDP (Lightpanda) backend ──────────────────────────────────
    // Uses ws://127.0.0.1:21111 by default (Lightpanda endpoint).
    // If Lightpanda is not running, connect will fail and benchmarks
    // will be skipped with a clear error.
    const cdpResult = await runBackendBenchmarks(
      sidecarPath,
      "cdp (Lightpanda)",
      warmup,
      iterations,
      { endpoint: process.env.LPD_ENDPOINT || "ws://127.0.0.1:21111" },
      fixtureUrl
    );
    suite.backends.push(cdpResult);

    // ── 2. Chromium backend ─────────────────────────────────────────
    const chromiumResult = await runBackendBenchmarks(
      sidecarPath,
      "chromium (Puppeteer)",
      warmup,
      iterations,
      { backend: "chromium" },
      fixtureUrl
    );
    suite.backends.push(chromiumResult);
  } finally {
    server.stop();
  }

  // ── Output JSON ───────────────────────────────────────────────────
  console.log(JSON.stringify(suite, null, 2));

  // ── Summary table ─────────────────────────────────────────────────
  log("info", "");
  log("info", "=== Comparison Summary ===");

  const benchmarks = ["navigation", "js_evaluation", "dom_inspect", "network_capture"];
  for (const bench of benchmarks) {
    log("info", "");
    log("info", `--- ${bench} ---`);
    for (const backend of suite.backends) {
      const r = backend.results[bench];
      if (!r) {
        log("info", `  ${backend.backend}: N/A`);
        continue;
      }
      if (r.status === "ok") {
        log("info", `  ${backend.backend}: avg=${r.avg.toFixed(1)}ms  p50=${r.p50.toFixed(1)}ms  p95=${r.p95.toFixed(1)}ms  runs=${r.metadata.validRuns}/${r.metadata.totalRuns}`);
      } else if (r.status === "skip") {
        log("info", `  ${backend.backend}: SKIP — ${r.metadata.reason || "not available"}`);
      } else {
        const err = r.errors ? r.errors[0] : "unknown";
        log("info", `  ${backend.backend}: FAIL — ${err}`);
      }
    }
  }

  // Connection summary.
  log("info", "");
  log("info", "--- connection ---");
  for (const backend of suite.backends) {
    const r = backend.results.connection;
    if (r.status === "ok") {
      log("info", `  ${backend.backend}: ${r.time_ms.toFixed(1)}ms (endpoint=${r.endpoint})`);
    } else {
      log("info", `  ${backend.backend}: FAIL — ${r.error}`);
    }
  }

  // Exit with non-zero if any non-skip benchmark failed.
  let hasFailure = false;
  for (const backend of suite.backends) {
    for (const bench of benchmarks) {
      const r = backend.results[bench];
      if (r && r.status === "fail") hasFailure = true;
    }
  }
  if (hasFailure) {
    log("info", "");
    log("info", "Some benchmarks failed (not skipped). Check errors above.");
    process.exit(1);
  }
}

main().catch((err) => {
  log("error", "Fatal error:", err.message);
  console.error(err);
  process.exit(1);
});
