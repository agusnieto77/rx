# Tests for the canonical post normalizer (Task 36).
#
# These tests validate the normalizer that converts parsed raw posts
# (list-of-vectors from .rx_parse_posts) into a stable canonical schema
# with consistent types, column order, and NA representation.

# --- Test 1: Canonical fields returns 26 fields in correct order ---
test_that(".rx_canonical_fields returns 26 fields in the expected order", {
  fields <- xtweetsR:::.rx_canonical_fields()

  testthat::expect_length(fields, 26L, info = "26 canonical fields")
  testthat::expect_equal(
    fields,
    c(
      "post_id", "text",
      "author_id", "username", "display_name",
      "created_at",
      "reply_count", "repost_count", "like_count", "quote_count",
      "bookmark_count", "view_count",
      "conversation_id",
      "is_reply", "is_repost", "is_quote",
      "reply_to_post_id", "quoted_post_id",
      # Entity fields (Task 56)
      "hashtags", "mentions", "urls",
      # Media fields (Task 57)
      "media_type", "media_urls",
      # Observation-level provenance (Task 46)
      "collected_at", "collection_query", "collection_id"
    ),
    info = "field order matches canonical definition"
  )
})

# --- Test 2: Type map matches canonical fields ---
test_that(".rx_type_map has entries for all canonical fields", {
  fields <- xtweetsR:::.rx_canonical_fields()
  type_map <- xtweetsR:::.rx_type_map()

  testthat::expect_setequal(names(type_map), fields, info = "type map covers all fields")
  testthat::expect_true(
    all(type_map %in% c("character", "integer", "logical", "list")),
    info = "type map only contains valid types"
  )
  testthat::expect_equal(type_map["post_id"], "character", info = "post_id is character")
  testthat::expect_equal(type_map["reply_count"], "integer", info = "reply_count is integer")
  testthat::expect_equal(type_map["is_reply"], "logical", info = "is_reply is logical")
  testthat::expect_equal(type_map["hashtags"], "list", info = "hashtags is list")
  testthat::expect_equal(type_map["mentions"], "list", info = "mentions is list")
  testthat::expect_equal(type_map["urls"], "list", info = "urls is list")
})

# --- Test 3: NA defaults has entries for all canonical fields ---
test_that(".rx_na_defaults has entries for all canonical fields", {
  fields <- xtweetsR:::.rx_canonical_fields()
  na_defs <- xtweetsR:::.rx_na_defaults()

  testthat::expect_setequal(names(na_defs), fields, info = "NA defaults covers all fields")

  # Check that character fields default to NA.
  char_fields <- names(xtweetsR:::.rx_type_map())[
    xtweetsR:::.rx_type_map() == "character"
  ]
  for (field in char_fields) {
    testthat::expect_true(
      is.na(na_defs[[field]]),
      info = paste(field, "NA default is NA")
    )
  }

  # Check that integer fields default to 0L.
  int_fields <- names(xtweetsR:::.rx_type_map())[
    xtweetsR:::.rx_type_map() == "integer"
  ]
  for (field in int_fields) {
    testthat::expect_equal(
      na_defs[[field]],
      0L,
      info = paste(field, "NA default is 0L")
    )
  }

  # Check that logical fields default to FALSE.
  log_fields <- names(xtweetsR:::.rx_type_map())[
    xtweetsR:::.rx_type_map() == "logical"
  ]
  for (field in log_fields) {
    testthat::expect_false(
      na_defs[[field]],
      info = paste(field, "NA default is FALSE")
    )
  }

  # Check that list fields default to list(NULL).
  list_fields <- names(xtweetsR:::.rx_type_map())[
    xtweetsR:::.rx_type_map() == "list"
  ]
  for (field in list_fields) {
    testthat::expect_equal(
      na_defs[[field]],
      list(NULL),
      info = paste(field, "NA default is list(NULL)")
    )
  }
})

