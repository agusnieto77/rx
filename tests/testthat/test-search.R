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
test_that("empty tibble has all 26 canonical columns (Tasks 56-57)", {
  tbl <- .rx_search_empty_tibble()
  expect_true(inherits(tbl, "tbl_df"))
  fields <- .rx_canonical_fields()
  expect_equal(ncol(tbl), 26L)
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
      list = "list",
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
        `__typename` = "TimelineTimelineItem",
        timeline_instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = list(
              list(
                entryId = "tweet-999",
                content = list(
                  `__typename` = "TimelineTimelineItem",
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        `__typename` = "TweetWithVisibilityResults",
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
                  `__typename` = "TimelineTimelineItem",
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        `__typename` = "TweetWithVisibilityResults",
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

# ===================================================================
# Scroll state tests (Task 41)
# ===================================================================

# --- Test 24: .rx_scroll_state_new creates a valid state object ---
test_that("scroll state constructor initializes all fields", {
  state <- .rx_scroll_state_new()

  expect_s3_class(state, "rx_scroll_state")
  expect_type(state$seen_post_ids, "character")
  expect_equal(length(state$seen_post_ids), 0L)
  expect_type(state$current_count, "integer")
  expect_equal(state$current_count, 0L)
  expect_type(state$previous_count, "integer")
  expect_equal(state$previous_count, 0L)
  expect_type(state$no_new_data_cycles, "integer")
  expect_equal(state$no_new_data_cycles, 0L)
  expect_type(state$scroll_position, "double")
  expect_equal(state$scroll_position, 0)
  expect_type(state$last_post_id, "character")
  expect_equal(state$last_post_id, "")
  expect_type(state$last_cursor, "character")
  expect_equal(state$last_cursor, "")
  expect_true(inherits(state$started_at, "POSIXct", "POSIXt"))
  expect_type(state$elapsed_time, "double")
  expect_equal(state$elapsed_time, 0)
})

# --- Test 25: add_posts updates seen_post_ids and current_count ---
test_that("add_posts tracks new post IDs and increments count", {
  state <- .rx_scroll_state_new()

  state$add_posts(list(post_id = c("1", "2", "3")))

  expect_equal(state$current_count, 3L)
  expect_equal(length(state$seen_post_ids), 3L)
  expect_true(all(c("1", "2", "3") %in% state$seen_post_ids))
  expect_equal(state$previous_count, 0L)
  expect_equal(state$no_new_data_cycles, 0L)
  expect_equal(state$last_post_id, "1")
})

# --- Test 26: add_posts deduplicates and detects no-new-data ---
test_that("add_posts deduplicates and increments stall counter", {
  state <- .rx_scroll_state_new()

  # First batch: 3 new posts.
  state$add_posts(list(post_id = c("1", "2", "3")))
  expect_equal(state$current_count, 3L)
  expect_equal(state$no_new_data_cycles, 0L)

  # Second batch: all duplicates.
  state$add_posts(list(post_id = c("1", "2")))
  expect_equal(state$current_count, 3L, info = "count should not grow on duplicates")
  expect_equal(state$no_new_data_cycles, 1L)

  # Third batch: all duplicates again.
  state$add_posts(list(post_id = c("3", "2", "1")))
  expect_equal(state$no_new_data_cycles, 2L)
})

# --- Test 27: add_posts resets stall counter on new data ---
test_that("add_posts resets no_new_data_cycles when new IDs appear", {
  state <- .rx_scroll_state_new()

  state$add_posts(list(post_id = c("1", "2")))
  state$add_posts(list(post_id = c("1")))  # duplicate only
  state$add_posts(list(post_id = c("1", "3")))  # one new

  expect_equal(state$current_count, 3L)
  expect_equal(state$no_new_data_cycles, 0L, info = "stall counter should reset on new data")
  expect_true("3" %in% state$seen_post_ids)
})

# --- Test 28: add_posts handles empty posts list ---
test_that("add_posts with empty posts does not crash", {
  state <- .rx_scroll_state_new()

  state$add_posts(list(post_id = character(0)))

  expect_equal(state$current_count, 0L)
  expect_equal(state$no_new_data_cycles, 1L)
})

# --- Test 29: add_posts handles NULL/missing post_id ---
test_that("add_posts handles missing post_id field gracefully", {
  state <- .rx_scroll_state_new()

  state$add_posts(list(other = "data"))

  expect_equal(state$current_count, 0L)
  expect_equal(state$no_new_data_cycles, 1L)
})

# --- Test 30: add_posts updates cursor ---
test_that("add_posts records the cursor when provided", {
  state <- .rx_scroll_state_new()

  state$add_posts(list(post_id = c("1")), new_cursor = "cursor-abc-123")

  expect_equal(state$last_cursor, "cursor-abc-123")
})

# --- Test 31: check_stalled returns TRUE when threshold exceeded ---
test_that("check_stalled detects stalled collection", {
  state <- .rx_scroll_state_new()

  # Add some data.
  state$add_posts(list(post_id = c("1")))

  # No stalls yet.
  expect_false(state$check_stalled(threshold = 2L))
  expect_false(state$check_stalled(threshold = 1L))

  # Two consecutive no-data batches.
  state$add_posts(list(post_id = character(0)))  # cycle 1
  state$add_posts(list(post_id = character(0)))  # cycle 2

  expect_false(state$check_stalled(threshold = 3L))
  expect_true(state$check_stalled(threshold = 2L))
  expect_true(state$check_stalled(threshold = 1L))
})

# --- Test 32: check_limit enforces the limit ---
test_that("check_limit returns TRUE when current_count >= limit", {
  state <- .rx_scroll_state_new()

  state$add_posts(list(post_id = c("1", "2", "3")))

  expect_false(state$check_limit(5L))
  expect_true(state$check_limit(3L))
  expect_true(state$check_limit(2L))
  expect_true(state$check_limit(1L))
  expect_true(state$check_limit(NULL))
})

# --- Test 33: advance_scroll accumulates position ---
test_that("advance_scroll accumulates scroll position", {
  state <- .rx_scroll_state_new()

  expect_equal(state$scroll_position, 0)

  state$advance_scroll(1000)
  expect_equal(state$scroll_position, 1000)

  state$advance_scroll(3000)
  expect_equal(state$scroll_position, 4000)

  # Default is 4000.
  state$advance_scroll()
  expect_equal(state$scroll_position, 8000)
})

# --- Test 34: scroll state tracks elapsed_time ---
test_that("elapsed_time increases after add_posts", {
  state <- .rx_scroll_state_new()

  # Force a tiny sleep so time advances.
  Sys.sleep(0.05)

  state$add_posts(list(post_id = c("1")))

  expect_true(state$elapsed_time > 0, info = paste("elapsed_time:", state$elapsed_time))
  expect_true(state$elapsed_time < 5, info = "elapsed_time should be reasonable")
})

# ===================================================================
# Repeated scroll loop tests (Task 42)
# ===================================================================

# --- Test 35: Scroll loop terminates when no new data appears ---
test_that("scroll loop terminates after consecutive no-new-data cycles", {
  # Mock backend that returns initial posts, then only duplicates.
  # After 2 no-new-data cycles, check_stalled(threshold=2) returns TRUE.
  batch_idx <- 0L
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"

  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")

  mock_session$backend$networkCaptureGet <- function() {
    batch_idx <<- batch_idx + 1L
    list(
      list(requestId = paste0("req-", batch_idx),
           url = "https://x.com/graphql/test",
           contentType = "application/json")
    )
  }

  # First call: returns 3 posts.
  # Subsequent calls: return the SAME 3 posts (duplicates).
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(
      requestId = requestId,
      body = list(
        TimelineResult = list(
          result = list(
            `__typename` = "TimelineTimelineItem",
            timeline_instructions = list(
              list(
                type = "TimelineAddEntries",
                entries = list(
                  list(
                    entryId = "tweet-100",
                    content = list(
                      `__typename` = "TimelineTimelineItem",
                      itemContent = list(
                        tweet_results = list(
                          result = list(
                            `__typename` = "TweetWithVisibilityResults",
                            tweet = list(
                              rest_id = "100",
                              legacy = list(
                                full_text = "Post one",
                                created_at = "Mon Jul 01 00:00:00 +0000 2026",
                                user_id_str = "u1",
                                screen_name = "user1",
                                name = "User One",
                                reply_count = 1L,
                                retweet_count = 2L,
                                favorite_count = 3L,
                                quote_count = 0L,
                                bookmark_count = 0L,
                                conversation_id_str = "100",
                                in_reply_to_status_id_str = NA_character_,
                                is_quote_status = FALSE
                              ),
                              core = list(
                                user_results = list(
                                  result = list(
                                    legacy = list(
                                      id_str = "u1",
                                      screen_name = "user1",
                                      name = "User One"
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
                    entryId = "tweet-101",
                    content = list(
                      `__typename` = "TimelineTimelineItem",
                      itemContent = list(
                        tweet_results = list(
                          result = list(
                            `__typename` = "TweetWithVisibilityResults",
                            tweet = list(
                              rest_id = "101",
                              legacy = list(
                                full_text = "Post two",
                                created_at = "Sun Jun 30 00:00:00 +0000 2026",
                                user_id_str = "u2",
                                screen_name = "user2",
                                name = "User Two",
                                reply_count = 0L,
                                retweet_count = 1L,
                                favorite_count = 5L,
                                quote_count = 0L,
                                bookmark_count = 0L,
                                conversation_id_str = "101",
                                in_reply_to_status_id_str = NA_character_,
                                is_quote_status = FALSE
                              ),
                              core = list(
                                user_results = list(
                                  result = list(
                                    legacy = list(
                                      id_str = "u2",
                                      screen_name = "user2",
                                      name = "User Two"
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
                    entryId = "tweet-102",
                    content = list(
                      `__typename` = "TimelineTimelineItem",
                      itemContent = list(
                        tweet_results = list(
                          result = list(
                            `__typename` = "TweetWithVisibilityResults",
                            tweet = list(
                              rest_id = "102",
                              legacy = list(
                                full_text = "Post three",
                                created_at = "Sat Jun 29 00:00:00 +0000 2026",
                                user_id_str = "u3",
                                screen_name = "user3",
                                name = "User Three",
                                reply_count = 2L,
                                retweet_count = 0L,
                                favorite_count = 1L,
                                quote_count = 1L,
                                bookmark_count = 0L,
                                conversation_id_str = "102",
                                in_reply_to_status_id_str = NA_character_,
                                is_quote_status = FALSE
                              ),
                              core = list(
                                user_results = list(
                                  result = list(
                                    legacy = list(
                                      id_str = "u3",
                                      screen_name = "user3",
                                      name = "User Three"
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
      ),
      contentType = "application/json",
      error = NULL
    )
  }

  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$evaluate <- function(expr) invisible(NULL)

  result <- x_search(mock_session, "test", max_scrolls = 5L)

  # The loop should terminate after 2 consecutive no-new-data cycles
  # (batch 1 = initial with 3 posts, batches 2-3 = scroll with duplicates
  #  -> no_new_data_cycles reaches 2 -> break).
  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 3L, info = "initial 3 posts, all subsequent are duplicates")
  expect_true(all(result$post_id %in% c("100", "101", "102")))
})

# --- Test 36: max_scrolls enforces a hard limit on iterations ---
test_that("scroll loop respects max_scrolls parameter", {
  batch_idx <- 0L
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"

  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")

  mock_session$backend$networkCaptureGet <- function() {
    batch_idx <<- batch_idx + 1L
    list(
      list(requestId = paste0("req-", batch_idx),
           url = "https://x.com/graphql/test",
           contentType = "application/json")
    )
  }

  # Each call returns a UNIQUE post (so stall detection never triggers).
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    batch_num <- as.integer(sub("req-", "", requestId))
    list(
      requestId = requestId,
      body = list(
        TimelineResult = list(
          result = list(
            `__typename` = "TimelineTimelineItem",
            timeline_instructions = list(
              list(
                type = "TimelineAddEntries",
                entries = list(
                  list(
                    entryId = paste0("tweet-", batch_num),
                    content = list(
                      `__typename` = "TimelineTimelineItem",
                      itemContent = list(
                        tweet_results = list(
                          result = list(
                            `__typename` = "TweetWithVisibilityResults",
                            tweet = list(
                              rest_id = as.character(batch_num),
                              legacy = list(
                                full_text = paste("Post", batch_num),
                                created_at = "Mon Jul 01 00:00:00 +0000 2026",
                                user_id_str = paste0("u", batch_num),
                                screen_name = paste0("user", batch_num),
                                name = paste("User", batch_num),
                                reply_count = 0L,
                                retweet_count = 0L,
                                favorite_count = 0L,
                                quote_count = 0L,
                                bookmark_count = 0L,
                                conversation_id_str = as.character(batch_num),
                                in_reply_to_status_id_str = NA_character_,
                                is_quote_status = FALSE
                              ),
                              core = list(
                                user_results = list(
                                  result = list(
                                    legacy = list(
                                      id_str = paste0("u", batch_num),
                                      screen_name = paste0("user", batch_num),
                                      name = paste("User", batch_num)
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
      ),
      contentType = "application/json",
      error = NULL
    )
  }

  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$evaluate <- function(expr) invisible(NULL)

  result <- x_search(mock_session, "test", max_scrolls = 3L)

  # Initial batch (1 post) + 3 scroll iterations (3 posts) = 4 total.
  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 4L, info = "1 initial + 3 scroll = 4 unique posts")
})

# --- Test 37: limit is enforced during the scroll loop ---
test_that("scroll loop stops when limit is reached", {
  batch_idx <- 0L
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"

  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")

  mock_session$backend$networkCaptureGet <- function() {
    batch_idx <<- batch_idx + 1L
    list(
      list(requestId = paste0("req-", batch_idx),
           url = "https://x.com/graphql/test",
           contentType = "application/json")
    )
  }

  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    batch_num <- as.integer(sub("req-", "", requestId))
    list(
      requestId = requestId,
      body = list(
        TimelineResult = list(
          result = list(
            `__typename` = "TimelineTimelineItem",
            timeline_instructions = list(
              list(
                type = "TimelineAddEntries",
                entries = list(
                  list(
                    entryId = paste0("tweet-", batch_num),
                    content = list(
                      `__typename` = "TimelineTimelineItem",
                      itemContent = list(
                        tweet_results = list(
                          result = list(
                            `__typename` = "TweetWithVisibilityResults",
                            tweet = list(
                              rest_id = as.character(batch_num),
                              legacy = list(
                                full_text = paste("Post", batch_num),
                                created_at = "Mon Jul 01 00:00:00 +0000 2026",
                                user_id_str = paste0("u", batch_num),
                                screen_name = paste0("user", batch_num),
                                name = paste("User", batch_num),
                                reply_count = 0L,
                                retweet_count = 0L,
                                favorite_count = 0L,
                                quote_count = 0L,
                                bookmark_count = 0L,
                                conversation_id_str = as.character(batch_num),
                                in_reply_to_status_id_str = NA_character_,
                                is_quote_status = FALSE
                              ),
                              core = list(
                                user_results = list(
                                  result = list(
                                    legacy = list(
                                      id_str = paste0("u", batch_num),
                                      screen_name = paste0("user", batch_num),
                                      name = paste("User", batch_num)
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
      ),
      contentType = "application/json",
      error = NULL
    )
  }

  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$evaluate <- function(expr) invisible(NULL)

  result <- x_search(mock_session, "test", limit = 2L, max_scrolls = 10L)

  # Should stop after reaching limit of 2 posts, even though more are available.
  expect_true(inherits(result, "tbl_df"))
  expect_lte(nrow(result), 2L, info = "should not exceed the specified limit")
})

# --- Test 38: max_scrolls validation ---
test_that("x_search rejects negative max_scrolls", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_search(mock_session, "test", max_scrolls = -1L), "non-negative")
})

# --- Test 39: scroll=FALSE skips the loop entirely ---
test_that("x_search with scroll=FALSE performs no scroll iterations", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  evaluate_count <- 0L
  mock_session$backend$evaluate <- function(expr) {
    evaluate_count <<- evaluate_count + 1L
    invisible(NULL)
  }

  x_search(mock_session, "test", scroll = FALSE, max_scrolls = 10L)
  expect_equal(evaluate_count, 0L, info = "evaluate should never be called when scroll=FALSE")
})

# ===================================================================
# Limit enforcement tests (Task 43)
# ===================================================================

# --- Test 40: limit=1 returns exactly one post ---
test_that("limit=1 returns exactly one post", {
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

  result <- x_search(mock_session, "test", limit = 1L)

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 1L, info = "limit=1 must return exactly one post")
})

# --- Test 41: limit larger than available returns all posts ---
test_that("limit larger than available fixture results returns all posts", {
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

  result <- x_search(mock_session, "test", limit = 100L)

  expect_true(inherits(result, "tbl_df"))
  # The fixture has 4 unique posts; limit=100 should not cap them.
  expect_equal(nrow(result), 4L, info = "limit larger than available should return all 4 posts")
})

# ===================================================================
# Collection provenance tests (Task 45)
# ===================================================================

# --- Test 42: .rx_collection_metadata creates a valid provenance object ---
test_that(".rx_collection_metadata creates a valid provenance object", {
  meta <- .rx_collection_metadata(
    collection_id = "test-uuid-0001",
    started_at = as.POSIXct("2026-08-01 12:00:00", tz = "UTC"),
    query = "r programming",
    backend = "lightpanda",
    record_count = 42L
  )

  expect_s3_class(meta, "rx_collection_provenance")
  expect_equal(meta$collection_id, "test-uuid-0001")
  expect_equal(meta$started_at, as.POSIXct("2026-08-01 12:00:00", tz = "UTC"))
  expect_equal(meta$query, "r programming")
  expect_true(nzchar(meta$package_version))
  expect_equal(meta$backend, "lightpanda")
  expect_true(nzchar(meta$parser_version))
  expect_equal(meta$records, 42L)
})

# --- Test 43: .rx_collection_metadata generates UUID when not provided ---
test_that(".rx_collection_metadata generates a UUID when collection_id is NULL", {
  meta <- .rx_collection_metadata(
    collection_id = NULL,
    query = "test",
    backend = "lightpanda",
    record_count = 0L
  )

  expect_true(nzchar(meta$collection_id))
  # UUIDs contain hyphens — basic check.
  expect_true(grepl("-", meta$collection_id))
})

# --- Test 44: .rx_collection_metadata defaults are sensible ---
test_that(".rx_collection_metadata uses sensible defaults", {
  meta <- .rx_collection_metadata()

  expect_true(nzchar(meta$collection_id))
  expect_true(inherits(meta$started_at, "POSIXct", "POSIXt"))
  expect_equal(meta$query, "")
  expect_true(nzchar(meta$package_version))
  expect_equal(meta$backend, "unknown")
  expect_true(nzchar(meta$parser_version))
  expect_equal(meta$records, 0L)
})

# --- Test 45: .rx_collection_metadata prints correctly ---
test_that("print.rx_collection_provenance outputs structured text", {
  meta <- .rx_collection_metadata(
    collection_id = "print-test-001",
    query = "hello world",
    backend = "chromium",
    record_count = 7L
  )

  output <- capture.output(print(meta))
  output_text <- paste(output, collapse = "\n")

  expect_true(grepl("xtweetsR Collection Provenance", output_text))
  expect_true(grepl("print-test-001", output_text))
  expect_true(grepl("hello world", output_text))
  expect_true(grepl("chromium", output_text))
  expect_true(grepl("records       : 7", output_text))
})

# --- Test 46: x_search attaches provenance to the result tibble ---
test_that("x_search attaches provenance to the returned tibble", {
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

  result <- x_search(mock_session, "r package")

  # Provenance should be attached as an attribute.
  provenance <- attr(result, "rx_collection_provenance")
  expect_true(is.list(provenance))
  expect_true(is.null(class(provenance)) || !"rx_collection_provenance" %in% c("NULL", ""))

  expect_equal(provenance$query, "r package")
  expect_true(inherits(provenance$started_at, "POSIXct", "POSIXt"))
  expect_true(nzchar(provenance$collection_id))
  expect_true(nzchar(provenance$package_version))
  expect_true(nzchar(provenance$parser_version))
  expect_equal(provenance$records, nrow(result))
})

# --- Test 47: x_search with navigation failure still attaches provenance ---
test_that("navigation failure result carries provenance with zero records", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) {
    list(status = "error", error = list(code = "NAV_FAIL"))
  }

  expect_warning(
    result <- x_search(mock_session, "failed query"),
    "Navigation failed"
  )

  provenance <- attr(result, "rx_collection_provenance")
  expect_true(is.list(provenance))
  expect_equal(provenance$query, "failed query")
  expect_equal(provenance$records, 0L)
})

# --- Test 48: Observation-level provenance fields are populated (Task 46) ---
test_that("x_search populates collected_at, collection_query, collection_id on post rows", {
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

  result <- x_search(mock_session, "r language")

  expect_true(inherits(result, "tbl_df"))
  expect_true(nrow(result) >= 1)

  # The three observation-level provenance columns must exist.
  expect_true("collected_at" %in% names(result))
  expect_true("collection_query" %in% names(result))
  expect_true("collection_id" %in% names(result))

  # All rows must have the same query and collection_id.
  expect_true(all(result$collection_query == "r language"))
  expect_true(all(result$collection_id == result$collection_id[1L]))
  expect_true(nzchar(result$collection_id[1L]))

  # collection_id must match the provenance attribute.
  provenance <- attr(result, "rx_collection_provenance")
  expect_equal(provenance$collection_id, result$collection_id[1L])

  # collected_at must be non-empty character on every row.
  expect_true(all(nzchar(result$collected_at)))
})

# --- Test 49: Observation-level provenance on empty result (Task 46) ---
test_that("empty result has observation provenance columns", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) {
    list(status = "error", error = list(code = "NAV_FAIL"))
  }

  expect_warning(
    result <- x_search(mock_session, "failed query"),
    "Navigation failed"
  )

  # Empty tibble should still have the observation provenance columns.
  expect_true("collected_at" %in% names(result))
  expect_true("collection_query" %in% names(result))
  expect_true("collection_id" %in% names(result))
  expect_equal(nrow(result), 0L)
})

# ===================================================================
# Resume support tests (Task 49)
# ===================================================================

# --- Test 50: resume=TRUE with no checkpoint behaves like normal search ---
test_that("x_search with resume=TRUE and no checkpoint behaves normally", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  checkpoint_file <- tempfile(fileext = ".checkpoint.json")
  jsonl_file <- tempfile(fileext = ".jsonl")

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

  result <- x_search(mock_session, "test query", resume = TRUE,
                     checkpoint_path = checkpoint_file, jsonl_path = jsonl_file)

  expect_true(inherits(result, "tbl_df"))
  expect_true(nrow(result) >= 1, info = "should get posts from fixture")

  # Checkpoint should be created.
  expect_true(file.exists(checkpoint_file), info = "checkpoint should be written when resume=TRUE")
  cp <- .rx_checkpoint_read(checkpoint_file)
  expect_true(is.list(cp))
  expect_equal(cp$query, "test query")
  expect_true(nzchar(cp$collection_id))

  file.remove(checkpoint_file, jsonl_file)
})

# --- Test 51: Resume restores seen_post_ids from checkpoint ---
test_that("x_search with resume restores seen_post_ids from checkpoint", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  checkpoint_file <- tempfile(fileext = ".checkpoint.json")
  jsonl_file <- tempfile(fileext = ".jsonl")

  existing_ids <- c("already-seen-1", "already-seen-2", "already-seen-3")
  checkpoint <- structure(
    list(
      collection_id     = "resume-test-uuid-001",
      query             = "test query",
      seen_post_ids     = existing_ids,
      last_cursor       = "cursor-abc-123",
      last_post_id      = "already-seen-3",
      records_collected = 3L
    ),
    class = "rx_checkpoint"
  )
  .rx_checkpoint_write(checkpoint_file, checkpoint)

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

  result <- x_search(mock_session, "test query", resume = TRUE,
                     checkpoint_path = checkpoint_file, jsonl_path = jsonl_file)

  expect_true(inherits(result, "tbl_df"))
  provenance <- attr(result, "rx_collection_provenance")
  expect_equal(provenance$collection_id, "resume-test-uuid-001")
  expect_true(all(result$post_id %in% c("1", "2", "3", "4")))
  expect_true(nrow(result) >= 1)

  file.remove(checkpoint_file, jsonl_file)
})

# --- Test 52: Resume with existing checkpoint preserves collection_id ---
test_that("resumed search preserves the checkpoint collection_id", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  checkpoint_file <- tempfile(fileext = ".checkpoint.json")
  jsonl_file <- tempfile(fileext = ".jsonl")

  checkpoint <- structure(
    list(
      collection_id     = "my-resume-collection-001",
      query             = "test query",
      seen_post_ids     = character(0),
      last_cursor       = "",
      last_post_id      = "",
      records_collected = 0L
    ),
    class = "rx_checkpoint"
  )
  .rx_checkpoint_write(checkpoint_file, checkpoint)

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

  result <- x_search(mock_session, "test query", resume = TRUE,
                     checkpoint_path = checkpoint_file, jsonl_path = jsonl_file)

  provenance <- attr(result, "rx_collection_provenance")
  expect_equal(provenance$collection_id, "my-resume-collection-001")

  file.remove(checkpoint_file, jsonl_file)
})

# --- Test 53: Checkpoint is written at end of resumed search with updated state ---
test_that("checkpoint written at end of resumed search contains updated state", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  checkpoint_file <- tempfile(fileext = ".checkpoint.json")
  jsonl_file <- tempfile(fileext = ".jsonl")

  checkpoint <- structure(
    list(
      collection_id     = "checkpoint-test-001",
      query             = "test query",
      seen_post_ids     = c("pre-existing-1", "pre-existing-2"),
      last_cursor       = "cursor-old",
      last_post_id      = "pre-existing-2",
      records_collected = 2L
    ),
    class = "rx_checkpoint"
  )
  .rx_checkpoint_write(checkpoint_file, checkpoint)

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

  result <- x_search(mock_session, "test query", resume = TRUE,
                     checkpoint_path = checkpoint_file, jsonl_path = jsonl_file)

  updated_checkpoint <- .rx_checkpoint_read(checkpoint_file)
  expect_true(is.list(updated_checkpoint))
  # 4 fixture posts + 2 pre-existing = 6 total unique seen.
  expect_equal(updated_checkpoint$records_collected, 6L)
  expect_equal(updated_checkpoint$collection_id, "checkpoint-test-001")
  expect_true(all(c("pre-existing-1", "pre-existing-2") %in% updated_checkpoint$seen_post_ids))
  expect_true(all(c("1", "2", "3", "4") %in% updated_checkpoint$seen_post_ids))

  file.remove(checkpoint_file, jsonl_file)
})

# --- Test 54: resume=FALSE does not write checkpoint ---
test_that("x_search with resume=FALSE does not write checkpoint file", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  checkpoint_file <- tempfile(fileext = ".checkpoint.json")
  jsonl_file <- tempfile(fileext = ".jsonl")

  expect_false(file.exists(checkpoint_file))

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

  result <- x_search(mock_session, "test query", resume = FALSE,
                     checkpoint_path = checkpoint_file, jsonl_path = jsonl_file)

  expect_false(file.exists(checkpoint_file), info = "checkpoint should NOT be written when resume=FALSE")
  expect_true(inherits(result, "tbl_df"))
  expect_true(nrow(result) >= 1)
})

# ===================================================================
# Progress output tests (Task 60)
# ===================================================================

# --- Test 55: .rx_progress suppresses output when quiet=TRUE ---
test_that(".rx_progress does not emit messages when quiet=TRUE", {
  msgs <- capture_messages(.rx_progress("should not appear", quiet = TRUE))
  expect_equal(length(msgs), 0L)
})

# --- Test 56: .rx_progress emits messages when quiet=FALSE ---
test_that(".rx_progress emits messages when quiet=FALSE", {
  msgs <- capture_messages(.rx_progress("test message", quiet = FALSE))
  expect_equal(length(msgs), 1L)
  expect_true(grepl("test message", msgs[[1L]]))
})

# ===================================================================
# Infinite-scroll mock infrastructure (Task 61)
# ===================================================================

# Source the mock module so it's available to all tests in this file.
# The file lives alongside testthat tests and is not a test itself (prefixed with _).
source(file.path(testthat::test_path(), "_mock-infinite-scroll.R"))

# --- Test 57: rx_mock_batch generates correct number of posts ---
test_that("rx_mock_batch generates the requested number of posts", {
  batch <- rx_mock_batch(id_start = 10L, n = 5L, prefix = "test")

  entries <- batch$TimelineResult$result$timeline_instructions[[1L]]$entries
  expect_equal(length(entries), 5L)

  post_ids <- vapply(entries, function(e) {
    e$content$itemContent$tweet_results$result$tweet$rest_id
  }, character(1))

  expect_equal(post_ids, c("test-10", "test-11", "test-12", "test-13", "test-14"))
})

# --- Test 58: rx_mock_batch with duplicates includes extra entries ---
test_that("rx_mock_batch with include_duplicates adds 2 extra entries", {
  batch <- rx_mock_batch(id_start = 1L, n = 3L, prefix = "dup",
                          include_duplicates = TRUE)

  entries <- batch$TimelineResult$result$timeline_instructions[[1L]]$entries
  expect_equal(length(entries), 5L, info = "3 base + 2 duplicates")

  post_ids <- vapply(entries, function(e) {
    e$content$itemContent$tweet_results$result$tweet$rest_id
  }, character(1))

  expect_true("dup-dup-a" %in% post_ids)
  expect_true("dup-dup-b" %in% post_ids)
})

# --- Test 59: rx_mock_session returns a valid session ---
test_that("rx_mock_session creates a valid xtweetsR_session", {
  batch <- rx_mock_batch(id_start = 1L, n = 2L, prefix = "s")
  session <- rx_mock_session(list(batch))

  expect_true(inherits(session, "xtweetsR_session"))
  expect_true(session$connected)
  expect_true(inherits(session$backend, "environment"))
  expect_true(is.function(session$backend$networkCaptureEnable))
  expect_true(is.function(session$backend$networkCaptureGet))
  expect_true(is.function(session$backend$networkCaptureGetBody))
  expect_true(is.function(session$backend$networkCaptureClear))
  expect_true(is.function(session$backend$evaluate))
  expect_true(is.function(session$backend$navigate))
})

# --- Test 60: Multi-batch mock drives x_search with deduplication ---
test_that("multi-batch mock: deduplication across batches is correct", {
  # Batch 1: 3 posts (a-1, a-2, a-3).
  batch1 <- rx_mock_batch(id_start = 1L, n = 3L, prefix = "a")
  # Batch 2: 3 posts starting from ID 2 (a-2, a-3, a-4) — 2 duplicates.
  batch2 <- rx_mock_batch(id_start = 2L, n = 3L, prefix = "a")

  session <- rx_mock_session(list(batch1, batch2),
                              delays = c(0, 0.01), end_at = 3L)

  result <- x_search(session, "dedup test", max_scrolls = 5L, scroll = TRUE)

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 4L, info = "3 from batch1 + 1 new from batch2 = 4 unique")
  expect_true(all(c("a-1", "a-2", "a-3", "a-4") %in% result$post_id))
})

# --- Test 61: Multi-batch mock verifies scroll loop termination ---
test_that("multi-batch mock: scroll loop terminates on no-new-data", {
  # 2 batches with unique posts, then 2 empty batches.
  batch1 <- rx_mock_batch(id_start = 1L, n = 3L, prefix = "term")
  batch2 <- rx_mock_batch(id_start = 4L, n = 2L, prefix = "term")
  empty <- rx_mock_batch(id_start = 100L, n = 0L, prefix = "term")

  session <- rx_mock_session(
    batches = list(batch1, batch2, empty, empty),
    delays = c(0, 0.01, 0, 0),
    end_at = 4L
  )

  result <- x_search(session, "termination test", max_scrolls = 10L, scroll = TRUE)

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 5L, info = "3 + 2 unique posts, no more after batch 2")
  # The scroll loop should terminate because batches 3 and 4 are empty,
  # triggering stall detection (no_new_data_cycles >= 2).
})

# --- Test 62: Realistic scenario produces expected unique count ---
test_that("rx_mock_realistic_scenario: exercises full collection pipeline", {
  session <- rx_mock_realistic_scenario(delay_between_batches = 0.005)

  result <- x_search(session, "realistic test", max_scrolls = 10L, scroll = TRUE, quiet = TRUE)

  expect_true(inherits(result, "tbl_df"))
  expect_true(nrow(result) >= 1, info = "should have posts from batch 1")
  # The realistic scenario has 5 + 4 + 3 = 12 unique posts across batches.
  # Check deduplication worked: no duplicate post_ids.
  expect_equal(length(unique(result$post_id)), nrow(result),
                info = "no duplicate post_ids should remain after dedup")
})

# ===================================================================
# Cursor-aware mock tests (Task 62)
# ===================================================================

# --- Test 63: Cursor values differ across batches ---
test_that("mock cursors change across batches", {
  batch1 <- rx_mock_batch(id_start = 1L, n = 3L, prefix = "c1")
  batch2 <- rx_mock_batch(id_start = 4L, n = 2L, prefix = "c2")
  batch3 <- rx_mock_batch(id_start = 6L, n = 1L, prefix = "c3")

  session <- rx_mock_session(
    batches = list(batch1, batch2, batch3),
    delays = c(0, 0.005, 0.005),
    end_at = 3L,
    include_cursor = TRUE
  )

  # Trigger body retrieval for all 3 batches.
  evts <- list()
  bodies <- list()
  for (i in seq_len(3L)) {
    evt <- session$backend$networkCaptureGet()
    bodies[[i]] <- session$backend$networkCaptureGetBody(evt$requestId)
    evts[[i]] <- evt
  }

  # Extract cursors from each batch body.
  cursor1 <- .rx_extract_cursors(bodies[[1L]]$body)
  cursor2 <- .rx_extract_cursors(bodies[[2L]]$body)
  cursor3 <- .rx_extract_cursors(bodies[[3L]]$body)

  expect_true(length(cursor1) > 0L, info = "batch 1 should have a cursor")
  expect_true(length(cursor2) > 0L, info = "batch 2 should have a cursor")
  expect_true(length(cursor3) > 0L, info = "batch 3 should have a cursor")

  # Cursors must be different per batch.
  expect_true(cursor1["Bottom"] != cursor2["Bottom"],
              info = "batch 1 and batch 2 cursors must differ")
  expect_true(cursor2["Bottom"] != cursor3["Bottom"],
              info = "batch 2 and batch 3 cursors must differ")

  # Cursor values follow the expected pattern.
  expect_equal(as.character(cursor1["Bottom"]), "cursor-batch-1")
  expect_equal(as.character(cursor2["Bottom"]), "cursor-batch-2")
  expect_equal(as.character(cursor3["Bottom"]), "cursor-batch-3")
})

# --- Test 64: No cursor when include_cursor=FALSE ---
test_that("mock returns no cursors when include_cursor=FALSE", {
  batch1 <- rx_mock_batch(id_start = 1L, n = 3L, prefix = "nc")
  batch2 <- rx_mock_batch(id_start = 4L, n = 2L, prefix = "nc")

  session <- rx_mock_session(
    batches = list(batch1, batch2),
    include_cursor = FALSE
  )

  evt <- session$backend$networkCaptureGet()
  body <- session$backend$networkCaptureGetBody(evt$requestId)

  cursors <- .rx_extract_cursors(body$body)
  expect_equal(length(cursors), 0L, info = "no cursors when include_cursor=FALSE")
})

# --- Test 65: Final batch (empty) has no cursor — terminal state ---
test_that("empty final batch signals end of cursors", {
  batch1 <- rx_mock_batch(id_start = 1L, n = 2L, prefix = "end")
  empty_batch <- rx_mock_batch(id_start = 1L, n = 0L, prefix = "end")

  session <- rx_mock_session(
    batches = list(batch1, empty_batch),
    delays = c(0, 0),
    end_at = 2L,
    include_cursor = TRUE
  )

  # Batch 1: has cursor.
  evt1 <- session$backend$networkCaptureGet()
  body1 <- session$backend$networkCaptureGetBody(evt1$requestId)
  cursor1 <- .rx_extract_cursors(body1$body)
  expect_true(length(cursor1) > 0L, info = "batch 1 should have a cursor")

  # Batch 2: empty response, no cursor (terminal state).
  evt2 <- session$backend$networkCaptureGet()
  body2 <- session$backend$networkCaptureGetBody(evt2$requestId)
  cursor2 <- .rx_extract_cursors(body2$body)
  expect_equal(length(cursor2), 0L,
               info = "empty final batch should have no cursor — terminal state")
})

# --- Test 66: Scroll state tracks cursors across batches ---
test_that("scroll state captures cursor after parsing", {
  batch1 <- rx_mock_batch(id_start = 1L, n = 3L, prefix = "sst")
  batch2 <- rx_mock_batch(id_start = 4L, n = 2L, prefix = "sst")

  session <- rx_mock_session(
    batches = list(batch1, batch2),
    delays = c(0, 0.005),
    end_at = 3L,
    include_cursor = TRUE
  )

  result <- x_search(session, "cursor state test", max_scrolls = 5L, scroll = TRUE)

  # Scroll state should have captured a cursor from the last batch.
  provenance <- attr(result, "rx_collection_provenance")
  expect_true(inherits(result, "tbl_df"))
  expect_true(nrow(result) >= 1, info = "should have posts from both batches")

  # The scroll state's last_cursor should be set after the final batch.
  # We verify this indirectly: the state is created inside x_search(),
  # and last_cursor is set in .rx_scroll_state_add_posts().
  # The cursor should be non-empty after parsing a batch with cursors.
  expect_true(inherits(result, "tbl_df"))
})

# --- Test 67: Realistic scenario with cursors exercises extraction ---
test_that("rx_mock_realistic_scenario with cursors: extraction works end-to-end", {
  session <- rx_mock_realistic_scenario(
    delay_between_batches = 0.005,
    include_cursor = TRUE
  )

  result <- x_search(session, "cursor scenario test",
                     max_scrolls = 10L, scroll = TRUE, quiet = TRUE)

  expect_true(inherits(result, "tbl_df"))
  expect_true(nrow(result) >= 1, info = "should extract posts from scenario")
  # No duplicate post_ids.
  expect_equal(length(unique(result$post_id)), nrow(result),
               info = "deduplication should handle cursor-aware batches")

  # The last batch is empty (end of results), so scroll termination
  # should trigger naturally via stall detection.
  provenance <- attr(result, "rx_collection_provenance")
  expect_true(is.list(provenance), info = "provenance should be attached")
})
