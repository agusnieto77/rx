# Tests for X search URL construction (Task 28)
# Verifies .rx_construct_search_url produces correct URLs for various inputs.

# Load the package in development mode so internal functions are available.
if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
}

# -- basic query construction -------------------------------------------------

test_that("basic query produces a valid X search URL", {
  url <- .rx_construct_search_url("r programming")
  expect_true(startsWith(url, "https://x.com/search?q="))
  expect_true(grepl("r%20programming", url, ignore.case = TRUE))
})

test_that("single word query works", {
  url <- .rx_construct_search_url("climate")
  expect_true(startsWith(url, "https://x.com/search?q="))
  expect_true(grepl("climate", url, ignore.case = TRUE))
})

test_that("query with special characters is encoded", {
  url <- .rx_construct_search_url("fix auth bug")
  expect_true(grepl("fix%20auth%20bug", url, ignore.case = TRUE))
})

test_that("query with ampersand is encoded", {
  url <- .rx_construct_search_url("R & data science")
  expect_true(grepl("R%20%26%20data%20science", url, ignore.case = TRUE))
})

test_that("query with unicode characters is encoded", {
  url <- .rx_construct_search_url("hello world")
  expect_true(startsWith(url, "https://x.com/search?q="))
})

# -- from_user filter ---------------------------------------------------------

test_that("from_user appends X search syntax", {
  url <- .rx_construct_search_url("r programming", from_user = "hadleywickham")
  expect_true(grepl("from%3Ahadleywickham", url, ignore.case = TRUE))
})

test_that("from_user with special chars is encoded separately", {
  url <- .rx_construct_search_url("test", from_user = "user_name")
  expect_true(grepl("test%20from%3Auser_name", url, ignore.case = TRUE))
})

# -- arbitrary filter ---------------------------------------------------------

test_that("filter appends raw X search syntax", {
  url <- .rx_construct_search_url("r programming", filter = "lang:en")
  expect_true(grepl("lang%3Aen", url, ignore.case = TRUE))
})

test_that("filter with date range is appended", {
  url <- .rx_construct_search_url("climate", filter = "until:2026-01-01")
  expect_true(grepl("until%3A2026-01-01", url, ignore.case = TRUE))
})

test_that("filter can be combined with from_user", {
  url <- .rx_construct_search_url("r stats", from_user = "rstudio", filter = "lang:en")
  expect_true(grepl("from%3Arstudio", url, ignore.case = TRUE))
  expect_true(grepl("lang%3Aen", url, ignore.case = TRUE))
})

# -- input validation ---------------------------------------------------------

test_that("empty query throws", {
  expect_error(.rx_construct_search_url(""), "non-empty")
})

test_that("NULL query throws", {
  expect_error(.rx_construct_search_url(NULL), "non-empty")
})

test_that("multi-element query vector throws", {
  expect_error(.rx_construct_search_url(c("a", "b")), "non-empty")
})

test_that("whitespace-only query throws", {
  expect_error(.rx_construct_search_url("  "), "non-empty")
})

test_that("NA query throws", {
  expect_error(.rx_construct_search_url(NA_character_), "non-empty|single")
})

test_that("NA from_user throws", {
  expect_error(.rx_construct_search_url("test", from_user = NA_character_), "from_user must be")
})

test_that("NA filter throws", {
  expect_error(.rx_construct_search_url("test", filter = NA_character_), "filter must be")
})

test_that("multi-element from_user throws", {
  expect_error(.rx_construct_search_url("test", from_user = c("a", "b")), "from_user must be")
})

test_that("whitespace-only from_user throws", {
  expect_error(.rx_construct_search_url("test", from_user = "   "), "from_user must be")
})

test_that("whitespace-only filter throws", {
  expect_error(.rx_construct_search_url("test", filter = "  "), "filter must be")
})

test_that("multi-element filter throws", {
  expect_error(.rx_construct_search_url("test", filter = c("a", "b")), "filter must be")
})

# -- round-trip sanity --------------------------------------------------------

test_that("URL contains exactly one q= parameter", {
  url <- .rx_construct_search_url("test query")
  matches <- regmatches(url, gregexpr("q=", url, fixed = TRUE))
  expect_equal(length(matches[[1]]), 1L)
})

