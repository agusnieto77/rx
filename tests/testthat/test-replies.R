# Tests for x_replies() — replies extraction (Iteration 83).
#
# These tests cover:
# - Input validation for x_replies()
# - URL construction
# - Navigation failure handling
# - Fixture-based extraction (5 posts: 2 replies, 3 non-replies)
# - Filtering behavior (only replies returned)
# - Empty response handling
# - Unparseable response handling
# - Provenance attachment
# - Limit enforcement
# - Quiet mode

# --- x_replies() input validation tests ---

# --- Test 1: x_replies rejects NULL session ---
test_that("x_replies throws for NULL session", {
  expect_error(x_replies(NULL, "rstudio"), "session must be")
})

# --- Test 2: x_replies rejects non-xtweetsR_session ---
test_that("x_replies throws for plain list session", {
  expect_error(x_replies(list(foo = "bar"), "rstudio"), "session must be")
})

# --- Test 3: x_replies rejects empty username ---
test_that("x_replies throws for empty username", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_replies(mock_session, ""), "non-empty")
})

# --- Test 4: x_replies rejects whitespace-only username ---
test_that("x_replies throws for whitespace-only username", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_replies(mock_session, "   "), "non-empty")
})

# --- x_replies() URL construction tests ---

# --- Test 5: x_replies constructs search URL with @username ---
test_that("x_replies constructs URL with @username", {
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

  x_replies(mock_session, "rstudio")

  expect_true(grepl("@rstudio", captured_url),
              info = paste("captured URL:", captured_url))
  expect_true(grepl("f%3Dlive", captured_url, ignore.case = TRUE),
              info = paste("captured URL:", captured_url))
})

# --- Test 6: x_replies URL-encodes special characters in username ---
test_that("x_replies URL-encodes special characters in username", {
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

  x_replies(mock_session, "test+user")

  expect_true(grepl("test%2Buser", captured_url),
              info = paste("captured URL:", captured_url))
})

# --- x_replies() navigation failure tests ---

# --- Test 7: Navigation failure returns empty tibble with warning ---
test_that("x_replies navigation failure returns empty tibble with warning", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "error", error = list(code = "NAV_FAIL"))

  expect_warning(
    result <- x_replies(mock_session, "rstudio"),
    "Navigation failed"
  )
  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(grepl("^replies:", provenance$query))
  expect_equal(provenance$records, 0L)
})

# --- x_replies() fixture integration tests ---

# --- Test 8: x_replies extracts replies from fixture ---
test_that("x_replies extracts 2 replies from fixture (5 total posts)", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-replies-response.json"
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
    list(requestId = "req-1", url = "https://x.com/search?q=@rstudio", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_replies(mock_session, "rstudio")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 2L, info = "fixture has 5 posts, 2 of which are replies")
  expect_true("post_id" %in% names(result))
  expect_true("text" %in% names(result))
  expect_true("is_reply" %in% names(result))
  expect_true("reply_to_post_id" %in% names(result))
})

# --- Test 9: x_replies returns only posts where is_reply is TRUE ---
test_that("x_replies filters to only reply posts", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-replies-response.json"
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
    list(requestId = "req-1", url = "https://x.com/search?q=@rstudio", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_replies(mock_session, "rstudio")

  # All returned posts must be replies
  expect_true(all(result$is_reply == TRUE),
              info = "all returned posts should have is_reply = TRUE")
  # Should not include non-reply posts (200 = regular mention, 203 = mention with URL)
  expect_false("1900000000000000200" %in% result$post_id)
  expect_false("1900000000000000203" %in% result$post_id)
  # Should include reply posts (201 and 204)
  expect_true("1900000000000000201" %in% result$post_id)
  expect_true("1900000000000000204" %in% result$post_id)
})

# --- Test 10: x_replies handles no events captured ---
test_that("x_replies returns empty tibble when no events captured", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_replies(mock_session, "rstudio")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
  expect_equal(ncol(result), 26L)
})

# --- Test 11: x_replies handles unparseable response body ---
test_that("x_replies handles unparseable response body gracefully", {
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

  result <- x_replies(mock_session, "rstudio")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
  expect_equal(ncol(result), 26L)

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(is.list(provenance))
  expect_equal(provenance$records, 0L)
  expect_true(grepl("^replies:", provenance$query))
})

# --- x_replies() provenance tests ---

