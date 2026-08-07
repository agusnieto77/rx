# xtweetsR Architecture

xtweetsR is an R package that controls Lightpanda (a headless browser) via the Chrome DevTools Protocol (CDP) to collect structured post data from X/Twitter. It supports search queries, user timelines, individual post lookups, network-first extraction, DOM fallback, deduplication, checkpoints, incremental persistence, and reproducible research metadata.

## High-level Design

The package uses a **process-sidecar architecture**. R launches a Node.js/TypeScript process that speaks JSONL over stdin/stdout. The sidecar uses Puppeteer's CDP WebSocket to talk to Lightpanda. This keeps browser automation code (TypeScript) separate from the R API, avoids R package binary dependencies for CDP, and isolates the async event loop from R's synchronous execution model.

```
User R code
    |
    v
R API layer (search.R, session.R, etc.)
    |
    v
Backend abstraction (backend.R)
    |
    v
Sidecar IPC (sidecar.R) -- JSONL over stdin/stdout -- processx::process
    |
    v
TypeScript sidecar (inst/node/src/)
    |
    v
CDP WebSocket -- ws://127.0.0.1:21111 -- Lightpanda
```

## R Module Overview

### `R/config.R`

Endpoint resolution for Lightpanda connection. Single public responsibility: resolve the WebSocket endpoint using a strict precedence chain.

- `.rx_resolve_endpoint(endpoint)` -- Explicit argument > `LPD_ENDPOINT` env var > default `ws://127.0.0.1:21111`. Returns a list with `endpoint`, `token`, and `source` (character string indicating which source was used).
- `.rx_get_token()` -- Reads `LPD_TOKEN` env var. Returns `NULL` if unset. Never hardcodes secrets.

Used by `backend.R` (during connect) and `session.R` (during x_session creation).

### `R/errors.R`

Structured error system using S3 class chains. Every error is a `simpleError` with a custom class chain and a `code` attribute.

Error constructors:

| Function | Class chain | Code |
|----------|-------------|------|
| `.rx_error_lpd_connection()` | `rx_lpd_connection_error`, `rx_error`, `error`, `condition` | `LPD_CONNECTION_ERROR` |
| `.rx_error_cdp()` | `rx_cdp_error`, `rx_error`, `error`, `condition` | `CDP_ERROR` |
| `.rx_error_page_load()` | `rx_page_load_error`, `rx_error`, `error`, `condition` | `PAGE_LOAD_ERROR` |
| `.rx_error_network()` | `rx_network_error`, `rx_error`, `error`, `condition` | `NETWORK_ERROR` |
| `.rx_error_parser()` | `rx_parser_error`, `rx_error`, `error`, `condition` | `PARSER_ERROR` |
| `.rx_error_timeout()` | `rx_timeout`, `rx_error`, `error`, `condition` | `TIMEOUT` |
| `.rx_error_no_new_data()` | `rx_no_new_data`, `rx_error`, `error`, `condition` | `NO_NEW_DATA` |

This lets callers use `tryCatch()` with specific error classes (e.g., `function(e) if (inherits(e, "rx_cdp_error")) ...`).

### `R/sidecar.R`

R-sidecar communication layer. Manages the TypeScript sidecar process lifecycle and implements the JSONL request/response protocol.

- `.rx_resolve_sidecar_path(sidecar_path)` -- Resolves the sidecar directory: explicit path > `system.file("node", package = "xtweetsR")` > development layout `inst/node`. Returns `NULL` if not found.
- `.rx_start_sidecar(sidecar_path)` -- Spawns `node dist/index.js` via `processx::process$new()`. Waits for a JSONL startup message (`type: "startup"`) on stderr. Returns the `processx::process` object.
- `.rx_send_request(proc, method, params, reqId)` -- Writes a JSONL request line to stdin, reads stdout matching by `id`, with a 30-second timeout. Returns a list with `$result` or `$error`.
- `.rx_stop_sidecar(proc)` -- Sends SIGTERM, escalates to SIGKILL if the process does not exit within the timeout.
- `.rx_close_browser(proc)` -- Sends a `close` method request over the protocol. Returns `{closed, reason}`.

The sidecar is the IPC bridge. Every browser operation (connect, navigate, evaluate, network capture, DOM inspect) flows through `.rx_send_request()`.

### `R/backend.R`

Abstraction layer between the public R API and Lightpanda-specific implementation. All browser operations go through a backend object.

