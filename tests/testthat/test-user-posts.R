# Tests for x_user_posts() URL/navigation layer (Task 52).
#
# These tests cover:
# - .rx_construct_user_timeline_url() URL construction
# - Input validation (session, username, limit)
# - Navigation with fixture data (mock backend, no browser)
# - Navigation failure handling

# --- URL construction tests are in test-search-url.R ---

# --- Test 1: x_user_posts rejects NULL session ---
test_that("x_user_posts throws for NULL session", {
  expect_error(x_user_posts(NULL, "testuser"), "session must be")
})

# --- Test 2: x_user_posts rejects non-xtweetsR_session ---
test_that("x_user_posts throws for plain list session", {
  expect_error(x_user_posts(list(foo = "bar"), "testuser"), "session must be")
})

# --- Test 3: x_user_posts rejects empty username ---
test_that("x_user_posts throws for empty username", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_user_posts(mock_session, ""), "non-empty")
})

# --- Test 4: x_user_posts rejects whitespace-only username ---
test_that("x_user_posts throws for whitespace-only username", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_user_posts(mock_session, "   "), "non-empty")
})

# --- Test 5: x_user_posts input validation - invalid limit ---
test_that("x_user_posts throws for negative limit", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  expect_error(x_user_posts(mock_session, "testuser", limit = -1), "positive")
})

# --- Test 6: Navigation failure returns empty tibble with warning ---
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
    result <- x_user_posts(mock_session, "testuser"),
    "Navigation failed"
  )
  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)

  # Provenance query should be the username with @.
  provenance <- attr(result, "rx_collection_provenance")
  expect_equal(provenance$query, "@testuser")
  expect_equal(provenance$records, 0L)
})

# --- Test 7: Successful path with fixture data (no browser) ---
test_that("x_user_posts processes fixture data through mock backend", {
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
    list(requestId = "req-1", url = "https://x.com/hadleywickham", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_user_posts(mock_session, "hadleywickham")

  expect_true(inherits(result, "tbl_df"))
  expect_true(nrow(result) >= 1, info = "fixture has posts, should get at least one")
  expect_true("post_id" %in% names(result))
  expect_true("text" %in% names(result))

  # Provenance should show the username.
  provenance <- attr(result, "rx_collection_provenance")
  expect_equal(provenance$query, "@hadleywickham")
})

# --- Test 8: x_user_posts with path parameter navigates to path URL ---
test_that("x_user_posts with path navigates to the correct URL", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

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

  x_user_posts(mock_session, "hadleywickham", path = "media")

  expect_true(grepl("hadleywickham/media$", captured_url),
              info = paste("captured URL:", captured_url))
})

# --- Test 9: username with @ is handled correctly ---
test_that("x_user_posts strips @ from username in provenance", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) {
    expect_true(grepl("^https://x.com/hadleywickham$", url),
                info = paste("URL should strip @:", url))
    list(status = "ok")
  }
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  x_user_posts(mock_session, "@hadleywickham")
})

# --- Test 10: scroll=FALSE skips the scroll step ---
test_that("x_user_posts with scroll=FALSE skips scrolling", {
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

  x_user_posts(mock_session, "testuser", scroll = FALSE)
  expect_false(scroll_called, info = "scroll should NOT be triggered when scroll=FALSE")
})

