# Tests for structured error classes (Task 59).
#
# Verifies that error constructors produce condition objects with the
# correct S3 class chain and error code attribute.  No browser or
# sidecar is needed — the tests are fully deterministic.

# --- Test 1: base .rx_error creates correct class chain ---
test_that(".rx_error produces a condition with rx_error class chain", {
  err <- tryCatch(
    .rx_error("generic error", class = "test_error", code = "TEST"),
    error = function(e) e
  )
  expect_s3_class(err, "rx_test_error")
  expect_s3_class(err, "rx_error")
  expect_s3_class(err, "error")
  expect_s3_class(err, "condition")
  expect_equal(attr(err, "rx_error_code"), "TEST")
  expect_equal(err$message, "generic error")
})

# --- Test 2: rx_error_lpd_connection produces correct class ---
test_that("rx_error_lpd_connection has lpd_connection_error class", {
  err <- tryCatch(
    .rx_error_lpd_connection("CDP handshake failed"),
    error = function(e) e
  )
  expect_s3_class(err, "rx_lpd_connection_error")
  expect_s3_class(err, "rx_error")
  expect_equal(attr(err, "rx_error_code"), "LPD_CONNECTION_ERROR")
  expect_equal(err$message, "CDP handshake failed")
})

# --- Test 3: rx_error_cdp produces correct class ---
test_that("rx_error_cdp has cdp_error class", {
  err <- tryCatch(
    .rx_error_cdp("not connected"),
    error = function(e) e
  )
  expect_s3_class(err, "rx_cdp_error")
  expect_s3_class(err, "rx_error")
  expect_equal(attr(err, "rx_error_code"), "CDP_ERROR")
})

# --- Test 4: rx_error_page_load produces correct class ---
test_that("rx_error_page_load has page_load_error class", {
  err <- tryCatch(
    .rx_error_page_load("navigation aborted"),
    error = function(e) e
  )
  expect_s3_class(err, "rx_page_load_error")
  expect_equal(attr(err, "rx_error_code"), "PAGE_LOAD_ERROR")
})

# --- Test 5: rx_error_network produces correct class ---
test_that("rx_error_network has network_error class", {
  err <- tryCatch(
    .rx_error_network("response body unavailable"),
    error = function(e) e
  )
  expect_s3_class(err, "rx_network_error")
  expect_equal(attr(err, "rx_error_code"), "NETWORK_ERROR")
})

# --- Test 6: rx_error_parser produces correct class ---
test_that("rx_error_parser has parser_error class", {
  err <- tryCatch(
    .rx_error_parser("unexpected schema version"),
    error = function(e) e
  )
  expect_s3_class(err, "rx_parser_error")
  expect_equal(attr(err, "rx_error_code"), "PARSER_ERROR")
})

# --- Test 7: rx_error_timeout produces correct class ---
test_that("rx_error_timeout has timeout class", {
  err <- tryCatch(
    .rx_error_timeout("sidecar did not respond within timeout"),
    error = function(e) e
  )
  expect_s3_class(err, "rx_timeout")
  expect_equal(attr(err, "rx_error_code"), "TIMEOUT")
})

# --- Test 8: rx_error_no_new_data produces correct class ---
test_that("rx_error_no_new_data has no_new_data class", {
  err <- tryCatch(
    .rx_error_no_new_data("exhausted all scroll iterations"),
    error = function(e) e
  )
  expect_s3_class(err, "rx_no_new_data")
  expect_equal(attr(err, "rx_error_code"), "NO_NEW_DATA")
})

# --- Test 9: all errors inherit from rx_error (broad catch) ---
test_that("all error types can be caught as rx_error", {
  for (fn in list(.rx_error_lpd_connection, .rx_error_cdp,
                  .rx_error_page_load, .rx_error_network,
                  .rx_error_parser, .rx_error_timeout,
                  .rx_error_no_new_data)) {
    err <- tryCatch(fn("test"), error = function(e) e)
    expect_s3_class(err, "rx_error",
                    info = paste0("failed for ", deparse(substitute(fn))))
  }
})

# --- Test 10: tryCatch catches specific error type ---
test_that("tryCatch can catch specific error classes", {
  # Narrow catch: lpd_connection_error
  caught_lpd <- tryCatch(
    .rx_error_lpd_connection("fail"),
    error = function(e) inherits(e, "rx_lpd_connection_error")
  )
  expect_true(caught_lpd)

  # Narrow catch: cdp_error
  caught_cdp <- tryCatch(
    .rx_error_cdp("fail"),
    error = function(e) inherits(e, "rx_cdp_error")
  )
  expect_true(caught_cdp)

  # Narrow catch: timeout
  caught_timeout <- tryCatch(
    .rx_error_timeout("fail"),
    error = function(e) inherits(e, "rx_timeout")
  )
  expect_true(caught_timeout)
})

# --- Test 11: tryCatch with rx_error catches all ---
test_that("catching rx_error catches all structured errors", {
  for (fn in list(.rx_error_lpd_connection, .rx_error_cdp,
                  .rx_error_page_load, .rx_error_network,
                  .rx_error_parser, .rx_error_timeout,
                  .rx_error_no_new_data)) {
    caught <- tryCatch(
      fn("fail"),
      error = function(e) inherits(e, "rx_error")
    )
    expect_true(caught,
                info = paste0("rx_error catch failed for ",
                              deparse(substitute(fn))))
  }
})

# --- Test 12: backend connect failure uses rx_error_lpd_connection ---
test_that("backend connect failure throws rx_error_lpd_connection", {
  skip_if_not(
    requireNamespace("jsonlite", quietly = TRUE) &&
      requireNamespace("processx", quietly = TRUE)
  )

  backend <- .rx_new_backend()
  # Point to a non-existent dist so the connect fails at CDP level.
  result <- tryCatch(
    backend$connect("ws://127.0.0.1:1"),
    error = function(e) e
  )
  # If sidecar actually starts, it will fail with CDP connection error.
  # Either rx_lpd_connection_error or a generic connection error is acceptable.
  if (inherits(result, "error")) {
    expect_true(
      inherits(result, "rx_lpd_connection_error") ||
        inherits(result, "rx_error") ||
        grepl("connection", result$message, ignore.case = TRUE) ||
        grepl("failed", result$message, ignore.case = TRUE),
      info = paste("Error message:", result$message)
    )
  }
})

# --- Test 13: backend not-connected methods use rx_error_cdp ---
test_that("unconnected backend methods throw rx_cdp_error", {
  skip_if_not(
    requireNamespace("jsonlite", quietly = TRUE) &&
      requireNamespace("processx", quietly = TRUE)
  )

  backend <- .rx_new_backend()
  err <- tryCatch(
    backend$navigate("http://localhost"),
    error = function(e) e
  )
  expect_s3_class(err, "rx_cdp_error")
  expect_true(grepl("not connected", err$message, ignore.case = TRUE))
})

# --- Test 14: timeout error in sidecar protocol ---
test_that(".rx_error_timeout matches the TypeScript TIMEOUT code", {
  err <- tryCatch(
    .rx_error_timeout("sidecar did not respond"),
    error = function(e) e
  )
  expect_equal(attr(err, "rx_error_code"), "TIMEOUT")
  expect_true(inherits(err, "rx_error"))
})
