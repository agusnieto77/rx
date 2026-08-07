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
