# Tests for x_thread() — thread extraction (Iteration 82).
#
# These tests cover:
# - Input validation for x_thread()
# - URL normalization through x_thread()
# - Navigation failure handling
# - Fixture-based thread extraction (4 posts: parent + 3 replies)
# - Empty response handling
# - Provenance attachment
# - Conversation_id grouping
# - Deduplication within thread
# - Quiet mode

# --- x_thread() input validation tests ---

# --- Test 1: x_thread rejects NULL session ---
test_that("x_thread throws for NULL session", {
  expect_error(x_thread(NULL, "1234567890123456789"), "session must be")
})

# --- Test 2: x_thread rejects non-xtweetsR_session ---
test_that("x_thread throws for plain list session", {
  expect_error(x_thread(list(foo = "bar"), "1234567890123456789"), "session must be")
})

# --- Test 3: x_thread rejects empty post_id ---
test_that("x_thread throws for empty post_id", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_thread(mock_session, ""), "non-empty")
})

# --- Test 4: x_thread rejects whitespace-only post_id ---
test_that("x_thread throws for whitespace-only post_id", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_thread(mock_session, "   "), "non-empty")
})

# --- x_thread() URL normalization tests ---

# --- Test 5: x_thread normalizes bare post ID to canonical URL ---
test_that("x_thread normalizes bare post ID to canonical URL", {
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

  x_thread(mock_session, "1234567890123456789")

  expect_true(grepl("^https://x.com/status/1234567890123456789$", captured_url)
              )
})

# --- Test 6: x_thread normalizes x.com full URL ---
test_that("x_thread normalizes x.com URL to canonical form", {
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

  x_thread(mock_session, "https://x.com/rstudio/status/1234567890123456789")

  expect_true(grepl("^https://x.com/status/1234567890123456789$", captured_url)
              )
})

# --- Test 7: x_thread normalizes twitter.com URL ---
test_that("x_thread normalizes twitter.com URL to x.com", {
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

  x_thread(mock_session, "https://twitter.com/rstudio/status/9876543210987654321")

  expect_true(grepl("^https://x.com/status/9876543210987654321$", captured_url)
              )
})

# --- x_thread() navigation failure tests ---

# --- Test 8: Navigation failure returns empty tibble with warning ---
test_that("x_thread navigation failure returns empty tibble with warning", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "error", error = list(code = "NAV_FAIL"))

  expect_warning(
    result <- x_thread(mock_session, "1234567890123456789"),
    "Navigation failed"
  )
  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(grepl("^thread:", provenance$query))
  expect_equal(provenance$records, 0L)
})

# --- x_thread() fixture integration tests ---

# --- Test 9: x_thread extracts all posts from thread fixture ---
test_that("x_thread extracts multiple posts from thread fixture", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-thread-response.json"
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
    list(requestId = "req-1", url = "https://x.com/status/1900000000000000100", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_thread(mock_session, "1900000000000000100")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 4L)
  expect_true("post_id" %in% names(result))
  expect_true("text" %in% names(result))
  expect_true("is_reply" %in% names(result))
  expect_true("reply_to_post_id" %in% names(result))
})

# --- Test 10: Thread posts share the same conversation_id ---
test_that("x_thread posts in the same thread share conversation_id", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-thread-response.json"
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
    list(requestId = "req-1", url = "https://x.com/status/1900000000000000100", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_thread(mock_session, "1900000000000000100")

  # All 4 posts should share the same conversation_id
  expect_equal(length(unique(result$conversation_id)), 1L
              )
  expect_equal(unique(result$conversation_id), "1900000000000000100")
})

# --- Test 11: Thread includes both parent and replies ---
test_that("x_thread returns parent tweet and all replies", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-thread-response.json"
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
    list(requestId = "req-1", url = "https://x.com/status/1900000000000000100", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_thread(mock_session, "1900000000000000100")

  # Check that the parent tweet (1900000000000000100) is present
  expect_true("1900000000000000100" %in% result$post_id)
  # Check that reply tweets are present
  expect_true("1900000000000000101" %in% result$post_id)
  expect_true("1900000000000000102" %in% result$post_id)
  expect_true("1900000000000000103" %in% result$post_id)
})