# --- Test 4: Normalizer handles NULL input ---
test_that(".rx_normalize_posts(NULL) returns an empty normalized list", {
  result <- xtweetsR:::.rx_normalize_posts(NULL)

  fields <- xtweetsR:::.rx_canonical_fields()
  testthat::expect_true(is.list(result), info = "result is a list")
  testthat::expect_setequal(names(result), fields, info = "has all canonical fields")

  for (field in fields) {
    testthat::expect_equal(
      length(result[[field]]),
      0L,
      info = paste(field, "is zero-length for NULL input")
    )
  }
})

# --- Test 5: Normalizer handles empty list input ---
test_that(".rx_normalize_posts(list()) returns an empty normalized list", {
  result <- xtweetsR:::.rx_normalize_posts(list())

  fields <- xtweetsR:::.rx_canonical_fields()
  testthat::expect_true(is.list(result), info = "result is a list")
  testthat::expect_setequal(names(result), fields, info = "has all canonical fields")

  for (field in fields) {
    testthat::expect_equal(
      length(result[[field]]),
      0L,
      info = paste(field, "is zero-length for empty list input")
    )
  }
})

# --- Test 6: Normalizer handles input with fewer fields than canonical ---
test_that(".rx_normalize_posts pads shorter vectors to post_id length", {
  coerced_parsed <- list(
    post_id = c("100", "200"),
    text = c("Hello"),
    author_id = c("a1", "a2"),
    username = c("user1", "user2"),
    display_name = c("User One", "User Two"),
    created_at = c("Mon Jan 01 00:00:00 +0000 2025", "Tue Jan 02 00:00:00 +0000 2025"),
    reply_count = 42L,
    repost_count = c(10L, 20L),
    like_count = c(100L, 200L),
    quote_count = c(5L, 10L),
    bookmark_count = c(3L, 7L),
    view_count = c(1000L, 2000L),
    conversation_id = c("100", "200"),
    is_reply = c(TRUE, FALSE),
    is_repost = c(FALSE, FALSE),
    is_quote = c(FALSE, FALSE),
    reply_to_post_id = c(NA_character_, NA_character_),
    quoted_post_id = c(NA_character_, NA_character_)
  )

  normalized <- xtweetsR:::.rx_normalize_posts(coerced_parsed)

  testthat::expect_equal(length(normalized$post_id), 2L, info = "two posts")
  testthat::expect_equal(length(normalized$text), 2L, info = "text padded to 2")
  testthat::expect_true(
    all(is.integer(normalized$reply_count)),
    info = "reply_count coerced to integer"
  )
  testthat::expect_equal(normalized$reply_count, 42L, info = "reply_count value preserved after coercion")
  testthat::expect_true(
    all(is.logical(normalized$is_reply)),
    info = "is_reply coerced to logical"
  )
  testthat::expect_true(
    normalized$is_reply,
    info = "is_reply TRUE preserved after coercion"
  )
})

# --- Test 7: Normalizer preserves exact values from fixture ---
test_that("normalizer preserves exact values from x-search-response.json", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)

  testthat::expect_equal(
    normalized$post_id,
    c("1900000000000000001", "1900000000000000002", "1900000000000000003", "1900000000000000004"),
    info = "post_id values preserved from fixture"
  )
  testthat::expect_equal(
    normalized$text,
    c(
      "New release of the tidyverse ecosystem is out. Check it out!",
      "Using R to analyze climate data — here is a quick walkthrough of the pipeline.",
      "Quasiquotation in R is powerful once you understand it. Thread below on when to use !! vs {{",
      "Great thread on quasiquotation! Here is my take on the design trade-offs."
    ),
    info = "text values preserved from fixture"
  )
  testthat::expect_equal(
    normalized$reply_count,
    c(12L, 5L, 20L, 8L),
    info = "reply_count values preserved from fixture"
  )
})