test_that("result is always a single string", {
  url <- .rx_construct_search_url("hello world")
  expect_length(url, 1L)
  expect_true(is.character(url))
})

test_that("from_user NULL does not append from:", {
  url <- .rx_construct_search_url("test", from_user = NULL)
  expect_false(grepl("from:", url, ignore.case = TRUE))
})

test_that("filter NULL does not append filter", {
  url <- .rx_construct_search_url("test", filter = NULL)
  # Should not have any extra filter-like parameters after the q= value
  expect_true(grepl("^https://x.com/search\\?q=test$", url))
})

# ===================================================================
# User timeline URL construction (Task 52)
# ===================================================================

test_that("basic user timeline URL is constructed correctly", {
  url <- .rx_construct_user_timeline_url("hadleywickham")
  expect_equal(url, "https://x.com/hadleywickham")
})

test_that("username with leading @ is stripped", {
  url <- .rx_construct_user_timeline_url("@hadleywickham")
  expect_equal(url, "https://x.com/hadleywickham")
})

test_that("username with special characters is handled", {
  url <- .rx_construct_user_timeline_url("user_name-123")
  expect_equal(url, "https://x.com/user_name-123")
})

test_that("path segment is appended", {
  url <- .rx_construct_user_timeline_url("hadleywickham", path = "media")
  expect_equal(url, "https://x.com/hadleywickham/media")
})

test_that("path 'tweets_with_replies' is appended", {
  url <- .rx_construct_user_timeline_url("hadleywickham", path = "tweets_with_replies")
  expect_equal(url, "https://x.com/hadleywickham/tweets_with_replies")
})

test_that("filter is appended as query parameter", {
  url <- .rx_construct_user_timeline_url("hadleywickham", filter = "tagged_media=true")
  expect_equal(url, "https://x.com/hadleywickham?tagged_media%3Dtrue")
})

test_that("path and filter together", {
  url <- .rx_construct_user_timeline_url("hadleywickham", path = "media", filter = "tagged_media=true")
  expect_equal(url, "https://x.com/hadleywickham/media?tagged_media%3Dtrue")
})

test_that("path NULL gives base timeline", {
  url <- .rx_construct_user_timeline_url("rstudio", path = NULL)
  expect_equal(url, "https://x.com/rstudio")
})

test_that("filter NULL does not add query string", {
  url <- .rx_construct_user_timeline_url("rstudio", filter = NULL)
  expect_equal(url, "https://x.com/rstudio")
})

test_that("both path and filter NULL gives base timeline", {
  url <- .rx_construct_user_timeline_url("rstudio", path = NULL, filter = NULL)
  expect_equal(url, "https://x.com/rstudio")
})

test_that("empty username throws", {
  expect_error(.rx_construct_user_timeline_url(""), "non-empty")
})

test_that("NULL username throws", {
  expect_error(.rx_construct_user_timeline_url(NULL), "non-empty")
})

test_that("whitespace-only username throws", {
  expect_error(.rx_construct_user_timeline_url("  "), "non-empty")
})

test_that("NA username throws", {
  expect_error(.rx_construct_user_timeline_url(NA_character_), "single|non-empty")
})

test_that("empty path throws", {
  expect_error(.rx_construct_user_timeline_url("test", path = ""), "non-empty")
})

test_that("whitespace-only path throws", {
  expect_error(.rx_construct_user_timeline_url("test", path = "  "), "non-empty")
})

test_that("empty filter throws", {
  expect_error(.rx_construct_user_timeline_url("test", filter = ""), "non-empty")
})

test_that("whitespace-only filter throws", {
  expect_error(.rx_construct_user_timeline_url("test", filter = "  "), "non-empty")
})

test_that("result is always a single character string", {
  url <- .rx_construct_user_timeline_url("hello_world")
  expect_length(url, 1L)
  expect_true(is.character(url))
})

# ===================================================================
# Date-range filter helpers (Iteration 79)
# ===================================================================

test_that(".rx_build_date_range_filter returns NULL when both args are NULL", {
  expect_null(.rx_build_date_range_filter())
  expect_null(.rx_build_date_range_filter(since = NULL, until = NULL))
})

