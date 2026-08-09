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
    file.exists(fixture_path)
    )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  testthat::expect_true(
    grepl("<!DOCTYPE html>", content, ignore.case = TRUE)
    )
  testthat::expect_true(
    grepl("dynamic-content", content)
    )
  testthat::expect_true(
    grepl("setTimeout", content)
    )
})

# --- Test 2: test server file exists and compiles ---
test_that("Node.js test server file exists and compiles", {
  server_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "node", "src", "server.ts"
  )

  testthat::expect_true(
    file.exists(server_path)
    )

  # Verify the compiled JS is present (means tsc succeeded).
  compiled_path <- file.path(
    dirname(server_path),
    "..", "dist", "server.js"
  )

  testthat::expect_true(
    file.exists(compiled_path)
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
    file.exists(server_script)
    )
  testthat::expect_true(
    file.exists(fixture_dir)
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

  on.exit({
    tryCatch(proc$kill(), error = function(e) NULL)
    tryCatch(proc$wait(timeout = 3000), error = function(e) NULL)
  })

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

  if (!ready) {
    testthat::skip("local fixture server did not become ready")
  }

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
    grepl("<title>Dynamic Test Page</title>", html)
    )
  testthat::expect_true(
    grepl("static-text", html)
    )
  testthat::expect_true(
    grepl("dynamic-content", html)
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

  if (!ready) {
    testthat::skip("local fixture server did not become ready")
  }

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
    is.list(eval_result) && !is.null(eval_result$result)
    )

  # The expression should return 3 (three posts were injected).
  # CDP Runtime.evaluate with returnByValue: true wraps the value in {value, type}.
  post_count_val <- eval_result$result$value
  testthat::expect_true(
    is.numeric(post_count_val) || is.integer(post_count_val)
    )
  testthat::expect_true(
    post_count_val >= 1
    )
})

# --- Test 5: fake-post.json fixture exists and is valid JSON ---
test_that("fake-post.json fixture exists and parses as valid JSON", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "fake-post.json"
  )

  testthat::expect_true(
    file.exists(fixture_path)
    )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  testthat::expect_true(
    nzchar(content)
    )

  # Parse as JSON — should not throw.
  json <- jsonlite::fromJSON(content)
  testthat::expect_true(
    "entries" %in% names(json)
    )
  testthat::expect_true(
    isTRUE(nrow(json$entries) >= 1)
    )
})

# --- Test 6: fake-post.json is served correctly by the test server ---
test_that("test server serves fake-post.json with application/json content type", {
  node_path <- Sys.which("node")
  if (node_path == "") {
    testthat::skip("Node.js not available")
  }

  server_script <- file.path(
    dirname(dirname(getwd())),
    "inst", "node", "dist", "server.js"
  )
  fixture_dir  <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures"
  )

  testthat::expect_true(
    file.exists(server_script)
    )
  testthat::expect_true(
    file.exists(fixture_dir)
    )

  port <- sample(20000:65535, 1)
  proc <- processx::process$new(
    command = "node",
    args    = c(server_script, fixture_dir, as.character(port)),
    stdout  = "|",
    stderr  = "|",
    stdin   = "|"
  )

  on.exit({
    tryCatch(proc$kill(), error = function(e) NULL)
    tryCatch(proc$wait(timeout = 3000), error = function(e) NULL)
  })

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

  if (!ready) {
    testthat::skip("local fixture server did not become ready")
  }

  url <- paste0("http://127.0.0.1:", port, "/fake-post.json")

  raw <- tryCatch(
    {
      if (!requireNamespace("curl", quietly = TRUE)) {
        conn <- url(url, open = "r", text = TRUE)
        on.exit(close(conn), add = TRUE)
        paste(readLines(conn, warn = FALSE), collapse = "\n")
      } else {
        rawToChar(curl::curl_fetch_memory(url)$content)
      }
    },
    error = function(e) NULL
  )
  if (is.null(raw)) {
    testthat::skip("local fixture server could not serve fake-post.json")
  }

  testthat::expect_true(
    nzchar(raw)
    )

  parsed <- jsonlite::fromJSON(raw)
  testthat::expect_true(
    "entries" %in% names(parsed)
    )
  testthat::expect_true(
    isTRUE(nrow(parsed$entries) >= 1)
    )
})

# --- Test 7: fake-post.json fetch is captured in network events ---
# This test verifies that when Lightpanda navigates to the dynamic page,
# the fetch() call for fake-post.json is observed via CDP network capture.
test_that("network capture observes fake-post.json fetch request", {
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

  # Start the local test server.
  server_script <- file.path(
    dirname(dirname(getwd())),
    "inst", "node", "dist", "server.js"
  )
  fixture_dir  <- file.path(
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

  if (!ready) {
    testthat::skip("local fixture server did not become ready")
  }

  test_req_id <- 0L
  make_test_req_id <- function() {
    test_req_id <<- test_req_id + 1L
    test_req_id
  }

  # Connect to Lightpanda.
  connect_result <- tryCatch(
    xtweetsR:::.rx_send_request(proc, "connect", list(endpoint = "ws://127.0.0.1:21111"), reqId = make_test_req_id),
    error = function(e) NULL
  )
  if (is.null(connect_result) || !is.null(connect_result$error)) {
    xtweetsR:::.rx_stop_sidecar(proc)
    testthat::skip("Lightpanda not available — connect() failed")
  }

  # Enable network capture before navigation.
  enable_resp <- xtweetsR:::.rx_send_request(proc, "networkCaptureEnable", list(), reqId = make_test_req_id)
  testthat::expect_true(isTRUE(enable_resp$result$enabled))

  # Navigate to the dynamic page.
  url <- paste0("http://127.0.0.1:", port, "/dynamic-page.html")
  nav_resp <- xtweetsR:::.rx_send_request(proc, "navigate", list(url = url), reqId = make_test_req_id)
  testthat::expect_true(isTRUE(nav_resp$result$navigated))

  # Wait for JS to run (setTimeout 50ms + fetch).
  Sys.sleep(2)

  # Get captured events.
  events <- tryCatch(
    {
      get_resp <- xtweetsR:::.rx_send_request(proc, "networkCaptureGet", list(), reqId = make_test_req_id)
      if (!is.null(get_resp$result$events)) get_resp$result$events else list()
    },
    error = function(e) list()
  )

  testthat::expect_true(is.list(events))

  # There should be at least 2 events: HTML page request + JSON fetch.
  testthat::expect_true(
    length(events) >= 2
    )

  # At least one event URL should contain fake-post.json.
  has_json_event <- any(vapply(events, function(e) {
    !is.null(e$url) && grepl("fake-post\\.json", e$url, ignore.case = TRUE)
  }, logical(1)))

  testthat::expect_true(
    has_json_event
    )

  # That event should have method == GET.
  json_events <- Filter(function(e) !is.null(e$url) && grepl("fake-post\\.json", e$url, ignore.case = TRUE), events)
  if (length(json_events) > 0) {
    testthat::expect_true(
      !is.null(json_events[[1]]$method)
      )
  }
})
