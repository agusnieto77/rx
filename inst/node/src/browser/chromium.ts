// xtweetsR — Chromium backend via Puppeteer
//
// Controls a local Chromium (or Chrome) instance using Puppeteer.
// Implements the same JSONL request/response protocol as the CDP backend,
// proving that the backend abstraction is real — the same high-level
// navigation/evaluation calls work regardless of browser engine.
//
// This module is a spike: it implements only the methods required to
// navigate the local fixture and evaluate JavaScript. Network capture
// and DOM inspection are not yet implemented.
//
// Usage:
//   1. import { ChromiumBackend } from "./chromium.js";
//   2. const backend = new ChromiumBackend();
//   3. await backend.connect({ type: "chromium" });
//   4. const result = await backend.navigate("http://localhost:8080/");
//   5. const value = await backend.evaluate("document.title");

import type { Page, Browser } from "puppeteer";

// ── public types ─────────────────────────────────────────────────────

export interface ChromiumConnectOptions {
  /** Backend type — always "chromium" for this module. */
  type?: string;
  /** Chrome/Chromium executable path. Defaults to Puppeteer's bundled Chromium. */
  executablePath?: string;
  /** Launch Chromium in headless mode (default: true). */
  headless?: boolean;
  /** Additional Puppeteer launch options (passed through to puppeteer.launch). */
  launchOptions?: Record<string, unknown>;
}

export interface NavigateResult {
  url: string;
  navigated: true;
  status: string;
}

export interface EvaluateResult {
  evaluated: true;
  result?: Record<string, unknown> | null;
}

export interface ChromiumConnectResult {
  connected: true;
  endpoint: string;
}

// ── ChromiumBackend ──────────────────────────────────────────────────

/**
 * Manages a Puppeteer-controlled Chromium instance.
 *
 * The lifecycle is:
 *   new ChromiumBackend() → connect() → navigate()/evaluate() → close()
 *
 * connect() spawns Chromium (or attaches to a CDP endpoint).
 * navigate() and evaluate() operate on the default page.
 * close() shuts down the browser and cleans up resources.
 */
export class ChromiumBackend {
  private browser: Browser | null = null;
  private page: Page | null = null;
  private _isConnected = false;

  get isConnected(): boolean {
    return this._isConnected && this.browser !== null;
  }

  // -- connect ----------------------------------------------------------

  /**
   * Launch or attach Chromium.
   *
   * Accepts options to control how Chromium is launched:
   *   - type: "chromium" (default) — spawns a local Chromium instance
   *   - type: "cdp" — attaches to an existing CDP endpoint
   *   - executablePath: path to a custom Chrome/Chromium binary
   *   - headless: whether to run in headless mode (default: true)
   *
   * When type is "chromium", Puppeteer spawns a fresh browser.
   * When type is "cdp", Puppeteer attaches to an existing Chrome DevTools
   * protocol endpoint (same as the Lightpanda backend but via Puppeteer).
   *
   * @param options Configuration for the Chromium instance.
   * @returns A promise that resolves when the browser is ready.
   */
  async connect(options: ChromiumConnectOptions = {}): Promise<ChromiumConnectResult> {
    if (this.browser !== null) {
      await this.close();
    }

    const type = options.type ?? "chromium";
    const headless = options.headless ?? true;

    if (type === "cdp" && options.type !== undefined) {
      // Attach to an existing CDP endpoint — useful for testing with
      // Lightpanda or a running Chrome instance.
      const endpoint = options.launchOptions?.endpoint as string | undefined;
      if (!endpoint) {
        throw new Error("CDP endpoint URL required when type='cdp'");
      }
      const { default: puppeteer } = await import("puppeteer");
      this.browser = await puppeteer.connect({ browserWSEndpoint: endpoint });
      this._isConnected = true;
      log("info", "ChromiumBackend attached to CDP endpoint", endpoint);
    } else {
      // Spawn a local Chromium instance.
      const { default: puppeteer } = await import("puppeteer");
      const launchOpts: Record<string, unknown> = {
        headless,
        args: [
          "--no-sandbox",
          "--disable-setuid-sandbox",
          "--disable-dev-shm-usage",
          "--disable-gpu",
        ],
      };
      if (options.executablePath) {
        launchOpts.executablePath = options.executablePath;
      }
      // Merge any additional launch options.
      if (options.launchOptions && typeof options.launchOptions === "object") {
        Object.assign(launchOpts, options.launchOptions);
      }
      this.browser = await puppeteer.launch(launchOpts as Parameters<typeof puppeteer.launch>[0]);
      this._isConnected = true;
      log("info", "ChromiumBackend launched Chromium (headless=" + headless + ")");
    }

    // Get the first page (or create one if none exists).
    const pages = await this.browser.pages();
    if (pages.length > 0) {
      this.page = pages[0];
    } else {
      this.page = await this.browser.newPage();
    }

    // Disable CDP network domain by default (unlike the CDP backend).
    // The Chromium backend does not implement network capture in this spike.

    return { connected: true, endpoint: this.browser.wsEndpoint() ?? "local" };
  }

