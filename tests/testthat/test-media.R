# Tests for the media module (Iteration 86).
#
# These tests validate the media extraction and relational result
# infrastructure that complements the posts tibble with a separate
# media table.

# --- Test 1: .rx_media_fields returns 4 fields in correct order ---
test_that(".rx_media_fields returns 4 fields in canonical order", {
  fields <- xtweetsR:::.rx_media_fields()
  testthat::expect_length(fields, 4L, info = "4 media fields")
  testthat::expect_equal(
    fields,
    c("media_id", "media_type", "media_url", "post_id"),
    info = "field order matches canonical definition"
  )
})

# --- Test 2: .rx_extract_media returns empty on NULL input ---
test_that(".rx_extract_media returns empty vectors on NULL input", {
  result <- xtweetsR:::.rx_extract_media(NULL)
  testthat::expect_type(result, "list", info = "returns a list")
  testthat::expect_length(result, 4L, info = "4 fields")
  testthat::expect_equal(length(result$media_id), 0L, info = "empty media_id")
  testthat::expect_equal(length(result$media_type), 0L, info = "empty media_type")
  testthat::expect_equal(length(result$media_url), 0L, info = "empty media_url")
  testthat::expect_equal(length(result$post_id), 0L, info = "empty post_id")
})

# --- Test 3: .rx_extract_media returns empty on empty parsed list ---
test_that(".rx_extract_media returns empty vectors on empty parsed list", {
  result <- xtweetsR:::.rx_extract_media(list(post_id = character(0)))
  testthat::expect_length(result$media_id, 0L, info = "empty media_id")
  testthat::expect_length(result$media_type, 0L, info = "empty media_type")
  testthat::expect_length(result$media_url, 0L, info = "empty media_url")
  testthat::expect_length(result$post_id, 0L, info = "empty post_id")
})

# --- Test 4: .rx_extract_media skips posts with no media ---
test_that(".rx_extract_media skips posts without media", {
  parsed <- list(
    post_id = c("1", "2"),
    text = c("no media", "also no media"),
    media_type = list(character(0), character(0)),
    media_urls = list(character(0), character(0))
  )
  result <- xtweetsR:::.rx_extract_media(parsed)
  testthat::expect_length(result$media_id, 0L, info = "no media items extracted")
})

# --- Test 5: .rx_extract_media extracts single media item ---
test_that(".rx_extract_media extracts a single media item", {
  parsed <- list(
    post_id = c("1"),
    text = c("one photo"),
    media_type = list(c("photo")),
    media_urls = list(c("https://pbs.twimg.com/media/abc.jpg"))
  )
  result <- xtweetsR:::.rx_extract_media(parsed)
  testthat::expect_length(result$media_id, 1L, info = "1 media item extracted")
  testthat::expect_equal(result$media_type[1L], "photo", info = "media_type preserved")
  testthat::expect_equal(result$media_url[1L], "https://pbs.twimg.com/media/abc.jpg", info = "media_url preserved")
  testthat::expect_equal(result$post_id[1L], "1", info = "post_id preserved")
})

# --- Test 6: .rx_extract_media expands multiple media items ---
test_that(".rx_extract_media expands multiple media items per post", {
  parsed <- list(
    post_id = c("1"),
    text = c("two photos"),
    media_type = list(c("photo", "photo")),
    media_urls = list(c("https://pbs.twimg.com/media/a.jpg", "https://pbs.twimg.com/media/b.jpg"))
  )
  result <- xtweetsR:::.rx_extract_media(parsed)
  testthat::expect_length(result$media_id, 2L, info = "2 media items extracted from 1 post")
  testthat::expect_equal(result$post_id, c("1", "1"), info = "same post_id for both")
  testthat::expect_equal(result$media_type, c("photo", "photo"), info = "both types preserved")
})