# --- Test 8: Normalizer output has all canonical fields ---
test_that("normalizer output has all 26 canonical fields", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)

  fields <- xtweetsR:::.rx_canonical_fields()
  testthat::expect_setequal(names(normalized), fields, info = "all 26 fields present")
  testthat::expect_length(names(normalized), 26L, info = "exactly 26 fields")
})

# --- Test 9: Normalizer output field order matches canonical order ---
test_that("normalizer output is in canonical field order", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)

  testthat::expect_equal(
    names(normalized),
    .rx_canonical_fields(),
    info = "output fields are in canonical order"
  )
})

# --- Test 10: Type coercion works correctly ---
test_that("normalizer coerces types correctly", {
  coerced_parsed <- list(
    post_id = c(100, 200),
    text = c("Hello", "World"),
    author_id = c("a1", "a2"),
    username = c("user1", "user2"),
    display_name = c("User One", "User Two"),
    created_at = c("Mon Jan 01 00:00:00 +0000 2025", "Tue Jan 02 00:00:00 +0000 2025"),
    reply_count = c("42", "84"),
    repost_count = c(10L, 20L),
    like_count = c(100L, 200L),
    quote_count = c(5L, 10L),
    bookmark_count = c(3L, 7L),
    view_count = c(1000L, 2000L),
    conversation_id = c("100", "200"),
    is_reply = c("TRUE", "FALSE"),
    is_repost = c(FALSE, FALSE),
    is_quote = c(FALSE, FALSE),
    reply_to_post_id = c(NA_character_, NA_character_),
    quoted_post_id = c(NA_character_, NA_character_)
  )

  normalized <- xtweetsR:::.rx_normalize_posts(coerced_parsed)

  testthat::expect_true(
    all(is.character(normalized$post_id)),
    info = "post_id coerced to character"
  )
  testthat::expect_equal(normalized$post_id, c("100", "200"), info = "post_id value preserved after coercion")
  testthat::expect_true(
    all(is.integer(normalized$reply_count)),
    info = "reply_count coerced to integer"
  )
  testthat::expect_equal(normalized$reply_count, c(42L, 84L), info = "reply_count value preserved after coercion")
  testthat::expect_true(
    all(is.logical(normalized$is_reply)),
    info = "is_reply coerced to logical"
  )
  testthat::expect_true(
    normalized$is_reply,
    info = "is_reply TRUE preserved after coercion"
  )
})

# --- Test 11: Normalizer handles input with NA values in character fields ---
test_that("NA character values are preserved as NA_character_", {
  na_parsed <- list(
    post_id = c("100"),
    text = c("Hello"),
    author_id = c(NA_character_),
    username = c(NA_character_),
    display_name = c(NA_character_),
    created_at = c(NA_character_)
  )

  normalized <- xtweetsR:::.rx_normalize_posts(na_parsed)

  testthat::expect_true(
    all(is.na(normalized$author_id)),
    info = "NA author_id preserved"
  )
  testthat::expect_true(
    all(is.na(normalized$username)),
    info = "NA username preserved"
  )
  testthat::expect_true(
    all(is.na(normalized$display_name)),
    info = "NA display_name preserved"
  )
})

# --- Test 12: Normalizer coerces numeric post_id to character ---
test_that("numeric post_id values are coerced to character", {
  coerced_parsed <- list(
    post_id = c(100, 200),
    text = c("Hello", "World"),
    author_id = c("a1", "a2"),
    username = c("user1", "user2"),
    display_name = c("User One", "User Two"),
    created_at = c("Mon Jan 01 00:00:00 +0000 2025", "Tue Jan 02 00:00:00 +0000 2025"),
    reply_count = c(42L, 84L),
    repost_count = c(10L, 20L),
    like_count = c(100L, 200L),
    quote_count = c(5L, 10L),
    bookmark_count = c(3L, 7L),
    view_count = c(1000L, 2000L),
    conversation_id = c("100", "200"),
    is_reply = c(TRUE, FALSE),
    is_repost = c(FALSE, FALSE),
    is_quote = c(FALSE, FALSE),
    reply_to_post_id = c(NA_character_, NA_character_),
    quoted_post_id = c(NA_character_, NA_character_)
  )

  normalized <- xtweetsR:::.rx_normalize_posts(coerced_parsed)

  testthat::expect_true(
    all(is.character(normalized$post_id)),
    info = "all post_id values are character after coercion"
  )
  testthat::expect_equal(normalized$post_id, c("100", "200"), info = "values preserved after coercion")
})