**Factory:** `.rx_new_backend(sidecar_path)` returns an R environment with the following methods:

| Method | Description |
|--------|-------------|
| `$connect(endpoint, token)` | Starts the sidecar, resolves endpoint via `config.R`, connects to CDP |
| `$navigate(url)` | Navigates to a URL, returns `{url, status, result}` |
| `$evaluate(expr)` | Evaluates JavaScript, returns `{result, error}` |
| `$domInspect(selector)` | Returns full page HTML (if `selector = NULL`) or matched elements as a data frame |
| `$networkCaptureEnable()` | Enables CDP Network domain |
| `$networkCaptureGet()` | Returns captured events, clears the main buffer |
| `$networkCaptureGetBody(requestId)` | Fetches response body via `Network.getResponseBody`; auto-parses JSON |
| `$networkCaptureClear()` | Disables CDP Network domain, clears all state |
| `$close()` | Closes the browser, stops the sidecar process |

The backend is an R **environment** (not a list), so mutations to `$connected` propagate to the caller. Each backend has a monotonic request ID counter for matching requests to responses.

### `R/session.R`

Public session management.

- **`x_session(endpoint, sidecar_path, quiet)`** -- Creates a browser session. Starts the sidecar, resolves the endpoint, connects the backend. Returns an environment with `$backend`, `$endpoint`, `$connected`, and `$close()`. Has a finalizer registered via `.onExit()` to prevent orphaned sidecar processes if the R session crashes.
- **`x_close(session, quiet)`** -- Explicitly closes a session (browser + sidecar).
- **`print.xtweetsR_session`** (S3 method) -- Displays backend type, endpoint, and connection status.

Session is the handle passed to all public API functions: `x_search()`, `x_post()`, `x_user_posts()`, `x_debug_network()`, `x_debug_dom()`.

### `R/doctor.R`

Diagnostic tooling.

- **`x_doctor()`** -- Runs 8 independent checks:
  1. R version
  2. Node.js presence
  3. Sidecar start + ping
  4. Lightpanda CDP connection
  5. CDP session (connect + close proves session alive)
  6. JavaScript evaluation (`1 + 1`)
  7. Network capture (enables CDP Network domain)
  8. X navigation (navigate to `https://x.com`)

Checks 1-2 are standalone. Check 3 starts its own sidecar instance. Checks 4-8 are skipped (`n/a`) if check 3 fails (sidecar dependency). Each check is isolated -- a failure in one does not prevent later checks from running.

Returns a list with class `rx_doctor` containing `checks`, `results` ("ok", "missing", "error", or "n/a"), and `details` vectors.

### `R/search.R`

The core collection engine. Contains the main public API and the scroll/deduplication loop.

**Public functions:**

- **`x_search(session, query, limit, scroll, max_scrolls, resume, checkpoint_path, jsonl_path, quiet)`** -- Navigates to an X search URL, captures network responses, parses/normalizes posts, deduplicates, and returns a tibble.
- **`x_user_posts(session, username, limit, path, scroll, max_scrolls, resume, checkpoint_path, jsonl_path, quiet)`** -- Fetches posts from a user's timeline. Reuses the same pipeline as `x_search()`.
- **`x_post(session, post_id, limit, quiet)`** -- Fetches a single post by URL or bare post ID.

**Search pipeline:**

1. Enable network capture (`$networkCaptureEnable()`)
2. Construct URL via `search_url.R`, navigate (`$navigate()`)
3. Wait 3 seconds for async content to load
4. Extract initial batch from network events (`.rx_search_extract_from_events()`)
5. Bounded scroll loop: scroll, wait 3s, extract, deduplicate, check limit/stall
6. Merge all batches
7. Inject observation-level provenance (`collected_at`, `collection_query`, `collection_id`)
8. Normalize -> tibble -> deduplicate -> apply limit
9. Write checkpoint (if `resume = TRUE`)
10. Attach `rx_collection_provenance` as an attribute on the result tibble

**Scroll state:** `.rx_scroll_state_new()` creates an R environment with methods for tracking `seen_post_ids`, `current_count`, `previous_count`, `no_new_data_cycles`, `scroll_position`, `last_post_id`, `last_cursor`, `started_at`, and `elapsed_time`. The loop is bounded: it stops when `limit` is reached or when `no_new_data_cycles >= max_scrolls` (default 5).

