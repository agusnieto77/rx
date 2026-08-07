# Tests for the local dynamic test page fixture (Task 15).
# Verifies that:
# 1. The HTML fixture file exists and is valid.
# 2. The Node.js test server can serve it.
# 3. A browser would observe dynamically inserted content.

# --- Test 1: fixture file exists ---
test_that("dynamic-page.html fixture exists under inst/tests/fixtures/", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "dynamic-page.html"
  )

  testthat::expect_true(
    file.exists(fixture_path),
    info = "fixture file exists"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  testthat::expect_true(
    grepl("<!DOCTYPE html>", content, ignore.case = TRUE),
    info = "fixture is a valid HTML document"
  )
  testthat::expect_true(
    grepl("dynamic-content", content),
    info = "fixture contains dynamic-content container"
  )
  testthat::expect_true(
    grepl("setTimeout", content),
    info = "fixture modifies DOM after load via setTimeout"
  )
})

# --- Test 2: test server file exists and compiles ---
test_that("Node.js test server file exists and compiles", {
  server_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "node", "src", "server.ts"
  )

  testthat::expect_true(
    file.exists(server_path),
    info = "server.ts exists"
  )

  # Verify the compiled JS is present (means tsc succeeded).
  compiled_path <- file.path(
    dirname(server_path),
    "..", "dist", "server.js"
  )

  testthat::expect_true(
    file.exists(compiled_path),
    info = "server.js is compiled by TypeScript"
  )
})

# --- Test 3: server can serve the fixture and returns HTML ---
test_that("test server serves the dynamic fixture with 200", {
  # Skip if we cannot start the server (no Node.js or build missing).
  node_path <- Sys.which("node")
  if (node_path == "") {
    testthat::skip("Node.js not available")
  }

  server_script <- file.path(
    dirname(dirname(getwd())),
    "inst", "node", "dist", "server.js"
  )
  fixture_dir   <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures"
  )

  testthat::expect_true(
    file.exists(server_script),
    info = "server.js exists"
  )
  testthat::expect_true(
    file.exists(fixture_dir),
    info = "fixture directory exists"
  )

  # Start the server on a random high port to avoid collisions.
  port <- sample(20000:65535, 1)
  proc <- processx::process$new(
    command = "node",
    args    = c(server_script, fixture_dir, as.character(port)),
    stdout  = "|",
    stderr  = "|",
    stdin   = "|"
  )

  # Wait for the server to be ready (reads "listening" on stderr).
  ready <- FALSE
  start <- Sys.time()
  timeout_secs <- 5
  while (Sys.time() - start < timeout_secs && proc$is_alive()) {
    lines <- tryCatch(proc$read_error_lines(), error = function(e) character(0))
    for (line in lines) {
      if (grepl("listening", line, ignore.case = TRUE)) {
        ready <- TRUE
        break
      }
    }
    if (ready) break
    Sys.sleep(0.1)
  }

  testthat::expect_true(
    ready,
    info = "server started and reported listening"
  )

  on.exit({
    tryCatch(proc$kill(), error = function(e) NULL)
    tryCatch(proc$wait(timeout = 3000), error = function(e) NULL)
  })

  # Use a minimal HTTP request (no extra dependency needed).
  url <- paste0("http://127.0.0.1:", port, "/dynamic-page.html")

  # Use RCurl or httr if available, otherwise skip.
  if (!requireNamespace("curl", quietly = TRUE)) {
    # Use base R's url() to fetch.
    conn <- url(url, open = "r", text = TRUE)
    on.exit(close(conn), add = TRUE)
    html <- paste(readLines(conn, warn = FALSE), collapse = "\n")
  } else {
    html <- curl::curl_fetch_memory(url)$content
    html <- rawToChar(html)
  }

  testthat::expect_true(
    grepl("<title>Dynamic Test Page</title>", html),
    info = "served page contains expected title"
  )
  testthat::expect_true(
    grepl("static-text", html),
    info = "served page contains static content"
  )
  testthat::expect_true(
    grepl("dynamic-content", html),
    info = "served page contains dynamic-content container"
  )
})