# --- Test 13: Normalizer handles input with extra fields (ignores them) ---
test_that("normalizer ignores extra non-canonical fields in input", {
  extra_parsed <- list(
    post_id = c("100"),
    text = c("Hello"),
    author_id = c("a1"),
    username = c("user1"),
    display_name = c("User One"),
    created_at = c("Mon Jan 01 00:00:00 +0000 2025"),
    reply_count = 42L,
    repost_count = 10L,
    like_count = 100L,
    quote_count = 5L,
    bookmark_count = 3L,
    view_count = 1000L,
    conversation_id = c("100"),
    is_reply = TRUE,
    is_repost = FALSE,
    is_quote = FALSE,
    reply_to_post_id = NA_character_,
    quoted_post_id = NA_character_,
    extra_field = "should be ignored"
  )

  normalized <- xtweetsR:::.rx_normalize_posts(extra_parsed)

  testthat::expect_setequal(
    names(normalized),
    .rx_canonical_fields(),
    info = "output only contains canonical fields"
  )
  testthat::expect_equal(normalized$text, "Hello", info = "text value preserved")
})

# --- Test 14: Type map iteration checks types correctly ---
test_that("type map iteration validates all field types", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  type_map <- xtweetsR:::.rx_type_map()

  for (field in setdiff(.rx_canonical_fields(), c("post_id", "text"))) {
    expected_type <- type_map[[field]]
    actual <- normalized[[field]]

    if (expected_type == "character") {
      testthat::expect_true(
        is.character(actual),
        info = paste(field, "is character")
      )
    } else if (expected_type == "integer") {
      testthat::expect_true(
        is.integer(actual),
        info = paste(field, "is integer")
      )
    } else if (expected_type == "logical") {
      testthat::expect_true(
        is.logical(actual),
        info = paste(field, "is logical")
      )
    } else if (expected_type == "list") {
      testthat::expect_true(
        is.list(actual),
        info = paste(field, "is list")
      )
    }
  }
})

# --- Test 15: Normalizer handles input with extra non-canonical fields ---
test_that("normalizer ignores extra non-canonical fields in input", {
  extra_parsed <- list(
    post_id = c("100"),
    text = c("Hello"),
    author_id = c("a1"),
    username = c("user1"),
    display_name = c("User One"),
    created_at = c("Mon Jan 01 00:00:00 +0000 2025"),
    reply_count = 42L,
    repost_count = 10L,
    like_count = 100L,
    quote_count = 5L,
    bookmark_count = 3L,
    view_count = 1000L,
    conversation_id = c("100"),
    is_reply = TRUE,
    is_repost = FALSE,
    is_quote = FALSE,
    reply_to_post_id = NA_character_,
    quoted_post_id = NA_character_,
    extra_field = "should be ignored"
  )

  normalized <- xtweetsR:::.rx_normalize_posts(extra_parsed)

  testthat::expect_setequal(
    names(normalized),
    .rx_canonical_fields(),
    info = "output only contains canonical fields"
  )
})