**Network extraction:** `.rx_search_extract_from_events()` filters captured events using `.rx_search_is_candidate()` -- a heuristic that matches X/Twitter domain + JSON content type or `/graphql`/`/internal.alg.com` URL paths.

### `R/parser.R`

Parses X/Twitter GraphQL search response structure into structured post data.

- **`.rx_validate_response_schema(response)`** -- Detects X response structure changes. Checks: (1) missing `data$timeline$instructions` or no `TimelineAddEntries`, (2) entries exist but zero valid post objects, (3) incompatible field types. Throws `PARSER_ERROR` on detection.
- **`.rx_parse_posts(response)`** -- Main parser. Walks `data$timeline$instructions`, finds `TimelineAddEntries`, extracts tweet objects from `content$itemContent$tweet_results$result`. Returns a list of 23 fields.

**Extractor helpers:**

| Function | Extracts |
|----------|----------|
| `.rx_find_tweet_result()` | Navigates to the tweet result object |
| `.rx_extract_author_id()` | From `core.user_results.result.id` |
| `.rx_extract_username()` | From `core.user_results.result.legacy.screen_name` |
| `.rx_extract_display_name()` | From `core.user_results.result.legacy.name` |
| `.rx_extract_int()` | Integer metric from legacy object |
| `.rx_extract_view_count()` | Nested `legacy$views$count` |
| `.rx_extract_bool()` | Boolean flag from legacy |
| `.rx_extract_cursors()` | Pagination cursors from `TimelineAddToModule` |
| `.rx_extract_hashtags()` | From `entities$hashtags` |
| `.rx_extract_mentions()` | From `entities$user_mentions` |
| `.rx_extract_urls()` | From `entities$urls`, prefers `expanded_url` |
| `.rx_extract_media_types()` | From `extended_entities$media` |
| `.rx_extract_media_urls()` | Photo URLs or video variant URLs |

Parser version: `"0.1.0"` -- bumped when output schema changes.

### `R/normalizer.R`

Converts parsed raw posts into a stable canonical 26-field schema.

**Canonical field list (defined by `.rx_canonical_fields()`):**

| Field | Type | NA default |
|-------|------|------------|
| `post_id` | character | `NA_character_` |
| `text` | character | `NA_character_` |
| `author_id` | character | `NA_character_` |
| `username` | character | `NA_character_` |
| `display_name` | character | `NA_character_` |
| `created_at` | character | `NA_character_` |
| `reply_count` | integer | `0L` |
| `repost_count` | integer | `0L` |
| `like_count` | integer | `0L` |
| `quote_count` | integer | `0L` |
| `bookmark_count` | integer | `0L` |
| `view_count` | integer | `0L` |
| `conversation_id` | character | `NA_character_` |
| `is_reply` | logical | `FALSE` |
| `is_repost` | logical | `FALSE` |
| `is_quote` | logical | `FALSE` |
| `reply_to_post_id` | character | `NA_character_` |
| `quoted_post_id` | character | `NA_character_` |
| `hashtags` | list (character) | `list(NULL)` |
| `mentions` | list (character) | `list(NULL)` |
| `urls` | list (character) | `list(NULL)` |
| `media_type` | list (character) | `list(NULL)` |
| `media_urls` | list (character) | `list(NULL)` |
| `collected_at` | character | `NA_character_` |
| `collection_query` | character | `NA_character_` |
| `collection_id` | character | `NA_character_` |

**Functions:**

- `.rx_type_map()` -- Maps field name to expected R type.
- `.rx_na_defaults()` -- Returns NA defaults per field.
- `.rx_normalize_posts(parsed)` -- Coerces each field to expected type, pads to `post_id` length, reorders to canonical order. Returns empty list for NULL/invalid input.
- `.rx_coerce(raw, expected_type, n, na_val)` -- Truncates/pads and coerces type.
- `.rx_empty_normalized(fields, na_defs)` -- Zero-length vectors for all fields.
- `.rx_normalized_to_tibble(normalized)` -- Converts list-of-vectors to tibble.
- `.rx_deduplicate_posts(posts)` -- Removes duplicate `post_id` rows, first-seen order.
- `.rx_deduplicate_tibble(tbl)` -- Uses `!duplicated(tbl$post_id)`.

### `R/persistence.R`

JSONL append-only persistence and checkpoint state management. Independent from Arrow/DuckDB (optional formats).

