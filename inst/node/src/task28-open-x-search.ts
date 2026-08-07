/**
 * Task 28: Open an X search URL — prove Lightpanda can navigate to a search
 * results page and capture the navigation result.
 *
 * This script starts a sidecar, connects to a configured Lightpanda endpoint,
 * navigates to an X search URL constructed from a query, and records the page
 * title, final URL, and a network summary.
 *
 * Usage:
 *   npx ts-node src/task28-open-x-search.ts "r programming"
 *   LPD_ENDPOINT=ws://127.0.0.1:21111 npx ts-node src/task28-open-x-search.ts "climate"
 */

import { spawn } from "child_process";
import { createInterface } from "readline";
import { resolve, join, dirname } from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const query = process.argv[2] || "r programming";
const TARGET_URL = `https://x.com/search?q=${encodeURIComponent(query)}`;

interface Request {
  id: number;
  method: string;
  params?: Record<string, unknown>;
}

interface Response {
  id?: number;
  result?: Record<string, unknown>;
  error?: { code: string; message: string };
}

let reqCounter = 0;

function nextId(): number {
  return ++reqCounter;
}

function sendRequest(
  proc: ReturnType<typeof spawn>,
  method: string,
  params?: Record<string, unknown>,
): Promise<Response> {
  return new Promise((resolve, reject) => {
    const id = nextId();
    const req: Request = { id, method, params };
    if (!proc.stdin) {
      reject(new Error("Sidecar stdin is not available"));
      return;
    }
    proc.stdin.write(JSON.stringify(req) + "\n");

    const stdout = proc.stdout;
    if (!stdout) {
      reject(new Error("Sidecar stdout is not available"));
      return;
    }
    const rl = createInterface({ input: stdout });
    const timeout = setTimeout(() => {
      rl.close();
      reject(new Error(`${method} request timed out after 30s`));
    }, 30_000);

    rl.on("line", (line) => {
      try {
        const res: Response = JSON.parse(line);
        if (res.id === id) {
          clearTimeout(timeout);
          rl.close();
          resolve(res);
        }
      } catch {
        // ignore parse errors on non-JSON lines
      }
    });

    proc.on("error", (err) => {
      clearTimeout(timeout);
      rl.close();
      reject(err);
    });

    proc.on("close", (code) => {
      if (code !== 0 && code !== null) {
        rl.close();
        reject(new Error(`Sidecar exited with code ${code}`));
      }
    });
  });
}

