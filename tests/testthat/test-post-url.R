# Tests for x_post() URL normalization and navigation (Task 54).
#
# These tests cover:
# - .rx_normalize_post_url() URL parsing and ID extraction
# - .rx_construct_post_url() canonical URL construction
# - Input validation for x_post()
# - Navigation with fixture data (mock backend, no browser)
# - Navigation failure handling

# --- URL normalization tests ---

# --- Test 1: Full x.com post URL returns canonical form ---
test_that(".rx_normalize_post_url rewrites canonical x.com URLs", {
  result <- .rx_normalize_post_url("https://x.com/rstudio/status/1234567890123456789")
  expect_equal(result, "https://x.com/status/1234567890123456789")
})

# --- Test 2: x.com URL with trailing slash ---
test_that(".rx_normalize_post_url handles trailing slash", {
  result <- .rx_normalize_post_url("https://x.com/rstudio/status/1234567890123456789/")
  expect_equal(result, "https://x.com/status/1234567890123456789")
})

# --- Test 3: twitter.com legacy domain ---
test_that(".rx_normalize_post_url handles twitter.com domain", {
  result <- .rx_normalize_post_url("https://twitter.com/rstudio/status/9876543210987654321")
  expect_equal(result, "https://x.com/status/9876543210987654321")
})

# --- Test 4: Bare numeric post ID (19 digits) ---
test_that(".rx_normalize_post_url handles bare post IDs", {
  result <- .rx_normalize_post_url("1234567890123456789")
  expect_equal(result, "https://x.com/status/1234567890123456789")
})

# --- Test 5: Bare post ID with leading zeros ---
test_that(".rx_normalize_post_url handles 15-digit IDs", {
  result <- .rx_normalize_post_url("123456789012345")
  expect_equal(result, "https://x.com/status/123456789012345")
})

# --- Test 6: t.co short link returns unchanged ---
test_that(".rx_normalize_post_url returns t.co links unchanged", {
  result <- .rx_normalize_post_url("https://t.co/abc123def")
  expect_equal(result, "https://t.co/abc123def")
})

# --- Test 7: Non-matching URL returns unchanged ---
test_that(".rx_normalize_post_url returns unknown URLs unchanged", {
  input <- "https://example.com/some/path"
  result <- .rx_normalize_post_url(input)
  expect_equal(result, input)
})

# --- Test 8: NA input returns NA ---
test_that(".rx_normalize_post_url passes through NA", {
  result <- .rx_normalize_post_url(NA_character_)
  expect_true(is.na(result))
})

# --- Test 9: Non-character input returns unchanged ---
test_that(".rx_normalize_post_url returns non-character inputs unchanged", {
  expect_equal(.rx_normalize_post_url(123L), 123L)
  expect_equal(.rx_normalize_post_url(NULL), NULL)
})

# --- Test 10: Empty string returns canonical URL for empty ID ---
test_that(".rx_normalize_post_url trims whitespace", {
  result <- .rx_normalize_post_url("  https://x.com/rstudio/status/1234567890123456789  ")
  expect_equal(result, "https://x.com/status/1234567890123456789")
})

# --- Test 11: Bare post ID with whitespace ---
test_that(".rx_normalize_post_url trims whitespace from bare IDs", {
  result <- .rx_normalize_post_url("  1234567890123456789  ")
  expect_equal(result, "https://x.com/status/1234567890123456789")
})

# --- .rx_construct_post_url() tests ---

# --- Test 12: .rx_construct_post_url builds canonical URL ---
test_that(".rx_construct_post_url builds canonical post URL", {
  result <- .rx_construct_post_url("1234567890123456789")
  expect_equal(result, "https://x.com/status/1234567890123456789")
})

# --- Test 13: .rx_construct_post_url rejects non-numeric ID ---
test_that(".rx_construct_post_url rejects non-numeric ID", {
  expect_error(.rx_construct_post_url("abc"), "numeric")
})

# --- Test 14: .rx_construct_post_url rejects NULL ---
test_that(".rx_construct_post_url rejects NULL", {
  expect_error(.rx_construct_post_url(NULL), "single non-empty")
})

# --- x_post() input validation tests ---

# --- Test 15: x_post rejects NULL session ---
test_that("x_post throws for NULL session", {
  expect_error(x_post(NULL, "1234567890123456789"), "session must be")
})