- `.rx_jsonl_write(path, posts, append = TRUE)` -- Serializes each tibble row as a JSON object, appends to file.
- `.rx_jsonl_read(path)` -- Reads JSONL lines, reconstructs tibble with type inference from the first line.
- `.rx_jsonl_empty_tibble()` -- Zero-row tibble with the canonical schema.
- `.rx_checkpoint_from_state(state, collection_id, query)` -- Converts scroll state to serializable `{collection_id, query, seen_post_ids, last_cursor, last_post_id, records_collected}`.
- `.rx_checkpoint_write(path, checkpoint)` -- Writes checkpoint as pretty JSON (overwrite mode).
- `.rx_checkpoint_read(path)` -- Parses JSON checkpoint, validates required fields, returns an `rx_checkpoint` object or `NULL` if the file is missing.

### `R/export.R`

Export functions for saving collected data.

- **`x_save(posts, path)`** -- Saves post tibble to disk. Format is inferred from the file extension:
  - `.parquet` -- Uses `arrow::write_parquet()`. Falls back to JSONL with a warning if Arrow is not installed.
  - `.duckdb` -- Creates a DuckDB database with a `posts` table. Falls back to JSONL with a warning if DuckDB is not installed.
  - `.jsonl` -- Uses jsonlite (always available).

Internal functions:

- `.rx_save_parquet(posts, path)` -- Arrow-backed parquet save.
- `.rx_save_duckdb(posts, path)` -- Creates DuckDB with a `posts` table; drops the table first to guarantee a clean canonical schema.
- `.rx_duckdb_read(path)` -- Reads the DuckDB `posts` table back into a tibble. Returns an empty canonical tibble if the file is missing or DuckDB is unavailable.

### `R/search_url.R`

URL construction helpers for X/Twitter.

- `.rx_construct_search_url(query, from_user, filter)` -- Builds `https://x.com/search?q=<encoded>`. Supports `from:<username>` and raw filter syntax.
- `.rx_normalize_post_url(url_or_id)` -- Accepts a full post URL or bare post ID, returns a canonical `https://x.com/status/<id>`. Handles `x.com` URLs, legacy `twitter.com` URLs, and `t.co` short links (returned as-is). Bare IDs of 15-20 digits are treated as post IDs.
- `.rx_construct_post_url(post_id)` -- Builds `https://x.com/status/<id>` from a numeric post ID.
- `.rx_construct_user_timeline_url(username, path, filter)` -- Builds `https://x.com/<username>[/<path>][?<filter>]`. Strips leading `@` from username.

### `R/debug.R`

Development and debugging tools.

- **`x_debug_network(session)`** -- Returns a data frame of captured network events (requestId, url, method, resourceType, status, protocol, cache flags, contentType). Clears the capture buffer after reading.
- **`x_debug_dom(session, selector)`** -- Returns full page HTML (if `selector = NULL`) or matched elements as a data frame (index, tagName, id, className, outerHTML).

Both functions use `session$backend$networkCaptureGet()` and `session$backend$domInspect()` respectively.

### `R/xtweetsR-package.R`

Package-level documentation stub. Declares the `xtweetsR` keyword and imports `utils::packageVersion`.

## TypeScript Sidecar Architecture

The sidecar lives in `inst/node/src/`. It is compiled with TypeScript in strict mode and distributed as a single `dist/index.js` entry point.

### Protocol (JSONL over stdin/stdout)

```
Request:  { "id": <number>, "method": string, "params": <any>? }
Response: { "id": <same>, "result": <any> }
Error:    { "id": <same>, "error": { "code": string, "message": string } }
Log:      Written to stderr only
```

The main loop reads lines from stdin, dispatches to method handlers, and writes the response to stdout. All log output goes to stderr.

### Available Methods

| Method | Async | Description |
|--------|-------|-------------|
| `ping` | No | Returns `{pong: true, version: "0.1.0"}` |
| `connect` | Yes | Connects to Lightpanda CDP endpoint. SSRF-guarded (ws/wss + loopback only) |
| `close` | No | Closes CDP connection. Idempotent |
| `navigate` | Yes | Navigates to HTTP(S) URL. SSRF-guarded. 30s timeout |
| `evaluate` | Yes | Evaluates JavaScript via `Runtime.evaluate`. Returns `{evaluated: true, result}` |
| `networkCaptureEnable` | Yes | Enables CDP Network domain, registers `Network.requestWillBeSent` and `Network.responseReceived` listeners |
| `networkCaptureGet` | No | Returns a snapshot of captured events, clears the main buffer |
| `networkCaptureClear` | Yes | Disables CDP Network domain, removes listeners, clears all state |
| `networkCaptureGetBody` | Yes | Uses `Network.getResponseBody` CDP command. Auto-parses JSON for `application/json` |
| `domInspect` | Yes | Evaluates `document.documentElement.outerHTML` (full HTML) or `document.querySelectorAll` (selector mode) |

