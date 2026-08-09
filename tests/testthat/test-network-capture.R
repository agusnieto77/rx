# Tests for CDP network event capture (Task 21).
# Verifies that:
# 1. networkCaptureEnable enables CDP Network domain events.
# 2. networkCaptureGet returns structured event data.
# 3. networkCaptureClear resets captured events.
# 4. Events contain expected fields (requestId, url, method, resourceType).
# 5. networkCaptureGetBody retrieves response bodies.

# Load the package in development mode so internal functions are available.
if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
}

# --- Test 1: network capture methods exist on the backend ---
test_that("backend has network capture methods", {
  backend <- .rx_new_backend()
  testthat::expect_true(is.function(backend$networkCaptureEnable))
  testthat::expect_true(is.function(backend$networkCaptureGet))
  testthat::expect_true(is.function(backend$networkCaptureGetBody))
  testthat::expect_true(is.function(backend$networkCaptureClear))
})

# --- Test 2: networkCaptureEnable requires connection ---
test_that("networkCaptureEnable fails when not connected", {
  backend <- .rx_new_backend()
  testthat::expect_error(
    backend$networkCaptureEnable(),
    "not connected",
    fixed = TRUE
  )
})

# --- Test 3: networkCaptureGet returns structured data after navigation ---
# This test requires both the sidecar and a running server with a fixture.
# If Lightpanda is not available, skip.
test_that("network events are captured when navigating to the local fixture", {
  # Start sidecar.
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

  # Start the local test server on a random port.
  server_script <- file.path(
    dirname(dirname(getwd())),
    "inst", "node", "dist", "server.js"
  )
  fixture_dir <- file.path(
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

  # Per-test request ID counter.
  test_req_id <- 0L
  make_test_req_id <- function() {
    test_req_id <<- test_req_id + 1L
    test_req_id
  }

  # Connect to Lightpanda (skip if not available).
  connect_result <- tryCatch(
    xtweetsR:::.rx_send_request(proc, "connect", list(endpoint = "ws://127.0.0.1:21111"), reqId = make_test_req_id),
    error = function(e) NULL
  )
  if (is.null(connect_result) || !is.null(connect_result$error)) {
    xtweetsR:::.rx_stop_sidecar(proc)
    testthat::skip("Lightpanda not available — connect() failed")
  }

  # Enable network capture.
  enable_resp <- xtweetsR:::.rx_send_request(proc, "networkCaptureEnable", list(), reqId = make_test_req_id)
  testthat::expect_false(is.null(enable_resp$result$enabled))
  testthat::expect_true(isTRUE(enable_resp$result$enabled))

  # Navigate to the local fixture.
  url <- paste0("http://127.0.0.1:", port, "/dynamic-page.html")
  nav_resp <- xtweetsR:::.rx_send_request(proc, "navigate", list(url = url), reqId = make_test_req_id)
  testthat::expect_false(is.null(nav_resp$result$navigated))
  testthat::expect_true(isTRUE(nav_resp$result$navigated))

  # Wait for network events to be captured (give the page time to load resources).
  Sys.sleep(1)

  # Get captured events.
  events <- tryCatch(
    {
      get_resp <- xtweetsR:::.rx_send_request(proc, "networkCaptureGet", list(), reqId = make_test_req_id)
      if (!is.null(get_resp$result$events)) get_resp$result$events else list()
    },
    error = function(e) list()
  )

  testthat::expect_true(is.list(events))

  # Events should not be empty — at minimum we should see the HTML page request.
  testthat::expect_true(
    length(events) >= 1
    )

  # Each event must have a requestId.
  for (ev in events) {
    testthat::expect_true("requestId" %in% names(ev))
    testthat::expect_true(nzchar(ev$requestId))
  }

  # At least one event should have a URL.
  has_url <- any(vapply(events, function(e) !is.null(e$url) && nzchar(e$url), logical(1)))
  testthat::expect_true(has_url)

  # At least one event should have a method.
  has_method <- any(vapply(events, function(e) !is.null(e$method) && nzchar(e$method), logical(1)))
  testthat::expect_true(has_method)

  # At least one event should have a resourceType.
  has_type <- any(vapply(events, function(e) !is.null(e$resourceType) && nzchar(e$resourceType), logical(1)))
  testthat::expect_true(has_type)
})

# --- Test 4: networkCaptureClear resets events ---
test_that("networkCaptureClear resets the captured events buffer", {
  # This test uses a mock approach — directly test the sidecar methods
  # via JSONL since network capture requires an active Lightpanda connection.
  # We'll verify clear works on the empty buffer (which is always safe).
  proc <- tryCatch(
    {
      p <- xtweetsR:::.rx_start_sidecar()
      if (!p$is_alive()) { NULL } else { p }
    },
    error = function(e) NULL
  )

  if (is.null(proc)) {
    testthat::skip("sidecar cannot start")
  }

  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  # Clear should always succeed even without a connection.
  test_req_id <- 0L
  make_test_req_id <- function() {
    test_req_id <<- test_req_id + 1L
    test_req_id
  }

  clear_resp <- tryCatch(
    xtweetsR:::.rx_send_request(proc, "networkCaptureClear", list(), reqId = make_test_req_id),
    error = function(e) NULL
  )

  testthat::expect_false(is.null(clear_resp$result$cleared))
  testthat::expect_true(isTRUE(clear_resp$result$cleared))
})

# --- Test 5: networkCaptureGetBody method exists on the backend ---
test_that("backend has networkCaptureGetBody method", {
  backend <- .rx_new_backend()
  testthat::expect_true(is.function(backend$networkCaptureGetBody))
})

# --- Test 6: networkCaptureGetBody requires connection ---
test_that("networkCaptureGetBody fails when not connected", {
  backend <- .rx_new_backend()
  testthat::expect_error(
    backend$networkCaptureGetBody("fake-id"),
    "not connected",
    fixed = TRUE
  )
})

# --- Test 7: response body is captured and parsed as JSON ---
# This test verifies that the fake-post.json response body is captured
# via CDP Network.getResponseBody and returned as parsed JSON to R.
test_that("response body is captured for JSON network requests", {
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
  fixture_dir <- file.path(
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

  # Per-test request ID counter.
  test_req_id <- 0L
  make_test_req_id <- function() {
    test_req_id <<- test_req_id + 1L
    test_req_id
  }

  # Connect to Lightpanda (skip if not available).
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

  # Navigate to the dynamic page (it fetches fake-post.json via fetch()).
  url <- paste0("http://127.0.0.1:", port, "/dynamic-page.html")
  nav_resp <- xtweetsR:::.rx_send_request(proc, "navigate", list(url = url), reqId = make_test_req_id)
  testthat::expect_true(isTRUE(nav_resp$result$navigated))

  # Wait for JS to run (setTimeout 50ms + fetch).
  Sys.sleep(2)

  # Get captured events to find the fake-post.json requestId.
  events <- tryCatch(
    {
      get_resp <- xtweetsR:::.rx_send_request(proc, "networkCaptureGet", list(), reqId = make_test_req_id)
      if (!is.null(get_resp$result$events)) get_resp$result$events else list()
    },
    error = function(e) list()
  )

  # Find the event for fake-post.json.
  json_events <- Filter(function(e) {
    !is.null(e$url) && grepl("fake-post\\.json", e$url, ignore.case = TRUE)
  }, events)

  testthat::expect_true(
    length(json_events) > 0
    )

  if (length(json_events) == 0) {
    testthat::skip("no fake-post.json event found, skipping body capture test")
  }

  json_req_id <- json_events[[1]]$requestId
  testthat::expect_true(nzchar(json_req_id))

  # Get the response body using the requestId.
  body_resp <- tryCatch(
    {
      xtweetsR:::.rx_send_request(
        proc,
        "networkCaptureGetBody",
        list(requestId = json_req_id),
        reqId = make_test_req_id
      )
    },
    error = function(e) NULL
  )

  testthat::expect_false(is.null(body_resp))

  # The body should be parsed JSON (jsonlite returns a list).
  testthat::expect_false(
    is.null(body_resp$result$body)
    )

  testthat::expect_true(
    is.list(body_resp$result$body)
    )

  # The parsed body should contain the 'entries' field.
  body <- body_resp$result$body
  testthat::expect_true(
    "entries" %in% names(body)
    )

  # The parsed body should have at least one post entry.
  testthat::expect_true(
    isTRUE(nrow(body$entries) >= 1)
    )

  # Content type should be application/json.
  testthat::expect_true(
    identical(body_resp$result$contentType, "application/json")
    )

  # Error should be null.
  testthat::expect_true(
    is.null(body_resp$result$error)
    )
})
