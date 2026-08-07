/**
 * Task 29: Capture X search network traffic.
 *
 * Navigates to an X search URL, captures all network traffic (fetch/XHR/GraphQL),
 * records operation names, response content types, and candidate response URLs.
 * Identifies candidate post-bearing responses without building a full parser.
 *
 * Usage:
 *   npx ts-node src/task29-capture-x-network.ts "r programming"
 *   LPD_ENDPOINT=ws://127.0.0.1:21111 npx ts-node src/task29-capture-x-network.ts "climate change"
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

// ── candidate analysis ───────────────────────────────────────────────

interface CandidatePostResponse {
  url: string;
  method?: string;
  resourceType?: string;
  status?: number;
  contentType?: string;
  isXhrFetch: boolean;
  isJson: boolean;
  isGraphQLLike: boolean;
  isXDomain: boolean;
  postCandidateScore: number;
}

/**
 * Heuristics for identifying candidate post-bearing responses.
 *
 * Scoring:
 *   +3  X/Twitter domain
 *   +2  XHR/fetch resource type
 *   +2  application/json content type
 *   +2  URL contains graphQL, query, timeline, tweet, post, result keywords
 *   +1  URL path contains /api, /graphql, /internal
 *   +1  URL contains cursor, next, refresh (pagination patterns)
 *
 * Responses scoring >= 3 are marked as candidate post-bearing.
 */
function scoreCandidate(event: Record<string, unknown>): CandidatePostResponse {
  const url = (event.url as string) || "";
  const method = event.method as string | undefined;
  const resourceType = event.resourceType as string | undefined;
  const status = event.status as number | undefined;
  const contentType = (event.contentType as string) ||
    ((event.protocol as string) ? undefined : undefined);

  const isXhrFetch = resourceType === "xhr" || resourceType === "fetch";
  const isJson = Boolean(
    contentType?.includes("application/json") ||
      url.endsWith(".json") ||
      contentType?.includes("json"),
  );

  const isXDomain = url.includes("x.com") || url.includes("twitter.com");
  const isGraphQLLike =
    url.includes("graphql") || url.includes("/api/graphql");

  const urlLower = url.toLowerCase();
  const isApiPath =
    urlLower.includes("/api/") ||
    urlLower.includes("/graphql") ||
    urlLower.includes("/internal/");

  const isPagination =
    urlLower.includes("cursor") ||
    urlLower.includes("next") ||
    urlLower.includes("refresh");

  const isPostKeyword =
    urlLower.includes("tweet") ||
    urlLower.includes("post") ||
    urlLower.includes("result") ||
    urlLower.includes("timeline") ||
    urlLower.includes("search");

  let score = 0;
  if (isXDomain) score += 3;
  if (isXhrFetch) score += 2;
  if (isJson) score += 2;
  if (isPostKeyword) score += 2;
  if (isApiPath) score += 1;
  if (isPagination) score += 1;

  return {
    url,
    method,
    resourceType,
    status,
    contentType,
    isXhrFetch,
    isJson,
    isGraphQLLike,
    isXDomain,
    postCandidateScore: score,
  };
}

/**
 * Extract operation name from a potential GraphQL request body.
 * Returns null if no operation name is found.
 */
async function extractOperationName(
  proc: ReturnType<typeof spawn>,
  requestId: string,
): Promise<string | null> {
  try {
    const resp = await sendRequest(proc, "networkCaptureGetBody", { requestId });
    if (resp.result && typeof resp.result.body === "string") {
      const body = resp.result.body as string;
      // GraphQL operations: "query OpName { ... }" or "mutation OpName { ... }"
      const match = body.match(/(?:query|mutation|subscription)\s+(\w+)/i);
      if (match && match[1] !== "query" && match[1] !== "mutation") {
        return match[1];
      }
      // Alternative: { "operationName": "..." }
      const jsonMatch = body.match(/"operationName"\s*:\s*"([^"]+)"/);
      if (jsonMatch) return jsonMatch[1];
    }
  } catch {
    // body retrieval failed — not fatal
  }
  return null;
}

async function tryGetBodyAndScore(
  proc: ReturnType<typeof spawn>,
  url: string,
): Promise<{ hasBody: boolean; opName: string | null }> {
  try {
    const resp = await sendRequest(proc, "networkCaptureGetBody", { requestId: url });
    if (resp.result && typeof resp.result.body === "string") {
      const body = resp.result.body;
      const match = body.match(/(?:query|mutation|subscription)\s+(\w+)/i);
      const opName =
        (match && match[1] !== "query" && match[1] !== "mutation" ? match[1] : null) ||
        body.match(/"operationName"\s*:\s*"([^"]+)"/)?.[1] ||
        null;
      return { hasBody: true, opName };
    }
  } catch {
    // body retrieval failed
  }
  return { hasBody: false, opName: null };
}

// ── main ─────────────────────────────────────────────────────────────

