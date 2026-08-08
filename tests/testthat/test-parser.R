# Tests for the X search response post parser (Tasks 31–34).
#
# These tests validate the post discovery parser that extracts
# post_id, text, author_id, username, display_name, created_at,
# and engagement metrics (reply_count, repost_count, like_count,
# quote_count, bookmark_count, view_count) from the X GraphQL
# timeline fixture.
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

  testthat::expect_true(is.list(result))
  testthat::expect_true("post_id" %in% names(result))
  testthat::expect_true("text" %in% names(result))
  testthat::expect_true("author_id" %in% names(result))
  testthat::expect_true("username" %in% names(result))
  testthat::expect_true("display_name" %in% names(result))
  testthat::expect_true("created_at" %in% names(result))
  testthat::expect_true("reply_count" %in% names(result))
  testthat::expect_true("repost_count" %in% names(result))
  testthat::expect_true("like_count" %in% names(result))
  testthat::expect_true("quote_count" %in% names(result))
  testthat::expect_true("bookmark_count" %in% names(result))
  testthat::expect_true("view_count" %in% names(result))
  testthat::expect_true("conversation_id" %in% names(result))
  testthat::expect_true("is_reply" %in% names(result))
  testthat::expect_true("is_repost" %in% names(result))
  testthat::expect_true("is_quote" %in% names(result))
  testthat::expect_true("reply_to_post_id" %in% names(result))
  testthat::expect_true("quoted_post_id" %in% names(result))
  testthat::expect_true(length(result$post_id) >= 1)
  testthat::expect_true(length(result$text) >= 1)
  testthat::expect_equal(
    length(result$post_id), length(result$text)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$author_id)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$username)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$display_name)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$created_at)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$reply_count)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$repost_count)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$like_count)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$quote_count)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$bookmark_count)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$view_count)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$conversation_id)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$is_reply)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$is_repost)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$is_quote)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$reply_to_post_id)
    )
  testthat::expect_equal(
    length(result$post_id), length(result$quoted_post_id)
    )
  testthat::expect_true("cursors" %in% names(result))
  testthat::expect_true("hashtags" %in% names(result))
  testthat::expect_true("mentions" %in% names(result))
  testthat::expect_true("urls" %in% names(result))
  testthat::expect_true(is.list(result$hashtags))
  testthat::expect_true(is.list(result$mentions))
  testthat::expect_true(is.list(result$urls))
  testthat::expect_true(is.list(result$media_type))
  testthat::expect_true(is.list(result$media_urls))
  testthat::expect_equal(length(result$hashtags), 4L)
  testthat::expect_equal(length(result$mentions), 4L)
  testthat::expect_equal(length(result$urls), 4L)
  testthat::expect_equal(length(result$media_type), 4L)
  testthat::expect_equal(length(result$media_urls), 4L)
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
    all(is.character(result$post_id))
    )
  testthat::expect_true(
    all(nzchar(result$post_id))
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
    "1900000000000000003",
    "1900000000000000004"
  )

  testthat::expect_equal(
    result$post_id, expected_ids
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
    "Quasiquotation in R is powerful once you understand it. Thread below on when to use !! vs {{",
    "Great thread on quasiquotation! Here is my take on the design trade-offs."
  )

  testthat::expect_equal(
    result$text, expected_texts
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

  testthat::expect_equal(length(result$post_id), 1L)
  testthat::expect_equal(result$post_id, "123")
})

# --- Test 6: Empty/malformed response returns empty vectors ---
test_that("malformed responses return empty vectors without crashing", {
  # NULL response.
  result_null <- xtweetsR:::.rx_parse_posts(NULL)
  testthat::expect_equal(length(result_null$post_id), 0L)

  # Empty list.
  result_empty <- xtweetsR:::.rx_parse_posts(list())
  testthat::expect_equal(length(result_empty$post_id), 0L)
  testthat::expect_equal(length(result_empty$created_at), 0L)

  # List missing timeline structure.
  result_missing <- xtweetsR:::.rx_parse_posts(list(data = list()))
  testthat::expect_equal(length(result_missing$post_id), 0L)
  testthat::expect_equal(length(result_missing$created_at), 0L)
})

