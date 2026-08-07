# Tests for the canonical post normalizer (Task 36).
#
# These tests validate the normalizer that converts parsed raw posts
# (list-of-vectors from .rx_parse_posts) into a stable canonical schema
# with consistent types, column order, and NA representation.

# --- Test 1: Canonical fields returns 18 fields in correct order ---
test_that(".rx_canonical_fields returns 18 fields in the expected order", {
  fields <- xtweetsR:::.rx_canonical_fields()

  testthat::expect_length(fields, 18L, info = "18 canonical fields")
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
      "reply_to_post_id", "quoted_post_id"
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
    all(type_map %in% c("character", "integer", "logical")),
    info = "all types are one of character/integer/logical"
  )

  # Verify type assignments for a sample of fields.
  testthat::expect_equal(type_map["post_id"], "character", info = "post_id is character")
  testthat::expect_equal(type_map["reply_count"], "integer", info = "reply_count is integer")
  testthat::expect_equal(type_map["is_reply"], "logical", info = "is_reply is logical")
})

# --- Test 3: NA defaults cover all fields ---
test_that(".rx_na_defaults has entries for all canonical fields", {
  fields <- xtweetsR:::.rx_canonical_fields()
  na_defs <- xtweetsR:::.rx_na_defaults()

  testthat::expect_setequal(names(na_defs), fields, info = "NA defaults cover all fields")

  # Character fields should have NA_character_.
  char_fields <- names(type_map <- xtweetsR:::.rx_type_map())[
    xtweetsR:::.rx_type_map() == "character"
  ]
  for (f in char_fields) {
    testthat::expect_true(
      is.na(na_defs[[f]]),
      info = paste(f, "default is NA")
    )
  }

  # Integer fields should have 0L.
  int_fields <- names(xtweetsR:::.rx_type_map())[
    xtweetsR:::.rx_type_map() == "integer"
  ]
  for (f in int_fields) {
    testthat::expect_equal(
      na_defs[[f]], 0L,
      info = paste(f, "default is 0L")
    )
  }

  # Logical fields should have FALSE.
  log_fields <- names(xtweetsR:::.rx_type_map())[
    xtweetsR:::.rx_type_map() == "logical"
  ]
  for (f in log_fields) {
    testthat::expect_false(
      na_defs[[f]],
      info = paste(f, "default is FALSE")
    )
  }
})

# --- Test 4: Normalizer returns empty normalized list for NULL input ---
test_that("NULL input returns empty normalized list", {
  fields <- xtweetsR:::.rx_canonical_fields()
  result <- xtweetsR:::.rx_normalize_posts(NULL)

  testthat::expect_true(is.list(result), info = "result is a list")
  testthat::expect_setequal(names(result), fields, info = "has all canonical fields")

  for (field in fields) {
    type <- xtweetsR:::.rx_type_map()[[field]]
    testthat::expect_equal(
      length(result[[field]]), 0L,
      info = paste(field, "is zero-length on NULL input")
    )
    testthat::expect_true(
      is(typeof(result[[field]]), type),
      info = paste(field, "has correct type:", type)
    )
  }
})

# --- Test 5: Normalizer returns empty normalized list for empty input ---
test_that("empty list input returns empty normalized list", {
  fields <- xtweetsR:::.rx_canonical_fields()
  result <- xtweetsR:::.rx_normalize_posts(list())

  testthat::expect_true(is.list(result), info = "result is a list")
  testthat::expect_setequal(names(result), fields, info = "has all canonical fields")

  for (field in fields) {
    testthat::expect_equal(
      length(result[[field]]), 0L,
      info = paste(field, "is zero-length on empty input")
    )
  }
})

# --- Test 6: Normalizer returns empty normalized list for non-list input ---
test_that("non-list input returns empty normalized list", {
  fields <- xtweetsR:::.rx_canonical_fields()
  result <- xtweetsR:::.rx_normalize_posts("not a list")
  testthat::expect_equal(
    length(result$post_id), 0L,
    info = "non-list input returns empty post_id"
  )
  testthat::expect_equal(
    length(result$text), 0L,
    info = "non-list input returns empty text"
  )

  result2 <- xtweetsR:::.rx_normalize_posts(123)
  testthat::expect_equal(
    length(result2$post_id), 0L,
    info = "numeric input returns empty post_id"
  )
})

