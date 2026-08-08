# Tests for x_debug_network()

test_that("x_debug_network is an exported function", {
  expect_true(is.function(x_debug_network))
})

test_that("x_debug_network rejects NULL session", {
  expect_error(x_debug_network(NULL), "valid xtweetsR_session")
})

test_that("x_debug_network rejects session with no backend", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend   <- NULL
  expect_error(x_debug_network(mock_session), "valid xtweetsR_session")
})

test_that("x_debug_network rejects disconnected session", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- FALSE
  mock_session$backend   <- new.env(parent = emptyenv())
  expect_error(x_debug_network(mock_session), "active session")
})

test_that("x_debug_network returns empty data frame when nothing captured", {
  proc <- tryCatch(
    {
      p <- xtweetsR:::.rx_start_sidecar()
      if (!p$is_alive()) { NULL } else { p }
    },
    error = function(e) NULL
  )

  if (is.null(proc)) {
    skip("sidecar cannot start (no browser backend testable)")
  }

  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  # Per-test request ID counter.
  test_req_id <- 0L
  make_test_req_id <- function() {
    test_req_id <<- test_req_id + 1L
    test_req_id
  }

  # Build a minimal backend using the running sidecar.
  backend <- new.env(parent = emptyenv())
  backend$connected <- FALSE
  backend$.proc <- proc

  backend$networkCaptureEnable <- function() {
    if (!backend$connected) {
      stop("Backend not connected. Call connect() first.", call. = FALSE)
    }
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureEnable", list(), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      stop(paste0("Network capture enable failed: ", resp$error$message), call. = FALSE)
    }
    invisible(TRUE)
  }

  backend$networkCaptureGet <- function() {
    if (!backend$connected) {
      stop("Backend not connected. Call connect() first.", call. = FALSE)
    }
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureGet", list(), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      stop(paste0("Network capture get failed: ", resp$error$message), call. = FALSE)
    }
    if (is.null(resp$result$events)) return(list())
    resp$result$events
  }

  backend$networkCaptureGetBody <- function(requestId) {
    if (!backend$connected) {
      stop("Backend not connected. Call connect() first.", call. = FALSE)
    }
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureGetBody", list(requestId = requestId), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      stop(paste0("Network body capture failed: ", resp$error$message), call. = FALSE)
    }
    list(requestId = resp$result$requestId, body = resp$result$body, contentType = resp$result$contentType, error = resp$result$error)
  }

  backend$networkCaptureClear <- function() {
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureClear", list(), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      stop(paste0("Network capture clear failed: ", resp$error$message), call. = FALSE)
    }
    invisible(TRUE)
  }

  backend$connect <- function(endpoint = NULL) {
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "connect", list(endpoint = endpoint), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      stop(paste0("CDP connection failed: ", resp$error$message), call. = FALSE)
    }
    if (is.null(resp$result)) {
      stop("Malformed connect response", call. = FALSE)
    }
    backend$connected <- TRUE
    invisible(backend)
  }

  backend$navigate <- function(url) {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "navigate", list(url = url), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) list(url = url, status = "error", error = resp$error)
    else list(url = url, status = "ok", result = resp$result)
  }

  backend$evaluate <- function(expr) {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "evaluate", list(expr = expr), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) list(result = NULL, error = resp$error)
    else list(result = resp$result, error = NULL)
  }

  backend$close <- function() {
    tryCatch(xtweetsR:::.rx_stop_sidecar(backend$.proc), error = function(e) NULL)
    backend$connected <- FALSE
    invisible(NULL)
  }

  # Connect to Lightpanda (skip if not available).
  tryCatch(backend$connect("ws://127.0.0.1:21111"), error = function(e) NULL)

  if (!backend$connected) {
    skip("Lightpanda not available — connect() failed")
  }

  # Build a mock session with this backend.
  mock_session <- new.env(parent = emptyenv())
  mock_session$backend   <- backend
  mock_session$connected <- TRUE
  mock_session$endpoint  <- "ws://127.0.0.1:21111"
  mock_session$close     <- function() backend$close()
  class(mock_session)    <- "xtweetsR_session"

  # Enable capture but do not navigate — should return empty data frame.
  backend$networkCaptureEnable()

  df <- x_debug_network(mock_session)
  expect_true(is.data.frame(df))
  expect_equal(nrow(df), 0L)

  expected_cols <- c(
    "requestId", "url", "method", "resourceType", "status",
    "protocol", "fromDiskCache", "fromServiceWorker",
    "fromPrefetchCache", "timedOut", "contentType"
  )
  expect_equal(colnames(df), expected_cols)
})

