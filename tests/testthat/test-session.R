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

# --- Test 1: x_session() exists and is exported ---
test_that("x_session is an exported function", {
  testthat::expect_true(
    exists("x_session", envir = asNamespace("xtweetsR")),
    info = "x_session exists in the package namespace"
  )
  testthat::expect_true(
    "x_session" %in% getNamespaceExports("xtweetsR"),
    info = "x_session is exported"
  )
})

# --- Test 2: x_session() returns a session object with correct structure ---
test_that("x_session() returns a valid session object", {
  sess <- xtweetsR::x_session()
  testthat::defer(sess$close())

  testthat::expect_s3_class(sess, "xtweetsR_session")
  testthat::expect_true(is.list(sess))
  testthat::expect_true(!is.null(sess$backend))
  testthat::expect_true(isTRUE(sess$connected))
  testthat::expect_true(is.character(sess$endpoint))
  testthat::expect_true(nchar(sess$endpoint) > 0)
  testthat::expect_true(is.function(sess$close))
})

# --- Test 3: print.xtweetsR_session does not error ---
test_that("print.xtweetsR_session works without error", {
  sess <- xtweetsR::x_session()
  testthat::defer(sess$close())

  # Capture output to verify it doesn't error and produces text.
  output <- capture.output(print(sess))
  testthat::expect_true(length(output) > 0, info = "print produces output")
  testthat::expect_true(
    any(grepl("xtweetsR_session", output)),
    info = "output contains class name"
  )
  testthat::expect_true(
    any(grepl("endpoint", output, ignore.case = TRUE)),
    info = "output contains endpoint info"
  )
  testthat::expect_true(
    any(grepl("connected", output, ignore.case = TRUE)),
    info = "output contains connection status"
  )
})

# --- Test 4: session$close() cleans up resources ---
test_that("session$close() releases resources", {
  sess <- xtweetsR::x_session()

  testthat::expect_true(isTRUE(sess$connected))

  sess$close()

  testthat::expect_null(sess$backend)
  testthat::expect_false(sess$connected)
})

# --- Test 5: session$close() is idempotent ---
test_that("session$close() can be called multiple times safely", {
  sess <- xtweetsR::x_session()
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
  sess <- xtweetsR::x_session(endpoint = "ws://custom.host:9999")
  testthat::defer(sess$close())

  testthat::expect_equal(sess$endpoint, "ws://custom.host:9999")
})

# --- Test 7: session close returns invisible NULL ---
test_that("x_session()$close() returns invisible NULL", {
  sess <- xtweetsR::x_session()
  testthat::defer(sess$close())

  result <- sess$close()
  testthat::expect_null(result)
})

# --- Test 8: x_close is exported ---
test_that("x_close is an exported function", {
  testthat::expect_true(
    exists("x_close", envir = asNamespace("xtweetsR")),
    info = "x_close exists in the package namespace"
  )
  testthat::expect_true(
    "x_close" %in% getNamespaceExports("xtweetsR"),
    info = "x_close is exported"
  )
})

# --- Test 9: x_close(NULL) does not error ---
test_that("x_close(NULL) returns invisibly without error", {
  result <- xtweetsR::x_close(NULL)
  testthat::expect_null(result)
})