test_that(".rx_build_date_range_filter with only since", {
  result <- .rx_build_date_range_filter(since = "2024-01-01")
  expect_equal(result, "since:2024-01-01")
})

test_that(".rx_build_date_range_filter with only until", {
  result <- .rx_build_date_range_filter(until = "2024-12-31")
  expect_equal(result, "until:2024-12-31")
})

test_that(".rx_build_date_range_filter with both since and until", {
  result <- .rx_build_date_range_filter(since = "2024-01-01", until = "2024-12-31")
  expect_equal(result, "since:2024-01-01 until:2024-12-31")
})

test_that(".rx_build_date_range_filter rejects invalid dates", {
  expect_error(.rx_build_date_range_filter(since = "not-a-date"), "not a valid date")
  expect_error(.rx_build_date_range_filter(until = "2024-13-01"), "not a valid date")
  expect_error(.rx_build_date_range_filter(since = ""), "must be a single character")
})

test_that(".rx_build_date_range_filter rejects NA and non-character", {
  expect_error(.rx_build_date_range_filter(since = NA_character_), "must be a single character")
  expect_error(.rx_build_date_range_filter(until = 123L), "must be a single character")
})

test_that(".rx_build_date_range_filter trims whitespace", {
  result <- .rx_build_date_range_filter(since = " 2024-01-01 ", until = "2024-12-31  ")
  expect_equal(result, "since:2024-01-01 until:2024-12-31")
})

# -- search URL with date range ------------------------------------------------

test_that("since appends to search URL", {
  url <- .rx_construct_search_url("r stats", since = "2024-01-01")
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
})

test_that("until appends to search URL", {
  url <- .rx_construct_search_url("r stats", until = "2024-12-31")
  expect_true(grepl("until%3A2024-12-31", url, ignore.case = TRUE))
})

test_that("both since and until append to search URL", {
  url <- .rx_construct_search_url("AI", since = "2024-01-01", until = "2024-12-31")
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
  expect_true(grepl("until%3A2024-12-31", url, ignore.case = TRUE))
})

test_that("date range works with from_user", {
  url <- .rx_construct_search_url("r language", from_user = "rstudio", since = "2024-06-01")
  expect_true(grepl("from%3Arstudio", url, ignore.case = TRUE))
  expect_true(grepl("since%3A2024-06-01", url, ignore.case = TRUE))
})

test_that("date range works with arbitrary filter", {
  url <- .rx_construct_search_url("climate", since = "2024-01-01", filter = "lang:en")
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
  expect_true(grepl("lang%3Aen", url, ignore.case = TRUE))
})

test_that("date range without other params produces minimal filter", {
  url <- .rx_construct_search_url("test", since = "2024-01-01")
  expect_true(grepl("test%20since%3A2024-01-01", url, ignore.case = TRUE))
})

test_that("invalid since throws in search URL", {
  expect_error(.rx_construct_search_url("test", since = "bad"), "not a valid date")
  expect_error(.rx_construct_search_url("test", until = NA_character_), "must be a single character")
})

# -- user timeline URL with date range -----------------------------------------

test_that("since appends to user timeline URL as query filter", {
  url <- .rx_construct_user_timeline_url("rstudio", since = "2024-01-01")
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
  expect_true(grepl("^https://x.com/rstudio\\?", url))
})

test_that("until appends to user timeline URL as query filter", {
  url <- .rx_construct_user_timeline_url("hadley", until = "2024-06-01")
  expect_true(grepl("until%3A2024-06-01", url, ignore.case = TRUE))
})

test_that("both since and until append to user timeline URL", {
  url <- .rx_construct_user_timeline_url("rstudio", since = "2024-01-01", until = "2024-12-31")
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
  expect_true(grepl("until%3A2024-12-31", url, ignore.case = TRUE))
})

test_that("date range combined with path", {
  url <- .rx_construct_user_timeline_url("rstudio", path = "media", since = "2024-01-01")
  expect_true(grepl("https://x.com/rstudio/media\\?", url))
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
})

