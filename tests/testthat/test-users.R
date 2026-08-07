# Tests for the users module (Iteration 85).
#
# These tests validate the user extraction and relational result
# infrastructure that complements the posts tibble with a separate
# users table.

# --- Test 1: .rx_users_fields returns 3 fields in correct order ---
test_that(".rx_users_fields returns 3 fields in canonical order", {
  fields <- xtweetsR:::.rx_users_fields()
  testthat::expect_length(fields, 3L, info = "3 user fields")
  testthat::expect_equal(
    fields,
    c("user_id", "username", "display_name"),
    info = "field order matches canonical definition"
  )
})

# --- Test 2: .rx_extract_users returns empty on NULL input ---
test_that(".rx_extract_users returns empty vectors on NULL input", {
  result <- xtweetsR:::.rx_extract_users(NULL)
  testthat::expect_type(result, "list", info = "returns a list")
  testthat::expect_length(result, 3L, info = "3 fields")
  testthat::expect_equal(length(result$user_id), 0L, info = "empty user_id")
  testthat::expect_equal(length(result$username), 0L, info = "empty username")
  testthat::expect_equal(length(result$display_name), 0L, info = "empty display_name")
})

# --- Test 3: .rx_extract_users returns empty on empty parsed list ---
test_that(".rx_extract_users returns empty vectors on empty parsed list", {
  result <- xtweetsR:::.rx_extract_users(list(post_id = character(0)))
  testthat::expect_length(result$user_id, 0L, info = "empty user_id")
  testthat::expect_length(result$username, 0L, info = "empty username")
  testthat::expect_length(result$display_name, 0L, info = "empty display_name")
})

# --- Test 4: .rx_extract_users deduplicates by author_id ---
test_that(".rx_extract_users deduplicates users by author_id", {
  parsed <- list(
    post_id = c("1", "2", "3"),
    author_id = c("abc", "abc", "xyz"),
    username = c("alice", "alice", "bob"),
    display_name = c("Alice", "Alice", "Bob")
  )
  result <- xtweetsR:::.rx_extract_users(parsed)
  testthat::expect_length(result$user_id, 2L, info = "2 unique users")
  testthat::expect_equal(result$user_id[1L], "abc", info = "first user preserved")
  testthat::expect_equal(result$user_id[2L], "xyz", info = "second user preserved")
  testthat::expect_equal(result$username[1L], "alice", info = "first username from first post")
  testthat::expect_equal(result$display_name[1L], "Alice", info = "first display_name from first post")
})

# --- Test 5: .rx_extract_users skips NA author_id ---
test_that(".rx_extract_users skips NA and empty author_ids", {
  parsed <- list(
    post_id = c("1", "2", "3"),
    author_id = c("abc", NA_character_, "xyz"),
    username = c("alice", "unknown", "bob"),
    display_name = c("Alice", NA_character_, "Bob")
  )
  result <- xtweetsR:::.rx_extract_users(parsed)
  testthat::expect_length(result$user_id, 2L, info = "NA author_id skipped")
  testthat::expect_equal(result$user_id, c("abc", "xyz"), info = "only valid authors kept")
})

# --- Test 6: .rx_extract_users handles empty author_id strings ---
test_that(".rx_extract_users skips empty/whitespace-only author_ids", {
  parsed <- list(
    post_id = c("1", "2"),
    author_id = c("abc", "   "),
    username = c("alice", "nobody"),
    display_name = c("Alice", "Nobody")
  )
  result <- xtweetsR:::.rx_extract_users(parsed)
  testthat::expect_length(result$user_id, 1L, info = "whitespace author_id skipped")
  testthat::expect_equal(result$user_id[1L], "abc", info = "only valid author kept")
})