### Error Codes

`PARSE_ERROR`, `INVALID_REQUEST`, `UNKNOWN_METHOD`, `LPD_CONNECTION_ERROR`, `CDP_ERROR`, `PAGE_LOAD_ERROR`, `JS_EXCEPTION`, `NETWORK_ERROR`, `ABORTED`, `ALREADY_CONNECTING`, `REQUEST_ID_NOT_FOUND`.

### SSRF Protection

**Connect:** Validates WebSocket URL scheme (ws/wss only), rejects userinfo, allows only loopback addresses (localhost, 127.x.x.x, ::1, [127.x.x.x]).

**Navigate:** Validates HTTP(S) only, rejects userinfo, blocks RFC 1918 private ranges, link-local, carrier-grade NAT, documentation ranges, IPv6 private ranges, numeric IP obfuscation patterns, and IPv4-mapped IPv6.

### Concurrency Safety

A generation counter (`connectGen`) prevents stale connect operations after `close()`. A `connecting` flag prevents concurrent connect attempts.

### CDP Connection Layer

`inst/node/src/browser/connection.ts` provides a `DefaultCdpConnection` class:

- `connect(endpointUrl)` -- Creates a WebSocket, waits for the `open` event. 30s timeout.
- `sendCommand(method, params)` -- Dispatches a CDP command with an incrementing ID, waits for the response via a pending map with a 30s timeout.
- `on(event, listener)` / `removeListener(event, listener)` -- Event emitter for CDP events (`Page.loadEventFired`, `Network.requestWillBeSent`, etc.) and `close`.
- Message handler distinguishes responses (have `id`) from events (have `method`), routes accordingly.

### Test Infrastructure

- **`protocol.test.ts`** -- Node.js tests for the JSONL protocol: ping/pong, unknown method error, malformed JSON, process shutdown, connect/close error paths, parameter validation.
- **`server.ts`** -- Static file test server for local testing. Not shipped with the package.
- **`task27-navigate-x.ts`**, **`task28-open-x-search.ts`**, **`task29-capture-x-network.ts`** -- Development scripts for live X testing. Not shipped with the package.

## Data Flow: End-to-End

Here is how `x_search(sess, "R language")` processes a search:

```
User calls x_search(sess, "R language")
    |
    v
search.R: x_search()
  - Validates inputs
  - Constructs search URL via search_url.R
  - Enables network capture via backend
    |
    v
backend.R: $connect() -> starts sidecar via sidecar.R
  |
  v
sidecar.R: .rx_start_sidecar() -- spawns node dist/index.js
    |
    v
backend.R: $navigate(url)
  |
  v
sidecar.R: .rx_send_request(proc, "navigate", {url})
    |
    v
index.ts: handleNavigate() -- sends CDP Page.navigate
    |
    v
browser/connection.ts -- CDP command over WebSocket to Lightpanda
    |
    v
[Lightpanda browser] -- loads x.com/search, triggers XHR/fetch requests
    |
    v
index.ts: handleNetworkCaptureEnable() -- listeners capture Network events
    |
    v
backend.R: $networkCaptureGet() -- returns captured events to R
    |
    v
search.R: .rx_search_extract_from_events(events, backend)
  - Filters events: X-domain + JSON content type OR /graphql path
  - For each candidate: $networkCaptureGetBody(requestId)
  - Calls .rx_parse_posts() on each JSON body
    |
    v
parser.R: .rx_parse_posts(response)
  - Validates schema (.rx_validate_response_schema)
  - Walks data$timeline$instructions -> TimelineAddEntries
  - Extracts tweet objects from tweet_results.result
  - Returns list of 23-field post objects
    |
    v
normalizer.R: .rx_normalize_posts(parsed)
  - Coerces types, pads missing values, orders to canonical 26-field schema
  |
  v
normalizer.R: .rx_normalized_to_tibble(normalized)
  |
  v
normalizer.R: .rx_deduplicate_posts(tibble)
  - Removes duplicate post_id rows
    |
    v
search.R: Bounded scroll loop
  - scrollPage(), extract(), merge(), check_limit(), check_stalled()
  |
    v
search.R: Inject observation provenance (collected_at, collection_query, collection_id)
  |
  v
search.R: Apply limit, write checkpoint (if resume)
  |
  v
search.R: Attach rx_collection_provenance as attribute
  |
  v
Returns tibble (with provenance attribute)
```