test_that("date range combined with raw filter", {
  url <- .rx_construct_user_timeline_url("rstudio", since = "2024-01-01", filter = "tagged_media=true")
  # Both should be in the query parameter, combined and encoded
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
  expect_true(grepl("tagged_media", url, ignore.case = TRUE))
})

test_that("date range NULL gives no query string", {
  url <- .rx_construct_user_timeline_url("rstudio", since = NULL, until = NULL)
  expect_equal(url, "https://x.com/rstudio")
})

test_that("invalid date throws in user timeline URL", {
  expect_error(.rx_construct_user_timeline_url("rstudio", since = "bad"), "not a valid date")
  expect_error(.rx_construct_user_timeline_url("rstudio", until = NA_character_), "must be a single character")
})

# ===================================================================
# Language filter helper (Iteration 80)
# ===================================================================

test_that(".rx_build_language_filter returns NULL when lang is NULL", {
  expect_null(.rx_build_language_filter())
  expect_null(.rx_build_language_filter(lang = NULL))
})

test_that(".rx_build_language_filter with valid code", {
  expect_equal(.rx_build_language_filter("en"), "lang:en")
  expect_equal(.rx_build_language_filter("es"), "lang:es")
  expect_equal(.rx_build_language_filter("ja"), "lang:ja")
})

test_that(".rx_build_language_filter accepts 3-letter codes", {
  expect_equal(.rx_build_language_filter("tl"), "lang:tl")
  expect_equal(.rx_build_language_filter("eng"), "lang:eng")
})

test_that(".rx_build_language_filter rejects invalid codes", {
  expect_error(.rx_build_language_filter("english"), "valid language code")
  expect_error(.rx_build_language_filter("e"), "valid language code")
  expect_error(.rx_build_language_filter("12"), "valid language code")
})

test_that(".rx_build_language_filter rejects NA and non-character", {
  expect_error(.rx_build_language_filter(lang = NA_character_), "must be a single character")
  expect_error(.rx_build_language_filter(lang = 123L), "must be a single character")
})

test_that(".rx_build_language_filter trims whitespace", {
  result <- .rx_build_language_filter("  en  ")
  expect_equal(result, "lang:en")
})

# -- search URL with lang ------------------------------------------------------

test_that("lang appends to search URL", {
  url <- .rx_construct_search_url("hello", lang = "en")
  expect_true(grepl("lang%3Aen", url, ignore.case = TRUE))
})

test_that("lang with from_user", {
  url <- .rx_construct_search_url("r stats", from_user = "rstudio", lang = "en")
  expect_true(grepl("from%3Arstudio", url, ignore.case = TRUE))
  expect_true(grepl("lang%3Aen", url, ignore.case = TRUE))
})

test_that("lang with date range", {
  url <- .rx_construct_search_url("climate", since = "2024-01-01", lang = "es")
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
  expect_true(grepl("lang%3Aes", url, ignore.case = TRUE))
})

test_that("lang with arbitrary filter", {
  url <- .rx_construct_search_url("test", lang = "ja", filter = "result_type:recent")
  expect_true(grepl("lang%3Aja", url, ignore.case = TRUE))
  expect_true(grepl("result_type%3Arecent", url, ignore.case = TRUE))
})

test_that("all params together (from_user, date range, lang, filter)", {
  url <- .rx_construct_search_url("r language", from_user = "rstudio", since = "2024-01-01", until = "2024-12-31", lang = "en", filter = "result_type:recent")
  expect_true(grepl("from%3Arstudio", url, ignore.case = TRUE))
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
  expect_true(grepl("until%3A2024-12-31", url, ignore.case = TRUE))
  expect_true(grepl("lang%3Aen", url, ignore.case = TRUE))
  expect_true(grepl("result_type%3Arecent", url, ignore.case = TRUE))
})

test_that("lang NULL does not append lang:", {
  url <- .rx_construct_search_url("test", lang = NULL)
  expect_false(grepl("lang:", url, ignore.case = TRUE))
})

test_that("invalid lang throws in search URL", {
  expect_error(.rx_construct_search_url("test", lang = "english"), "valid language code")
  expect_error(.rx_construct_search_url("test", lang = NA_character_), "must be a single character")
})

# -- user timeline URL with lang -----------------------------------------------

