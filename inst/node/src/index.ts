// xtweetsR TypeScript sidecar — entry point
// Reads JSONL requests from stdin, writes JSONL responses to stdout.
// Logs go to stderr.

import { createInterface } from "readline";

const VERSION = "0.1.0";

// ── helpers ──────────────────────────────────────────────────────────

function respond(id: unknown, result: unknown): void {
  process.stdout.write(JSON.stringify({ id, result }) + "\n");
}

function error(id: unknown, code: string, message: string): void {
  process.stdout.write(
    JSON.stringify({ id, error: { code, message } }) + "\n"
  );
}

// ── ping handler ─────────────────────────────────────────────────────

function handlePing(id: unknown): void {
  respond(id, { pong: true, version: VERSION });
}

// ── main loop ────────────────────────────────────────────────────────

async function main(): Promise<void> {
  // Deterministic startup message on stderr.
  process.stderr.write(
    JSON.stringify({ type: "startup", version: VERSION }) + "\n"
  );

  const rl = createInterface({ input: process.stdin });

  for await (const line of rl) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    let parsed: unknown;
    try {
      parsed = JSON.parse(trimmed);
    } catch {
      // Malformed JSON → structured error.
      error(null, "PARSE_ERROR", "Invalid JSON input");
      continue;
    }

    if (
      typeof parsed !== "object" ||
      parsed === null
    ) {
      error(null, "INVALID_REQUEST", "Request must be a JSON object");
      continue;
    }

    const req = parsed as Record<string, unknown>;
    const id = req.id;
    const method = req.method;

    if (typeof method !== "string") {
      error(id, "INVALID_REQUEST", "Missing 'method' field");
      continue;
    }

    // Route to the handler.
    switch (method) {
      case "ping":
        handlePing(id);
        break;
      default:
        error(id, "UNKNOWN_METHOD", `Method "${method}" is not implemented`);
        break;
    }
  }
}

main().catch((err) => {
  process.stderr.write(
    JSON.stringify({ type: "fatal", error: (err as Error).message }) + "\n"
  );
  process.exit(1);
});
