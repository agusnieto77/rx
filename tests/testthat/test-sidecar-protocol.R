# Tests for the R ↔ TypeScript sidecar protocol.
# Verifies: valid request, unknown method, malformed JSON, process shutdown.
#
# NOTE: On some platforms (e.g. certain Windows/WSL setups), the
# processx package segfaults at the C level when spawning processes.
# In those cases, the protocol is still verified by the Node-based
# integration tests in inst/node/src/protocol.test.ts.
if (tolower(Sys.getenv("SKIP_PROTOCOL_TESTS", unset = "false")) == "true") {
  testthat::skip("protocol tests skipped (SKIP_PROTOCOL_TESTS=true)")
}

# Helper: find the sidecar JS path. During `R CMD check` the package
# is installed so `system.file` works. During `devtools::test` we
# point to the source tree's `inst/node/`.
.sidecar_path <- function() {
  xtweetsR:::.rx_resolve_sidecar_path()
}

# Try to start the sidecar. Returns NULL if it cannot start (e.g.
# processx segfaults on this platform).  Tests that need the sidecar
# call `skip_if_no_sidecar()` first.
.try_start_sidecar <- function() {
  tryCatch(
    {
      p <- xtweetsR:::.rx_start_sidecar(sidecar_path = .sidecar_path())
      if (p$is_alive()) {
        return(p)
      }
      NULL
    },
    error = function(e) NULL
  )
}

# Skip the current test if the sidecar cannot be started.
.skip_if_no_sidecar <- function() {
  proc <- .try_start_sidecar()
  if (is.null(proc)) {
    testthat::skip("sidecar process cannot start (processx unavailable)")
  }
  # Store on the environment so the caller can use it.
  attr(.skip_if_no_sidecar, "proc") <- proc
  invisible(proc)
}

# Create a per-test request ID counter so tests don't share global state.
.make_req_id <- function() {
  count <- 0L
  function() {
    count <<- count + 1L
    count
  }
}

# --- Test 1: valid ping request ---
test_that("valid ping request returns expected response", {
  reqId <- .make_req_id()
  proc <- .try_start_sidecar()
  testthat::skip_if(is.null(proc), "sidecar process cannot start")
  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  resp <- xtweetsR:::.rx_send_request(proc, "ping", reqId = reqId)

  testthat::expect_true(
    is.list(resp)
    )
  testthat::expect_true(
    !is.null(resp$result)
    )
  testthat::expect_true(
    resp$result$pong == TRUE
    )
  testthat::expect_true(
    is.character(resp$result$version)
    )
  testthat::expect_equal(
    resp$id, 1L
    )
})

# --- Test 2: unknown method returns structured error ---
test_that("unknown method returns structured error", {
  reqId <- .make_req_id()
  proc <- .try_start_sidecar()
  testthat::skip_if(is.null(proc), "sidecar process cannot start")
  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  resp <- xtweetsR:::.rx_send_request(proc, "nonexistent_method", reqId = reqId)

  testthat::expect_true(
    is.list(resp)
    )
  testthat::expect_true(
    !is.null(resp$error)
    )
  testthat::expect_equal(
    resp$error$code, "UNKNOWN_METHOD"
    )
  testthat::expect_true(
    is.character(resp$error$message)
    )
  testthat::expect_true(
    nchar(resp$error$message) > 0
    )
})

# --- Test 3: malformed JSON produces structured error ---
test_that("malformed JSON produces a parse error on stderr", {
  proc <- .try_start_sidecar()
  testthat::skip_if(is.null(proc), "sidecar process cannot start")

  # Send malformed JSON directly via the process handle.
  # This bypasses .rx_send_request which validates input first.
  proc$write_input("not valid json {{{\n")
  proc$write_input("\n") # flush

  # Read the error response from stdout.
  timeout <- 10
  start <- Sys.time()
  found_error <- FALSE

  while (Sys.time() - start < timeout) {
    if (!proc$is_alive()) break
    lines <- tryCatch(proc$read_output_lines(), error = function(e) character(0))
    if (length(lines) > 0) {
      for (line in lines) {
        if (nzchar(line)) {
          parsed <- tryCatch(
            jsonlite::fromJSON(line, simplifyVector = FALSE),
            error = function(e) NULL
          )
          if (!is.null(parsed) && !is.null(parsed$error) && parsed$error$code == "PARSE_ERROR") {
            found_error <- TRUE
            break
          }
        }
      }
    }
    if (found_error) break
    Sys.sleep(0.05)
  }
  xtweetsR:::.rx_stop_sidecar(proc)

  testthat::expect_true(
    found_error
    )
})

# --- Test 4: process shutdown leaves no orphan ---
test_that("stop sidecar cleanly terminates the process", {
  proc <- .try_start_sidecar()
  testthat::skip_if(is.null(proc), "sidecar process cannot start")

  testthat::expect_true(
    proc$is_alive()
    )
  xtweetsR:::.rx_stop_sidecar(proc)

  # Give a moment for the process to actually terminate.
  Sys.sleep(0.2)
  testthat::expect_false(
    proc$is_alive()
    )
})

# --- Test 5: browser close when not connected ---
test_that("close_browser when not connected returns not_connected", {
  proc <- .try_start_sidecar()
  testthat::skip_if(is.null(proc), "sidecar process cannot start")
  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  resp <- xtweetsR:::.rx_close_browser(proc)

  testthat::expect_true(
    is.list(resp)
    )
  testthat::expect_equal(
    resp$closed, FALSE
    )
  testthat::expect_equal(
    resp$reason, "not_connected"
    )
})

# --- Test 6: browser close twice is safe ---
test_that("close_browser twice does not crash the sidecar", {
  reqId <- .make_req_id()
  proc <- .try_start_sidecar()
  testthat::skip_if(is.null(proc), "sidecar process cannot start")
  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  # First close.
  r1 <- xtweetsR:::.rx_close_browser(proc)
  testthat::expect_false(r1$closed)

  # Second close.
  r2 <- xtweetsR:::.rx_close_browser(proc)
  testthat::expect_false(r2$closed)

  # Sidecar is still alive and responsive.
  ping_resp <- xtweetsR:::.rx_send_request(proc, "ping", reqId = reqId)
  testthat::expect_true(
    ping_resp$result$pong == TRUE
    )
})

# --- Test 7: browser close after failed connect ---
test_that("close_browser after failed connect is safe", {
  reqId <- .make_req_id()
  proc <- .try_start_sidecar()
  testthat::skip_if(is.null(proc), "sidecar process cannot start")
  on.exit(xtweetsR:::.rx_stop_sidecar(proc))

  # Attempt to connect to an unreachable endpoint.
  # This returns an error because no server is listening.
  conn_resp <- xtweetsR:::.rx_send_request(proc, "connect", list(endpoint = "ws://127.0.0.1:1"), reqId = reqId)

  testthat::expect_true(
    !is.null(conn_resp$error)
    )
  testthat::expect_equal(
    conn_resp$error$code, "LPD_CONNECTION_ERROR"
    )

  # Close after failed connect — should be safe.
  close_resp <- xtweetsR:::.rx_close_browser(proc)

  testthat::expect_false(
    close_resp$closed
    )
})