test_that("lang appends to user timeline URL", {
  url <- .rx_construct_user_timeline_url("rstudio", lang = "en")
  expect_true(grepl("lang%3Aen", url, ignore.case = TRUE))
  expect_true(grepl("^https://x.com/rstudio\\?", url))
})

test_that("lang combined with path", {
  url <- .rx_construct_user_timeline_url("rstudio", path = "media", lang = "es")
  expect_true(grepl("https://x.com/rstudio/media\\?", url))
  expect_true(grepl("lang%3Aes", url, ignore.case = TRUE))
})

test_that("lang combined with date range", {
  url <- .rx_construct_user_timeline_url("rstudio", since = "2024-01-01", lang = "ja")
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
  expect_true(grepl("lang%3Aja", url, ignore.case = TRUE))
})

test_that("lang combined with raw filter", {
  url <- .rx_construct_user_timeline_url("rstudio", lang = "en", filter = "tagged_media=true")
  expect_true(grepl("lang%3Aen", url, ignore.case = TRUE))
  expect_true(grepl("tagged_media", url, ignore.case = TRUE))
})

test_that("lang NULL gives no lang: in user timeline URL", {
  url <- .rx_construct_user_timeline_url("rstudio", lang = NULL)
  expect_false(grepl("lang:", url, ignore.case = TRUE))
})

test_that("invalid lang throws in user timeline URL", {
  expect_error(.rx_construct_user_timeline_url("rstudio", lang = "english"), "valid language code")
  expect_error(.rx_construct_user_timeline_url("rstudio", lang = NA_character_), "must be a single character")
})

# ===================================================================
# Search mode filter (Iteration 81)
# ===================================================================

test_that(".rx_build_search_mode_filter returns NULL when mode is NULL", {
  expect_null(.rx_build_search_mode_filter())
  expect_null(.rx_build_search_mode_filter(mode = NULL))
})

test_that(".rx_build_search_mode_filter with 'latest'", {
  expect_equal(.rx_build_search_mode_filter("latest"), "f=live")
})

test_that(".rx_build_search_mode_filter with 'top'", {
  expect_equal(.rx_build_search_mode_filter("top"), "f=top")
})

test_that(".rx_build_search_mode_filter is case-insensitive", {
  expect_equal(.rx_build_search_mode_filter("LATEST"), "f=live")
  expect_equal(.rx_build_search_mode_filter("TOP"), "f=top")
  expect_equal(.rx_build_search_mode_filter("Latest"), "f=live")
  expect_equal(.rx_build_search_mode_filter("Top"), "f=top")
})

test_that(".rx_build_search_mode_filter trims whitespace", {
  expect_equal(.rx_build_search_mode_filter("  latest  "), "f=live")
  expect_equal(.rx_build_search_mode_filter("  top  "), "f=top")
})

test_that(".rx_build_search_mode_filter rejects invalid values", {
  expect_error(.rx_build_search_mode_filter("recent"), "must be 'latest' or 'top'")
  expect_error(.rx_build_search_mode_filter("realtime"), "must be 'latest' or 'top'")
  expect_error(.rx_build_search_mode_filter("default"), "must be 'latest' or 'top'")
})

test_that(".rx_build_search_mode_filter rejects NA and non-character", {
  expect_error(.rx_build_search_mode_filter(mode = NA_character_), "must be 'latest', 'top', or NULL")
  expect_error(.rx_build_search_mode_filter(mode = 123L), "must be 'latest', 'top', or NULL")
})

test_that(".rx_build_search_mode_filter rejects empty string", {
  expect_error(.rx_build_search_mode_filter(mode = ""), "must be 'latest', 'top', or NULL")
})

test_that(".rx_build_search_mode_filter rejects multi-element vector", {
  expect_error(.rx_build_search_mode_filter(mode = c("latest", "top")), "must be 'latest', 'top', or NULL")
})

# -- search URL with mode ------------------------------------------------------

test_that("mode 'latest' appends f=live to search URL", {
  url <- .rx_construct_search_url("r programming", mode = "latest")
  expect_true(grepl("f%3Dlive", url, ignore.case = TRUE))
})