# --- Test 16: All canonical fields present after normalizing fixture ---
test_that("normalized fixture has all canonical fields with correct types", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  fields <- xtweetsR:::.rx_canonical_fields()

  testthat::expect_setequal(names(normalized), fields, info = "has all canonical fields")

  type_map <- xtweetsR:::.rx_type_map()
  for (field in fields) {
    expected_type <- type_map[[field]]
    actual <- normalized[[field]]

    if (expected_type == "character") {
      testthat::expect_true(
        is.character(actual),
        info = paste(field, "is character")
      )
    } else if (expected_type == "integer") {
      testthat::expect_true(
        is.integer(actual),
        info = paste(field, "is integer")
      )
    } else if (expected_type == "logical") {
      testthat::expect_true(
        is.logical(actual),
        info = paste(field, "is logical")
      )
    } else if (expected_type == "list") {
      testthat::expect_true(
        is.list(actual),
        info = paste(field, "is list")
      )
    }
  }
})

# --- Test 17: Normalizer preserves all fixture values ---
test_that("normalized fixture preserves all expected values", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)

  testthat::expect_equal(normalized$post_id[1L], "1900000000000000001", info = "first post_id correct")
  testthat::expect_equal(normalized$username[2L], "rstats_david", info = "second username correct")
  testthat::expect_equal(normalized$like_count[3L], 150L, info = "third like_count correct")
  testthat::expect_false(normalized$is_repost[1L], info = "is_repost FALSE for first post")
})

# --- Test 18: Empty response returns all twenty-one empty vectors ---
test_that("empty response returns all twenty-one empty vectors", {
  result_null <- xtweetsR:::.rx_parse_posts(NULL)
  testthat::expect_equal(length(result_null$post_id), 0L, info = "NULL returns empty post_id")
  testthat::expect_equal(length(result_null$text), 0L, info = "NULL returns empty text")
  testthat::expect_equal(length(result_null$author_id), 0L, info = "NULL returns empty author_id")
  testthat::expect_equal(length(result_null$username), 0L, info = "NULL returns empty username")
  testthat::expect_equal(length(result_null$display_name), 0L, info = "NULL returns empty display_name")
  testthat::expect_equal(length(result_null$created_at), 0L, info = "NULL returns empty created_at")
  testthat::expect_equal(length(result_null$reply_count), 0L, info = "NULL returns empty reply_count")
  testthat::expect_equal(length(result_null$repost_count), 0L, info = "NULL returns empty repost_count")
  testthat::expect_equal(length(result_null$like_count), 0L, info = "NULL returns empty like_count")
  testthat::expect_equal(length(result_null$quote_count), 0L, info = "NULL returns empty quote_count")
  testthat::expect_equal(length(result_null$bookmark_count), 0L, info = "NULL returns empty bookmark_count")
  testthat::expect_equal(length(result_null$view_count), 0L, info = "NULL returns empty view_count")
  testthat::expect_equal(length(result_null$conversation_id), 0L, info = "NULL returns empty conversation_id")
  testthat::expect_equal(length(result_null$is_reply), 0L, info = "NULL returns empty is_reply")
  testthat::expect_equal(length(result_null$is_repost), 0L, info = "NULL returns empty is_repost")
  testthat::expect_equal(length(result_null$is_quote), 0L, info = "NULL returns empty is_quote")
  testthat::expect_equal(length(result_null$reply_to_post_id), 0L, info = "NULL returns empty reply_to_post_id")
  testthat::expect_equal(length(result_null$quoted_post_id), 0L, info = "NULL returns empty quoted_post_id")
  testthat::expect_equal(length(result_null$hashtags), 0L, info = "NULL returns empty hashtags")
  testthat::expect_equal(length(result_null$mentions), 0L, info = "NULL returns empty mentions")
  testthat::expect_equal(length(result_null$urls), 0L, info = "NULL returns empty urls")
  testthat::expect_equal(length(result_null$cursors), 0L, info = "NULL returns empty cursors")
})

# --- Test 19: .rx_normalized_to_tibble returns a tibble (Task 37) ---
test_that(".rx_normalized_to_tibble returns a tibble that inherits from tbl_df", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tbl <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  testthat::expect_s3_class(tbl, "tbl_df", info = "result inherits from tbl_df")
  testthat::expect_s3_class(tbl, "tbl", info = "result inherits from tbl")
  testthat::expect_s3_class(tbl, "data.frame", info = "result inherits from data.frame")
})

