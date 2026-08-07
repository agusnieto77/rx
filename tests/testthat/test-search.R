# Tests for x_search() and search helpers (Task 39).
#
# These tests cover:
# - Input validation (session, query, limit)
# - .rx_search_is_candidate heuristic
# - .rx_search_empty_tibble schema
# - Integration path (fixture-based, no browser needed)

# --- Test 1: .rx_search_is_candidate accepts X domain JSON ---
test_that("is_candidate returns TRUE for X domain JSON events", {
  evt <- list(
    requestId = "req-1",
    url = "https://x.com/graphql/abc123",
    contentType = "application/json"
  )
  expect_true(.rx_search_is_candidate(evt))
})

# --- Test 2: .rx_search_is_candidate accepts twitter.com ---
test_that("is_candidate returns TRUE for twitter.com domain events", {
  evt <- list(
    requestId = "req-2",
    url = "https://twitter.com/graphql/xyz789",
    contentType = "text/json"
  )
  expect_true(.rx_search_is_candidate(evt))
})

# --- Test 3: .rx_search_is_candidate rejects non-X domains ---
test_that("is_candidate returns FALSE for non-X domain events", {
  evt <- list(
    requestId = "req-3",
    url = "https://example.com/api/data",
    contentType = "application/json"
  )
  expect_false(.rx_search_is_candidate(evt))
})

# --- Test 4: .rx_search_is_candidate rejects non-JSON content ---
test_that("is_candidate returns FALSE for non-JSON content type", {
  evt <- list(
    requestId = "req-4",
    url = "https://x.com/some-page",
    contentType = "text/html"
  )
  expect_false(.rx_search_is_candidate(evt))
})

# --- Test 5: .rx_search_is_candidate handles NULL event ---
test_that("is_candidate returns FALSE for NULL event", {
  expect_false(.rx_search_is_candidate(NULL))
})

# --- Test 6: .rx_search_is_candidate handles missing fields ---
test_that("is_candidate returns FALSE when required fields are missing", {
  evt <- list(requestId = "req-5")
  expect_false(.rx_search_is_candidate(evt))
})

# --- Test 7: .rx_search_is_candidate accepts GraphQL URL without explicit content-type ---
test_that("is_candidate returns TRUE for X GraphQL URLs (implicit JSON)", {
  evt <- list(
    requestId = "req-6",
    url = "https://x.com/graphql/TimelineQuery/abc"
  )
  expect_true(.rx_search_is_candidate(evt))
})

# --- Test 8: .rx_search_is_candidate accepts internal.alg.com ---
test_that("is_candidate returns TRUE for internal.alg.com URLs", {
  evt <- list(
    requestId = "req-7",
    url = "https://x.com/internal.alg.com/search"
  )
  expect_true(.rx_search_is_candidate(evt))
})

# --- Test 9: .rx_search_empty_tibble has canonical schema ---
test_that("empty tibble has all 18 canonical columns", {
  tbl <- .rx_search_empty_tibble()
  expect_true(inherits(tbl, "tbl_df"))
  fields <- .rx_canonical_fields()
  expect_equal(ncol(tbl), 18L)
  expect_equal(sort(names(tbl)), sort(fields))
  expect_equal(nrow(tbl), 0L)
})

# --- Test 10: .rx_search_empty_tibble has correct column types ---
test_that("empty tibble preserves correct column types", {
  tbl <- .rx_search_empty_tibble()
  type_map <- .rx_type_map()

  for (field in names(tbl)) {
    expected_type <- type_map[[field]]
    col <- tbl[[field]]
    actual_type <- switch(expected_type,
      character = "character",
      integer = "integer",
      logical = "logical",
      "unknown"
    )
    expect_equal(actual_type, typeof(col), info = paste("field:", field))
  }
})

# --- Test 11: Input validation - NULL session ---
test_that("x_search throws for NULL session", {
  expect_error(x_search(NULL, "test"), "session must be")
})

# --- Test 12: Input validation - non-xtweetsR_session object ---
test_that("x_search throws for plain list session", {
  expect_error(x_search(list(foo = "bar"), "test"), "session must be")
})