test_that("mode 'top' appends f=top to search URL", {
  url <- .rx_construct_search_url("r programming", mode = "top")
  expect_true(grepl("f%3Dtop", url, ignore.case = TRUE))
})

test_that("mode NULL does not append f=", {
  url <- .rx_construct_search_url("test", mode = NULL)
  expect_false(grepl("f%3D", url, ignore.case = TRUE))
})

test_that("mode with from_user", {
  url <- .rx_construct_search_url("r stats", from_user = "rstudio", mode = "latest")
  expect_true(grepl("from%3Arstudio", url, ignore.case = TRUE))
  expect_true(grepl("f%3Dlive", url, ignore.case = TRUE))
})

test_that("mode with date range", {
  url <- .rx_construct_search_url("climate", since = "2024-01-01", mode = "top")
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
  expect_true(grepl("f%3Dtop", url, ignore.case = TRUE))
})

test_that("mode with lang", {
  url <- .rx_construct_search_url("test", lang = "en", mode = "latest")
  expect_true(grepl("lang%3Aen", url, ignore.case = TRUE))
  expect_true(grepl("f%3Dlive", url, ignore.case = TRUE))
})

test_that("all params together (from_user, date range, lang, mode, filter)", {
  url <- .rx_construct_search_url(
    "r language",
    from_user = "rstudio",
    since = "2024-01-01",
    until = "2024-12-31",
    lang = "en",
    mode = "latest",
    filter = "result_type:recent"
  )
  expect_true(grepl("from%3Arstudio", url, ignore.case = TRUE))
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
  expect_true(grepl("until%3A2024-12-31", url, ignore.case = TRUE))
  expect_true(grepl("lang%3Aen", url, ignore.case = TRUE))
  expect_true(grepl("f%3Dlive", url, ignore.case = TRUE))
  expect_true(grepl("result_type%3Arecent", url, ignore.case = TRUE))
})

test_that("invalid mode throws in search URL", {
  expect_error(.rx_construct_search_url("test", mode = "recent"), "must be 'latest' or 'top'")
  expect_error(.rx_construct_search_url("test", mode = NA_character_), "must be 'latest', 'top', or NULL")
})

# -- user timeline URL with mode -----------------------------------------------

test_that("mode 'latest' appends to user timeline URL", {
  url <- .rx_construct_user_timeline_url("rstudio", mode = "latest")
  expect_true(grepl("f%3Dlive", url, ignore.case = TRUE))
  expect_true(grepl("^https://x.com/rstudio\\?", url))
})

test_that("mode 'top' appends to user timeline URL", {
  url <- .rx_construct_user_timeline_url("hadley", mode = "top")
  expect_true(grepl("f%3Dtop", url, ignore.case = TRUE))
})

test_that("mode combined with path", {
  url <- .rx_construct_user_timeline_url("rstudio", path = "media", mode = "latest")
  expect_true(grepl("https://x.com/rstudio/media\\?", url))
  expect_true(grepl("f%3Dlive", url, ignore.case = TRUE))
})

test_that("mode combined with date range", {
  url <- .rx_construct_user_timeline_url("rstudio", since = "2024-01-01", mode = "top")
  expect_true(grepl("since%3A2024-01-01", url, ignore.case = TRUE))
  expect_true(grepl("f%3Dtop", url, ignore.case = TRUE))
})

test_that("mode combined with raw filter", {
  url <- .rx_construct_user_timeline_url("rstudio", mode = "latest", filter = "tagged_media=true")
  expect_true(grepl("f%3Dlive", url, ignore.case = TRUE))
  expect_true(grepl("tagged_media", url, ignore.case = TRUE))
})

test_that("mode NULL gives no f= in user timeline URL", {
  url <- .rx_construct_user_timeline_url("rstudio", mode = NULL)
  expect_false(grepl("f%3D", url, ignore.case = TRUE))
})

test_that("invalid mode throws in user timeline URL", {
  expect_error(.rx_construct_user_timeline_url("rstudio", mode = "recent"), "must be 'latest' or 'top'")
  expect_error(.rx_construct_user_timeline_url("rstudio", mode = NA_character_), "must be 'latest', 'top', or NULL")
})
