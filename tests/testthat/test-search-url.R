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