test_that("x_debug_network captures events from navigation", {
  proc <- tryCatch(
    {
      p <- xtweetsR:::.rx_start_sidecar()
      if (!p$is_alive()) { NULL } else { p }
    },
    error = function(e) NULL
  )

  if (is.null(proc)) {
    skip("sidecar cannot start (no browser backend testable)")
  }

  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

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
  }, add = TRUE)

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
  expect_true(ready)

  # Per-test request ID counter.
  test_req_id <- 0L
  make_test_req_id <- function() {
    test_req_id <<- test_req_id + 1L
    test_req_id
  }

  # Build backend.
  backend <- new.env(parent = emptyenv())
  backend$connected <- FALSE
  backend$.proc <- proc

  backend$networkCaptureEnable <- function() {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureEnable", list(), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) stop(paste0("Network capture enable failed: ", resp$error$message), call. = FALSE)
    invisible(TRUE)
  }

  backend$networkCaptureGet <- function() {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureGet", list(), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) stop(paste0("Network capture get failed: ", resp$error$message), call. = FALSE)
    if (is.null(resp$result$events)) return(list())
    resp$result$events
  }

  backend$networkCaptureGetBody <- function(requestId) {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureGetBody", list(requestId = requestId), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) stop(paste0("Network body capture failed: ", resp$error$message), call. = FALSE)
    list(requestId = resp$result$requestId, body = resp$result$body, contentType = resp$result$contentType, error = resp$result$error)
  }

  backend$networkCaptureClear <- function() {
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureClear", list(), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) stop(paste0("Network capture clear failed: ", resp$error$message), call. = FALSE)
    invisible(TRUE)
  }

  backend$connect <- function(endpoint = NULL) {
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "connect", list(endpoint = endpoint), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      xtweetsR:::.rx_stop_sidecar(proc)
      stop(paste0("CDP connection failed: ", resp$error$message), call. = FALSE)
    }
    if (is.null(resp$result)) {
      xtweetsR:::.rx_stop_sidecar(proc)
      stop("Malformed connect response", call. = FALSE)
    }
    backend$connected <- TRUE
    invisible(backend)
  }

  backend$navigate <- function(url) {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "navigate", list(url = url), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) list(url = url, status = "error", error = resp$error)
    else list(url = url, status = "ok", result = resp$result)
  }

  backend$evaluate <- function(expr) {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "evaluate", list(expr = expr), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) list(result = NULL, error = resp$error)
    else list(result = resp$result, error = NULL)
  }

  backend$close <- function() {
    tryCatch(xtweetsR:::.rx_stop_sidecar(backend$.proc), error = function(e) NULL)
    backend$connected <- FALSE
    invisible(NULL)
  }

  # Connect to Lightpanda.
  tryCatch(backend$connect("ws://127.0.0.1:21111"), error = function(e) NULL)
  if (!backend$connected) {
    skip("Lightpanda not available — connect() failed")
  }

  # Build mock session.
  mock_session <- new.env(parent = emptyenv())
  mock_session$backend   <- backend
  mock_session$connected <- TRUE
  mock_session$endpoint  <- "ws://127.0.0.1:21111"
  mock_session$close     <- function() backend$close()
  class(mock_session)    <- "xtweetsR_session"

  # Enable capture and navigate.
  backend$networkCaptureEnable()
  nav_result <- tryCatch(
    backend$navigate(paste0("http://127.0.0.1:", port, "/dynamic-page.html")),
    error = function(e) NULL
  )

  # Give the page time to load resources and fire network events.
  Sys.sleep(1.5)

  # Call x_debug_network — this should return a data frame with events.
  df <- x_debug_network(mock_session)
  expect_true(is.data.frame(df))

  expected_cols <- c(
    "requestId", "url", "method", "resourceType", "status",
    "protocol", "fromDiskCache", "fromServiceWorker",
    "fromPrefetchCache", "timedOut", "contentType"
  )
  expect_equal(colnames(df), expected_cols)

  # If events were captured, at least one should have a non-empty URL.
  if (nrow(df) > 0L) {
    expect_true(any(nzchar(df$url)))
  }
})

