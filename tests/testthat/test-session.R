# Tests for x_session() — Task 18
#
# Verifies: session object creation, structure, print method.
#
# NOTE: On some platforms (e.g. certain Windows/WSL setups), the
# processx package segfaults at the C level when spawning processes.
# In those cases, the protocol is still verified by the Node-based
# integration tests in inst/node/src/protocol.test.ts.

# Load the package in development mode so internal functions are available.
if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
}

if (tolower(Sys.getenv("SKIP_PROTOCOL_TESTS", unset = "false")) == "true") {
  testthat::skip("session tests skipped (SKIP_PROTOCOL_TESTS=true)")
}

# Helper: attempt to create a session; skip the test if Lightpanda is unavailable.
# Tests that require an actual browser connection should wrap their setup
# in this guard to avoid spurious failures in CI environments without Lightpanda.
.try_create_session <- function(...) {
  sess <- tryCatch(
    xtweetsR::x_session(...),
    error = function(e) NULL
  )
  if (is.null(sess)) {
    testthat::skip("Lightpanda not available — session creation failed")
  }
  sess
}

# --- Test 1: x_session() exists and is exported ---
test_that("x_session is an exported function", {
  testthat::expect_true(
    exists("x_session", envir = asNamespace("xtweetsR"))
    )
  testthat::expect_true(
    "x_session" %in% getNamespaceExports("xtweetsR")
    )
})

# --- Test 2: x_session() returns a session object with correct structure ---
test_that("x_session() returns a valid session object", {
  sess <- .try_create_session()
  testthat::defer(sess$close())

  testthat::expect_s3_class(sess, "xtweetsR_session")
  testthat::expect_true(is.environment(sess))
  testthat::expect_true(!is.null(sess$backend))
  testthat::expect_true(isTRUE(sess$connected))
  testthat::expect_true(is.character(sess$endpoint))
  testthat::expect_true(nchar(sess$endpoint) > 0)
  testthat::expect_true(is.function(sess$close))
})

# --- Test 3: print.xtweetsR_session does not error ---
test_that("print.xtweetsR_session works without error", {
  sess <- .try_create_session()
  testthat::defer(sess$close())

  # Capture output to verify it doesn't error and produces text.
  output <- capture.output(print(sess))
  testthat::expect_true(length(output) > 0)
  testthat::expect_true(
    any(grepl("xtweetsR_session", output))
    )
  testthat::expect_true(
    any(grepl("endpoint", output, ignore.case = TRUE))
    )
  testthat::expect_true(
    any(grepl("connected", output, ignore.case = TRUE))
    )
})

# --- Test 4: session$close() cleans up resources ---
test_that("session$close() releases resources", {
  sess <- .try_create_session()

  testthat::expect_true(isTRUE(sess$connected))

  sess$close()

  testthat::expect_null(sess$backend)
  testthat::expect_false(sess$connected)
})

# --- Test 5: session$close() is idempotent ---
test_that("session$close() can be called multiple times safely", {
  sess <- .try_create_session()
  testthat::defer(sess$close())

  sess$close()
  # Second close should not error.
  r2 <- sess$close()
  testthat::expect_null(r2)
  testthat::expect_null(sess$backend)
  testthat::expect_false(sess$connected)
})

# --- Test 6: x_session() with explicit endpoint ---
test_that("x_session() respects explicit endpoint parameter", {
  sess <- .try_create_session(endpoint = "ws://custom.host:9999")
  testthat::defer(sess$close())

  testthat::expect_equal(sess$endpoint, "ws://custom.host:9999")
})

# --- Test 7: session close returns invisible NULL ---
test_that("x_session()$close() returns invisible NULL", {
  sess <- .try_create_session()
  testthat::defer(sess$close())

  result <- sess$close()
  testthat::expect_null(result)
})

# --- Test 8: x_close is exported ---
test_that("x_close is an exported function", {
  testthat::expect_true(
    exists("x_close", envir = asNamespace("xtweetsR"))
    )
  testthat::expect_true(
    "x_close" %in% getNamespaceExports("xtweetsR")
    )
})

# --- Test 9: x_close(NULL) does not error ---
test_that("x_close(NULL) returns invisibly without error", {
  result <- xtweetsR::x_close(NULL)
  testthat::expect_null(result)
})

# --- Test 10: x_session() → x_close() succeeds end-to-end ---
test_that("x_session() then x_close() completes without error", {
  sess <- .try_create_session()
  testthat::expect_true(isTRUE(sess$connected))

  result <- xtweetsR::x_close(sess)
  testthat::expect_null(result)
  testthat::expect_false(sess$connected)
})

# --- Test 11: x_close() is idempotent (repeated calls do not crash) ---
test_that("x_close() can be called multiple times safely", {
  sess <- .try_create_session()

  # First close via x_close.
  xtweetsR::x_close(sess)
  testthat::expect_false(sess$connected)

  # Second close — should not error.
  r2 <- xtweetsR::x_close(sess)
  testthat::expect_null(r2)

  # Third close — still safe.
  r3 <- xtweetsR::x_close(sess)
  testthat::expect_null(r3)
})

# --- Test 12: x_close() leaves no child process ---
test_that("x_close() terminates the sidecar process", {
  sess <- .try_create_session()
  proc <- sess$backend$.proc
  testthat::expect_true(!is.null(proc))
  testthat::expect_true(proc$is_alive())

  xtweetsR::x_close(sess)

  # Give the process a moment to terminate.
  Sys.sleep(0.2)
  testthat::expect_false(
    proc$is_alive()
    )
})

# --- Test 13: x_close() on a session already closed via $close() ---
test_that("x_close() on an already-closed session is safe", {
  sess <- .try_create_session()

  # Close via the session's own $close() method.
  sess$close()
  testthat::expect_false(sess$connected)

  # Now call x_close — should not error.
  result <- xtweetsR::x_close(sess)
  testthat::expect_null(result)
  testthat::expect_false(sess$connected)
})

# --- Test 14: x_close() on a session with NULL backend ---
test_that("x_close() on a session with NULL backend returns invisibly", {
  sess <- .try_create_session()
  sess$close()

  # Manually set backend to NULL (simulates double-close state).
  sess$backend <- NULL

  result <- xtweetsR::x_close(sess)
  testthat::expect_null(result)
})
