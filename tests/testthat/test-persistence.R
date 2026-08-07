# Tests for JSONL persistence helpers (Task 47).
#
# These tests validate the append-only JSONL read/write pipeline that
# supports incremental persistence of post collections without requiring
# Arrow or DuckDB.

# --- Test 1: .rx_jsonl_empty_tibble returns empty tibble with canonical schema ---
test_that(".rx_jsonl_empty_tibble returns a tibble with 21 canonical columns", {
  tbl <- xtweetsR:::.rx_jsonl_empty_tibble()

  testthat::expect_s3_class(tbl, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(ncol(tbl), 21L, info = "21 canonical columns")
  testthat::expect_equal(nrow(tbl), 0L, info = "zero rows")
  testthat::expect_equal(
    colnames(tbl),
    xtweetsR:::.rx_canonical_fields(),
    info = "column names match canonical schema"
  )
})

# --- Test 2: .rx_jsonl_write and read round-trip with a small tibble ---
test_that("write and read back a small tibble preserves data", {
  skip_if_not(requireNamespace("tibble", quietly = TRUE))

  fields <- xtweetsR:::.rx_canonical_fields()
  n <- 3L
  df <- data.frame(
    post_id       = paste0("post-", 1:n),
    text          = paste0("text number ", 1:n),
    author_id     = paste0("auth-", 1:n),
    username      = paste0("user", 1:n),
    display_name  = paste0("User ", 1:n),
    created_at    = paste0("2025-01-0", 1:n, "T00:00:00Z"),
    reply_count   = (1:n) * 2L,
    repost_count  = (1:n) * 3L,
    like_count    = (1:n) * 5L,
    quote_count   = (1:n) * 1L,
    bookmark_count = (1:n) * 4L,
    view_count    = (1:n) * 10L,
    conversation_id = paste0("conv-", 1:n),
    is_reply      = FALSE,
    is_repost     = FALSE,
    is_quote      = FALSE,
    reply_to_post_id = NA_character_,
    quoted_post_id   = NA_character_,
    collected_at     = format(Sys.time(), iso8601 = TRUE),
    collection_query = "r programming",
    collection_id    = "test-uuid-001",
    stringsAsFactors = FALSE
  )
  tbl <- tibble::as_tibble(df)

  tmp <- tempfile(fileext = ".jsonl")
  on.exit(file.remove(tmp), ignore = TRUE)

  # Write with append = FALSE (overwrite).
  xtweetsR:::.rx_jsonl_write(tmp, tbl, append = FALSE)

  # Read back.
  loaded <- xtweetsR:::.rx_jsonl_read(tmp)

  testthat::expect_equal(nrow(loaded), n, info = "row count matches")
  testthat::expect_equal(ncol(loaded), 21L, info = "column count matches")
  testthat::expect_equal(
    loaded$post_id,
    paste0("post-", 1:n),
    info = "post_id values preserved"
  )
  testthat::expect_equal(
    loaded$text,
    paste0("text number ", 1:n),
    info = "text values preserved"
  )
})

# --- Test 3: Two batches can be appended ---
test_that("two batches can be appended and read back together", {
  skip_if_not(requireNamespace("tibble", quietly = TRUE))

  make_batch <- function(start, count) {
    n <- count
    df <- data.frame(
      post_id       = paste0("post-", start:(start + n - 1)),
      text          = paste0("batch post ", start),
      author_id     = paste0("auth-", start),
      username      = paste0("user", start),
      display_name  = paste0("User ", start),
      created_at    = "2025-01-01T00:00:00Z",
      reply_count   = 1L,
      repost_count  = 2L,
      like_count    = 3L,
      quote_count   = 0L,
      bookmark_count = 0L,
      view_count    = 100L,
      conversation_id = paste0("conv-", start),
      is_reply      = FALSE,
      is_repost     = FALSE,
      is_quote      = FALSE,
      reply_to_post_id = NA_character_,
      quoted_post_id   = NA_character_,
      collected_at     = format(Sys.time(), iso8601 = TRUE),
      collection_query = "r programming",
      collection_id    = "test-uuid-001",
      stringsAsFactors = FALSE
    )
    tibble::as_tibble(df)
  }

  tmp <- tempfile(fileext = ".jsonl")
  on.exit(file.remove(tmp), ignore = TRUE)

  batch1 <- make_batch(1, 2)
  batch2 <- make_batch(10, 3)

  # Write batch 1 (overwrite).
  xtweetsR:::.rx_jsonl_write(tmp, batch1, append = FALSE)
  # Append batch 2.
  xtweetsR:::.rx_jsonl_write(tmp, batch2, append = TRUE)

  loaded <- xtweetsR:::.rx_jsonl_read(tmp)

  testthat::expect_equal(nrow(loaded), 5L, info = "5 total rows (2 + 3)")
  testthat::expect_true(
    all(c("post-1", "post-2") %in% loaded$post_id),
    info = "batch 1 posts are present"
  )
  testthat::expect_true(
    all(c("post-10", "post-11", "post-12") %in% loaded$post_id),
    info = "batch 2 posts are present"
  )
})

# --- Test 4: Duplicate writing is NOT deduplicated by the reader ---
test_that("duplicate writing preserves duplicates (not deduplicated)", {
  skip_if_not(requireNamespace("tibble", quietly = TRUE))

  df <- data.frame(
    post_id       = "post-dup",
    text          = "duplicate",
    author_id     = "auth-dup",
    username      = "userdup",
    display_name  = "User Dup",
    created_at    = "2025-01-01T00:00:00Z",
    reply_count   = 1L,
    repost_count  = 2L,
    like_count    = 3L,
    quote_count   = 0L,
    bookmark_count = 0L,
    view_count    = 100L,
    conversation_id = "conv-dup",
    is_reply      = FALSE,
    is_repost     = FALSE,
    is_quote      = FALSE,
    reply_to_post_id = NA_character_,
    quoted_post_id   = NA_character_,
    collected_at     = format(Sys.time(), iso8601 = TRUE),
    collection_query = "test",
    collection_id    = "test-uuid-001",
    stringsAsFactors = FALSE
  )
  tbl <- tibble::as_tibble(df)

  tmp <- tempfile(fileext = ".jsonl")
  on.exit(file.remove(tmp), ignore = TRUE)

  # Write the same row twice (append).
  xtweetsR:::.rx_jsonl_write(tmp, tbl, append = FALSE)
  xtweetsR:::.rx_jsonl_write(tmp, tbl, append = TRUE)

  loaded <- xtweetsR:::.rx_jsonl_read(tmp)

  testthat::expect_equal(nrow(loaded), 2L, info = "duplicate row written twice")
  testthat::expect_equal(
    loaded$post_id,
    c("post-dup", "post-dup"),
    info = "both copies are present"
  )
})

# --- Test 5: Writing zero-row tibble is a no-op ---
test_that("writing a zero-row tibble does not create content", {
  fields <- xtweetsR:::.rx_canonical_fields()
  type_map <- xtweetsR:::.rx_type_map()
  cols <- lapply(fields, function(f) {
    switch(type_map[[f]],
      character = character(0),
      integer = integer(0),
      logical = logical(0)
    )
  })
  names(cols) <- fields
  empty_tbl <- tibble::as_tibble(cols)

  tmp <- tempfile(fileext = ".jsonl")
  on.exit(file.remove(tmp), ignore = TRUE)

  xtweetsR:::.rx_jsonl_write(tmp, empty_tbl, append = FALSE)

  # File should be empty or not contain valid JSON lines.
  loaded <- xtweetsR:::.rx_jsonl_read(tmp)
  testthat::expect_equal(nrow(loaded), 0L, info = "zero-row output")
})

# --- Test 6: Reading a non-existent file returns empty tibble ---
test_that("reading a non-existent file returns an empty canonical tibble", {
  tmp <- tempfile(fileext = ".jsonl")
  # Do NOT create the file.

  loaded <- xtweetsR:::.rx_jsonl_read(tmp)

  testthat::expect_s3_class(loaded, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(loaded), 0L, info = "zero rows")
  testthat::expect_equal(ncol(loaded), 21L, info = "21 columns")
})

# --- Test 7: Column types are preserved through round-trip ---
test_that("integer and logical column types are preserved", {
  skip_if_not(requireNamespace("tibble", quietly = TRUE))

  df <- data.frame(
    post_id       = "post-int",
    text          = "type test",
    author_id     = "auth-1",
    username      = "user1",
    display_name  = "User One",
    created_at    = "2025-01-01T00:00:00Z",
    reply_count   = 42L,
    repost_count  = 7L,
    like_count    = 99L,
    quote_count   = 0L,
    bookmark_count = 1L,
    view_count    = 1500L,
    conversation_id = "conv-1",
    is_reply      = TRUE,
    is_repost     = FALSE,
    is_quote      = FALSE,
    reply_to_post_id = NA_character_,
    quoted_post_id   = NA_character_,
    collected_at     = format(Sys.time(), iso8601 = TRUE),
    collection_query = "test",
    collection_id    = "test-uuid-001",
    stringsAsFactors = FALSE
  )
  tbl <- tibble::as_tibble(df)

  tmp <- tempfile(fileext = ".jsonl")
  on.exit(file.remove(tmp), ignore = TRUE)

  xtweetsR:::.rx_jsonl_write(tmp, tbl, append = FALSE)
  loaded <- xtweetsR:::.rx_jsonl_read(tmp)

  testthat::expect_equal(
    loaded$reply_count,
    42L,
    info = "integer type preserved for reply_count"
  )
  testthat::expect_equal(
    loaded$like_count,
    99L,
    info = "integer type preserved for like_count"
  )
  testthat::expect_true(
    isTRUE(loaded$is_reply),
    info = "logical type preserved for is_reply"
  )
  testthat::expect_false(
    isFALSE(loaded$is_repost),
    info = "logical type preserved for is_repost"
  )
})

# --- Test 8: .rx_checkpoint_from_state creates a valid checkpoint ---
test_that(".rx_checkpoint_from_state creates a valid checkpoint from scroll state", {
  fields <- xtweetsR:::.rx_canonical_fields()
  type_map <- xtweetsR:::.rx_type_map()
  cols <- lapply(fields, function(f) {
    switch(type_map[[f]],
      character = character(0),
      integer = integer(0),
      logical = logical(0)
    )
  })
  names(cols) <- fields
  empty_tbl <- tibble::as_tibble(cols)

  # Create a scroll state and add posts.
  state <- xtweetsR:::.rx_scroll_state_new()
  state$add_posts(list(post_id = c("post-1", "post-2", "post-3")))

  checkpoint <- xtweetsR:::.rx_checkpoint_from_state(
    state = state,
    collection_id = "test-col-uuid",
    query = "r programming"
  )

  testthat::expect_s3_class(checkpoint, "rx_checkpoint", info = "has rx_checkpoint class")
  testthat::expect_equal(checkpoint$collection_id, "test-col-uuid")
  testthat::expect_equal(checkpoint$query, "r programming")
  testthat::expect_equal(checkpoint$seen_post_ids, c("post-1", "post-2", "post-3"))
  testthat::expect_equal(checkpoint$records_collected, 3L)
  testthat::expect_equal(checkpoint$last_cursor, "")
  testthat::expect_equal(checkpoint$last_post_id, "post-1")
})

# --- Test 9: Checkpoint write and read round-trip ---
test_that("checkpoint write and read round-trip preserves all fields", {
  # Create a scroll state with populated fields.
  state <- xtweetsR:::.rx_scroll_state_new()
  state$add_posts(list(post_id = c("post-a", "post-b")))
  state$advance_scroll(4000)

  checkpoint <- xtweetsR:::.rx_checkpoint_from_state(
    state = state,
    collection_id = "roundtrip-uuid-001",
    query = "test query"
  )

  tmp <- tempfile(fileext = ".json")
  on.exit(file.remove(tmp), ignore = TRUE)

  xtweetsR:::.rx_checkpoint_write(tmp, checkpoint)

  loaded <- xtweetsR:::.rx_checkpoint_read(tmp)

  testthat::expect_s3_class(loaded, "rx_checkpoint", info = "returns rx_checkpoint")
  testthat::expect_equal(loaded$collection_id, "roundtrip-uuid-001")
  testthat::expect_equal(loaded$query, "test query")
  testthat::expect_equal(loaded$seen_post_ids, c("post-a", "post-b"))
  testthat::expect_equal(loaded$records_collected, 2L)
  testthat::expect_equal(loaded$last_post_id, "post-a")
})

# --- Test 10: Checkpoint write with NULL is a no-op ---
test_that("writing NULL checkpoint does not crash", {
  tmp <- tempfile(fileext = ".json")
  on.exit(file.remove(tmp), ignore = TRUE)

  result <- xtweetsR:::.rx_checkpoint_write(tmp, NULL)
  testthat::expect_null(result)
})

# --- Test 11: Reading a non-existent checkpoint returns NULL ---
test_that("reading a non-existent checkpoint file returns NULL", {
  tmp <- tempfile(fileext = ".json")
  # Do NOT create the file.

  result <- xtweetsR:::.rx_checkpoint_read(tmp)
  testthat::expect_null(result, info = "returns NULL for missing file")
})

# --- Test 12: Checkpoint with empty seen_post_ids ---
test_that("checkpoint handles empty seen_post_ids", {
  state <- xtweetsR:::.rx_scroll_state_new()
  # Don't add any posts.

  checkpoint <- xtweetsR:::.rx_checkpoint_from_state(
    state = state,
    collection_id = "empty-seen-uuid",
    query = "empty test"
  )

  testthat::expect_equal(checkpoint$seen_post_ids, character(0))
  testthat::expect_equal(checkpoint$records_collected, 0L)

  tmp <- tempfile(fileext = ".json")
  on.exit(file.remove(tmp), ignore = TRUE)

  xtweetsR:::.rx_checkpoint_write(tmp, checkpoint)
  loaded <- xtweetsR:::.rx_checkpoint_read(tmp)

  testthat::expect_equal(loaded$seen_post_ids, character(0))
  testthat::expect_equal(loaded$records_collected, 0L)
  testthat::expect_equal(loaded$collection_id, "empty-seen-uuid")
})

# --- Test 13: Checkpoint preserves last_cursor ---
test_that("checkpoint preserves last_cursor value", {
  state <- xtweetsR:::.rx_scroll_state_new()
  state$add_posts(list(post_id = c("post-1")))

  checkpoint <- xtweetsR:::.rx_checkpoint_from_state(
    state = state,
    collection_id = "cursor-uuid",
    query = "cursor test"
  )
  # Manually set a cursor.
  checkpoint$last_cursor <- "MTkzNjE2NzE4NDQxMjIzMTQ1NHx8fA=="

  tmp <- tempfile(fileext = ".json")
  on.exit(file.remove(tmp), ignore = TRUE)

  xtweetsR:::.rx_checkpoint_write(tmp, checkpoint)
  loaded <- xtweetsR:::.rx_checkpoint_read(tmp)

  testthat::expect_equal(loaded$last_cursor, "MTkzNjE2NzE4NDQxMjIzMTQ1NHx8fA==")
})
