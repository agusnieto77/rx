# Tests for x_debug_dom() and the domInspect sidecar method.
#
# Covers:
#   - Sidecar responds to domInspect with full HTML when no selector
#   - Sidecar responds to domInspect with element matches when selector provided
#   - R x_debug_dom() returns correct data frame structures
#   - Pre-connect guard rejects domInspect
#   - Selector returns empty data frame when nothing matches

test_req_id <- 0L
make_test_req_id <- function() {
  test_req_id <<- test_req_id + 1L
  test_req_id
}

# --- Test 1: sidecar domInspect returns full HTML ---
test_that("sidecar domInspect returns full HTML for a loaded page", {
  skip_on_os("windows") # Local test server setup may differ on Windows

  # Start the sidecar.
  sc_dir <- system.file("node", package = "xtweetsR")
  proc <- tryCatch(
    xtweetsR:::.rx_start_sidecar(sidecar_path = sc_dir),
    error = function(e) NULL
  )
  if (is.null(proc)) {
    testthat::skip("sidecar failed to start")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  # Connect to Lightpanda (skip if unavailable).
  conn_resp <- tryCatch(
    xtweetsR:::.rx_send_request(proc, "connect", list(), reqId = make_test_req_id()),
    error = function(e) NULL
  )
  if (is.null(conn_resp) || !is.null(conn_resp$error)) {
    testthat::skip("Lightpanda not available")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc), add = TRUE)

  # Navigate to the local dynamic page.
  port <- getOption("rx_local_server_port") %||% 18932L
  url <- paste0("http://127.0.0.1:", port, "/dynamic-page.html")
  xtweetsR:::.rx_send_request(proc, "navigate", list(url = url), reqId = make_test_req_id())

  # Wait for JS to execute.
  Sys.sleep(1.5)

  # Call domInspect with no selector — should return full HTML.
  resp <- xtweetsR:::.rx_send_request(proc, "domInspect", list(), reqId = make_test_req_id())

  testthat::expect_true(is.list(resp), info = "domInspect returns a list")
  testthat::expect_false(is.null(resp$result), info = "domInspect result is present")
  testthat::expect_true(is.character(resp$result$html), info = "result$html is a string")
  testthat::expect_true(
    grepl("<html", resp$result$html, ignore.case = TRUE),
    info = "HTML contains <html> tag"
  )
  testthat::expect_true(
    grepl("data-post-id", resp$result$html),
    info = "HTML contains dynamically injected post elements"
  )
})

# --- Test 2: domInspect with CSS selector returns matched elements ---
test_that("sidecar domInspect with selector returns matched element info", {
  skip_on_os("windows")

  sc_dir <- system.file("node", package = "xtweetsR")
  proc <- tryCatch(
    xtweetsR:::.rx_start_sidecar(sidecar_path = sc_dir),
    error = function(e) NULL
  )
  if (is.null(proc)) {
    testthat::skip("sidecar failed to start")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  conn_resp <- tryCatch(
    xtweetsR:::.rx_send_request(proc, "connect", list(), reqId = make_test_req_id()),
    error = function(e) NULL
  )
  if (is.null(conn_resp) || !is.null(conn_resp$error)) {
    testthat::skip("Lightpanda not available")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc), add = TRUE)

  port <- getOption("rx_local_server_port") %||% 18932L
  url <- paste0("http://127.0.0.1:", port, "/dynamic-page.html")
  xtweetsR:::.rx_send_request(proc, "navigate", list(url = url), reqId = make_test_req_id())

  Sys.sleep(1.5)

  # Query the post elements by their data attribute selector.
  resp <- xtweetsR:::.rx_send_request(proc, "domInspect", list(
    selector = "[data-post-id]"
  ), reqId = make_test_req_id())

  testthat::expect_true(is.list(resp), info = "domInspect selector returns a list")
  testthat::expect_false(is.null(resp$result), info = "result is present")
  testthat::expect_true(is.list(resp$result$found), info = "found is an array")

  matches <- resp$result$found
  testthat::expect_true(length(matches) >= 1L, info = "at least one post element is matched")

  # Each match should have tagName, id, className, outerHTML.
  for (m in matches) {
    testthat::expect_true(!is.null(m$tagName), info = "match has tagName")
    testthat::expect_true(!is.null(m$outerHTML), info = "match has outerHTML")
  }
})