async function run(): Promise<void> {
  const endpoint = process.env.LPD_ENDPOINT || "ws://127.0.0.1:21111";

  console.error("=== Task 29: Capture X Search Network Traffic ===");
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
      console.error(
        `CONNECT FAILED: ${connectResp.error.code} — ${connectResp.error.message}`
      );
      // Fall through to finally block for cleanup

      const result = {
        task: 29,
        status: "failed",
        failure: "LPD_CONNECTION_ERROR",
        message: `${connectResp.error.code}: ${connectResp.error.message}`,
        endpoint,
        query,
        url: TARGET_URL,
        network_artifacts: {
          total_events: 0,
          candidates: [],
          operation_names: [],
          content_types: [],
          candidate_urls: [],
        },
      };
      console.error("\n=== RESULT ===");
      console.error(JSON.stringify(result, null, 2));
      return;
    }
    console.error("Connected to Lightpanda.");

    // Enable network capture
    console.error("Enabling network capture...");
    const netResp = await sendRequest(proc, "networkCaptureEnable", {});
    if (netResp.error) {
      console.error(
        `Network capture enable: ${netResp.error.code} — ${netResp.error.message}`
      );
    } else {
      console.error("Network capture enabled.");
    }

    // Navigate to search URL
    console.error(`Navigating to ${TARGET_URL}...`);
    const navResp = await sendRequest(proc, "navigate", { url: TARGET_URL });

    if (navResp.error) {
      console.error(
        `NAVIGATION FAILED: ${navResp.error.code} — ${navResp.error.message}`
      );
    } else {
      console.error("Navigation completed.");
    }

    // Small delay to let any lazy network requests complete
    await new Promise((r) => setTimeout(r, 2000));

    // Retrieve captured network events
    let events: Record<string, unknown>[] = [];
    try {
      const netSummary = await sendRequest(proc, "networkCaptureGet", {});
      if (netSummary.result && netSummary.result.events) {
        events = netSummary.result.events as Record<string, unknown>[];
      }
    } catch {
      console.error("Could not retrieve network capture events.");
    }

    console.error(`Captured ${events.length} network events.`);

    // Score each event as a candidate post-bearing response
    const candidates: CandidatePostResponse[] = events.map(scoreCandidate);
    const topCandidates = candidates
      .filter((c) => c.postCandidateScore >= 1)
      .sort((a, b) => b.postCandidateScore - a.postCandidateScore);

    // Extract operation names from high-scoring XHR/fetch/GraphQL responses
    const graphqlCandidates = topCandidates.filter(
      (c) => c.isGraphQLLike || c.isXhrFetch || c.url.includes("/api/")
    );

    console.error(
      `Analyzing ${graphqlCandidates.length} candidate responses for operation names...`
    );

    const operationNames = new Set<string>();
    const bodyCaptureResults: Array<{
      url: string;
      operationName: string | null;
      hasBody: boolean;
      bodyPreview?: string;
      bodySize?: number;
    }> = [];

    for (const candidate of graphqlCandidates.slice(0, 20)) {
      // We don't have requestId directly from the scoring, but we can try
      // to get the body via networkCaptureGetBody if the sidecar tracks it
      const opName = await extractOperationName(proc, candidate.url);
      if (opName) {
        operationNames.add(opName);
        bodyCaptureResults.push({
          url: candidate.url,
          operationName: opName,
          hasBody: true,
        });
      }
    }

    // Collect unique content types
    const contentTypes = [
      ...new Set(
        events
          .map((e) => (e.contentType as string) || (e.protocol as string) || "unknown")
          .filter((ct) => ct !== "unknown" && ct !== "")
      ),
    ];

    // Collect unique X domain URLs
    const xDomainUrls = [
      ...new Set(
        events
          .filter((e) => {
            const u = e.url as string || "";
            return u.includes("x.com") || u.includes("twitter.com");
          })
          .map((e) => e.url)
      ),
    ];

    // Build structured result
    const result = {
      task: 29,
      status: navResp.error ? "partial" : "success",
      query,
      url: TARGET_URL,
      final_url:
        (navResp.result &&
          typeof navResp.result === "object" &&
          "url" in navResp.result &&
          navResp.result.url) ||
        TARGET_URL,
      endpoint,
      navigation_error: navResp.error
        ? `${navResp.error.code}: ${navResp.error.message}`
        : null,
      network_artifacts: {
        total_events: events.length,
        unique_domains: [
          ...new Set(
            events.map((e) => {
              const u = e.url as string || "";
              try {
                return new URL(u).hostname;
              } catch {
                return "unknown";
              }
            })
          ),
        ],
        xhr_fetch_events: candidates.filter((c) => c.isXhrFetch).length,
        document_events: events.filter(
          (e) => (e.resourceType as string) === "document"
        ).length,
        content_types: contentTypes,
        operation_names: [...operationNames],
        candidate_count: topCandidates.length,
        candidates: topCandidates
          .slice(0, 30)
          .map((c) => ({
            url: c.url,
            score: c.postCandidateScore,
            method: c.method,
            resourceType: c.resourceType,
            status: c.status,
            contentType: c.contentType,
            isGraphQLLike: c.isGraphQLLike,
            isJson: c.isJson,
            isXDomain: c.isXDomain,
          })),
        candidate_urls: topCandidates.slice(0, 30).map((c) => c.url),
        body_captures: bodyCaptureResults,
        x_domain_urls: xDomainUrls.slice(0, 20),
      },
    };

    console.error("\n=== RESULT ===");
    console.error(JSON.stringify(result, null, 2));
  } finally {
    // Clean up — attempt close, then kill
    try {
      await sendRequest(proc, "close");
    } catch {
      // ignore close errors (process may already be dead)
    }
    try {
      proc.kill("SIGTERM");
    } catch {
      // ignore kill errors
    }
    try {
      proc.stderr.destroy();
    } catch {
      // ignore destroy errors
    }
  }
}

run().catch((err) => {
  console.error(`Task 29 error: ${err.message}`);
  console.error(
    JSON.stringify(
      {
        task: 29,
        status: "failed",
        failure: "TASK_ERROR",
        message: err.message,
        query,
      },
      null,
      2
    )
  );
  process.exit(1);
});