# --- Test 7: Normalizer returns empty list when post_id is missing ---
test_that("missing post_id field returns empty normalized list", {
  parsed_no_id <- list(
    text = character(0),
    reply_count = integer(0)
  )
  fields <- xtweetsR:::.rx_canonical_fields()
  result <- xtweetsR:::.rx_normalize_posts(parsed_no_id)

  testthat::expect_equal(
    length(result$post_id), 0L,
    info = "post_id is zero-length when missing from input"
  )
})

# --- Test 8: Normalizer validates all canonical fields present ---
test_that("normalizer output has all 18 canonical fields", {
  # Load fixture and parse.
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)
  raw <- xtweetsR:::.rx_parse_posts(parsed)
  normalized <- xtweetsR:::.rx_normalize_posts(raw)

  fields <- xtweetsR:::.rx_canonical_fields()
  testthat::expect_setequal(names(normalized), fields, info = "all 18 fields present")
  testthat::expect_length(names(normalized), 18L, info = "exactly 18 fields")
})

# --- Test 9: Normalizer output column lengths are all equal ---
test_that("all output columns have the same length", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)
  raw <- xtweetsR:::.rx_parse_posts(parsed)
  normalized <- xtweetsR:::.rx_normalize_posts(raw)

  lengths <- sapply(normalized, length)
  testthat::expect_true(
    all(lengths == lengths[1L]),
    info = "all columns have the same length"
  )
  testthat::expect_equal(
    lengths[1L], 4L,
    info = "length matches fixture (4 tweets)"
  )
})

# --- Test 10: Normalizer coerces types correctly ---
test_that("normalizer coerces fields to expected types", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)
  raw <- xtweetsR:::.rx_parse_posts(parsed)
  normalized <- xtweetsR:::.rx_normalize_posts(raw)

  type_map <- xtweetsR:::.rx_type_map()

  for (field in names(type_map)) {
    expected_type <- type_map[[field]]
    actual <- normalized[[field]]

    if (expected_type == "character") {
      testthat::expect_true(
        all(is.character(actual)),
        info = paste(field, "is character")
      )
    } else if (expected_type == "integer") {
      testthat::expect_true(
        all(is.integer(actual)),
        info = paste(field, "is integer")
      )
    } else if (expected_type == "logical") {
      testthat::expect_true(
        all(is.logical(actual)),
        info = paste(field, "is logical")
      )
    }
  }
})

# --- Test 11: Normalizer preserves field order ---
test_that("normalizer output is in canonical field order", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)
  raw <- xtweetsR:::.rx_parse_posts(parsed)
  normalized <- xtweetsR:::.rx_normalize_posts(raw)

  testthat::expect_equal(
    names(normalized),
    .rx_canonical_fields(),
    info = "output fields are in canonical order"
  )
})

# --- Test 12: Normalizer pads missing fields with NA defaults ---
test_that("missing fields in parsed input are filled with NA defaults", {
  # Minimal parsed input with only post_id and text.
  minimal_parsed <- list(
    post_id = c("100", "200"),
    text = c("Hello", "World")
  )

  normalized <- xtweetsR:::.rx_normalize_posts(minimal_parsed)

  # post_id and text should be preserved.
  testthat::expect_equal(normalized$post_id, c("100", "200"), info = "post_id preserved")
  testthat::expect_equal(normalized$text, c("Hello", "World"), info = "text preserved")

  # All other fields should be padded to length 2 with NA defaults.
  type_map <- xtweetsR:::.rx_type_map()
  for (field in setdiff(.rx_canonical_fields(), c("post_id", "text"))) {
    testthat::expect_equal(
      length(normalized[[field]]), 2L,
      info = paste(field, "padded to length 2")
    )
    if (type_map[[field]] == "character") {
      testthat::expect_true(
        all(is.na(normalized[[field]])),
        info = paste(field, "filled with NA_character_")
      )
    } else if (type_map[[field]] == "integer") {
      testthat::expect_equal(
        normalized[[field]], c(0L, 0L),
        info = paste(field, "filled with 0L")
      )
    } else if (type_map[[field]] == "logical") {
      testthat::expect_false(
        any(normalized[[field]]),
        info = paste(field, "filled with FALSE")
      )
    }
  }
})