# --- Test 7: .rx_extract_media handles mixed media types ---
test_that(".rx_extract_media handles mixed media types (photo + video)", {
  parsed <- list(
    post_id = c("1"),
    text = c("mixed media"),
    media_type = list(c("photo", "video")),
    media_urls = list(c("https://pbs.twimg.com/media/a.jpg", "https://video.example.com/stream.mp4"))
  )
  result <- xtweetsR:::.rx_extract_media(parsed)
  testthat::expect_length(result$media_id, 2L, info = "2 items from mixed types")
  testthat::expect_equal(result$media_type, c("photo", "video"), info = "mixed types preserved")
})

# --- Test 8: .rx_extract_media mixes posts with and without media ---
test_that(".rx_extract_media mixes posts with and without media", {
  parsed <- list(
    post_id = c("1", "2", "3"),
    text = c("photo", "no media", "video"),
    media_type = list(c("photo"), character(0), c("video")),
    media_urls = list(c("https://pbs.twimg.com/media/a.jpg"), character(0), c("https://video.example.com/v.mp4"))
  )
  result <- xtweetsR:::.rx_extract_media(parsed)
  testthat::expect_length(result$media_id, 2L, info = "2 media items from 3 posts")
  testthat::expect_equal(result$post_id, c("1", "3"), info = "only posts with media")
})

# --- Test 9: .rx_extract_media handles NA media_type ---
test_that(".rx_extract_media handles NA media_type", {
  parsed <- list(
    post_id = c("1"),
    text = c("na type"),
    media_type = list(c(NA_character_)),
    media_urls = list(c("https://pbs.twimg.com/media/na.jpg"))
  )
  result <- xtweetsR:::.rx_extract_media(parsed)
  testthat::expect_length(result$media_id, 1L, info = "still extracted despite NA type")
  testthat::expect_true(is.na(result$media_type[1L]), info = "NA type preserved")
})

# --- Test 10: .rx_extract_media handles missing media_urls ---
test_that(".rx_extract_media handles missing media_urls with existing types", {
  parsed <- list(
    post_id = c("1"),
    text = c("no url"),
    media_type = list(c("photo")),
    media_urls = list(NULL)
  )
  result <- xtweetsR:::.rx_extract_media(parsed)
  testthat::expect_length(result$media_id, 1L, info = "extracted despite no URL")
  testthat::expect_true(is.na(result$media_url[1L]), info = "NA url for missing media_urls")
})

# --- Test 11: .rx_media_to_tibble returns empty tibble on empty input ---
test_that(".rx_media_to_tibble returns empty tibble on empty input", {
  result <- xtweetsR:::.rx_media_to_tibble(list())
  testthat::expect_s3_class(result, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(result), 0L, info = "zero rows")
  testthat::expect_equal(ncol(result), 4L, info = "4 columns")
  testthat::expect_equal(names(result), .rx_media_fields(), info = "column names match")
})

# --- Test 12: .rx_media_to_tibble converts correctly ---
test_that(".rx_media_to_tibble converts media list to tibble", {
  media <- list(
    media_id = c("1", "1"),
    media_type = c("photo", "video"),
    media_url = c("https://pbs.twimg.com/media/a.jpg", "https://video.example.com/v.mp4"),
    post_id = c("1", "1")
  )
  result <- xtweetsR:::.rx_media_to_tibble(media)
  testthat::expect_s3_class(result, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(result), 2L, info = "2 rows")
  testthat::expect_equal(result$media_type[1L], "photo", info = "first media_type")
  testthat::expect_equal(result$post_id[2L], "1", info = "second post_id")
})

# --- Test 13: .rx_media_to_tibble handles NA values ---
test_that(".rx_media_to_tibble handles NA media_type", {
  media <- list(
    media_id = c("1"),
    media_type = c(NA_character_),
    media_url = c("https://pbs.twimg.com/media/na.jpg"),
    post_id = c("1")
  )
  result <- xtweetsR:::.rx_media_to_tibble(media)
  testthat::expect_s3_class(result, "tbl_df", info = "returns a tibble")
  testthat::expect_true(is.na(result$media_type[1L]), info = "NA preserved")
})

# --- Test 14: .rx_media_to_tibble returns empty on malformed input ---
test_that(".rx_media_to_tibble returns empty tibble on malformed input", {
  result <- xtweetsR:::.rx_media_to_tibble(list(foo = "bar"))
  testthat::expect_s3_class(result, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(result), 0L, info = "zero rows for malformed input")
})