# --- Test 3: domInspect with non-matching selector returns empty ---
test_that("domInspect with non-matching selector returns empty found array", {
  skip_on_os("windows")

  sc_dir <- system.file("node", package = "xtweetsR")
  proc <- tryCatch(
    xtweetsR:::.rx_start_sidecar(sidecar_path = sc_dir),
    error = function(e) NULL
  )
  if (is.null(proc)) {
    testthat::skip("sidecar failed to start")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  conn_resp <- tryCatch(
    xtweetsR:::.rx_send_request(proc, "connect", list(), reqId = make_test_req_id()),
    error = function(e) NULL
  )
  if (is.null(conn_resp) || !is.null(conn_resp$error)) {
    testthat::skip("Lightpanda not available")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc), add = TRUE)

  port <- getOption("rx_local_server_port") %||% 18932L
  url <- paste0("http://127.0.0.1:", port, "/dynamic-page.html")
  xtweetsR:::.rx_send_request(proc, "navigate", list(url = url), reqId = make_test_req_id())

  Sys.sleep(1)

  resp <- xtweetsR:::.rx_send_request(proc, "domInspect", list(
    selector = "[this-selector-does-not-exist-xyz]"
  ), reqId = make_test_req_id())

  testthat::expect_false(is.null(resp$result), info = "result is present even with no matches")
  testthat::expect_equal(resp$result$found, list(), info = "found is empty for non-matching selector")
})

# --- Test 4: x_debug_dom() returns correct data frame (full HTML) ---
test_that("x_debug_dom returns a data frame with html column for full inspection", {
  skip_on_os("windows")

  sc_dir <- system.file("node", package = "xtweetsR")
  proc <- tryCatch(
    xtweetsR:::.rx_start_sidecar(sidecar_path = sc_dir),
    error = function(e) NULL
  )
  if (is.null(proc)) {
    testthat::skip("sidecar failed to start")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  conn_resp <- tryCatch(
    xtweetsR:::.rx_send_request(proc, "connect", list(), reqId = make_test_req_id()),
    error = function(e) NULL
  )
  if (is.null(conn_resp) || !is.null(conn_resp$error)) {
    testthat::skip("Lightpanda not available")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc), add = TRUE)

  port <- getOption("rx_local_server_port") %||% 18932L
  url <- paste0("http://127.0.0.1:", port, "/dynamic-page.html")
  xtweetsR:::.rx_send_request(proc, "navigate", list(url = url), reqId = make_test_req_id())

  Sys.sleep(1.5)

  # Build a mock backend and session to test x_debug_dom without
  # depending on the full R package machinery.
  state <- new.env(parent = emptyenv())
  state$.proc <- proc
  state$connected <- TRUE

  backend <- new.env(parent = emptyenv())
  backend$connected <- TRUE
  backend$domInspect <- function(selector = NULL) {
    params <- if (is.null(selector)) list() else list(selector = selector)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(proc, "domInspect", params, reqId = make_test_req_id()),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      list(result = NULL, error = resp$error)
    } else {
      list(result = resp$result, error = NULL)
    }
  }
  backend$evaluate <- function(expr) NULL
  backend$navigate <- function(url) NULL
  backend$close <- function() NULL
  backend$networkCaptureEnable <- function() invisible(TRUE)
  backend$networkCaptureGet <- function() list()
  backend$networkCaptureGetBody <- function(requestId) NULL
  backend$networkCaptureClear <- function() invisible(TRUE)

  mock_session <- new.env(parent = emptyenv())
  mock_session$backend <- backend
  mock_session$connected <- TRUE
  class(mock_session) <- "xtweetsR_session"

  # Call x_debug_dom with no selector.
  df <- xtweetsR::x_debug_dom(mock_session)

  testthat::expect_s3_class(df, "data.frame", info = "returns a data frame")
  testthat::expect_equal(ncol(df), 1L, info = "single column")
  testthat::expect_true("html" %in% names(df), info = "column is named 'html'")
  testthat::expect_equal(nrow(df), 1L, info = "single row")
  testthat::expect_true(is.character(df$html), info = "html column is character")
  testthat::expect_true(
    grepl("data-post-id", df$html),
    info = "HTML contains dynamically injected content"
  )
})