  // -- navigate ---------------------------------------------------------

  /**
   * Navigate the current page to a URL.
   *
   * @param url The URL to navigate to.
   * @returns Navigation result with the final URL.
   */
  async navigate(url: string): Promise<NavigateResult> {
    if (!this._isConnected || this.browser === null) {
      throw new Error("ChromiumBackend not connected — call connect() first");
    }
    if (this.page === null) {
      throw new Error("No page available — connect() did not create one");
    }

    const response = await this.page.goto(url, {
      waitUntil: "load",
      timeout: 30_000,
    });

    return {
      url,
      navigated: true,
      status: response ? String(response.status()) : "unknown",
    };
  }

  // -- evaluate ---------------------------------------------------------

  /**
   * Evaluate JavaScript in the current page context.
   *
   * @param expression The JavaScript expression to evaluate.
   * @returns The evaluated result, serialized to a plain object.
   */
  async evaluate(expression: string): Promise<EvaluateResult> {
    if (!this._isConnected || this.browser === null) {
      throw new Error("ChromiumBackend not connected — call connect() first");
    }
    if (this.page === null) {
      throw new Error("No page available — connect() did not create one");
    }

    // Puppeteer's evaluate() returns a JavaScript value serialized to JSON.
    // For primitive values it returns the value directly.
    // For objects, it returns a plain JS object (not a Puppeteer JSHandle).
    const result = await this.page.evaluate(expression);

    // Convert the result to a Record<string, unknown> for protocol consistency.
    // Primitive values (string, number, boolean, null) are wrapped in a value field.
    // Objects/arrays are returned as-is.
    const serialized = serializeValue(result);

    return {
      evaluated: true,
      result: serialized,
    };
  }

  // -- close ------------------------------------------------------------

  /**
   * Close the browser and release resources.
   * Safe to call multiple times — subsequent calls are no-ops.
   */
  async close(): Promise<void> {
    if (this.browser === null) {
      this._isConnected = false;
      return;
    }

    try {
      await this.browser.close();
    } catch {
      // Browser may already be closed — safe to ignore.
    }
    this.browser = null;
    this.page = null;
    this._isConnected = false;
    log("info", "ChromiumBackend closed");
  }
}

// ── helpers ──────────────────────────────────────────────────────────

/**
 * Serialize a Puppeteer evaluate() result to a protocol-friendly object.
 *
 * Puppeteer's evaluate() returns:
 *   - Primitives (string, number, boolean, null, undefined) as-is
 *   - Objects/arrays as plain JS values (not JSHandles)
 *   - Functions throw an error
 *
 * We wrap primitives in a {value: ...} structure for consistency
 * with the CDP backend's returnByValue format.
 */
function serializeValue(value: unknown): Record<string, unknown> | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === "object") {
    // Objects and arrays — return as-is (already plain JS).
    return value as Record<string, unknown>;
  }
  // Primitives — wrap for protocol consistency.
  return { value };
}

function log(level: string, ...args: unknown[]): void {
  process.stderr.write(
    JSON.stringify({ type: level, ts: new Date().toISOString(), args }) + "\n"
  );
}