async function run(): Promise<void> {
  const endpoint = process.env.LPD_ENDPOINT || "ws://127.0.0.1:21111";

  console.error("=== Task 28: Open an X search URL ===");
  console.error(`Query: ${query}`);
  console.error(`Target URL: ${TARGET_URL}`);
  console.error(`Lightpanda endpoint: ${endpoint}`);

  // Resolve sidecar path
  const scriptDir = __dirname;
  const pkgDir = resolve(scriptDir, "..");
  const distDir = join(pkgDir, "dist");

  console.error(`Sidecar directory: ${distDir}`);

  // Start sidecar
  const proc = spawn("node", [join(distDir, "index.js")], {
    stdio: ["pipe", "pipe", "pipe"],
    cwd: pkgDir,
  });

  // Wait for startup message
  const rlStderr = createInterface({ input: proc.stderr });
  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => {
      rlStderr.close();
      proc.kill("SIGTERM");
      reject(new Error("Sidecar startup heartbeat timeout"));
    }, 10_000);

    rlStderr.on("line", (line) => {
      try {
        const msg = JSON.parse(line);
        if (msg.type === "startup") {
          clearTimeout(timeout);
          rlStderr.close();
          resolve();
        }
      } catch {
        // not JSON, ignore
      }
    });

    proc.on("error", (err) => {
      clearTimeout(timeout);
      rlStderr.close();
      reject(err);
    });
  });
  console.error("Sidecar started successfully.");

  try {
    // Connect to Lightpanda
    console.error("Connecting to Lightpanda...");
    const connectResp = await sendRequest(proc, "connect", { endpoint });
    if (connectResp.error) {
      console.error(`CONNECT FAILED: ${connectResp.error.code} — ${connectResp.error.message}`);
      await sendRequest(proc, "close");
      proc.kill("SIGTERM");
      console.error("\n=== RESULT: Connection failed ===");
      console.error(
        JSON.stringify({
          task: 28,
          status: "failed",
          failure: "LPD_CONNECTION_ERROR",
          message: `${connectResp.error.code}: ${connectResp.error.message}`,
          endpoint,
          url: TARGET_URL,
          query,
        })
      );
      return;
    }
    console.error("Connected to Lightpanda.");

    // Enable network capture
    console.error("Enabling network capture...");
    const netResp = await sendRequest(proc, "networkCaptureEnable", {});
    if (netResp.error) {
      console.error(`Network capture enable: ${netResp.error.code} — ${netResp.error.message}`);
      // Non-fatal — continue without network capture
    } else {
      console.error("Network capture enabled.");
    }

    // Navigate to search URL
    console.error(`Navigating to ${TARGET_URL}...`);
    const navResp = await sendRequest(proc, "navigate", { url: TARGET_URL });

    if (navResp.error) {
      console.error(`NAVIGATION FAILED: ${navResp.error.code} — ${navResp.error.message}`);
      console.error("\n=== RESULT: Navigation failed ===");
      console.error(
        JSON.stringify({
          task: 28,
          status: "failed",
          failure: navResp.error.code,
          message: navResp.error.message,
          endpoint,
          url: TARGET_URL,
          query,
        })
      );
      await sendRequest(proc, "close");
      proc.kill("SIGTERM");
      return;
    }

    console.error("Navigation response received.");

    // Extract page title via JavaScript evaluation
    let pageTitle = null;
    try {
      const titleResp = await sendRequest(proc, "evaluate", {
        expr: "document.title",
      });
      if (titleResp.result) {
        pageTitle =
          typeof titleResp.result === "string"
            ? titleResp.result
            : String(titleResp.result.result);
      }
    } catch {
      console.error("Could not evaluate document.title.");
    }

    // Retrieve captured network events
    let networkSummary: Record<string, unknown> = {};
    try {
      const netSummary = await sendRequest(proc, "networkCaptureGet", {});
      if (netSummary.result && netSummary.result.events) {
        const events = netSummary.result.events as Record<string, unknown>[];
        networkSummary = {
          total_events: events.length,
          unique_domains: [...new Set(events.map((e: Record<string, unknown>) => {
            const u = e.url as string || "";
            try { return new URL(u).hostname; } catch { return "unknown"; }
          }))].join(", "),
          xhr_events: events.filter((e: Record<string, unknown>) =>
            e.resourceType === "xhr" || e.resourceType === "fetch"
          ).length,
          doc_events: events.filter((e: Record<string, unknown>) =>
            e.resourceType === "document"
          ).length,
        };
      }
    } catch {
      console.error("Could not retrieve network capture summary.");
    }

    const finalUrl =
      (navResp.result &&
        typeof navResp.result === "object" &&
        "url" in navResp.result &&
        navResp.result.url) ||
      TARGET_URL;

    console.error("\n=== RESULT: Navigation completed ===");
    console.error(
      JSON.stringify({
        task: 28,
        status: "success",
        query,
        url: TARGET_URL,
        final_url: finalUrl,
        title: pageTitle,
        endpoint,
        navigation_result: navResp.result,
        network_summary: networkSummary,
      })
    );
  } finally {
    // Clean up
    try {
      await sendRequest(proc, "close");
    } catch {
      // ignore close errors
    }
    proc.kill("SIGTERM");
    proc.stderr.destroy();
  }
}

run().catch((err) => {
  console.error(`Task 28 error: ${err.message}`);
  console.error(JSON.stringify({
    task: 28,
    status: "failed",
    failure: "TASK_ERROR",
    message: err.message,
    query,
  }));
  process.exit(1);
});
