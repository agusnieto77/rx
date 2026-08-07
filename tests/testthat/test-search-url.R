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