# --- Test 20: Tibble has 21 columns and 4 rows from fixture ---
test_that("tibble has 21 columns and 4 rows from fixture", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tbl <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  testthat::expect_equal(ncol(tbl), 26L, info = "26 canonical columns")
  testthat::expect_equal(nrow(tbl), 4L, info = "4 posts from fixture")
})

# --- Test 21: post_id is character in the tibble (Task 37) ---
test_that("post_id is character in the tibble", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tbl <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  testthat::expect_true(
    is.character(tbl$post_id),
    info = "post_id is character in tibble"
  )
})

# --- Test 22: Empty normalized list returns zero-row tibble (Task 37) ---
test_that("empty normalized returns zero-row tibble", {
  empty_norm <- xtweetsR:::.rx_normalize_posts(NULL)
  tbl <- xtweetsR:::.rx_normalized_to_tibble(empty_norm)

  testthat::expect_s3_class(tbl, "tbl_df", info = "still a tibble")
  testthat::expect_equal(nrow(tbl), 0L, info = "zero rows")
})

# --- Test 23: NULL input returns empty tibble (Task 37) ---
test_that(".rx_normalized_to_tibble(NULL) returns empty tibble", {
  tbl <- xtweetsR:::.rx_normalized_to_tibble(NULL)
  testthat::expect_s3_class(tbl, "tbl_df", info = "still a tibble")
  testthat::expect_equal(nrow(tbl), 0L, info = "zero rows")
})

# --- Test 24: Tibble column names match canonical fields (Task 37) ---
test_that("tibble column names match canonical schema", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tbl <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  expected <- xtweetsR:::.rx_canonical_fields()
  testthat::expect_equal(names(tbl), expected, info = "column names match canonical fields")
})

# --- Test 25: .rx_deduplicate_posts removes duplicate post_id from tibble (Task 38) ---
test_that("deduplicate removes duplicate post_id from tibble, keeping first-seen", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tbl <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  # Manually add a duplicate row (copy of the first post).
  dup_tbl <- rbind(tbl, tbl[1L, , drop = FALSE])

  testthat::expect_equal(nrow(dup_tbl), 5L, info = "5 rows before dedup (4 + 1 dup)")

  deduped <- xtweetsR:::.rx_deduplicate_posts(dup_tbl)

  testthat::expect_equal(nrow(deduped), 4L, info = "4 rows after dedup")
  testthat::expect_equal(
    deduped$post_id,
    c("1900000000000000001", "1900000000000000002", "1900000000000000003", "1900000000000000004"),
    info = "first-seen order preserved"
  )
  testthat::expect_true(inherits(deduped, "tbl_df"), info = "still a tibble")
})

# --- Test 26: .rx_deduplicate_posts removes duplicate post_id from normalized list (Task 38) ---
test_that("deduplicate removes duplicate post_id from normalized list", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)

  # Create a normalized list with a duplicate post (extend post_id and other fields).
  dup_normalized <- lapply(normalized, function(vec) c(vec, vec[1L]))

  deduped <- xtweetsR:::.rx_deduplicate_posts(dup_normalized)

  testthat::expect_true(inherits(deduped, "tbl_df"), info = "returns a tibble")
  testthat::expect_equal(nrow(deduped), 4L, info = "4 rows after dedup")
})