# --- Test 12: x_replies attaches provenance with zero-row result ---
test_that("x_replies attaches provenance with zero-row result", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_replies(mock_session, "rstudio")

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(is.list(provenance))
  expect_true("collection_id" %in% names(provenance))
  expect_true("started_at" %in% names(provenance))
  expect_true("query" %in% names(provenance))
  expect_true("backend" %in% names(provenance))
  expect_true("records" %in% names(provenance))
  expect_equal(provenance$records, 0L)
  expect_equal(provenance$query, "replies:rstudio")
  expect_true(provenance$backend %in% c("lightpanda", "chromium", "unknown"))
  expect_true(inherits(provenance$started_at, "POSIXct"))
})

# --- Test 13: x_replies provenance uses replies: prefix ---
test_that("x_replies provenance uses replies: prefix in query", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list(
    list(requestId = "req-1", url = "https://x.com/search?q=@rstudio", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = list(), contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_replies(mock_session, "rstudio")

  provenance <- attr(result, "rx_collection_provenance")
  expect_equal(provenance$query, "replies:rstudio")
})

# --- Test 14: x_replies observation-level provenance fields are set ---
test_that("x_replies observation-level provenance fields are set on results", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-replies-response.json"
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
    list(requestId = "req-1", url = "https://x.com/search?q=@rstudio", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_replies(mock_session, "rstudio")

  expect_true("collected_at" %in% names(result))
  expect_true("collection_query" %in% names(result))
  expect_true("collection_id" %in% names(result))
  expect_equal(nchar(result$collection_id[[1]]), 36L)  # UUID format
  expect_true(all(result$collection_query == "replies:rstudio"))
})

# --- x_replies() limit tests ---

# --- Test 15: x_replies limit parameter works ---
test_that("x_replies respects limit parameter", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-replies-response.json"
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
    list(requestId = "req-1", url = "https://x.com/search?q=@rstudio", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_replies(mock_session, "rstudio", limit = 1L)

  expect_true(inherits(result, "tbl_df"))
  expect_true(nrow(result) <= 1L, info = "limit=1 should return at most 1 post")
})

# --- x_replies() edge case tests ---

# --- Test 16: x_replies with whitespace-only username ---
test_that("x_replies rejects whitespace-only username", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_replies(mock_session, "  "), "non-empty")
})

# --- Test 17: x_replies with NA username ---
test_that("x_replies rejects NA username", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_replies(mock_session, NA_character_), "non-empty")
})

# --- Test 18: x_replies with disconnected session ---
test_that("x_replies throws for disconnected session", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- FALSE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"

  expect_error(x_replies(mock_session, "rstudio"), "not connected")
})

# --- Test 19: x_replies quiet mode suppresses messages ---
test_that("x_replies quiet mode suppresses progress messages", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_message(
    x_replies(mock_session, "rstudio", quiet = TRUE),
    regexp = NA
  )
})

# --- Test 20: x_replies with limit=0 ---
test_that("x_replies rejects limit=0", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_replies(mock_session, "rstudio", limit = 0L), "positive")
})

# --- x_replies() mode parameter tests (Iteration 81) ---

# --- Test 21: x_replies mode='latest' produces f=live in URL ---
test_that("x_replies mode='latest' produces f=live in URL", {
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

  x_replies(mock_session, "rstudio", mode = "latest")

  expect_true(grepl("f%3Dlive", captured_url, ignore.case = TRUE),
              info = paste("captured URL:", captured_url))
})

# --- Test 22: x_replies mode='top' produces f=top in URL ---
test_that("x_replies mode='top' produces f=top in URL", {
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

  x_replies(mock_session, "rstudio", mode = "top")

  expect_true(grepl("f%3Dtop", captured_url, ignore.case = TRUE),
              info = paste("captured URL:", captured_url))
})

# --- Test 23: x_replies mode is case-insensitive ---
test_that("x_replies mode is case-insensitive", {
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

  x_replies(mock_session, "rstudio", mode = "TOP")

  expect_true(grepl("f%3Dtop", captured_url, ignore.case = TRUE),
              info = paste("captured URL:", captured_url))
})

# --- Test 24: x_replies rejects invalid mode ---
test_that("x_replies rejects invalid mode", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_replies(mock_session, "rstudio", mode = "recent"), "latest.*top")
  expect_error(x_replies(mock_session, "rstudio", mode = NA_character_), "latest.*top")
  expect_error(x_replies(mock_session, "rstudio", mode = "  "), "latest.*top")
})