# --- Test 11: Observation-level provenance columns exist ---
test_that("x_user_posts populates observation-level provenance", {
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
    list(requestId = "req-1", url = "https://x.com/hadleywickham", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_user_posts(mock_session, "hadleywickham")

  expect_true("collected_at" %in% names(result))
  expect_true("collection_query" %in% names(result))
  expect_true("collection_id" %in% names(result))
  expect_true(all(result$collection_query == "@hadleywickham"))
})

# --- Test 12: Limit is enforced ---
test_that("x_user_posts limit parameter truncates results", {
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
    list(requestId = "req-1", url = "https://x.com/hadleywickham", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_user_posts(mock_session, "hadleywickham", limit = 2L)

  expect_true(inherits(result, "tbl_df"))
  expect_lte(nrow(result), 2L, info = "should not exceed limit")
})

# --- Test 13: User timeline fixture extracts all posts ---
test_that("x_user_posts extracts all posts from user timeline fixture", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-user-timeline-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  # The parser should find all 5 posts from the user timeline fixture.
  posts <- xtweetsR:::.rx_parse_posts(parsed_fixture)
  expect_equal(length(posts$post_id), 5L, info = "fixture has 5 tweets")

  # All posts should be from the @rstudio account.
  expect_true(all(posts$username == "rstudio"),
              info = "all posts should be from @rstudio")
})

# --- Test 14: User timeline post fields match canonical schema ---
test_that("user timeline extraction produces all canonical fields", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-user-timeline-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  parsed <- xtweetsR:::.rx_parse_posts(parsed_fixture)
  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tibble_posts <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  # Should have the 26 canonical columns.
  expect_true(inherits(tibble_posts, "tbl_df"))
  expect_equal(ncol(tibble_posts), 26L)
  fields <- .rx_canonical_fields()
  expect_equal(sort(names(tibble_posts)), sort(fields))

  # Should have 5 rows.
  expect_equal(nrow(tibble_posts), 5L)
})

# --- Test 15: User timeline post IDs are unique character ---
test_that("user timeline post IDs are unique characters", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-user-timeline-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  parsed <- xtweetsR:::.rx_parse_posts(parsed_fixture)
  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tibble_posts <- xtweetsR:::.rx_normalized_to_tibble(normalized)
  deduped <- xtweetsR:::.rx_deduplicate_posts(tibble_posts)

  expect_true(all(inherits(deduped$post_id, "character")))
  expect_equal(length(unique(deduped$post_id)), nrow(deduped))
  expect_equal(nrow(deduped), 5L, info = "all 5 posts should be unique")
})

# --- Test 16: User timeline engagement metrics are correct ---
test_that("user timeline extraction captures correct engagement metrics", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-user-timeline-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  parsed <- xtweetsR:::.rx_parse_posts(parsed_fixture)
  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tibble_posts <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  # First post: reply=24, repost=89, like=456, quote=7, bookmark=32, view=45200
  first <- tibble_posts$post_id == "1800000000000000001"
  expect_true(any(first))
  if (any(first)) {
    expect_equal(tibble_posts$reply_count[first][1], 24L)
    expect_equal(tibble_posts$repost_count[first][1], 89L)
    expect_equal(tibble_posts$like_count[first][1], 456L)
    expect_equal(tibble_posts$quote_count[first][1], 7L)
    expect_equal(tibble_posts$bookmark_count[first][1], 32L)
    expect_equal(tibble_posts$view_count[first][1], 45200L)
  }
})

# --- Test 17: User timeline relationship fields are correct ---
test_that("user timeline extraction captures relationship fields", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-user-timeline-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  parsed <- xtweetsR:::.rx_parse_posts(parsed_fixture)
  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tibble_posts <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  # Post 4 is a reply to post 3.
  post4 <- tibble_posts$post_id == "1800000000000000004"
  expect_true(any(post4))
  if (any(post4)) {
    expect_true(tibble_posts$is_reply[post4][1])
    expect_equal(tibble_posts$reply_to_post_id[post4][1], "1800000000000000003")
  }

  # All posts have non-empty conversation_id.
  expect_true(all(!is.na(tibble_posts$conversation_id)))
})