# --- Test 7: .rx_extract_users preserves first-seen order ---
test_that(".rx_extract_users preserves first-seen order", {
  parsed <- list(
    post_id = c("1", "2", "3", "4"),
    author_id = c("charlie", "alice", "bob", "alice"),
    username = c("charlie", "alice", "bob", "alice"),
    display_name = c("Charlie", "Alice", "Bob", "Alice")
  )
  result <- xtweetsR:::.rx_extract_users(parsed)
  testthat::expect_equal(
    result$user_id,
    c("charlie", "alice", "bob"),
    info = "first-seen order preserved"
  )
})

# --- Test 8: .rx_users_to_tibble returns empty tibble on empty input ---
test_that(".rx_users_to_tibble returns empty tibble on empty input", {
  result <- xtweetsR:::.rx_users_to_tibble(list())
  testthat::expect_s3_class(result, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(result), 0L, info = "zero rows")
  testthat::expect_equal(ncol(result), 3L, info = "3 columns")
  testthat::expect_equal(names(result), .rx_users_fields(), info = "column names match")
})

# --- Test 9: .rx_users_to_tibble converts correctly ---
test_that(".rx_users_to_tibble converts user list to tibble", {
  users <- list(
    user_id = c("abc", "xyz"),
    username = c("alice", "bob"),
    display_name = c("Alice Smith", "Bob Jones")
  )
  result <- xtweetsR:::.rx_users_to_tibble(users)
  testthat::expect_s3_class(result, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(result), 2L, info = "2 rows")
  testthat::expect_equal(result$user_id[1L], "abc", info = "first user_id")
  testthat::expect_equal(result$username[2L], "bob", info = "second username")
  testthat::expect_equal(result$display_name[2L], "Bob Jones", info = "second display_name")
})

# --- Test 10: .rx_users_to_tibble handles NA values ---
test_that(".rx_users_to_tibble handles NA display_name", {
  users <- list(
    user_id = c("abc", "xyz"),
    username = c("alice", "bob"),
    display_name = c("Alice", NA_character_)
  )
  result <- xtweetsR:::.rx_users_to_tibble(users)
  testthat::expect_s3_class(result, "tbl_df", info = "returns a tibble")
  testthat::expect_true(is.na(result$display_name[2L]), info = "NA preserved")
})

# --- Test 11: .rx_users_to_tibble returns empty on malformed input ---
test_that(".rx_users_to_tibble returns empty tibble on malformed input", {
  result <- xtweetsR:::.rx_users_to_tibble(list(foo = "bar"))
  testthat::expect_s3_class(result, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(result), 0L, info = "zero rows for malformed input")
})