# --- Test 27: Different posts with same text are NOT deduplicated (Task 38) ---
test_that("different post_ids with identical text are kept", {
  same_text <- list(
    post_id = c("100", "200"),
    text = c("Same text", "Same text"),
    author_id = c("a1", "a2"),
    username = c("user1", "user2"),
    display_name = c("User One", "User Two"),
    created_at = c("Mon Jan 01 00:00:00 +0000 2025", "Tue Jan 02 00:00:00 +0000 2025"),
    reply_count = c(1L, 2L),
    repost_count = c(3L, 4L),
    like_count = c(5L, 6L),
    quote_count = c(0L, 1L),
    bookmark_count = c(2L, 3L),
    view_count = c(100L, 200L),
    conversation_id = c("100", "200"),
    is_reply = c(FALSE, FALSE),
    is_repost = c(FALSE, FALSE),
    is_quote = c(FALSE, FALSE),
    reply_to_post_id = c(NA_character_, NA_character_),
    quoted_post_id = c(NA_character_, NA_character_)
  )

  normalized <- xtweetsR:::.rx_normalize_posts(same_text)
  deduped <- xtweetsR:::.rx_deduplicate_posts(normalized)

  testthat::expect_equal(nrow(deduped), 2L, info = "both posts kept despite same text")
  testthat::expect_equal(
    deduped$post_id,
    c("100", "200"),
    info = "different post_ids are not collapsed"
  )
})

# --- Test 28: Empty input returns unchanged (Task 38) ---
test_that("zero-row tibble returns unchanged through deduplication", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  empty_norm <- xtweetsR:::.rx_normalize_posts(NULL)
  empty_tbl <- xtweetsR:::.rx_normalized_to_tibble(empty_norm)
  deduped <- xtweetsR:::.rx_deduplicate_posts(empty_tbl)

  testthat::expect_equal(nrow(deduped), 0L, info = "zero rows stays zero")
  testthat::expect_true(inherits(deduped, "tbl_df"), info = "still a tibble")
})

# --- Test 29: Deduplication preserves all column types (Task 38) ---
test_that("deduplication preserves column types", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tbl <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  # Add a duplicate to ensure we exercise the dedup path.
  dup_tbl <- rbind(tbl, tbl[1L, , drop = FALSE])
  deduped <- xtweetsR:::.rx_deduplicate_posts(dup_tbl)

  type_map <- xtweetsR:::.rx_type_map()

  for (field in names(type_map)) {
    expected_type <- type_map[[field]]
    actual <- deduped[[field]]

    if (expected_type == "character") {
      testthat::expect_true(
        is.character(actual),
        info = paste(field, "is character after dedup")
      )
    } else if (expected_type == "integer") {
      testthat::expect_true(
        is.integer(actual),
        info = paste(field, "is integer after dedup")
      )
    } else if (expected_type == "logical") {
      testthat::expect_true(
        is.logical(actual),
        info = paste(field, "is logical after dedup")
      )
    } else if (expected_type == "list") {
      testthat::expect_true(
        is.list(actual),
        info = paste(field, "is list after dedup")
      )
    }
  }
})

# --- Test 30: Canonical fields returns 26 fields (Tasks 56-57) ---
test_that(".rx_canonical_fields returns 26 fields including entity, media, and provenance fields", {
  fields <- xtweetsR:::.rx_canonical_fields()

  testthat::expect_length(fields, 26L, info = "26 canonical fields")
  testthat::expect_equal(
    fields[19:21],
    c("hashtags", "mentions", "urls"),
    info = "entity fields are at positions 19-21"
  )
  testthat::expect_equal(
    fields[22:23],
    c("media_type", "media_urls"),
    info = "media fields are at positions 22-23"
  )
  testthat::expect_equal(
    fields[24:26],
    c("collected_at", "collection_query", "collection_id"),
    info = "observation provenance fields are at the end"
  )
})

# --- Test 31: Type map covers observation provenance fields (Task 46) ---
test_that("observation provenance fields are character in type map", {
  type_map <- xtweetsR:::.rx_type_map()

  testthat::expect_equal(type_map["collected_at"], "character", info = "collected_at is character")
  testthat::expect_equal(type_map["collection_query"], "character", info = "collection_query is character")
  testthat::expect_equal(type_map["collection_id"], "character", info = "collection_id is character")
})