# --- Test 18: User timeline with x_user_posts() mock backend ---
test_that("x_user_posts full pipeline with user timeline fixture returns canonical tibble", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-user-timeline-response.json"
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
    list(requestId = "req-1", url = "https://x.com/rstudio", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_user_posts(mock_session, "rstudio")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 5L, info = "should return all 5 posts from fixture")
  expect_true("post_id" %in% names(result))
  expect_true("text" %in% names(result))
  expect_true("author_id" %in% names(result))
  expect_true("username" %in% names(result))
  expect_true("display_name" %in% names(result))
  expect_true("created_at" %in% names(result))
  expect_true("reply_count" %in% names(result))
  expect_true("repost_count" %in% names(result))
  expect_true("like_count" %in% names(result))
  expect_true("quote_count" %in% names(result))
  expect_true("bookmark_count" %in% names(result))
  expect_true("view_count" %in% names(result))
  expect_true("conversation_id" %in% names(result))
  expect_true("is_reply" %in% names(result))
  expect_true("is_repost" %in% names(result))
  expect_true("is_quote" %in% names(result))
  expect_true("reply_to_post_id" %in% names(result))
  expect_true("quoted_post_id" %in% names(result))
  expect_true("collected_at" %in% names(result))
  expect_true("collection_query" %in% names(result))
  expect_true("collection_id" %in% names(result))

  # All posts should be from @rstudio.
  expect_true(all(result$username == "rstudio"))

  # Provenance should show the username.
  provenance <- attr(result, "rx_collection_provenance")
  expect_equal(provenance$query, "@rstudio")
  expect_equal(provenance$records, 5L)
})

# --- Test 19: Empty user timeline response returns empty tibble ---
test_that("x_user_posts returns empty tibble when fixture has no posts", {
  empty_timeline <- list(
    data = list(
      timeline = list(
        instructions = list(
          list(type = "TimelineAddEntries", entries = list())
        )
      )
    )
  )

  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list(
    list(requestId = "req-1", url = "https://x.com/emptyuser", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = empty_timeline, error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_user_posts(mock_session, "emptyuser")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
  expect_equal(ncol(result), 26L)

  provenance <- attr(result, "rx_collection_provenance")
  expect_equal(provenance$records, 0L)
})

# --- Test 20: User timeline with no network events returns empty tibble ---
test_that("x_user_posts returns empty tibble when no network events", {
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list()
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_user_posts(mock_session, "nobody")

  expect_true(inherits(result, "tbl_df"))
  expect_equal(nrow(result), 0L)
})

# --- Test 21: x_user_posts with scroll=FALSE captures only initial batch ---
test_that("x_user_posts scroll=FALSE captures only initial data", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-user-timeline-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed_fixture <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  evaluate_calls <- 0L
  mock_session <- new.env(parent = emptyenv())
  mock_session$connected <- TRUE
  mock_session$backend <- new.env(parent = emptyenv())
  class(mock_session) <- "xtweetsR_session"
  mock_session$backend$networkCaptureEnable <- function() invisible(TRUE)
  mock_session$backend$navigate <- function(url) list(status = "ok")
  mock_session$backend$networkCaptureGet <- function() list(
    list(requestId = "req-1", url = "https://x.com/rstudio", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)
  mock_session$backend$evaluate <- function(expr) {
    evaluate_calls <<- evaluate_calls + 1L
    invisible(NULL)
  }

  result <- x_user_posts(mock_session, "rstudio", scroll = FALSE)

  expect_equal(evaluate_calls, 0L, info = "no evaluate calls when scroll=FALSE")
  expect_equal(nrow(result), 5L)
})

# --- Test 22: User timeline limit enforcement ---
test_that("x_user_posts limit truncates user timeline results", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-user-timeline-response.json"
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
    list(requestId = "req-1", url = "https://x.com/rstudio", contentType = "application/json")
  )
  mock_session$backend$networkCaptureGetBody <- function(requestId) {
    list(requestId = requestId, body = parsed_fixture, contentType = "application/json", error = NULL)
  }
  mock_session$backend$networkCaptureClear <- function() invisible(TRUE)

  result <- x_user_posts(mock_session, "rstudio", limit = 3L)

  expect_true(inherits(result, "tbl_df"))
  expect_lte(nrow(result), 3L, info = "should not exceed limit of 3")
  expect_true(all(result$username == "rstudio"))
})