# --- Test 12: .rx_relational_result wraps posts and users ---
test_that(".rx_relational_result returns rx_relational with users attribute", {
  posts <- tibble::tibble(
    post_id = c("1", "2"),
    text = c("hello", "world")
  )
  parsed <- list(
    post_id = c("1", "2"),
    author_id = c("abc", "xyz"),
    username = c("alice", "bob"),
    display_name = c("Alice", "Bob")
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  testthat::expect_s3_class(result, "rx_relational", info = "rx_relational class")
  testthat::expect_s3_class(result, "tbl_df", info = "also a tibble")
  users <- attr(result, "rx_users")
  testthat::expect_true(!is.null(users), info = "rx_users attribute exists")
  testthat::expect_s3_class(users, "tbl_df", info = "users is a tibble")
  testthat::expect_equal(nrow(users), 2L, info = "2 unique users")
})

# --- Test 13: .rx_relational_result with empty posts ---
test_that(".rx_relational_result handles empty posts", {
  posts <- tibble::tibble(post_id = character(0))
  parsed <- list(post_id = character(0))
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  testthat::expect_s3_class(result, "rx_relational", info = "rx_relational class")
  users <- attr(result, "rx_users")
  testthat::expect_equal(nrow(users), 0L, info = "zero users for empty input")
})

# --- Test 14: rx_users() accessor extracts users from relational result ---
test_that("rx_users() extracts users from rx_relational object", {
  posts <- tibble::tibble(
    post_id = c("1", "2"),
    text = c("hello", "world")
  )
  parsed <- list(
    post_id = c("1", "2"),
    author_id = c("abc", "xyz"),
    username = c("alice", "bob"),
    display_name = c("Alice", "Bob")
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  users <- xtweetsR::rx_users(result)
  testthat::expect_s3_class(users, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(users), 2L, info = "2 users extracted")
  testthat::expect_equal(users$username[1L], "alice", info = "first username")
})

# --- Test 15: rx_users() returns empty tibble on non-relational input ---
test_that("rx_users() returns empty tibble for non-relational objects", {
  posts <- tibble::tibble(post_id = c("1"), text = c("hello"))
  users <- xtweetsR::rx_users(posts)
  testthat::expect_s3_class(users, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(users), 0L, info = "zero users for non-relational input")
})

# --- Test 16: .rx_extract_users with all NA author_ids ---
test_that(".rx_extract_users returns empty when all author_ids are NA", {
  parsed <- list(
    post_id = c("1", "2"),
    author_id = c(NA_character_, NA_character_),
    username = c("unknown", "also_unknown"),
    display_name = c(NA_character_, NA_character_)
  )
  result <- xtweetsR:::.rx_extract_users(parsed)
  testthat::expect_length(result$user_id, 0L, info = "no valid users extracted")
})

# --- Test 17: Full pipeline — extract users from parsed search fixture ---
test_that("Full pipeline: extract users from a realistic parsed response", {
  fixture_path <- system.file("tests/fixtures/x-search-response.json", package = "xtweetsR")
  if (nzchar(fixture_path)) {
    data <- jsonlite::fromJSON(fixture_path, simplifyVector = FALSE)
    parsed <- xtweetsR:::.rx_parse_posts(data)
    users <- xtweetsR:::.rx_extract_users(parsed)
    user_tbl <- xtweetsR:::.rx_users_to_tibble(users)
    testthat::expect_s3_class(user_tbl, "tbl_df", info = "users is a tibble")
    testthat::expect_true(nrow(user_tbl) >= 1L, info = "at least 1 unique user from fixture")
    testthat::expect_true(all(names(user_tbl) %in% .rx_users_fields()), info = "correct columns")
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
    author_id = c("abc"),
    username = c("alice"),
    display_name = c("Alice")
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  testthat::expect_equal(ncol(result), 26L, info = "all 26 post columns preserved")
  testthat::expect_equal(nrow(result), 1L, info = "1 row preserved")
})

# --- Test 19: Print method for rx_relational ---
test_that("print.rx_relational prints posts and users", {
  posts <- tibble::tibble(
    post_id = c("1", "2"),
    text = c("hello", "world")
  )
  parsed <- list(
    post_id = c("1", "2"),
    author_id = c("abc", "xyz"),
    username = c("alice", "bob"),
    display_name = c("Alice", "Bob")
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  output <- capture.output(print(result))
  testthat::expect_true(any(grepl("# Posts", output, fixed = TRUE)), info = "prints posts header")
  testthat::expect_true(any(grepl("# Users", output, fixed = TRUE)), info = "prints users header")
  testthat::expect_true(any(grepl("2 row", output, fixed = TRUE)), info = "shows post count")
  testthat::expect_true(any(grepl("2 unique", output, fixed = TRUE)), info = "shows user count")
})

# --- Test 20: Print method with zero users ---
test_that("print.rx_relational skips users section when zero users", {
  posts <- tibble::tibble(
    post_id = c("1"),
    text = c("hello")
  )
  parsed <- list(
    post_id = c("1"),
    author_id = c(NA_character_),
    username = c(NA_character_),
    display_name = c(NA_character_)
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  output <- capture.output(print(result))
  testthat::expect_true(any(grepl("# Posts", output, fixed = TRUE)), info = "prints posts header")
  testthat::expect_false(any(grepl("# Users", output, fixed = TRUE)), info = "skips users section when empty")
})