# --- Test 7: Helper function .rx_find_tweet_result returns NULL for non-tweet entries ---
test_that(".rx_find_tweet_result returns NULL when nesting is missing", {
  # Entry with no content.
  testthat::expect_null(xtweetsR:::.rx_find_tweet_result(list()))
  testthat::expect_null(
    xtweetsR:::.rx_find_tweet_result(list(content = NULL))
    )
  testthat::expect_null(
    xtweetsR:::.rx_find_tweet_result(list(content = list(itemContent = NULL)))
    )
  testthat::expect_null(
    xtweetsR:::.rx_find_tweet_result(list(content = list(itemContent = list(tweet_results = NULL))))
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
  testthat::expect_true(is.list(result))
  testthat::expect_equal(result$rest_id, "456")
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
    all(is.character(result$author_id))
    )
  testthat::expect_true(
    all(is.character(result$username))
    )
  testthat::expect_true(
    all(is.character(result$display_name))
    )
  testthat::expect_equal(
    result$username,
    c("rstudio", "rstats_david", "landc", "hadleywickham")
    )
  testthat::expect_equal(
    result$display_name,
    c("RStudio", "David Robinson", "Lionel Henry", "Hadley Wickham")
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

  testthat::expect_equal(length(result$post_id), 1L)
  testthat::expect_equal(length(result$text), 1L)
  testthat::expect_true(
    all(is.na(result$author_id))
    )
  testthat::expect_true(
    all(is.na(result$username))
    )
  testthat::expect_true(
    all(is.na(result$display_name))
    )
})

# --- Test 10: Author extraction helpers handle edge cases ---
test_that("author extraction helpers return NULL for invalid input", {
  testthat::expect_null(xtweetsR:::.rx_extract_author_id(NULL))
  testthat::expect_null(xtweetsR:::.rx_extract_author_id(list()))
  testthat::expect_null(xtweetsR:::.rx_extract_author_id(list(core = NULL)))

  testthat::expect_null(xtweetsR:::.rx_extract_username(NULL))
  testthat::expect_null(xtweetsR:::.rx_extract_username(list()))

  testthat::expect_null(xtweetsR:::.rx_extract_display_name(NULL))
  testthat::expect_null(xtweetsR:::.rx_extract_display_name(list()))
})

# --- Test 11: Empty response returns all five empty vectors ---
test_that("empty response returns all five empty vectors", {
  result_null <- xtweetsR:::.rx_parse_posts(NULL)
  testthat::expect_equal(length(result_null$post_id), 0L)
  testthat::expect_equal(length(result_null$text), 0L)
  testthat::expect_equal(length(result_null$author_id), 0L)
  testthat::expect_equal(length(result_null$username), 0L)
  testthat::expect_equal(length(result_null$display_name), 0L)
  testthat::expect_equal(length(result_null$created_at), 0L)
  testthat::expect_equal(length(result_null$hashtags), 0L)
  testthat::expect_equal(length(result_null$mentions), 0L)
  testthat::expect_equal(length(result_null$urls), 0L)
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
    all(is.character(result$created_at))
    )
  testthat::expect_equal(
    result$created_at,
    c(
      "Mon Aug 04 14:30:00 +0000 2026",
      "Mon Aug 04 15:00:00 +0000 2026",
      "Mon Aug 04 15:30:00 +0000 2026",
      "Mon Aug 04 16:00:00 +0000 2026"
    )
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

  testthat::expect_equal(length(result$post_id), 1L)
  testthat::expect_true(
    all(is.na(result$created_at))
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

  testthat::expect_equal(length(result$post_id), 1L)
  testthat::expect_true(
    all(is.na(result$created_at))
    )
})

# --- Test 15: Engagement metrics extracted from fixture ---
test_that("engagement metrics are extracted correctly from x-search-response.json", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  # reply_count: 12, 5, 20, 8
  testthat::expect_equal(
    result$reply_count,
    c(12L, 5L, 20L, 8L)
    )

  # repost_count (from retweet_count): 45, 8, 30, 15
  testthat::expect_equal(
    result$repost_count,
    c(45L, 8L, 30L, 15L)
    )

  # like_count (from favorite_count): 230, 67, 150, 92
  testthat::expect_equal(
    result$like_count,
    c(230L, 67L, 150L, 92L)
    )

  # quote_count: 3, 1, 5, 0
  testthat::expect_equal(
    result$quote_count,
    c(3L, 1L, 5L, 0L)
    )

  # bookmark_count: 18, 4, 42, 11
  testthat::expect_equal(
    result$bookmark_count,
    c(18L, 4L, 42L, 11L)
    )

  # view_count (from views$count): 15420, 4210, 28500, 9800
  testthat::expect_equal(
    result$view_count,
    c(15420L, 4210L, 28500L, 9800L)
    )

  # All engagement metrics should be integer type.
  testthat::expect_true(all(is.integer(result$reply_count)))
  testthat::expect_true(all(is.integer(result$repost_count)))
  testthat::expect_true(all(is.integer(result$like_count)))
  testthat::expect_true(all(is.integer(result$quote_count)))
  testthat::expect_true(all(is.integer(result$bookmark_count)))
  testthat::expect_true(all(is.integer(result$view_count)))
})

# --- Test 16: Missing engagement metrics return 0L ---
test_that("missing engagement metrics return 0L rather than crashing", {
  # Tweet entry with empty legacy (no engagement data).
  response_no_metrics <- list(
    data = list(
      timeline = list(
        instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = list(
              list(
                entryId = "tweet-400",
                content = list(
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        rest_id = "400",
                        legacy = list(full_text = "No metrics here")
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

  result <- xtweetsR:::.rx_parse_posts(response_no_metrics)

  testthat::expect_equal(length(result$post_id), 1L)
  testthat::expect_equal(result$reply_count, 0L)
  testthat::expect_equal(result$repost_count, 0L)
  testthat::expect_equal(result$like_count, 0L)
  testthat::expect_equal(result$quote_count, 0L)
  testthat::expect_equal(result$bookmark_count, 0L)
  testthat::expect_equal(result$view_count, 0L)
})

# --- Test 17: Engagement metrics helpers handle edge cases ---
test_that(".rx_extract_int returns 0L for invalid input", {
  testthat::expect_equal(xtweetsR:::.rx_extract_int(NULL, "reply_count"), 0L)
  testthat::expect_equal(xtweetsR:::.rx_extract_int(list(), "reply_count"), 0L)
  testthat::expect_equal(xtweetsR:::.rx_extract_int(list(full_text = "hi"), "reply_count"), 0L)
  testthat::expect_equal(xtweetsR:::.rx_extract_int(list(reply_count = NA), "reply_count"), 0L)
  testthat::expect_equal(xtweetsR:::.rx_extract_int(list(reply_count = 42), "reply_count"), 42L)
})

test_that(".rx_extract_view_count returns 0L for missing views", {
  testthat::expect_equal(xtweetsR:::.rx_extract_view_count(NULL), 0L)
  testthat::expect_equal(xtweetsR:::.rx_extract_view_count(list()), 0L)
  testthat::expect_equal(xtweetsR:::.rx_extract_view_count(list(views = NULL)), 0L)
  testthat::expect_equal(xtweetsR:::.rx_extract_view_count(list(views = list())), 0L)
  testthat::expect_equal(xtweetsR:::.rx_extract_view_count(list(views = list(count = NA))), 0L)
  testthat::expect_equal(xtweetsR:::.rx_extract_view_count(list(views = list(count = 999))), 999L)
})

# --- Test 18: Empty response returns all twenty-one empty vectors ---
test_that("empty response returns all twenty-one empty vectors", {
  result_null <- xtweetsR:::.rx_parse_posts(NULL)
  testthat::expect_equal(length(result_null$post_id), 0L)
  testthat::expect_equal(length(result_null$text), 0L)
  testthat::expect_equal(length(result_null$author_id), 0L)
  testthat::expect_equal(length(result_null$username), 0L)
  testthat::expect_equal(length(result_null$display_name), 0L)
  testthat::expect_equal(length(result_null$created_at), 0L)
  testthat::expect_equal(length(result_null$reply_count), 0L)
  testthat::expect_equal(length(result_null$repost_count), 0L)
  testthat::expect_equal(length(result_null$like_count), 0L)
  testthat::expect_equal(length(result_null$quote_count), 0L)
  testthat::expect_equal(length(result_null$bookmark_count), 0L)
  testthat::expect_equal(length(result_null$view_count), 0L)
  testthat::expect_equal(length(result_null$conversation_id), 0L)
  testthat::expect_equal(length(result_null$is_reply), 0L)
  testthat::expect_equal(length(result_null$is_repost), 0L)
  testthat::expect_equal(length(result_null$is_quote), 0L)
  testthat::expect_equal(length(result_null$reply_to_post_id), 0L)
  testthat::expect_equal(length(result_null$quoted_post_id), 0L)
  testthat::expect_equal(length(result_null$hashtags), 0L)
  testthat::expect_equal(length(result_null$mentions), 0L)
  testthat::expect_equal(length(result_null$urls), 0L)
  testthat::expect_equal(length(result_null$media_type), 0L)
  testthat::expect_equal(length(result_null$media_urls), 0L)
  testthat::expect_equal(length(result_null$cursors), 0L)
})

# --- Test 19: Relationship fields extracted correctly from fixture ---
test_that("relationship fields are extracted correctly from x-search-response.json", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  # conversation_id: present on all 4 tweets
  testthat::expect_true(all(is.character(result$conversation_id)))
  testthat::expect_equal(
    result$conversation_id,
    c("1900000000000000001", "1900000000000000002", "1900000000000000003", "1900000000000000003")
    )

  # is_reply: only tweet 2 is a reply
  testthat::expect_true(all(is.logical(result$is_reply)))
  testthat::expect_equal(
    result$is_reply,
    c(FALSE, TRUE, FALSE, FALSE)
    )

  # is_repost: none are reposts
  testthat::expect_true(all(is.logical(result$is_repost)))
  testthat::expect_equal(
    result$is_repost,
    c(FALSE, FALSE, FALSE, FALSE)
    )

  # is_quote: only tweet 4 is a quote
  testthat::expect_true(all(is.logical(result$is_quote)))
  testthat::expect_equal(
    result$is_quote,
    c(FALSE, FALSE, FALSE, TRUE)
    )

  # reply_to_post_id: only tweet 2 has one
  testthat::expect_true(all(is.character(result$reply_to_post_id)))
  testthat::expect_equal(
    result$reply_to_post_id,
    c(NA_character_, "1900000000000000001", NA_character_, NA_character_)
    )

  # quoted_post_id: only tweet 4 has one
  testthat::expect_true(all(is.character(result$quoted_post_id)))
  testthat::expect_equal(
    result$quoted_post_id,
    c(NA_character_, NA_character_, NA_character_, "1900000000000000003")
    )
})

# --- Test 20: Missing relationship fields return safe defaults ---
test_that("missing relationship fields return safe defaults", {
  # Tweet entry without any relationship data.
  response_no_relationships <- list(
    data = list(
      timeline = list(
        instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = list(
              list(
                entryId = "tweet-500",
                content = list(
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        rest_id = "500",
                        legacy = list(full_text = "No relationships here")
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

  result <- xtweetsR:::.rx_parse_posts(response_no_relationships)

  testthat::expect_equal(length(result$post_id), 1L)
  testthat::expect_true(all(is.na(result$conversation_id)))
  testthat::expect_false(all(result$is_reply))
  testthat::expect_false(all(result$is_repost))
  testthat::expect_false(all(result$is_quote))
  testthat::expect_true(all(is.na(result$reply_to_post_id)))
  testthat::expect_true(all(is.na(result$quoted_post_id)))
})

# --- Test 21: Helper function .rx_extract_bool handles edge cases ---
test_that(".rx_extract_bool returns FALSE for invalid input", {
  testthat::expect_false(xtweetsR:::.rx_extract_bool(NULL, "in_reply_to_status_id_str"))
  testthat::expect_false(xtweetsR:::.rx_extract_bool(list(), "in_reply_to_status_id_str"))
  testthat::expect_false(xtweetsR:::.rx_extract_bool(list(full_text = "hi"), "in_reply_to_status_id_str"))
  testthat::expect_false(xtweetsR:::.rx_extract_bool(list(in_reply_to_status_id_str = NA), "in_reply_to_status_id_str"))
  testthat::expect_false(xtweetsR:::.rx_extract_bool(list(in_reply_to_status_id_str = NULL), "in_reply_to_status_id_str"))
  testthat::expect_true(xtweetsR:::.rx_extract_bool(list(in_reply_to_status_id_str = "123"), "in_reply_to_status_id_str"))
})

# --- Test 22: Cursor extraction from fixture ---
test_that("cursors are extracted from x-search-response.json", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  testthat::expect_true("cursors" %in% names(result))

  # The fixture has Bottom and Top cursors in TimelineAddToModule.
  testthat::expect_true(is.character(result$cursors))
  testthat::expect_true("Bottom" %in% names(result$cursors))
  testthat::expect_true("Top" %in% names(result$cursors))
  testthat::expect_true(nzchar(result$cursors["Bottom"]))
  testthat::expect_true(nzchar(result$cursors["Top"]))
})

# --- Test 23: Missing cursors returns empty ---
test_that("response without TimelineAddToModule returns empty cursors", {
  # Response with only Tweet entries, no cursor instruction.
  response_no_cursors <- list(
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
              )
            )
          )
        )
      )
    )
  )

  result <- xtweetsR:::.rx_parse_posts(response_no_cursors)

  testthat::expect_true(is.character(result$cursors))
  testthat::expect_equal(length(result$cursors), 0L)
})

# --- Test 24: .rx_extract_cursors handles edge cases ---
test_that(".rx_extract_cursors returns character(0) for invalid input", {
  testthat::expect_equal(xtweetsR:::.rx_extract_cursors(NULL), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_cursors(list()), character(0))
  testthat::expect_equal(
    xtweetsR:::.rx_extract_cursors(list(data = list())),
    character(0)
    )
})

# --- Test 25: Entity fields extracted from x-search-response.json ---
test_that("hashtags, mentions, and urls are extracted from x-search-response.json", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  # Hashtags: tweet1 has ["RStats", "tidyverse"], tweet2 has ["rstats"], tweet3 has [], tweet4 has []
  testthat::expect_true(is.list(result$hashtags))
  testthat::expect_equal(length(result$hashtags), 4L)
  testthat::expect_equal(as.character(result$hashtags[[1L]]), c("RStats", "tidyverse"))
  testthat::expect_equal(as.character(result$hashtags[[2L]]), "rstats")
  testthat::expect_equal(length(result$hashtags[[3L]]), 0L)
  testthat::expect_equal(length(result$hashtags[[4L]]), 0L)

  # Mentions: tweet1 has [], tweet2 has [@rstudio (RStudio)]
  testthat::expect_true(is.list(result$mentions))
  testthat::expect_equal(length(result$mentions), 4L)
  testthat::expect_equal(length(result$mentions[[1L]]), 0L)
  testthat::expect_equal(length(result$mentions[[2L]]), 1L)
  testthat::expect_equal(result$mentions[[2L]][["screen_name"]], "rstudio")
  testthat::expect_equal(result$mentions[[2L]][["name"]], "RStudio")
  testthat::expect_equal(length(result$mentions[[3L]]), 0L)
  testthat::expect_equal(length(result$mentions[[4L]]), 0L)

  # URLs: tweet1 has [https://posit.co/blog/new-release], tweet2 has [], tweet3 has [], tweet4 has []
  testthat::expect_true(is.list(result$urls))
  testthat::expect_equal(length(result$urls), 4L)
  testthat::expect_equal(as.character(result$urls[[1L]]), "https://posit.co/blog/new-release")
  testthat::expect_equal(length(result$urls[[2L]]), 0L)
  testthat::expect_equal(length(result$urls[[3L]]), 0L)
  testthat::expect_equal(length(result$urls[[4L]]), 0L)
})

# --- Test 26: Missing entities returns empty collections ---
test_that("tweets without entities return empty collections", {
  # Tweet entry without entities block.
  response_no_entities <- list(
    data = list(
      timeline = list(
        instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = list(
              list(
                entryId = "tweet-600",
                content = list(
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        rest_id = "600",
                        legacy = list(full_text = "No entities here")
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

  result <- xtweetsR:::.rx_parse_posts(response_no_entities)

  testthat::expect_equal(length(result$hashtags), 1L)
  testthat::expect_equal(length(result$hashtags[[1L]]), 0L)
  testthat::expect_equal(length(result$mentions), 1L)
  testthat::expect_equal(length(result$mentions[[1L]]), 0L)
  testthat::expect_equal(length(result$urls), 1L)
  testthat::expect_equal(length(result$urls[[1L]]), 0L)
})

# --- Test 27: Entity extraction helpers handle edge cases ---
test_that(".rx_extract_hashtags returns empty for invalid input", {
  testthat::expect_equal(xtweetsR:::.rx_extract_hashtags(NULL), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_hashtags(list()), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_hashtags(list(hashtags = NULL)), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_hashtags(list(hashtags = list())), character(0))
})

test_that(".rx_extract_mentions returns empty list for invalid input", {
  testthat::expect_equal(xtweetsR:::.rx_extract_mentions(NULL), list())
  testthat::expect_equal(xtweetsR:::.rx_extract_mentions(list()), list())
  testthat::expect_equal(xtweetsR:::.rx_extract_mentions(list(user_mentions = NULL)), list())
  testthat::expect_equal(xtweetsR:::.rx_extract_mentions(list(user_mentions = list())), list())
})

test_that(".rx_extract_urls returns empty for invalid input", {
  testthat::expect_equal(xtweetsR:::.rx_extract_urls(NULL), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_urls(list()), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_urls(list(urls = NULL)), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_urls(list(urls = list())), character(0))
})

# --- Test 28: Media fields extracted from x-search-response.json ---
test_that("media_type and media_urls are extracted from x-search-response.json", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  # media_type is a list with 4 elements (one per post)
  testthat::expect_true(is.list(result$media_type))
  testthat::expect_equal(length(result$media_type), 4L)

  # First 3 tweets have no media, 4th has 2 photos
  testthat::expect_equal(length(result$media_type[[1L]]), 0L)
  testthat::expect_equal(length(result$media_type[[2L]]), 0L)
  testthat::expect_equal(length(result$media_type[[3L]]), 0L)
  testthat::expect_equal(as.character(result$media_type[[4L]]), c("photo", "photo"))

  # media_urls is a list with 4 elements (one per post)
  testthat::expect_true(is.list(result$media_urls))
  testthat::expect_equal(length(result$media_urls), 4L)

  # First 3 tweets have no media URLs, 4th has 2
  testthat::expect_equal(length(result$media_urls[[1L]]), 0L)
  testthat::expect_equal(length(result$media_urls[[2L]]), 0L)
  testthat::expect_equal(length(result$media_urls[[3L]]), 0L)
  testthat::expect_equal(length(result$media_urls[[4L]]), 2L)
  testthat::expect_true("0" %in% names(result$media_urls[[4L]]))
  testthat::expect_true("1" %in% names(result$media_urls[[4L]]))
})

# --- Test 29: Posts without extended_entities parse normally ---
test_that("posts without extended_entities parse normally", {
  # Tweet entry without extended_entities block.
  response_no_media <- list(
    data = list(
      timeline = list(
        instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = list(
              list(
                entryId = "tweet-700",
                content = list(
                  itemContent = list(
                    tweet_results = list(
                      result = list(
                        rest_id = "700",
                        legacy = list(full_text = "No media here")
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

  result <- xtweetsR:::.rx_parse_posts(response_no_media)

  testthat::expect_equal(length(result$post_id), 1L)
  testthat::expect_equal(length(result$media_type), 1L)
  testthat::expect_equal(length(result$media_type[[1L]]), 0L)
  testthat::expect_equal(length(result$media_urls), 1L)
  testthat::expect_equal(length(result$media_urls[[1L]]), 0L)
})

# --- Test 30: Media extraction helpers handle edge cases ---
test_that(".rx_extract_media_types returns empty for invalid input", {
  testthat::expect_equal(xtweetsR:::.rx_extract_media_types(NULL), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_media_types(list()), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_media_types(list(media = NULL)), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_media_types(list(media = list())), character(0))
})

test_that(".rx_extract_media_urls returns empty for invalid input", {
  testthat::expect_equal(xtweetsR:::.rx_extract_media_urls(NULL), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_media_urls(list()), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_media_urls(list(media = NULL)), character(0))
  testthat::expect_equal(xtweetsR:::.rx_extract_media_urls(list(media = list())), character(0))
})

# --- Test 31: Animated GIF media extraction ---
test_that("animated_gif media with video_info variants is extracted", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-user-timeline-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  result <- xtweetsR:::.rx_parse_posts(parsed)

  # Tweet 5 (index 5) has an animated_gif with a video variant
  # Tweet 4 (index 4) has a photo
  testthat::expect_equal(length(result$media_type), 5L)
  testthat::expect_equal(as.character(result$media_type[[4L]]), "photo")
  testthat::expect_equal(as.character(result$media_type[[5L]]), "animated_gif")

  # The animated_gif should have the video variant URL in media_urls
  testthat::expect_true(length(result$media_urls[[5L]]) >= 1L)
  testthat::expect_true(any(grepl("tweet_video", result$media_urls[[5L]])))
})

# --- Test 32: Schema validation detects missing instructions ---
test_that(
  "response with data$timeline but no instructions throws PARSER_ERROR",
  {
    # data$timeline exists but instructions is missing entirely —
    # this means X changed the response key.
    response <- list(
      data = list(
        timeline = list(
          # No $instructions at all.
          something_else = "not_instructions"
        )
      )
    )

    testthat::expect_error(
      xtweetsR:::.rx_parse_posts(response),
      class = "rx_parser_error"
    )
  }
)

# --- Test 33: Schema validation detects empty instructions ---
test_that(
  "response with empty instructions array throws PARSER_ERROR",
  {
    # instructions exists but is empty — X may have changed the structure.
    response <- list(
      data = list(
        timeline = list(
          instructions = list()
        )
      )
    )

    testthat::expect_error(
      xtweetsR:::.rx_parse_posts(response),
      class = "rx_parser_error"
    )
  }
)

# --- Test 34: Schema validation detects wrong instruction type ---
test_that(
  "response with non-TimelineAddEntries instructions throws PARSER_ERROR",
  {
    # instructions exist but the type is not TimelineAddEntries —
    # X may have renamed the instruction type.
    response <- list(
      data = list(
        timeline = list(
          instructions = list(
            list(type = "TimelineSuppressEntries")
          )
        )
      )
    )

    testthat::expect_error(
      xtweetsR:::.rx_parse_posts(response),
      class = "rx_parser_error"
    )
  }
)

# --- Test 35: Schema validation detects entries with no valid post objects ---
test_that(
  "entries present but no valid post objects throws PARSER_ERROR",
  {
    # TimelineAddEntries exists with entries, but none contain
    # tweet_results/result — X changed the entry nesting.
    response <- list(
      data = list(
        timeline = list(
          instructions = list(
            list(
              type = "TimelineAddEntries",
              entries = list(
                list(
                  entryId = "cursor-bottom-abc",
                  content = list(
                    itemContent = list(
                      cursor = list(cursorType = "Bottom", value = "abc123")
                    )
                  )
                )
              )
            )
          )
        )
      )
    )

    testthat::expect_error(
      xtweetsR:::.rx_parse_posts(response),
      class = "rx_parser_error"
    )
  }
)

# --- Test 36: Error includes parser_version in the message ---
test_that(
  "schema errors include parser_version in the error message",
  {
    response <- list(
      data = list(
        timeline = list(
          something_else = "not_instructions"
        )
      )
    )

    err <- testthat::expect_error(
      xtweetsR:::.rx_parse_posts(response),
      class = "rx_parser_error"
    )

    testthat::expect_true(
      grepl("parser_version", conditionMessage(err), ignore.case = TRUE)
      )
    testthat::expect_true(
      grepl("0\\.1\\.0", conditionMessage(err))
      )
  }
)

# --- Test 37: Error includes diagnostic context ---
test_that(
  "schema errors include diagnostic context about what was expected vs found",
  {
    response <- list(
      data = list(
        timeline = list(
          instructions = list(
            list(type = "TimelineSuppressEntries")
          )
        )
      )
    )

    err <- testthat::expect_error(
      xtweetsR:::.rx_parse_posts(response),
      class = "rx_parser_error"
    )

    msg <- conditionMessage(err)
    testthat::expect_true(
      grepl("TimelineAddEntries", msg)
      )
    testthat::expect_true(
      grepl("TimelineSuppressEntries", msg)
      )
  }
)

# --- Test 38: Entries with mix of tweet and cursor — valid tweets still parse ---
test_that(
  "entries with both tweets and cursors parse the tweets (not an error)",
  {
    # This is the normal case: entries contain both tweet entries and
    # cursor entries. Valid tweets should be extracted, not an error.
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
    testthat::expect_equal(length(result$post_id), 1L)
    testthat::expect_equal(result$post_id, "123")
  }
)
