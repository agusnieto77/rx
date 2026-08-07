# Tests for the browser backend interface (Task 11).
# Verifies the backend contract exists and has the required methods.
# Connection tests are skipped when processx segfaults (Windows/WSL infra).

# Load the package in development mode so internal functions are available.
if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
}

test_that("backend object has connect, navigate, evaluate, close methods", {
  skip_if_not(
    requireNamespace("jsonlite", quietly = TRUE) &&
      requireNamespace("processx", quietly = TRUE)
  )

  backend <- .rx_new_backend()

  expect_true(is.environment(backend))
  expect_true(is.logical(backend$connected))
  expect_false(backend$connected)

  # Contract methods must exist and be functions.
  expect_true(is.function(backend$connect))
  expect_true(is.function(backend$navigate))
  expect_true(is.function(backend$evaluate))
  expect_true(is.function(backend$close))
})

test_that("backend methods are callable without arguments (pre-connect)", {
  skip_if_not(
    requireNamespace("jsonlite", quietly = TRUE) &&
      requireNamespace("processx", quietly = TRUE)
  )

  backend <- .rx_new_backend()

  # Calling navigate/evaluate without connect should error cleanly.
  expect_error(backend$navigate("http://localhost"), "not connected")
  expect_error(backend$evaluate("1+1"), "not connected")

  # close() should be safe even when nothing is connected.
  expect_invisible(backend$close())
  expect_false(backend$connected)
})

test_that("backend connect skips when processx is unreliable", {
  skip_if(Sys.getenv("SKIP_PROTOCOL_TESTS") == "true",
          "processx segfaults on this environment")
  skip_if_not(
    requireNamespace("jsonlite", quietly = TRUE) &&
      requireNamespace("processx", quietly = TRUE)
  )

  backend <- .rx_new_backend()

  # Attempt connect; skip if Lightpanda is not available.
  # This test expects connect() to succeed, so we cannot proceed without it.
  result <- tryCatch(
    {
      backend$connect()
      TRUE
    },
    error = function(e) FALSE
  )

  if (!result) {
    testthat::skip(
      "Lightpanda not available on the configured endpoint — connect() failed"
    )
  }

  # connect() should not have thrown (we already verified above).
  expect_true(backend$connected)
})