# --- Test 15: .rx_media_to_tibble returns empty on NULL input ---
test_that(".rx_media_to_tibble returns empty tibble on NULL input", {
  result <- xtweetsR:::.rx_media_to_tibble(NULL)
  testthat::expect_s3_class(result, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(result), 0L, info = "zero rows on NULL input")
})

# --- Test 16: Full pipeline — extract media from parsed search fixture ---
test_that("Full pipeline: extract media from a realistic parsed response", {
  fixture_path <- system.file("tests/fixtures/x-search-response.json", package = "xtweetsR")
  if (nzchar(fixture_path)) {
    data <- jsonlite::fromJSON(fixture_path, simplifyVector = FALSE)
    parsed <- xtweetsR:::.rx_parse_posts(data)
    media <- xtweetsR:::.rx_extract_media(parsed)
    media_tbl <- xtweetsR:::.rx_media_to_tibble(media)
    testthat::expect_s3_class(media_tbl, "tbl_df", info = "media is a tibble")
    testthat::expect_true(nrow(media_tbl) >= 1L, info = "at least 1 media item from fixture")
    testthat::expect_true(all(names(media_tbl) %in% .rx_media_fields()), info = "correct columns")
  } else {
    testthat::skip("fixture not available")
  }
})

# --- Test 17: .rx_relational_result wraps posts and media ---
test_that(".rx_relational_result returns rx_relational with media attribute", {
  posts <- tibble::tibble(
    post_id = c("1", "2"),
    text = c("hello", "world")
  )
  parsed <- list(
    post_id = c("1", "2"),
    media_type = list(c("photo", "photo"), character(0)),
    media_urls = list(c("https://pbs.twimg.com/media/a.jpg"), character(0))
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  testthat::expect_s3_class(result, "rx_relational", info = "rx_relational class")
  testthat::expect_s3_class(result, "tbl_df", info = "also a tibble")
  media <- attr(result, "rx_media")
  testthat::expect_true(!is.null(media), info = "rx_media attribute exists")
  testthat::expect_s3_class(media, "tbl_df", info = "media is a tibble")
  testthat::expect_equal(nrow(media), 1L, info = "1 media item (post 2 has none)")
})

# --- Test 18: .rx_relational_result with empty media ---
test_that(".rx_relational_result handles no media", {
  posts <- tibble::tibble(post_id = c("1"), text = c("no media"))
  parsed <- list(
    post_id = c("1"),
    media_type = list(character(0)),
    media_urls = list(character(0))
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  testthat::expect_s3_class(result, "rx_relational", info = "rx_relational class")
  media <- attr(result, "rx_media")
  testthat::expect_equal(nrow(media), 0L, info = "zero media for no-media input")
})

# --- Test 19: rx_media() accessor extracts media from relational result ---
test_that("rx_media() extracts media from rx_relational object", {
  posts <- tibble::tibble(
    post_id = c("1", "2"),
    text = c("hello", "world")
  )
  parsed <- list(
    post_id = c("1", "2"),
    media_type = list(c("photo", "video"), character(0)),
    media_urls = list(c("https://pbs.twimg.com/media/a.jpg"), character(0))
  )
  result <- xtweetsR:::.rx_relational_result(posts, parsed)
  media <- xtweetsR::rx_media(result)
  testthat::expect_s3_class(media, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(media), 1L, info = "1 media item extracted")
  testthat::expect_equal(media$media_type[1L], "photo", info = "media_type preserved")
})

# --- Test 20: rx_media() returns empty tibble on non-relational input ---
test_that("rx_media() returns empty tibble for non-relational objects", {
  posts <- tibble::tibble(post_id = c("1"), text = c("hello"))
  media <- xtweetsR::rx_media(posts)
  testthat::expect_s3_class(media, "tbl_df", info = "returns a tibble")
  testthat::expect_equal(nrow(media), 0L, info = "zero media for non-relational input")
})
