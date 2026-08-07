# Tests for the X search response post parser (Tasks 31–33).
#
# These tests validate the post discovery parser that extracts
# post_id, text, author_id, username, display_name, and created_at
# from the X GraphQL timeline fixture.
#
# All tests use the local fixture only. No browser or CDP connection is needed.

# --- Test 1: Parser returns posts with all fields from the fixture ---
test_that("parser extracts all fields from x-search-response.json", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  testthat::expect_true(is.list(result), info = "result is a list")
  testthat::expect_true("post_id" %in% names(result), info = "result has post_id")
  testthat::expect_true("text" %in% names(result), info = "result has text")
  testthat::expect_true("author_id" %in% names(result), info = "result has author_id")
  testthat::expect_true("username" %in% names(result), info = "result has username")
  testthat::expect_true("display_name" %in% names(result), info = "result has display_name")
  testthat::expect_true("created_at" %in% names(result), info = "result has created_at")
  testthat::expect_true(length(result$post_id) >= 1, info = "at least one post returned")
  testthat::expect_true(length(result$text) >= 1, info = "at least one text returned")
  testthat::expect_equal(
    length(result$post_id), length(result$text),
    info = "post_id and text have same length"
  )
  testthat::expect_equal(
    length(result$post_id), length(result$author_id),
    info = "post_id and author_id have same length"
  )
  testthat::expect_equal(
    length(result$post_id), length(result$username),
    info = "post_id and username have same length"
  )
  testthat::expect_equal(
    length(result$post_id), length(result$display_name),
    info = "post_id and display_name have same length"
  )
  testthat::expect_equal(
    length(result$post_id), length(result$created_at),
    info = "post_id and created_at have same length"
  )
})

# --- Test 2: post_id values are character strings ---
test_that("post_id values are character strings, not numeric", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
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
    testthat::test_path("..", ".."),
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
    testthat::test_path("..", ".."),
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
  testthat::expect_equal(length(result_empty$created_at), 0L, info = "empty list returns empty created_at")

  # List missing timeline structure.
  result_missing <- xtweetsR:::.rx_parse_posts(list(data = list()))
  testthat::expect_equal(length(result_missing$post_id), 0L, info = "missing timeline returns empty")
  testthat::expect_equal(length(result_missing$created_at), 0L, info = "missing timeline returns empty created_at")
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

# --- Test 8: Author fields extracted correctly from fixture ---
test_that("author fields are extracted correctly from x-search-response.json", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  testthat::expect_true(
    all(is.character(result$author_id)),
    info = "all author_id values are character"
  )
  testthat::expect_true(
    all(is.character(result$username)),
    info = "all username values are character"
  )
  testthat::expect_true(
    all(is.character(result$display_name)),
    info = "all display_name values are character"
  )
  testthat::expect_equal(
    result$username,
    c("rstudio", "rstats_david", "landc"),
    info = "usernames match fixture"
  )
  testthat::expect_equal(
    result$display_name,
    c("RStudio", "David Robinson", "Lionel Henry"),
    info = "display names match fixture"
  )
})

# --- Test 9: Missing author fields return NA ---
test_that("missing author fields return NA rather than crashing", {
  # Tweet entry without core/user_results (no author data).
  response_no_author <- list(
    data = list(
      timeline = list(
        instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = list(
              list(
                entryId = "tweet-100",
                content = list(
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        rest_id = "100",
                        legacy = list(full_text = "Hello without author")
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

  result <- xtweetsR:::.rx_parse_posts(response_no_author)

  testthat::expect_equal(length(result$post_id), 1L, info = "post extracted despite missing author")
  testthat::expect_equal(length(result$text), 1L, info = "text extracted despite missing author")
  testthat::expect_true(
    all(is.na(result$author_id)),
    info = "author_id is NA when core is missing"
  )
  testthat::expect_true(
    all(is.na(result$username)),
    info = "username is NA when core is missing"
  )
  testthat::expect_true(
    all(is.na(result$display_name)),
    info = "display_name is NA when core is missing"
  )
})

# --- Test 10: Author extraction helpers handle edge cases ---
test_that("author extraction helpers return NULL for invalid input", {
  testthat::expect_null(xtweetsR:::.rx_extract_author_id(NULL), info = "NULL result returns NULL")
  testthat::expect_null(xtweetsR:::.rx_extract_author_id(list()), info = "empty list returns NULL")
  testthat::expect_null(xtweetsR:::.rx_extract_author_id(list(core = NULL)), info = "no core returns NULL")

  testthat::expect_null(xtweetsR:::.rx_extract_username(NULL), info = "NULL result returns NULL")
  testthat::expect_null(xtweetsR:::.rx_extract_username(list()), info = "empty list returns NULL")

  testthat::expect_null(xtweetsR:::.rx_extract_display_name(NULL), info = "NULL result returns NULL")
  testthat::expect_null(xtweetsR:::.rx_extract_display_name(list()), info = "empty list returns NULL")
})

# --- Test 11: Empty response returns all five empty vectors ---
test_that("empty response returns all five empty vectors", {
  result_null <- xtweetsR:::.rx_parse_posts(NULL)
  testthat::expect_equal(length(result_null$post_id), 0L, info = "NULL returns empty post_id")
  testthat::expect_equal(length(result_null$text), 0L, info = "NULL returns empty text")
  testthat::expect_equal(length(result_null$author_id), 0L, info = "NULL returns empty author_id")
  testthat::expect_equal(length(result_null$username), 0L, info = "NULL returns empty username")
  testthat::expect_equal(length(result_null$display_name), 0L, info = "NULL returns empty display_name")
  testthat::expect_equal(length(result_null$created_at), 0L, info = "NULL returns empty created_at")
})

# --- Test 12: created_at values match fixture values ---
test_that("created_at values match fixture timestamps", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  testthat::expect_true(
    all(is.character(result$created_at)),
    info = "all created_at values are character"
  )
  testthat::expect_equal(
    result$created_at,
    c(
      "Mon Aug 04 14:30:00 +0000 2026",
      "Mon Aug 04 15:00:00 +0000 2026",
      "Mon Aug 04 15:30:00 +0000 2026"
    ),
    info = "created_at values match fixture"
  )
})

# --- Test 13: Missing created_at returns NA ---
test_that("missing created_at returns NA rather than crashing", {
  # Tweet entry without legacy$created_at.
  response_no_timestamp <- list(
    data = list(
      timeline = list(
        instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = list(
              list(
                entryId = "tweet-200",
                content = list(
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        rest_id = "200",
                        legacy = list(full_text = "No timestamp here")
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

  result <- xtweetsR:::.rx_parse_posts(response_no_timestamp)

  testthat::expect_equal(length(result$post_id), 1L, info = "post extracted despite missing timestamp")
  testthat::expect_true(
    all(is.na(result$created_at)),
    info = "created_at is NA when legacy lacks created_at"
  )
})

# --- Test 14: Empty legacy returns NA for created_at ---
test_that("empty legacy returns NA for created_at", {
  response_empty_legacy <- list(
    data = list(
      timeline = list(
        instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = list(
              list(
                entryId = "tweet-300",
                content = list(
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        rest_id = "300"
                        # No legacy at all
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

  result <- xtweetsR:::.rx_parse_posts(response_empty_legacy)

  testthat::expect_equal(length(result$post_id), 1L, info = "post extracted despite empty legacy")
  testthat::expect_true(
    all(is.na(result$created_at)),
    info = "created_at is NA when legacy is absent"
  )
})
