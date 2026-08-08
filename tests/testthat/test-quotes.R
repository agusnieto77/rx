# Tests for x_quotes() — quote tweets extraction (Iteration 84).
#
# These tests cover:
# - Input validation for x_quotes()
# - URL construction
# - Navigation failure handling
# - Fixture-based extraction (5 posts: 3 quotes, 2 non-quotes)
# - Filtering behavior (only quote tweets returned)
# - Empty response handling
# - Unparseable response handling
# - Provenance attachment
# - Limit enforcement
# - Quiet mode

# --- x_quotes() input validation tests ---

# --- Test 1: x_quotes rejects NULL session ---
test_that("x_quotes throws for NULL session", {
  expect_error(x_quotes(NULL, "1234567890123456789"), "session must be")
})

# --- Test 2: x_quotes rejects non-xtweetsR_session ---
test_that("x_quotes throws for plain list session", {
  expect_error(x_quotes(list(foo = "bar"), "1234567890123456789"), "session must be")
})

# --- Test 3: x_quotes rejects empty post_id ---
test_that("x_quotes throws for empty post_id", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_quotes(mock_session, ""), "non-empty")
})

# --- Test 4: x_quotes rejects whitespace-only post_id ---
test_that("x_quotes throws for whitespace-only post_id", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_quotes(mock_session, "   "), "non-empty")
})

# --- x_quotes() URL construction tests ---

# --- Test 5: x_quotes constructs search URL with post URL ---
test_that("x_quotes constructs URL with post URL", {
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

  x_quotes(mock_session, "1234567890123456789")

  expect_true(grepl("x\\.com/status/1234567890123456789", captured_url),
              info = paste("captured URL:", captured_url))
  expect_true(grepl("f%3Dlive", captured_url, ignore.case = TRUE),
              info = paste("captured URL:", captured_url))
})

# --- Test 6: x_quotes URL-encodes the post URL in search query ---
test_that("x_quotes URL-encodes the post URL", {
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

  x_quotes(mock_session, "https://x.com/rstudio/status/1234567890123456789")

  # The URL should be URL-encoded in the search query
  expect_true(grepl("q=", captured_url),
              info = paste("captured URL:", captured_url))
  expect_true(grepl("x\\.com", captured_url),
              info = paste("captured URL:", captured_url))
})

# --- x_quotes() navigation failure tests ---

# --- Test 7: Navigation failure returns empty tibble with warning ---
test_that("x_quotes navigation failure returns empty tibble with warning", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "error", error = list(code = "NAV_FAIL"))

  expect_warning(
    result <- x_quotes(mock_session, "1234567890123456789"),
    "Navigation failed"
  )
  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(grepl("^quotes:", provenance$query))
  expect_equal(provenance$records, 0L)
})

# --- x_quotes() fixture integration tests ---

# --- Test 8: x_quotes extracts only quote tweets from fixture ---
test_that("x_quotes extracts quote tweets from fixture", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-quote-tweets-response.json"
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
    list(requestId = "req-1", url = "https://x.com/search", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_quotes(mock_session, "1900000000000000100")

  expect_true(inherits(result, "tbl_df"))
  # Fixture has 3 quote tweets (300, 302, 304) and 2 non-quotes (301, 303)
  expect_equal(nrow(result), 3L, info = "3 quote tweets should be extracted from fixture")
  expect_true("post_id" %in% names(result))
  expect_true("is_quote" %in% names(result))
})

# --- Test 9: All returned posts have is_quote == TRUE ---
test_that("x_quotes returns only posts with is_quote TRUE", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-quote-tweets-response.json"
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
    list(requestId = "req-1", url = "https://x.com/search", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_quotes(mock_session, "1900000000000000100")

  expect_true(all(result$is_quote == TRUE),
              info = "all returned posts should have is_quote == TRUE")
})

# --- Test 10: All returned posts have the correct quoted_post_id ---
test_that("x_quotes filters by quoted_post_id match", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-quote-tweets-response.json"
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
    list(requestId = "req-1", url = "https://x.com/search", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_quotes(mock_session, "1900000000000000100")

  expect_true(all(result$quoted_post_id == "1900000000000000100"),
              info = "all returned posts should quote the target post")
})

# --- Test 11: Non-quote posts are excluded ---
test_that("x_quotes excludes non-quote posts from results", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-quote-tweets-response.json"
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
    list(requestId = "req-1", url = "https://x.com/search", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_quotes(mock_session, "1900000000000000100")

  # Posts 301 and 303 are non-quotes — should NOT appear
  expect_false("1900000000000000301" %in% result$post_id)
  expect_false("1900000000000000303" %in% result$post_id)
  # Quote posts 300, 302, 304 SHOULD appear
  expect_true("1900000000000000300" %in% result$post_id)
  expect_true("1900000000000000302" %in% result$post_id)
  expect_true("1900000000000000304" %in% result$post_id)
})

# --- x_quotes() empty/unparseable response tests ---

# --- Test 12: x_quotes returns empty tibble when no events captured ---
test_that("x_quotes returns empty tibble when no events captured", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_quotes(mock_session, "1234567890123456789")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
  expect_equal(ncol(result), 26L)
})