# --- Test 13: Normalizer truncates oversized vectors to post_id length ---
test_that("oversized vectors are truncated to post_id length", {
  oversized_parsed <- list(
    post_id = c("100", "200"),
    text = c("Hello", "World", "Extra", "More"),
    reply_count = c(1L, 2L, 3L)
  )

  normalized <- xtweetsR:::.rx_normalize_posts(oversized_parsed)

  testthat::expect_equal(length(normalized$post_id), 2L, info = "post_id is length 2")
  testthat::expect_equal(length(normalized$text), 2L, info = "text truncated to 2")
  testthat::expect_equal(length(normalized$reply_count), 2L, info = "reply_count truncated to 2")
  testthat::expect_equal(normalized$text, c("Hello", "World"), info = "text truncated correctly")
  testthat::expect_equal(normalized$reply_count, c(1L, 2L), info = "reply_count truncated correctly")
})

# --- Test 14: Normalizer output values match fixture ---
test_that("normalizer output values match fixture for key fields", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)
  raw <- xtweetsR:::.rx_parse_posts(parsed)
  normalized <- xtweetsR:::.rx_normalize_posts(raw)

  # post_id should be preserved exactly.
  expected_ids <- c(
    "1900000000000000001",
    "1900000000000000002",
    "1900000000000000003",
    "1900000000000000004"
  )
  testthat::expect_equal(normalized$post_id, expected_ids, info = "post_id preserved")

  # reply_count should be integer.
  testthat::expect_equal(normalized$reply_count, c(12L, 5L, 20L, 8L), info = "reply_count preserved as integer")

  # is_reply should be logical.
  testthat::expect_equal(normalized$is_reply, c(FALSE, TRUE, FALSE, FALSE), info = "is_reply preserved as logical")

  # username should be character.
  testthat::expect_equal(normalized$username, c("rstudio", "rstats_david", "landc", "hadleywickham"), info = "username preserved")
})

# --- Test 15: Normalizer handles input with extra non-canonical fields ---
test_that("extra fields in parsed input are silently ignored", {
  parsed_with_extra <- list(
    post_id = c("100"),
    text = c("Hello"),
    extra_field = "should be ignored",
    another = 123L
  )

  normalized <- xtweetsR:::.rx_normalize_posts(parsed_with_extra)

  testthat::expect_setequal(
    names(normalized),
    .rx_canonical_fields(),
    info = "output only contains canonical fields"
  )
  testthat::expect_false("extra_field" %in% names(normalized), info = "extra_field removed")
})

# --- Test 16: Normalizer handles single-row input ---
test_that("single-row input is normalized correctly", {
  single_parsed <- list(
    post_id = c("999"),
    text = c("Single post"),
    author_id = c("111"),
    username = c("testuser"),
    display_name = c("Test User"),
    created_at = c("Wed Jan 01 00:00:00 +0000 2025"),
    reply_count = c(1L),
    repost_count = c(2L),
    like_count = c(3L),
    quote_count = c(0L),
    bookmark_count = c(5L),
    view_count = c(100L),
    conversation_id = c("999"),
    is_reply = c(FALSE),
    is_repost = c(FALSE),
    is_quote = c(FALSE),
    reply_to_post_id = c(NA_character_),
    quoted_post_id = c(NA_character_)
  )

  normalized <- xtweetsR:::.rx_normalize_posts(single_parsed)

  testthat::expect_equal(length(normalized$post_id), 1L, info = "single row preserved")
  testthat::expect_equal(normalized$post_id, "999", info = "post_id preserved")
  testthat::expect_equal(normalized$reply_count, 1L, info = "integer preserved")
  testthat::expect_equal(normalized$is_reply, FALSE, info = "logical preserved")
})

# --- Test 17: Normalizer coerces character integers to integer type ---
test_that("character integers are coerced to integer type", {
  # Simulate parser returning integer fields as character (edge case).
  coerced_parsed <- list(
    post_id = c("100"),
    text = c("Hello"),
    reply_count = c("42"),  # character, not integer
    repost_count = c("10"),
    is_reply = c("TRUE")    # character, not logical
  )

  normalized <- xtweetsR:::.rx_normalize_posts(coerced_parsed)

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

# --- Test 18: Normalizer handles input with NA values in character fields ---
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

# --- Test 20: Tibble has correct number of rows and columns (Task 37) ---
test_that("tibble has 18 columns and 4 rows from fixture", {
  fixture_path <- file.path(
    testthat::test_path("..", ".."),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  normalized <- xtweetsR:::.rx_normalize_posts(parsed)
  tbl <- xtweetsR:::.rx_normalized_to_tibble(normalized)

  testthat::expect_equal(ncol(tbl), 18L, info = "18 canonical columns")
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
    }
  }
})