## Canonical Schema

The output of every collection function (`x_search`, `x_user_posts`, `x_post`) is a `tibble` with exactly 26 columns in a fixed order. Missing data is represented as `NA` (character/logical fields) or `0` (integer fields), never as `NULL` at the column level. List-columns (hashtags, mentions, urls, media_type, media_urls) use `list(NULL)` for posts without that data.

The tibble carries an `rx_collection_provenance` attribute (class `rx_collection_provenance`) containing:

- `collection_id` -- UUID v4
- `started_at` -- POSIXct timestamp
- `query` -- The search query string
- `package_version` -- Package version string
- `backend` -- `"lightpanda"` / `"chromium"` / `"unknown"`
- `parser_version` -- `"0.1.0"`
- `schema_version` -- Internal schema version string
- `records` -- Integer count of records in the tibble

## Module Dependencies

```
xtweetsR-package.R  (docs only)
config.R            <- backend.R, session.R
errors.R            <- (all modules)
sidecar.R           <- backend.R, doctor.R, session.R
backend.R           <- config.R, sidecar.R, errors.R
session.R           <- backend.R, sidecar.R, config.R, errors.R
doctor.R            <- backend.R, sidecar.R, errors.R
search_url.R        <- search.R
parser.R            <- search.R, errors.R
normalizer.R        <- search.R, persistence.R
persistence.R       <- search.R, export.R
export.R            <- normalizer.R, persistence.R, errors.R
search.R            <- config.R, backend.R, parser.R, normalizer.R,
                       persistence.R, search_url.R, errors.R
debug.R             <- session.R, backend.R
```

## Testing

Tests live under `tests/testthat/`. Each major module has a corresponding test file:

| Test file | Covers |
|-----------|--------|
| `test-parser.R` | Post extraction, field validation, schema-change detection, cursor extraction |
| `test-normalizer.R` | Type coercion, canonical schema, deduplication, tibble output |
| `test-search.R` | Scroll state, dedup across batches, limit enforcement, resume, mock scenarios |
| `test-search-url.R` | URL construction for search, user timeline, post URLs |
| `test-user-posts.R` | Input validation, navigation failure, fixture integration, limit |
| `test-post-url.R` | URL normalization, post URL construction, input validation, navigation |
| `test-persistence.R` | JSONL write/read, checkpoint round-trip, resume support |
| `test-export.R` | Parquet round-trip, DuckDB, JSONL fallback, input validation |
| `test-errors.R` | S3 class chains, error code attributes, tryCatch narrow/wide catches |
| `test-doctor.R` | All 8 diagnostic checks, independence, determinism |
| `test-protocol.ts` | JSONL protocol: ping, unknown method, malformed JSON, process shutdown |

The mock infrastructure (`_mock-infinite-scroll.R`) provides `rx_mock_batch()`, `rx_mock_session()`, and `rx_mock_realistic_scenario()` for testing collection logic without a live X connection.

## Configuration

| Mechanism | Description | Default |
|-----------|-------------|---------|
| `endpoint` argument | Explicit WebSocket URL | -- |
| `LPD_ENDPOINT` env var | Environment variable override | -- |
| Built-in default | Fallback endpoint | `ws://127.0.0.1:21111` |
| `LPD_TOKEN` env var | Optional authentication token | `NULL` |
| `sidecar_path` argument | Explicit sidecar directory | Package-installed `inst/node` |
| `quiet` parameter | Suppress progress messages | `FALSE` |
| `scroll` parameter | Enable scroll-based collection | `TRUE` |
| `max_scrolls` parameter | Maximum scroll iterations | `5` |
| `limit` parameter | Maximum number of posts to return | `100` |
| `resume` parameter | Resume from a checkpoint | `FALSE` |
| `checkpoint_path` | Path for checkpoint JSON | Auto-generated temp file |
| `jsonl_path` | Path for JSONL incremental writes | Auto-generated temp file |
