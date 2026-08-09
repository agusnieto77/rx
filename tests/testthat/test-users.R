# Tests for the users module (Iteration 85).
#
# These tests validate the user extraction and relational result
# infrastructure that complements the posts tibble with a separate
# users table.

# --- Test 1: .rx_users_fields returns 3 fields in correct order ---
test_that(".rx_users_fields returns 3 fields in canonical order", {
  fields <- xtweetsR:::.rx_users_fields()
  testthat::expect_length(fields, 3L)
  testthat::expect_equal(
    fields,
    c("user_id", "username", "display_name")
    )
})

# --- Test 2: .rx_extract_users returns empty on NULL input ---
test_that(".rx_extract_users returns empty vectors on NULL input", {
  result <- xtweetsR:::.rx_extract_users(NULL)
  testthat::expect_type(result, "list")
  testthat::expect_length(result, 3L)
  testthat::expect_equal(length(result$user_id), 0L)
  testthat::expect_equal(length(result$username), 0L)
  testthat::expect_equal(length(result$display_name), 0L)
})

# --- Test 3: .rx_extract_users returns empty on empty parsed list ---
test_that(".rx_extract_users returns empty vectors on empty parsed list", {
  result <- xtweetsR:::.rx_extract_users(list(post_id = character(0)))
  testthat::expect_length(result$user_id, 0L)
  testthat::expect_length(result$username, 0L)
  testthat::expect_length(result$display_name, 0L)
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
  testthat::expect_length(result$user_id, 2L)
  testthat::expect_equal(result$user_id[1L], "abc")
  testthat::expect_equal(result$user_id[2L], "xyz")
  testthat::expect_equal(result$username[1L], "alice")
  testthat::expect_equal(result$display_name[1L], "Alice")
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
  testthat::expect_length(result$user_id, 2L)
  testthat::expect_equal(result$user_id, c("abc", "xyz"))
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
  testthat::expect_length(result$user_id, 1L)
  testthat::expect_equal(result$user_id[1L], "abc")
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
    c("charlie", "alice", "bob")
    )
})

# --- Test 8: .rx_users_to_tibble returns empty tibble on empty input ---
test_that(".rx_users_to_tibble returns empty tibble on empty input", {
  result <- xtweetsR:::.rx_users_to_tibble(list())
  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_equal(nrow(result), 0L)
  testthat::expect_equal(ncol(result), 3L)
  testthat::expect_equal(names(result), .rx_users_fields())
})

# --- Test 9: .rx_users_to_tibble converts correctly ---
test_that(".rx_users_to_tibble converts user list to tibble", {
  users <- list(
    user_id = c("abc", "xyz"),
    username = c("alice", "bob"),
    display_name = c("Alice Smith", "Bob Jones")
  )
  result <- xtweetsR:::.rx_users_to_tibble(users)
  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_equal(result$user_id[1L], "abc")
  testthat::expect_equal(result$username[2L], "bob")
  testthat::expect_equal(result$display_name[2L], "Bob Jones")
})

# --- Test 10: .rx_users_to_tibble handles NA values ---
test_that(".rx_users_to_tibble handles NA display_name", {
  users <- list(
    user_id = c("abc", "xyz"),
    username = c("alice", "bob"),
    display_name = c("Alice", NA_character_)
  )
  result <- xtweetsR:::.rx_users_to_tibble(users)
  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_true(is.na(result$display_name[2L]))
})

# --- Test 11: .rx_users_to_tibble returns empty on malformed input ---
test_that(".rx_users_to_tibble returns empty tibble on malformed input", {
  result <- xtweetsR:::.rx_users_to_tibble(list(foo = "bar"))
  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_equal(nrow(result), 0L)
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
  testthat::expect_s3_class(result, "rx_relational")
  testthat::expect_s3_class(result, "tbl_df")
  users <- attr(result, "rx_users")
  testthat::expect_true(!is.null(users))
  testthat::expect_s3_class(users, "tbl_df")
  testthat::expect_equal(nrow(users), 2L)
})

# --- Test 13: .rx_relational_result with empty posts ---
test_that(".rx_relational_result handles empty posts", {
  posts <- tibble::tibble(post_id = character(0))
  parsed <- list(post_id = character(0))
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  testthat::expect_s3_class(result, "rx_relational")
  users <- attr(result, "rx_users")
  testthat::expect_equal(nrow(users), 0L)
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
  testthat::expect_s3_class(users, "tbl_df")
  testthat::expect_equal(nrow(users), 2L)
  testthat::expect_equal(users$username[1L], "alice")
})

# --- Test 15: rx_users() returns empty tibble on non-relational input ---
test_that("rx_users() returns empty tibble for non-relational objects", {
  posts <- tibble::tibble(post_id = c("1"), text = c("hello"))
  users <- xtweetsR::rx_users(posts)
  testthat::expect_s3_class(users, "tbl_df")
  testthat::expect_equal(nrow(users), 0L)
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
  testthat::expect_length(result$user_id, 0L)
})

# --- Test 17: Full pipeline — extract users from parsed search fixture ---
test_that("Full pipeline: extract users from a realistic parsed response", {
  fixture_path <- rx_fixture_path("x-search-response.json")
  if (nzchar(fixture_path)) {
    data <- jsonlite::fromJSON(fixture_path, simplifyVector = FALSE)
    parsed <- xtweetsR:::.rx_parse_posts(data)
    users <- xtweetsR:::.rx_extract_users(parsed)
    user_tbl <- xtweetsR:::.rx_users_to_tibble(users)
    testthat::expect_s3_class(user_tbl, "tbl_df")
    testthat::expect_true(nrow(user_tbl) >= 1L)
    testthat::expect_true(all(names(user_tbl) %in% .rx_users_fields()))
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
  testthat::expect_equal(ncol(result), 26L)
  testthat::expect_equal(nrow(result), 1L)
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
  testthat::expect_true(any(grepl("# Posts", output, fixed = TRUE)))
  testthat::expect_true(any(grepl("# Users", output, fixed = TRUE)))
  testthat::expect_true(any(grepl("2 row", output, fixed = TRUE)))
  testthat::expect_true(any(grepl("2 unique", output, fixed = TRUE)))
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
  testthat::expect_true(any(grepl("# Posts", output, fixed = TRUE)))
  testthat::expect_false(any(grepl("# Users", output, fixed = TRUE)))
})
