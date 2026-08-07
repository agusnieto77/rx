# Tests for the X search response post parser (Task 31).
#
# These tests validate the minimal post discovery parser that extracts
# only post_id and text from the X GraphQL timeline fixture.
#
# All tests use the local fixture only. No browser or CDP connection is needed.

# --- Test 1: Parser returns posts with post_id and text from the fixture ---
test_that("parser extracts post_id and text from x-search-response.json", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  testthat::expect_true(is.list(result), info = "result is a list")
  testthat::expect_true("post_id" %in% names(result), info = "result has post_id")
  testthat::expect_true("text" %in% names(result), info = "result has text")
  testthat::expect_true(length(result$post_id) >= 1, info = "at least one post returned")
  testthat::expect_true(length(result$text) >= 1, info = "at least one text returned")
  testthat::expect_equal(length(result$post_id), length(result$text), info = "post_id and text have same length")
})

# --- Test 2: post_id values are character strings ---
test_that("post_id values are character strings, not numeric", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  testthat::expect_true(
    all(is.character(result$post_id)),
    info = "all post_id values are character"
  )
  testthat::expect_true(
    all(nzchar(result$post_id)),
    info = "all post_id values are non-empty"
  )
})

# --- Test 3: Extracted post_ids match the fixture's rest_id values ---
test_that("extracted post_ids match fixture rest_id values exactly", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  # Expected post_ids from the fixture.
  expected_ids <- c(
    "1900000000000000001",
    "1900000000000000002",
    "1900000000000000003"
  )

  testthat::expect_equal(
    result$post_id, expected_ids,
    info = "post_ids match fixture rest_id values"
  )
})

# --- Test 4: Extracted texts match the fixture's full_text values ---
test_that("extracted text values match fixture full_text values exactly", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  # Expected texts from the fixture.
  expected_texts <- c(
    "New release of the tidyverse ecosystem is out. Check it out!",
    "Using R to analyze climate data — here is a quick walkthrough of the pipeline.",
    "Quasiquotation in R is powerful once you understand it. Thread below on when to use !! vs {{"
  )

  testthat::expect_equal(
    result$text, expected_texts,
    info = "texts match fixture full_text values"
  )
})

# --- Test 5: Non-tweet entries (cursors) are skipped ---
test_that("cursor and non-tweet entries are silently skipped", {
  # Build a minimal response that has both tweet entries and cursor entries.
  response <- list(
    data = list(
      timeline = list(
        instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = list(
              list(
                entryId = "tweet-123",
                content = list(
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        rest_id = "123",
                        legacy = list(full_text = "Hello world")
                      )
                    )
                  )
                )
              ),
              list(
                entryId = "cursor-bottom-456",
                content = list(
                  itemContent = list(
                    # No tweet_results — this is a cursor entry.
                    cursor = list(cursorType = "Bottom", value = "abc")
                  )
                )
              )
            )
          )
        )
      )
    )
  )

  result <- xtweetsR:::.rx_parse_posts(response)

  testthat::expect_equal(length(result$post_id), 1L, info = "only the tweet entry is returned")
  testthat::expect_equal(result$post_id, "123", info = "cursor entry was skipped")
})

# --- Test 6: Empty/malformed response returns empty vectors ---
test_that("malformed responses return empty vectors without crashing", {
  # NULL response.
  result_null <- xtweetsR:::.rx_parse_posts(NULL)
  testthat::expect_equal(length(result_null$post_id), 0L, info = "NULL input returns empty")

  # Empty list.
  result_empty <- xtweetsR:::.rx_parse_posts(list())
  testthat::expect_equal(length(result_empty$post_id), 0L, info = "empty list returns empty")

  # List missing timeline structure.
  result_missing <- xtweetsR:::.rx_parse_posts(list(data = list()))
  testthat::expect_equal(length(result_missing$post_id), 0L, info = "missing timeline returns empty")
})

# --- Test 7: Helper function .rx_find_tweet_result returns NULL for non-tweet entries ---
test_that(".rx_find_tweet_result returns NULL when nesting is missing", {
  # Entry with no content.
  testthat::expect_null(xtweetsR:::.rx_find_tweet_result(list()), info = "empty entry returns NULL")
  testthat::expect_null(
    xtweetsR:::.rx_find_tweet_result(list(content = NULL)),
    info = "content=NULL returns NULL"
  )
  testthat::expect_null(
    xtweetsR:::.rx_find_tweet_result(list(content = list(itemContent = NULL))),
    info = "itemContent=NULL returns NULL"
  )
  testthat::expect_null(
    xtweetsR:::.rx_find_tweet_result(list(content = list(itemContent = list(tweet_results = NULL)))),
    info = "tweet_results=NULL returns NULL"
  )

  # Entry with a valid tweet result.
  valid_entry <- list(
    content = list(
      itemContent = list(
        tweet_results = list(
          result = list(rest_id = "456")
        )
      )
    )
  )
  result <- xtweetsR:::.rx_find_tweet_result(valid_entry)
  testthat::expect_true(is.list(result), info = "valid entry returns a list")
  testthat::expect_equal(result$rest_id, "456", info = "rest_id is preserved")
})
