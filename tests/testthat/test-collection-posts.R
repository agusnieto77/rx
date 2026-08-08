# Tests for the collection-post relation module (Iteration 87).
#
# These tests validate the collection-post relation extraction and
# relational result infrastructure that complements the posts, users,
# and media tables with a relation table tracking which posts appeared
# in which collection runs and queries.

# --- Test 1: .rx_collection_posts_fields returns 4 fields in correct order ---
test_that(".rx_collection_posts_fields returns 4 fields in canonical order", {
  fields <- xtweetsR:::.rx_collection_posts_fields()
  testthat::expect_length(fields, 4L)
  testthat::expect_equal(
    fields,
    c("post_id", "collection_id", "collection_query", "collected_at")
    )
})

# --- Test 2: .rx_extract_collection_posts returns empty on NULL input ---
test_that(".rx_extract_collection_posts returns empty vectors on NULL input", {
  result <- xtweetsR:::.rx_extract_collection_posts(NULL)
  testthat::expect_type(result, "list")
  testthat::expect_length(result, 4L)
  testthat::expect_equal(length(result$post_id), 0L)
  testthat::expect_equal(length(result$collection_id), 0L)
  testthat::expect_equal(length(result$collection_query), 0L)
  testthat::expect_equal(length(result$collected_at), 0L)
})

# --- Test 3: .rx_extract_collection_posts returns empty on empty parsed list ---
test_that(".rx_extract_collection_posts returns empty vectors on empty parsed list", {
  result <- xtweetsR:::.rx_extract_collection_posts(list(post_id = character(0)))
  testthat::expect_length(result$post_id, 0L)
  testthat::expect_length(result$collection_id, 0L)
  testthat::expect_length(result$collection_query, 0L)
  testthat::expect_length(result$collected_at, 0L)
})

# --- Test 4: .rx_extract_collection_posts extracts relations with valid provenance ---
test_that(".rx_extract_collection_posts extracts relations from valid parsed data", {
  parsed <- list(
    post_id = c("1", "2", "3"),
    collection_id = c("uuid-1", "uuid-1", "uuid-2"),
    collection_query = c("r programming", "r programming", "AI"),
    collected_at = c("2026-01-01T00:00:00Z", "2026-01-01T00:00:01Z", "2026-01-02T00:00:00Z")
  )
  result <- xtweetsR:::.rx_extract_collection_posts(parsed)
  testthat::expect_length(result$post_id, 3L)
  testthat::expect_equal(result$post_id, c("1", "2", "3"))
  testthat::expect_equal(result$collection_id, c("uuid-1", "uuid-1", "uuid-2"))
  testthat::expect_equal(result$collection_query, c("r programming", "r programming", "AI"))
})

# --- Test 5: .rx_extract_collection_posts handles missing NA collection_id ---
test_that(".rx_extract_collection_posts handles NA collection_id", {
  parsed <- list(
    post_id = c("1", "2"),
    collection_id = c("uuid-1", NA_character_),
    collection_query = c("test", "test2"),
    collected_at = c("2026-01-01T00:00:00Z", "2026-01-02T00:00:00Z")
  )
  result <- xtweetsR:::.rx_extract_collection_posts(parsed)
  testthat::expect_length(result$post_id, 2L)
  testthat::expect_equal(result$collection_id[1L], "uuid-1")
  testthat::expect_true(is.na(result$collection_id[2L]))
})

# --- Test 6: .rx_extract_collection_posts handles missing NA collection_query ---
test_that(".rx_extract_collection_posts handles NA collection_query", {
  parsed <- list(
    post_id = c("1", "2"),
    collection_id = c("uuid-1", "uuid-2"),
    collection_query = c("test", NA_character_),
    collected_at = c("2026-01-01T00:00:00Z", "2026-01-02T00:00:00Z")
  )
  result <- xtweetsR:::.rx_extract_collection_posts(parsed)
  testthat::expect_length(result$collection_query, 2L)
  testthat::expect_true(is.na(result$collection_query[2L]))
})