# --- Test 13: Input validation - empty query ---
test_that("x_search throws for empty query", {
  # We need a mock session object with connected=TRUE and a backend
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "error")

  expect_error(x_search(mock_session, ""), "non-empty")
})

# --- Test 14: Input validation - query with whitespace only ---
test_that("x_search throws for whitespace-only query", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "error")

  expect_error(x_search(mock_session, "   "), "non-empty")
})

# --- Test 15: Input validation - invalid limit ---
test_that("x_search throws for negative limit", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "error")

  expect_error(x_search(mock_session, "test", limit = -1), "positive")
})

# --- Test 16: Navigation failure returns empty tibble with warning ---
test_that("navigation failure returns empty tibble with warning", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "error", error = list(code = "NAV_FAIL"))

  expect_warning(
    result <- x_search(mock_session, "test"),
    "Navigation failed"
  )
  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
})

# --- Test 17: Successful path with fixture data (no browser) ---
test_that("search pipeline processes fixture data through events", {
  # Build a mock session that simulates having captured a JSON response
  # from the x-search-response.json fixture.
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
  # Return a single event pointing to our fixture data.
  mock_session$backend$networkCaptureGet <- function() list(
    list(requestId = "req-1", url = "https://x.com/graphql/test", contentType = "application/json")
  )
  # Return the parsed fixture as the body.
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  # This test sleeps briefly (3s) due to the Sys.sleep in x_search.
  result <- x_search(mock_session, "test")

  expect_true(inherits(result, "tbl_df"))
  expect_true(nrow(result) >= 1, info = "fixture has posts, should get at least one")
  expect_true("post_id" %in% names(result))
  expect_true("text" %in% names(result))
})

# --- Test 18: Limit is enforced ---
test_that("limit truncates results to specified count", {
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
    list(requestId = "req-1", url = "https://x.com/graphql/test", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_search(mock_session, "test", limit = 2)

  expect_true(inherits(result, "tbl_df"))
  expect_lte(nrow(result), 2L)
})

# --- Test 19: Deduplication works in search pipeline ---
test_that("duplicate posts are deduplicated by search", {
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
  # Two events, both returning the same fixture — simulates duplicates.
  mock_session$backend$networkCaptureGet <- function() {
    list(
      list(requestId = "req-1", url = "https://x.com/graphql/test", contentType = "application/json"),
      list(requestId = "req-2", url = "https://x.com/graphql/test2", contentType = "application/json")
    )
  }
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_search(mock_session, "test")

  # The fixture has 4 unique posts. Two events would produce 8 raw posts,
  # but deduplication should collapse to 4 unique post_ids.
  expect_true(inherits(result, "tbl_df"))
  unique_ids <- unique(result$post_id)
  expect_true(length(unique_ids) >= 1)
  expect_true(length(unique_ids) == nrow(result), info = "no duplicates should remain")
})

# --- Test 20: Scroll helper expression is valid JavaScript ---
test_that(".rx_scroll_page executes a valid scroll expression", {
  # The scroll helper should be a simple window.scrollBy call.
  # We can't execute JS without a real browser, so we verify the
  # backend method is called by mocking it.
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  scroll_called <- FALSE
  mock_session$backend$evaluate <- function(expr) {
    scroll_called <<- TRUE
    expect_true(is.character(expr))
    expect_true(grepl("scrollBy", expr, fixed = TRUE))
    invisible(NULL)
  }

  x_search(mock_session, "test", scroll = TRUE)
  expect_true(scroll_called, info = "scroll should be triggered when scroll=TRUE")
})

# --- Test 21: Scroll with scroll=FALSE does not call evaluate ---
test_that("x_search with scroll=FALSE skips the scroll step", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  scroll_called <- FALSE
  mock_session$backend$evaluate <- function(expr) {
    scroll_called <<- TRUE
    invisible(NULL)
  }

  x_search(mock_session, "test", scroll = FALSE)
  expect_false(scroll_called, info = "scroll should NOT be triggered when scroll=FALSE")
})