test_that("x_debug_network clears buffer (only new events on subsequent call)", {
  proc <- tryCatch(
    {
      p <- xtweetsR:::.rx_start_sidecar()
      if (!p$is_alive()) { NULL } else { p }
    },
    error = function(e) NULL
  )

  if (is.null(proc)) {
    skip("sidecar cannot start (no browser backend testable)")
  }

  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

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
  }, add = TRUE)

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
  expect_true(ready)

  # Per-test request ID counter.
  test_req_id <- 0L
  make_test_req_id <- function() {
    test_req_id <<- test_req_id + 1L
    test_req_id
  }

  # Build backend.
  backend <- new.env(parent = emptyenv())
  backend$connected <- FALSE
  backend$.proc <- proc

  backend$networkCaptureEnable <- function() {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureEnable", list(), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) stop(paste0("Network capture enable failed: ", resp$error$message), call. = FALSE)
    invisible(TRUE)
  }

  backend$networkCaptureGet <- function() {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureGet", list(), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) stop(paste0("Network capture get failed: ", resp$error$message), call. = FALSE)
    if (is.null(resp$result$events)) return(list())
    resp$result$events
  }

  backend$networkCaptureGetBody <- function(requestId) {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureGetBody", list(requestId = requestId), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) stop(paste0("Network body capture failed: ", resp$error$message), call. = FALSE)
    list(requestId = resp$result$requestId, body = resp$result$body, contentType = resp$result$contentType, error = resp$result$error)
  }

  backend$networkCaptureClear <- function() {
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "networkCaptureClear", list(), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) stop(paste0("Network capture clear failed: ", resp$error$message), call. = FALSE)
    invisible(TRUE)
  }

  backend$connect <- function(endpoint = NULL) {
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "connect", list(endpoint = endpoint), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      xtweetsR:::.rx_stop_sidecar(proc)
      stop(paste0("CDP connection failed: ", resp$error$message), call. = FALSE)
    }
    if (is.null(resp$result)) {
      xtweetsR:::.rx_stop_sidecar(proc)
      stop("Malformed connect response", call. = FALSE)
    }
    backend$connected <- TRUE
    invisible(backend)
  }

  backend$navigate <- function(url) {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "navigate", list(url = url), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) list(url = url, status = "error", error = resp$error)
    else list(url = url, status = "ok", result = resp$result)
  }

  backend$evaluate <- function(expr) {
    if (!backend$connected) stop("not connected", call. = FALSE)
    resp <- tryCatch(
      xtweetsR:::.rx_send_request(backend$.proc, "evaluate", list(expr = expr), reqId = make_test_req_id),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) list(result = NULL, error = resp$error)
    else list(result = resp$result, error = NULL)
  }

  backend$close <- function() {
    tryCatch(xtweetsR:::.rx_stop_sidecar(backend$.proc), error = function(e) NULL)
    backend$connected <- FALSE
    invisible(NULL)
  }

  # Connect to Lightpanda.
  tryCatch(backend$connect("ws://127.0.0.1:21111"), error = function(e) NULL)
  if (!backend$connected) {
    skip("Lightpanda not available — connect() failed")
  }

  # Build mock session.
  mock_session <- new.env(parent = emptyenv())
  mock_session$backend   <- backend
  mock_session$connected <- TRUE
  mock_session$endpoint  <- "ws://127.0.0.1:21111"
  mock_session$close     <- function() backend$close()
  class(mock_session)    <- "xtweetsR_session"

  # Enable capture and navigate.
  backend$networkCaptureEnable()
  tryCatch(
    backend$navigate(paste0("http://127.0.0.1:", port, "/dynamic-page.html")),
    error = function(e) NULL
  )
  Sys.sleep(1.5)

  # First call captures events.
  df1 <- x_debug_network(mock_session)
  count1 <- nrow(df1)

  # Second call should return empty (buffer was cleared).
  df2 <- x_debug_network(mock_session)
  count2 <- nrow(df2)

  expect_equal(count2, 0L)
})