# --- Test 7: .rx_extract_collection_posts handles missing NA collected_at ---
test_that(".rx_extract_collection_posts handles NA collected_at", {
  parsed <- list(
    post_id = c("1", "2"),
    collection_id = c("uuid-1", "uuid-2"),
    collection_query = c("test", "test2"),
    collected_at = c("2026-01-01T00:00:00Z", NA_character_)
  )
  result <- xtweetsR:::.rx_extract_collection_posts(parsed)
  testthat::expect_true(is.na(result$collected_at[2L]))
})

# --- Test 8: .rx_collection_posts_to_tibble returns empty tibble on empty input ---
test_that(".rx_collection_posts_to_tibble returns empty tibble on empty input", {
  result <- xtweetsR:::.rx_collection_posts_to_tibble(list())
  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_equal(nrow(result), 0L)
  testthat::expect_equal(ncol(result), 4L)
  testthat::expect_equal(names(result), .rx_collection_posts_fields())
})

# --- Test 9: .rx_collection_posts_to_tibble converts correctly ---
test_that(".rx_collection_posts_to_tibble converts relation list to tibble", {
  relations <- list(
    post_id = c("1", "2"),
    collection_id = c("uuid-1", "uuid-2"),
    collection_query = c("r programming", "AI"),
    collected_at = c("2026-01-01T00:00:00Z", "2026-01-02T00:00:00Z")
  )
  result <- xtweetsR:::.rx_collection_posts_to_tibble(relations)
  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_equal(result$post_id[1L], "1")
  testthat::expect_equal(result$collection_query[2L], "AI")
})

# --- Test 10: .rx_collection_posts_to_tibble handles NA values ---
test_that(".rx_collection_posts_to_tibble handles NA collection_id", {
  relations <- list(
    post_id = c("1"),
    collection_id = c(NA_character_),
    collection_query = c("test"),
    collected_at = c("2026-01-01T00:00:00Z")
  )
  result <- xtweetsR:::.rx_collection_posts_to_tibble(relations)
  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_true(is.na(result$collection_id[1L]))
})

# --- Test 11: .rx_collection_posts_to_tibble returns empty on malformed input ---
test_that(".rx_collection_posts_to_tibble returns empty tibble on malformed input", {
  result <- xtweetsR:::.rx_collection_posts_to_tibble(list(foo = "bar"))
  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_equal(nrow(result), 0L)
})

# --- Test 12: .rx_collection_posts_to_tibble returns empty on NULL input ---
test_that(".rx_collection_posts_to_tibble returns empty tibble on NULL input", {
  result <- xtweetsR:::.rx_collection_posts_to_tibble(NULL)
  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_equal(nrow(result), 0L)
})