# --- Test 13: x_quotes handles unparseable response body gracefully ---
test_that("x_quotes handles unparseable response body gracefully", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list(
    list(requestId = "req-1", url = "https://x.com/graphql", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = "not json at all", contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_quotes(mock_session, "1234567890123456789")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
  expect_equal(ncol(result), 26L)

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(is.list(provenance))
  expect_equal(provenance$records, 0L)
  expect_true(grepl("^quotes:", provenance$query))
})

# --- Test 14: x_quotes attaches provenance with zero-row result on no-events ---
test_that("x_quotes attaches provenance with zero-row result on no-events", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_quotes(mock_session, "9876543210987654321")

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(is.list(provenance))
  expect_true("collection_id" %in% names(provenance))
  expect_true("started_at" %in% names(provenance))
  expect_true("query" %in% names(provenance))
  expect_true("backend" %in% names(provenance))
  expect_true("records" %in% names(provenance))
  expect_equal(provenance$records, 0L)
  expect_equal(provenance$query, "quotes:9876543210987654321")
  expect_true(provenance$backend %in% c("lightpanda", "chromium", "unknown"))
  expect_true(inherits(provenance$started_at, "POSIXct"))
})

# --- x_quotes() provenance tests ---

# --- Test 15: x_quotes provenance query uses quotes: prefix ---
test_that("x_quotes provenance uses quotes: prefix in query", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_quotes(mock_session, "abc123def456")

  provenance <- attr(result, "rx_collection_provenance")
  expect_equal(provenance$query, "quotes:abc123def456")
})

# --- Test 16: x_quotes provenance includes observation-level fields ---
test_that("x_quotes observation-level provenance fields are set on results", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-quote-tweets-response.json"
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
    list(requestId = "req-1", url = "https://x.com/search", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_quotes(mock_session, "1900000000000000100")

  expect_true("collected_at" %in% names(result))
  expect_true("collection_query" %in% names(result))
  expect_true("collection_id" %in% names(result))
  expect_equal(nchar(result$collection_id[[1]]), 36L)  # UUID format
  expect_true(all(result$collection_query == "quotes:1900000000000000100"))
})

# --- Test 17: x_quotes with whitespace-only post_id ---
test_that("x_quotes rejects whitespace-only post_id", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_quotes(mock_session, "  "), "non-empty")
})

# --- Test 18: x_quotes with NA post_id ---
test_that("x_quotes rejects NA post_id", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_quotes(mock_session, NA_character_), "non-empty")
})

# --- Test 19: x_quotes limit enforcement ---
test_that("x_quotes respects limit parameter", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-quote-tweets-response.json"
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
    list(requestId = "req-1", url = "https://x.com/search", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_quotes(mock_session, "1900000000000000100", limit = 2L)

  expect_equal(nrow(result), 2L,
              info = "limit=2 should return at most 2 quote tweets")
})

# --- Test 20: x_quotes with canonical URL post_id normalizes correctly ---
test_that("x_quotes normalizes x.com full URL to search query", {
  captured_url <- character(0)
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-quote-tweets-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) {
    captured_url <<- url
    list(status = "ok")
  }
  mock_session$backend$networkCaptureGet <- function() list(
    list(requestId = "req-1", url = "https://x.com/search", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_quotes(mock_session, "https://x.com/rstudio/status/1900000000000000100")

  expect_true(inherits(result, "tbl_df"))
  # Should navigate to a search URL containing the post URL
  expect_true(grepl("x\\.com/status/1900000000000000100", captured_url),
              info = paste("captured URL:", captured_url))
  # Should return quote tweets that quote 1900000000000000100
  expect_true(all(result$quoted_post_id == "1900000000000000100"))
})

# --- x_quotes() mode parameter tests (Iteration 81) ---

# --- Test 21: x_quotes mode='latest' produces f=live in URL ---
test_that("x_quotes mode='latest' produces f=live in URL", {
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

  x_quotes(mock_session, "1234567890123456789", mode = "latest")

  expect_true(grepl("f%3Dlive", captured_url, ignore.case = TRUE),
              info = paste("captured URL:", captured_url))
})

# --- Test 22: x_quotes mode='top' produces f=top in URL ---
test_that("x_quotes mode='top' produces f=top in URL", {
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

  x_quotes(mock_session, "1234567890123456789", mode = "top")

  expect_true(grepl("f%3Dtop", captured_url, ignore.case = TRUE),
              info = paste("captured URL:", captured_url))
})

# --- Test 23: x_quotes mode is case-insensitive ---
test_that("x_quotes mode is case-insensitive", {
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

  x_quotes(mock_session, "1234567890123456789", mode = "TOP")

  expect_true(grepl("f%3Dtop", captured_url, ignore.case = TRUE),
              info = paste("captured URL:", captured_url))
})

# --- Test 24: x_quotes rejects invalid mode ---
test_that("x_quotes rejects invalid mode", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_quotes(mock_session, "1234567890123456789", mode = "recent"), "latest.*top")
  expect_error(x_quotes(mock_session, "1234567890123456789", mode = NA_character_), "latest.*top")
  expect_error(x_quotes(mock_session, "1234567890123456789", mode = "  "), "latest.*top")
})