# --- Test 12: Thread distinguishes parent from replies via is_reply ---
test_that("x_thread correctly identifies parent vs reply posts", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-thread-response.json"
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
    list(requestId = "req-1", url = "https://x.com/status/1900000000000000100", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_thread(mock_session, "1900000000000000100")

  # Parent post should have is_reply = FALSE
  parent <- result[result$post_id == "1900000000000000100", ]
  expect_false(parent$is_reply)
  expect_true(is.na(parent$reply_to_post_id))

  # Reply posts should have is_reply = TRUE
  replies <- result[result$is_reply == TRUE, ]
  expect_equal(nrow(replies), 3L)
  expect_true(all(!is.na(replies$reply_to_post_id)))
})

# --- x_thread() empty/unparseable response tests ---

# --- Test 13: x_thread returns empty tibble when no events captured ---
test_that("x_thread returns empty tibble when no events captured", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_thread(mock_session, "1234567890123456789")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
  expect_equal(ncol(result), 26L)
})

# --- Test 14: x_thread handles unparseable response body gracefully ---
test_that("x_thread handles unparseable response body gracefully", {
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

  result <- x_thread(mock_session, "1234567890123456789")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
  expect_equal(ncol(result), 26L)

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(is.list(provenance))
  expect_equal(provenance$records, 0L)
  expect_true(grepl("^thread:", provenance$query))
})

# --- Test 15: x_thread attaches provenance with zero-row result on no-events ---
test_that("x_thread attaches provenance with zero-row result on no-events", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_thread(mock_session, "9876543210987654321")

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(is.list(provenance))
  expect_true("collection_id" %in% names(provenance))
  expect_true("started_at" %in% names(provenance))
  expect_true("query" %in% names(provenance))
  expect_true("backend" %in% names(provenance))
  expect_true("records" %in% names(provenance))
  expect_equal(provenance$records, 0L)
  expect_equal(provenance$query, "thread:9876543210987654321")
  expect_true(provenance$backend %in% c("lightpanda", "chromium", "unknown"))
  expect_true(inherits(provenance$started_at, "POSIXct"))
})

# --- Test 16: x_thread deduplicates identical posts in thread ---
test_that("x_thread deduplicates identical posts in thread", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-thread-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  # Duplicate the entire fixture entries to test dedup
  duplicated_fixture <- parsed_fixture
  duplicated_fixture$data$timeline$instructions[[1]]$entries <-
    c(parsed_fixture$data$timeline$instructions[[1]]$entries,
      parsed_fixture$data$timeline$instructions[[1]]$entries)

  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list(
    list(requestId = "req-1", url = "https://x.com/status/1900000000000000100", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = duplicated_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_thread(mock_session, "1900000000000000100")

  # Should have 4 unique posts, not 8
  expect_equal(nrow(result), 4L
              )
})

# --- x_thread() provenance tests ---

# --- Test 17: x_thread provenance query uses thread: prefix ---
test_that("x_thread provenance uses thread: prefix in query", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_thread(mock_session, "abc123def456")

  provenance <- attr(result, "rx_collection_provenance")
  expect_equal(provenance$query, "thread:abc123def456")
})

# --- Test 18: x_thread provenance includes observation-level fields ---
test_that("x_thread observation-level provenance fields are set on results", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-thread-response.json"
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
    list(requestId = "req-1", url = "https://x.com/status/1900000000000000100", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_thread(mock_session, "1900000000000000100")

  expect_true("collected_at" %in% names(result))
  expect_true("collection_query" %in% names(result))
  expect_true("collection_id" %in% names(result))
  expect_equal(nchar(result$collection_id[[1]]), 36L)  # UUID format
  expect_true(all(result$collection_query == "thread:1900000000000000100"))
})

# --- Test 19: x_thread with whitespace-only post_id ---
test_that("x_thread rejects whitespace-only post_id", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_thread(mock_session, "  "), "non-empty")
})

# --- Test 20: x_thread with NA post_id ---
test_that("x_thread rejects NA post_id", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_thread(mock_session, NA_character_), "non-empty")
})