# --- Test 22: Scroll batch with new posts merges correctly ---
test_that("scroll batch with new posts is merged and deduplicated", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  # Initial batch: fixture with 4 posts
  # Scroll batch: different fixture with 2 posts (simulating new content)
  # We need a second fixture with different post_ids.
  fixture_with_2_posts <- list(
    TimelineResult = list(
      result = list(
        __typename = "TimelineTimelineItem",
        timeline_instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = list(
              list(
                entryId = "tweet-999",
                content = list(
                  __typename = "TimelineTimelineItem",
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        __typename = "TweetWithVisibilityResults",
                        tweet = list(
                          rest_id = "999",
                          legacy = list(
                            full_text = "Scroll post 1",
                            created_at = "Mon Jul 01 00:00:00 +0000 2026",
                            user_id_str = "u-scroll-1",
                            screen_name = "scrolluser1",
                            name = "Scroll User One",
                            reply_count = 1L,
                            retweet_count = 2L,
                            favorite_count = 3L,
                            quote_count = 0L,
                            bookmark_count = 0L,
                            conversation_id_str = "999",
                            in_reply_to_status_id_str = NA_character_,
                            is_quote_status = FALSE
                          ),
                          core = list(
                            user_results = list(
                              result = list(
                                legacy = list(
                                  id_str = "u-scroll-1",
                                  screen_name = "scrolluser1",
                                  name = "Scroll User One"
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              ),
              list(
                entryId = "tweet-998",
                content = list(
                  __typename = "TimelineTimelineItem",
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        __typename = "TweetWithVisibilityResults",
                        tweet = list(
                          rest_id = "998",
                          legacy = list(
                            full_text = "Scroll post 2",
                            created_at = "Sun Jun 30 00:00:00 +0000 2026",
                            user_id_str = "u-scroll-2",
                            screen_name = "scrolluser2",
                            name = "Scroll User Two",
                            reply_count = 0L,
                            retweet_count = 1L,
                            favorite_count = 5L,
                            quote_count = 0L,
                            bookmark_count = 0L,
                            conversation_id_str = "998",
                            in_reply_to_status_id_str = NA_character_,
                            is_quote_status = FALSE
                          ),
                          core = list(
                            user_results = list(
                              result = list(
                                legacy = list(
                                  id_str = "u-scroll-2",
                                  screen_name = "scrolluser2",
                                  name = "Scroll User Two"
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )

  scroll_fixture <- jsonlite::toJSON(fixture_with_2_posts, auto_unbox = TRUE, simplifyVector = FALSE)

  initial_event <- list(
    requestId = "req-init-1", url = "https://x.com/graphql/init", contentType = "application/json"
  )
  scroll_event <- list(
    requestId = "req-scroll-1", url = "https://x.com/graphql/scroll", contentType = "application/json"
  )

  call_count <- 0L
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  # First call returns initial batch events
  mock_session$backend$networkCaptureGet <- function() {
    call_count <<- call_count + 1L
    if (call_count == 1L) {
      initial_event
    } else {
      # Second call (after scroll) returns scroll batch events
      scroll_event
    }
  }
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    if (grepl("^req-init", requestId)) {
      list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
    } else {
      # Parse scroll fixture as string
      list(requestId = requestId, body = scroll_fixture, contentType = "application/json", error = NULL)
    }
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$evaluate <- function(expr) invisible(NULL)

  result <- x_search(mock_session, "test", scroll = TRUE)

  expect_true(inherits(result, "tbl_df"))
  expect_true(nrow(result) >= 4, info = "initial batch has 4+ posts")
  expect_true(nrow(result) >= 6, info = "merged result should have initial + scroll posts (8 unique)")
  expect_true("post_id" %in% names(result))
  # Verify that posts from both batches exist
  expect_true(any(grepl("998|999", result$post_id)), info = "scroll batch posts should be present")
})

# --- Test 23: Scroll failure is non-fatal ---
test_that("x_search handles scroll evaluation failure gracefully", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  # Evaluate throws — scroll should fail silently
  mock_session$backend$evaluate <- function(expr) {
    stop("page closed")
  }

  # Should NOT throw; returns empty tibble gracefully
  expect_silent(result <- x_search(mock_session, "test", scroll = TRUE))
  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
})