# --- Test 5: x_debug_dom() returns correct data frame (selector mode) ---
test_that("x_debug_dom returns correct data frame for selector mode", {
  skip_on_os("windows")

  sc_dir <- system.file("node", package = "xtweetsR")
  proc <- tryCatch(
    xtweetsR:::.rx_start_sidecar(sidecar_path = sc_dir),
    error = function(e) NULL
  )
  if (is.null(proc)) {
    testthat::skip("sidecar failed to start")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  conn_resp <- tryCatch(
    xtweetsR:::.rx_send_request(proc, "connect", list(), reqId = make_test_req_id()),
    error = function(e) NULL
  )
  if (is.null(conn_resp) || !is.null(conn_resp$error)) {
    testthat::skip("Lightpanda not available")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc), add = TRUE)

  port <- getOption("rx_local_server_port") %||% 18932L
  url <- paste0("http://127.0.0.1:", port, "/dynamic-page.html")
  xtweetsR:::.rx_send_request(proc, "navigate", list(url = url), reqId = make_test_req_id())

  Sys.sleep(1.5)

  # Build mock backend (same as Test 4).
  state <- new.env(parent = emptyenv())
  state$.proc <- proc
  state$connected <- TRUE

  backend <- new.env(parent = emptyenv())
  backend$connected <- TRUE
  backend$domInspect <- function(selector = NULL) {
    params <- if (is.null(selector)) list() else list(selector = selector)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(proc, "domInspect", params, reqId = make_test_req_id()),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      list(result = NULL, error = resp$error)
    } else {
      list(result = resp$result, error = NULL)
    }
  }
  backend$evaluate <- function(expr) NULL
  backend$navigate <- function(url) NULL
  backend$close <- function() NULL
  backend$networkCaptureEnable <- function() invisible(TRUE)
  backend$networkCaptureGet <- function() list()
  backend$networkCaptureGetBody <- function(requestId) NULL
  backend$networkCaptureClear <- function() invisible(TRUE)

  mock_session <- new.env(parent = emptyenv())
  mock_session$backend <- backend
  mock_session$connected <- TRUE
  class(mock_session) <- "xtweetsR_session"

  # Call x_debug_dom with selector.
  df <- xtweetsR::x_debug_dom(mock_session, selector = "[data-post-id]")

  testthat::expect_s3_class(df, "data.frame", info = "returns a data frame")
  testthat::expect_true(nrow(df) >= 1L, info = "at least one post element found")
  expected_cols <- c("index", "tagName", "id", "className", "outerHTML")
  testthat::expect_true(all(expected_cols %in% names(df)), info = "all expected columns present")
  testthat::expect_true(is.character(df$tagName), info = "tagName is character")
  testthat::expect_true(is.integer(df$index), info = "index is integer")
})

# --- Test 6: x_debug_dom() rejects invalid session ---
test_that("x_debug_dom rejects invalid session", {
  testthat::expect_error(
    xtweetsR::x_debug_dom(NULL),
    "requires a valid xtweetsR_session",
    info = "NULL session throws"
  )

  testthat::expect_error(
    xtweetsR::x_debug_dom(list()),
    "requires a valid xtweetsR_session",
    info = "empty list session throws"
  )
})

# --- Test 7: x_debug_dom() rejects disconnected session ---
test_that("x_debug_dom rejects disconnected session", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$backend <- list(domInspect = function(selector = NULL) NULL)
  mock_session$connected <- FALSE
  class(mock_session) <- "xtweetsR_session"

  testthat::expect_error(
    xtweetsR::x_debug_dom(mock_session),
    "requires an active session",
    info = "disconnected session throws"
  )
})

# --- Test 8: x_debug_dom returns empty df for non-matching selector ---
test_that("x_debug_dom returns empty data frame for non-matching selector", {
  skip_on_os("windows")

  sc_dir <- system.file("node", package = "xtweetsR")
  proc <- tryCatch(
    xtweetsR:::.rx_start_sidecar(sidecar_path = sc_dir),
    error = function(e) NULL
  )
  if (is.null(proc)) {
    testthat::skip("sidecar failed to start")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  conn_resp <- tryCatch(
    xtweetsR:::.rx_send_request(proc, "connect", list(), reqId = make_test_req_id()),
    error = function(e) NULL
  )
  if (is.null(conn_resp) || !is.null(conn_resp$error)) {
    testthat::skip("Lightpanda not available")
  }
  on.exit(xtweetsR:::.rx_stop_sidecar(proc), add = TRUE)

  # Build mock backend without navigating — the page will be the default blank page.
  backend <- new.env(parent = emptyenv())
  backend$connected <- TRUE
  backend$domInspect <- function(selector = NULL) {
    params <- if (is.null(selector)) list() else list(selector = selector)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(proc, "domInspect", params, reqId = make_test_req_id()),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      list(result = NULL, error = resp$error)
    } else {
      list(result = resp$result, error = NULL)
    }
  }
  backend$evaluate <- function(expr) NULL
  backend$navigate <- function(url) NULL
  backend$close <- function() NULL
  backend$networkCaptureEnable <- function() invisible(TRUE)
  backend$networkCaptureGet <- function() list()
  backend$networkCaptureGetBody <- function(requestId) NULL
  backend$networkCaptureClear <- function() invisible(TRUE)

  mock_session <- new.env(parent = emptyenv())
  mock_session$backend <- backend
  mock_session$connected <- TRUE
  class(mock_session) <- "xtweetsR_session"

  # Non-matching selector on the default blank page.
  df <- xtweetsR::x_debug_dom(mock_session, selector = "[definitely-not-found-xyz]")

  testthat::expect_s3_class(df, "data.frame")
  testthat::expect_equal(nrow(df), 0L, info = "zero rows for non-matching selector")
  testthat::expect_true(all(c("index", "tagName", "id", "className", "outerHTML") %in% names(df)))
})