# --- Test 16: x_post rejects non-xtweetsR_session ---
test_that("x_post throws for plain list session", {
  expect_error(x_post(list(foo = "bar"), "1234567890123456789"), "session must be")
})

# --- Test 17: x_post rejects empty post_id ---
test_that("x_post throws for empty post_id", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_post(mock_session, ""), "non-empty")
})

# --- Test 18: x_post rejects whitespace-only post_id ---
test_that("x_post throws for whitespace-only post_id", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_post(mock_session, "   "), "non-empty")
})

# --- x_post() navigation tests ---

# --- Test 19: Navigation failure returns empty tibble with warning ---
test_that("x_post navigation failure returns empty tibble with warning", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "error", error = list(code = "NAV_FAIL"))

  expect_warning(
    result <- x_post(mock_session, "1234567890123456789"),
    "Navigation failed"
  )
  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(grepl("^post:", provenance$query))
  expect_equal(provenance$records, 0L)
})

# --- Test 20: x_post normalizes URL from bare ID ---
test_that("x_post normalizes bare post ID to canonical URL", {
  captured_url <- character(0)
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) {
    captured_url <<- url
    list(status = "ok")
  }
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  x_post(mock_session, "1234567890123456789")

  expect_true(grepl("^https://x.com/status/1234567890123456789$", captured_url),
              info = paste("captured URL:", captured_url))
})

# --- Test 21: x_post normalizes full URL ---
test_that("x_post normalizes full URL to canonical form", {
  captured_url <- character(0)
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) {
    captured_url <<- url
    list(status = "ok")
  }
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  x_post(mock_session, "https://x.com/rstudio/status/1234567890123456789")

  expect_true(grepl("^https://x.com/status/1234567890123456789$", captured_url),
              info = paste("captured URL:", captured_url))
})

# --- Test 22: x_post normalizes twitter.com URL ---
test_that("x_post normalizes twitter.com URLs to x.com", {
  captured_url <- character(0)
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) {
    captured_url <<- url
    list(status = "ok")
  }
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  x_post(mock_session, "https://twitter.com/rstudio/status/9876543210987654321")

  expect_true(grepl("^https://x.com/status/9876543210987654321$", captured_url),
              info = paste("captured URL:", captured_url))
})

# --- Test 23: x_post with fixture data through mock backend ---
test_that("x_post processes fixture data through mock backend", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list(
    list(requestId = "req-1", url = "https://x.com/status/1234567890123456789", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_post(mock_session, "1234567890123456789")

  expect_true(inherits(result, "tbl_df"))
  expect_true(nrow(result) >= 1, info = "fixture has posts, should get at least one")
  expect_true("post_id" %in% names(result))
  expect_true("text" %in% names(result))

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(grepl("^post:", provenance$query))
  expect_lte(provenance$records, 1L, info = "limit=1 should cap results")
})

# --- Test 24: x_post empty response returns zero-row tibble ---
test_that("x_post returns empty tibble when no events captured", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_post(mock_session, "1234567890123456789")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
  expect_equal(ncol(result), 24L)
})

# --- Test 25: x_post returns empty tibble when response body is unparseable ---
test_that("x_post handles unparseable response body gracefully", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list(
    list(requestId = "req-1", url = "https://x.com/graphql", contentType = "application/json")
  )
  # Return a response body that is NOT valid post data (a simple string).
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = "not json at all", contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_post(mock_session, "1234567890123456789")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
  expect_equal(ncol(result), 24L)

  # Provenance should still be attached.
  provenance <- attr(result, "rx_collection_provenance")
  expect_true(is.list(provenance))
  expect_equal(provenance$records, 0L)
  expect_true(grepl("^post:", provenance$query))
})

# --- Test 26: x_post provenance is attached when no events are captured ---
test_that("x_post attaches provenance with zero-row result on no-events", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_post(mock_session, "9876543210987654321")

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(is.list(provenance))
  expect_true("collection_id" %in% names(provenance))
  expect_true("started_at" %in% names(provenance))
  expect_true("query" %in% names(provenance))
  expect_true("backend" %in% names(provenance))
  expect_true("records" %in% names(provenance))
  expect_equal(provenance$records, 0L)
  expect_equal(provenance$query, "post:9876543210987654321")
  expect_true(provenance$backend %in% c("lightpanda", "chromium", "unknown"))
  expect_true(inherits(provenance$started_at, "POSIXct"))
})