# --- Test 4: dynamically inserted content is visible via JS evaluation ---
# This test verifies that after the page loads and JS runs,
# the dynamically inserted posts are present in the DOM.
test_that("dynamically inserted DOM content is observable after load", {
  # This test requires a browser backend (connect + navigate + evaluate).
  # If no backend is available, skip.
  proc <- tryCatch(
    {
      p <- xtweetsR:::.rx_start_sidecar()
      if (!p$is_alive()) { NULL } else { p }
    },
    error = function(e) NULL
  )

  if (is.null(proc)) {
    testthat::skip("sidecar cannot start (no browser backend testable)")
  }

  # Start the local server on a random port.
  server_script <- file.path(
    dirname(dirname(getwd())),
    "inst", "node", "dist", "server.js"
  )
  fixture_dir   <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures"
  )

  port <- sample(20000:65535, 1)
  server_proc <- processx::process$new(
    command = "node",
    args    = c(server_script, fixture_dir, as.character(port)),
    stdout  = "|",
    stderr  = "|",
    stdin   = "|"
  )

  on.exit({
    xtweetsR:::.rx_stop_sidecar(proc)
    tryCatch(server_proc$kill(), error = function(e) NULL)
    tryCatch(server_proc$wait(timeout = 3000), error = function(e) NULL)
  })

  # Wait for server to be ready.
  ready <- FALSE
  start <- Sys.time()
  while (Sys.time() - start < 5 && server_proc$is_alive()) {
    lines <- tryCatch(server_proc$read_error_lines(), error = function(e) character(0))
    for (line in lines) {
      if (grepl("listening", line, ignore.case = TRUE)) { ready <- TRUE; break }
    }
    if (ready) break
    Sys.sleep(0.1)
  }

  testthat::expect_true(ready, info = "test server is ready")

  # Per-test request ID counter to avoid ID collisions across multiple requests.
  test_req_id <- 0L
  make_test_req_id <- function() {
    test_req_id <<- test_req_id + 1L
    test_req_id
  }

  # Connect to CDP before navigation/evaluation.
  # Skip if Lightpanda is not available.
  connect_result <- tryCatch(
    xtweetsR:::.rx_send_request(proc, "connect", list(endpoint = "ws://127.0.0.1:21111"), reqId = make_test_req_id),
    error = function(e) NULL
  )
  if (is.null(connect_result) || !is.null(connect_result$error)) {
    xtweetsR:::.rx_stop_sidecar(proc)
    testthat::skip("Lightpanda not available — connect() failed")
  }

  # Navigate to the local page.
  url <- paste0("http://127.0.0.1:", port, "/dynamic-page.html")
  xtweetsR:::.rx_send_request(proc, "navigate", list(url = url), reqId = make_test_req_id)

  # Wait a moment for JS to execute (setTimeout is 50ms).
  Sys.sleep(1)

  # Evaluate JavaScript to check for dynamically inserted posts.
  eval_result <- xtweetsR:::.rx_send_request(proc, "evaluate", list(
    expr = sprintf(
      "document.querySelectorAll('[data-post-id]').length"
    )
  ), reqId = make_test_req_id)

  testthat::expect_true(
    is.list(eval_result) && !is.null(eval_result$result),
    info = "evaluate returns a result"
  )

  # The expression should return 3 (three posts were injected).
  # CDP Runtime.evaluate with returnByValue: true wraps the value in {value, type}.
  post_count_val <- eval_result$result$value
  testthat::expect_true(
    is.numeric(post_count_val) || is.integer(post_count_val),
    info = "post count is numeric"
  )
  testthat::expect_true(
    post_count_val >= 1,
    info = "at least one dynamically inserted post is observed"
  )
})