# --- Test 32: NA defaults cover observation provenance fields (Task 46) ---
test_that("observation provenance fields default to NA_character_", {
  na_defs <- xtweetsR:::.rx_na_defaults()

  testthat::expect_true(
    is.na(na_defs[["collected_at"]]),
    info = "collected_at default is NA"
  )
  testthat::expect_true(
    is.na(na_defs[["collection_query"]]),
    info = "collection_query default is NA"
  )
  testthat::expect_true(
    is.na(na_defs[["collection_id"]]),
    info = "collection_id default is NA"
  )
})

# --- Test 33: Tibble has 26 columns (Tasks 56-57) ---
test_that("tibble has 26 columns from fixture", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tbl <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  testthat::expect_equal(ncol(tbl), 26L, info = "26 canonical columns")
  testthat::expect_equal(nrow(tbl), 4L, info = "4 posts from fixture")
  testthat::expect_equal(
    names(tbl)[19:21],
    c("hashtags", "mentions", "urls"),
    info = "entity columns are at positions 19-21"
  )
  testthat::expect_equal(
    names(tbl)[22:23],
    c("media_type", "media_urls"),
    info = "media columns are at positions 22-23"
  )
  testthat::expect_equal(
    names(tbl)[24:26],
    c("collected_at", "collection_query", "collection_id"),
    info = "provenance columns are last"
  )
})

# --- Test 34: List columns (hashtags, mentions, urls) survive normalization and tibble conversion ---
test_that("list columns survive normalization and appear as list-columns in tibble", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tbl <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  # List columns should be lists (not character/integer/logical).
  testthat::expect_true(is.list(normalized$hashtags), info = "hashtags is a list after normalization")
  testthat::expect_true(is.list(normalized$mentions), info = "mentions is a list after normalization")
  testthat::expect_true(is.list(normalized$urls), info = "urls is a list after normalization")

  # Tibble columns should be list-columns.
  testthat::expect_true(is.list(tbl$hashtags), info = "hashtags column is a list-column")
  testthat::expect_true(is.list(tbl$mentions), info = "mentions column is a list-column")
  testthat::expect_true(is.list(tbl$urls), info = "urls column is a list-column")

  # Check specific values: tweet 1 has 2 hashtags.
  testthat::expect_equal(as.character(tbl$hashtags[[1L]]), c("RStats", "tidyverse"), info = "hashtags value correct")
  testthat::expect_equal(as.character(tbl$urls[[1L]]), "https://posit.co/blog/new-release", info = "urls value correct")
  testthat::expect_equal(tbl$mentions[[2L]][["screen_name"]], "rstudio", info = "mentions value correct")
})

# --- Test 35: Missing list fields get NA defaults and survive normalization ---
test_that("normalized list with no entity fields gets NA defaults for list columns", {
  partial <- list(
    post_id = c("100"),
    text = c("Hello world"),
    author_id = c("a1"), username = c("user1"), display_name = c("User One"),
    created_at = c("Mon Jan 01 00:00:00 +0000 2025"),
    reply_count = 1L, repost_count = 2L, like_count = 3L, quote_count = 0L,
    bookmark_count = 1L, view_count = 100L,
    conversation_id = c("100"),
    is_reply = c(FALSE), is_repost = c(FALSE), is_quote = c(FALSE),
    reply_to_post_id = c(NA_character_), quoted_post_id = c(NA_character_)
  )

  normalized <- xtweetsR:::.rx_normalize_posts(partial)

  # List columns should be filled with list(NULL) (NA default).
  testthat::expect_equal(normalized$hashtags, list(NULL), info = "hashtags defaults to list(NULL)")
  testthat::expect_equal(normalized$mentions, list(NULL), info = "mentions defaults to list(NULL)")
  testthat::expect_equal(normalized$urls, list(NULL), info = "urls defaults to list(NULL)")

  # Should still convert to tibble successfully.
  tbl <- xtweetsR:::.rx_normalized_to_tibble(normalized)
  testthat::expect_equal(nrow(tbl), 1L, info = "one row")
  testthat::expect_true(is.list(tbl$hashtags), info = "hashtags is list-column in tibble")
})
