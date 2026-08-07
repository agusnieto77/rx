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
function startSidecar() {
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
        proc.stderr.on("data", (d) => {
            stderrBuf += d.toString();
            if (resolved)
                return;
            const line = d.toString().trim();
            if (line) {
                try {
                    const parsed = JSON.parse(line);
                    if (parsed.type === "startup") {
                        resolved = true;
                        clearTimeout(timeout);
                        resolve({ proc, stderrBuf });
                    }
                }
                catch {
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
function sendRequest(proc, method, params) {
    return new Promise((resolve, reject) => {
        const id = method;
        const req = JSON.stringify({ id, method, ...(params ? { params } : {}) });
        if (proc.stdin)
            proc.stdin.write(req + "\n");
        const handler = (d) => {
            const line = d.toString().trim();
            if (!line)
                return;
            try {
                const parsed = JSON.parse(line);
                if (proc.stdout)
                    proc.stdout.removeListener("data", handler);
                resolve(parsed);
            }
            catch {
                // Not JSON, ignore
            }
        };
        if (proc.stdout)
            proc.stdout.once("data", handler);
        setTimeout(() => {
            if (proc.stdout)
                proc.stdout.removeListener("data", handler);
            reject(new Error(`No response for method: ${method}`));
        }, 3000);
    });
}
describe("sidecar protocol", () => {
    let proc = null;
    process.on("exit", () => {
        // Best-effort cleanup on process exit.
        if (proc && !proc.killed)
            proc.kill();
    });
    it("ping returns pong", async () => {
        const { proc: p } = await startSidecar();
        proc = p;
        const resp = await sendRequest(p, "ping");
        assert.strictEqual(resp.id, "ping");
        assert.strictEqual(resp.result.pong, true);
        assert.strictEqual(typeof resp.result.version, "string");
    });
    it("unknown method returns structured error", async () => {
        const { proc: p } = await startSidecar();
        const resp = await sendRequest(p, "nonexistent_method");
        assert.strictEqual(resp.id, "nonexistent_method");
        assert.strictEqual(resp.error.code, "UNKNOWN_METHOD");
        assert.strictEqual(typeof resp.error.message, "string");
    });
    it("malformed JSON returns PARSE_ERROR", async () => {
        const { proc: p } = await startSidecar();
        if (p.stdin)
            p.stdin.write("not valid json {{{\n");
        const resp = await new Promise((resolve) => {
            if (p.stdout)
                p.stdout.once("data", (d) => {
                    const parsed = JSON.parse(d.toString().trim());
                    resolve(parsed);
                });
        });
        assert.strictEqual(resp.error.code, "PARSE_ERROR");
    });
    it("process shutdown terminates cleanly", async () => {
        const { proc: p } = await startSidecar();
        proc = p;
        p.kill();
        await new Promise((resolve) => setTimeout(resolve, 200));
        assert.strictEqual(p.killed, true);
    });
    it("request with params echoes in result", async () => {
        const { proc: p } = await startSidecar();
        const resp = await sendRequest(p, "ping", { extra: "data" });
        assert.strictEqual(resp.id, "ping");
        assert.strictEqual(resp.result.pong, true);
    });
    it("connect to unreachable endpoint returns LPD_CONNECTION_ERROR", async () => {
        const { proc: p } = await startSidecar();
        const resp = await sendRequest(p, "connect", { endpoint: "ws://127.0.0.1:1" });
        assert.strictEqual(resp.id, "connect");
        assert.strictEqual(resp.error.code, "LPD_CONNECTION_ERROR");
        assert.strictEqual(typeof resp.error.message, "string");
        assert.ok(resp.error.message.includes("Failed to connect to CDP endpoint"));
    });
    it("connect with no endpoint falls back to default and returns LPD_CONNECTION_ERROR", async () => {
        const { proc: p } = await startSidecar();
        const resp = await sendRequest(p, "connect", {});
        assert.strictEqual(resp.id, "connect");
        assert.strictEqual(resp.error.code, "LPD_CONNECTION_ERROR");
    });
    it("connect with invalid endpoint format returns LPD_CONNECTION_ERROR", async () => {
        const { proc: p } = await startSidecar();
        const resp = await sendRequest(p, "connect", { endpoint: "not-a-url" });
        assert.strictEqual(resp.id, "connect");
        assert.strictEqual(resp.error.code, "LPD_CONNECTION_ERROR");
    });
});
//# sourceMappingURL=protocol.test.js.map