# --- Test 13: .rx_relational_result wraps posts and collection_posts ---
test_that(".rx_relational_result returns rx_relational with collection_posts attribute", {
  posts <- tibble::tibble(
    post_id = c("1", "2"),
    text = c("hello", "world")
  )
  parsed <- list(
    post_id = c("1", "2"),
    collection_id = c("uuid-1", "uuid-1"),
    collection_query = c("test", "test"),
    collected_at = c("2026-01-01T00:00:00Z", "2026-01-01T00:00:01Z")
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  testthat::expect_s3_class(result, "rx_relational")
  testthat::expect_s3_class(result, "tbl_df")
  rels <- attr(result, "rx_collection_posts")
  testthat::expect_true(!is.null(rels))
  testthat::expect_s3_class(rels, "tbl_df")
  testthat::expect_equal(nrow(rels), 2L)
})

# --- Test 14: .rx_relational_result with empty posts ---
test_that(".rx_relational_result handles empty posts", {
  posts <- tibble::tibble(post_id = character(0))
  parsed <- list(post_id = character(0))
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  testthat::expect_s3_class(result, "rx_relational")
  rels <- attr(result, "rx_collection_posts")
  testthat::expect_equal(nrow(rels), 0L)
})

# --- Test 15: rx_collection_posts() accessor extracts relations from relational result ---
test_that("rx_collection_posts() extracts relations from rx_relational object", {
  posts <- tibble::tibble(
    post_id = c("1", "2"),
    text = c("hello", "world")
  )
  parsed <- list(
    post_id = c("1", "2"),
    collection_id = c("uuid-1", "uuid-2"),
    collection_query = c("test1", "test2"),
    collected_at = c("2026-01-01T00:00:00Z", "2026-01-02T00:00:00Z")
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  rels <- xtweetsR::rx_collection_posts(result)
  testthat::expect_s3_class(rels, "tbl_df")
  testthat::expect_equal(nrow(rels), 2L)
  testthat::expect_equal(rels$collection_query[1L], "test1")
})

# --- Test 16: rx_collection_posts() returns empty tibble on non-relational input ---
test_that("rx_collection_posts() returns empty tibble for non-relational objects", {
  posts <- tibble::tibble(post_id = c("1"), text = c("hello"))
  rels <- xtweetsR::rx_collection_posts(posts)
  testthat::expect_s3_class(rels, "tbl_df")
  testthat::expect_equal(nrow(rels), 0L)
})

# --- Test 17: Full pipeline — extract relations from parsed search fixture ---
test_that("Full pipeline: extract collection posts from a realistic parsed response", {
  fixture_path <- system.file("tests/fixtures/x-search-response.json", package = "xtweetsR")
  if (nzchar(fixture_path)) {
    data <- jsonlite::fromJSON(fixture_path, simplifyVector = FALSE)
    parsed <- xtweetsR:::.rx_parse_posts(data)
    # Simulate observation-level provenance (normally injected by search pipeline).
    n <- length(parsed$post_id)
    if (n > 0L) {
      parsed$collection_id    <- rep("uuid-test-fixture", n)
      parsed$collection_query <- rep("fixture-test", n)
      parsed$collected_at     <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    }
    relations <- xtweetsR:::.rx_extract_collection_posts(parsed)
    rels_tbl <- xtweetsR:::.rx_collection_posts_to_tibble(relations)
    testthat::expect_s3_class(rels_tbl, "tbl_df")
    testthat::expect_true(nrow(rels_tbl) >= 1L)
    testthat::expect_true(all(names(rels_tbl) %in% .rx_collection_posts_fields()))
    testthat::expect_true(all(rels_tbl$collection_id == "uuid-test-fixture"))
  } else {
    testthat::skip("fixture not available")
  }
})

# --- Test 18: Relational result preserves all post columns ---
test_that(".rx_relational_result preserves all post columns", {
  posts <- tibble::tibble(
    post_id = c("1"),
    text = c("test"),
    author_id = c("abc"),
    username = c("alice"),
    display_name = c("Alice"),
    created_at = c("2026-01-01"),
    reply_count = 1L,
    repost_count = 2L,
    like_count = 3L,
    quote_count = 4L,
    bookmark_count = 5L,
    view_count = 6L,
    conversation_id = c("1"),
    is_reply = FALSE,
    is_repost = FALSE,
    is_quote = FALSE,
    reply_to_post_id = NA_character_,
    quoted_post_id = NA_character_,
    hashtags = list(c("rstats")),
    mentions = list(NULL),
    urls = list(NULL),
    media_type = list(NULL),
    media_urls = list(NULL),
    collected_at = c("2026-01-01T00:00:00Z"),
    collection_query = c("test"),
    collection_id = c("uuid-1234")
  )
  parsed <- list(
    post_id = c("1"),
    collection_id = c("uuid-1234"),
    collection_query = c("test"),
    collected_at = c("2026-01-01T00:00:00Z")
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  testthat::expect_equal(ncol(result), 26L)
  testthat::expect_equal(nrow(result), 1L)
  rels <- attr(result, "rx_collection_posts")
  testthat::expect_equal(nrow(rels), 1L)
})

# --- Test 19: Print method for rx_relational includes collection_posts ---
test_that("print.rx_relational prints posts and collection_posts", {
  posts <- tibble::tibble(
    post_id = c("1", "2"),
    text = c("hello", "world")
  )
  parsed <- list(
    post_id = c("1", "2"),
    collection_id = c("uuid-1", "uuid-1"),
    collection_query = c("test", "test"),
    collected_at = c("2026-01-01T00:00:00Z", "2026-01-01T00:00:01Z")
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  output <- capture.output(print(result))
  testthat::expect_true(any(grepl("# Posts", output, fixed = TRUE)))
  testthat::expect_true(any(grepl("# Collection-Post Relations", output, fixed = TRUE)))
  testthat::expect_true(any(grepl("2 row", output, fixed = TRUE)))
})

# --- Test 20: Print method skips collection_posts when empty ---
test_that("print.rx_relational skips collection_posts section when empty", {
  posts <- tibble::tibble(
    post_id = c("1"),
    text = c("hello")
  )
  parsed <- list(
    post_id = character(0)
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  output <- capture.output(print(result))
  testthat::expect_true(any(grepl("# Posts", output, fixed = TRUE)))
  testthat::expect_false(any(grepl("# Collection-Post Relations", output, fixed = TRUE)))
})

# --- Test 21: Relations track multiple collections for same post ---
test_that("Relations correctly track a post appearing in multiple collections", {
  parsed <- list(
    post_id = c("1", "1"),
    collection_id = c("uuid-1", "uuid-2"),
    collection_query = c("r programming", "R stats"),
    collected_at = c("2026-01-01T00:00:00Z", "2026-01-02T00:00:00Z")
  )
  result <- xtweetsR:::.rx_extract_collection_posts(parsed)
  testthat::expect_length(result$post_id, 2L)
  testthat::expect_equal(result$post_id, c("1", "1"))
  testthat::expect_equal(result$collection_id, c("uuid-1", "uuid-2"))
})

# --- Test 22: Empty collection_query and collected_at still extract ---
test_that(".rx_extract_collection_posts handles empty strings as provenance", {
  parsed <- list(
    post_id = c("1"),
    collection_id = c(""),
    collection_query = c(""),
    collected_at = c("")
  )
  result <- xtweetsR:::.rx_extract_collection_posts(parsed)
  testthat::expect_length(result$post_id, 1L)
  testthat::expect_equal(result$collection_id[1L], "")
})

# --- Test 23: Print method with all three relation tables ---
test_that("print.rx_relational prints users, media, and collection_posts together", {
  posts <- tibble::tibble(
    post_id = c("1"),
    text = c("hello with photo"),
    author_id = c("abc"),
    username = c("alice"),
    display_name = c("Alice"),
    created_at = c("2026-01-01"),
    reply_count = 0L, repost_count = 0L, like_count = 0L,
    quote_count = 0L, bookmark_count = 0L, view_count = 0L,
    conversation_id = c("1"),
    is_reply = FALSE, is_repost = FALSE, is_quote = FALSE,
    reply_to_post_id = NA_character_, quoted_post_id = NA_character_,
    hashtags = list(NULL), mentions = list(NULL), urls = list(NULL),
    media_type = list(c("photo")),
    media_urls = list(c("https://pbs.twimg.com/media/a.jpg")),
    collected_at = c("2026-01-01T00:00:00Z"),
    collection_query = c("test"),
    collection_id = c("uuid-1")
  )
  parsed <- list(
    post_id = c("1"),
    author_id = c("abc"),
    username = c("alice"),
    display_name = c("Alice"),
    media_type = list(c("photo")),
    media_urls = list(c("https://pbs.twimg.com/media/a.jpg")),
    collection_id = c("uuid-1"),
    collection_query = c("test"),
    collected_at = c("2026-01-01T00:00:00Z")
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  output <- capture.output(print(result))
  testthat::expect_true(any(grepl("# Posts", output, fixed = TRUE)))
  testthat::expect_true(any(grepl("# Users", output, fixed = TRUE)))
  testthat::expect_true(any(grepl("# Media", output, fixed = TRUE)))
  testthat::expect_true(any(grepl("# Collection-Post Relations", output, fixed = TRUE)))
})
