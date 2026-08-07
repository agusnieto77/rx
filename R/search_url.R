# Internal: X search URL construction
#
# This module provides helpers for building X/Twitter search URLs.
# X search URLs follow the pattern:
#   https://x.com/search?q=<url-encoded-query>
#
# @name search_url
# @aliases search_url
# @keywords internal
# @examples
#   # Internal use only — not exported.
#   .rx_construct_search_url("r programming")
#   .rx_construct_search_url("climate change", from_user = "alice")
NULL

#' Construct an X search URL from a query string.
#'
#' Takes a search query and returns a properly URL-encoded X search URL.
#' Query terms are separated by spaces (X's default search behaviour).
#' Optional filters can be appended as URL parameters (e.g. `from_user`).
#'
#' @param query Character string, the search query. Must be non-empty.
#' @param from_user Optional character string. When provided, appends
#'   `from:<username>` to the query before encoding (X search syntax).
#' @param filter Optional character string. Raw filter appended after the
#'   query (e.g. `"lang:en"` or `"until:2026-01-01"`). The filter is
#'   URL-encoded via `URLencode(raw, reserved=TRUE)`.
#'
#' @return Character string with the full X search URL.
#'
#' @noRd
.rx_construct_search_url <- function(query, from_user = NULL, filter = NULL) {
  # Use trimws so whitespace-only strings are rejected (nzchar("  ") is TRUE).
  if (!is.character(query) || length(query) != 1L || anyNA(query) || !nzchar(trimws(query))) {
    stop("query must be a single non-empty character string.", call. = FALSE)
  }

  # Build the raw query string that X's search expects.
  # trimws canonicalizes: " hello " becomes "hello" (consistent with from_user/filter).
  raw <- trimws(query)

  # X search syntax: `from:username` restricts to a specific user.
  # Validate type/length before using nzchar to avoid NA_character_ crashes.
  # Use trimws so whitespace-only strings are rejected (consistent with query).
  if (!is.null(from_user)) {
    if (!is.character(from_user) || length(from_user) != 1L || anyNA(from_user) || !nzchar(trimws(from_user))) {
      stop("from_user must be a single non-empty character string, or NULL.", call. = FALSE)
    }
    raw <- paste0(raw, " from:", trimws(from_user))
  }

  # Append an arbitrary filter (caller is responsible for valid syntax).
  # Validate type/length before using nzchar to avoid NA_character_ crashes.
  # Use trimws so whitespace-only strings are rejected (consistent with query).
  if (!is.null(filter)) {
    if (!is.character(filter) || length(filter) != 1L || anyNA(filter) || !nzchar(trimws(filter))) {
      stop("filter must be a single non-empty character string, or NULL.", call. = FALSE)
    }
    raw <- paste0(raw, " ", trimws(filter))
  }

  # URL-encode the full query string.
  # reserved = TRUE ensures characters like & and : are percent-encoded,
  # which is correct for a URL parameter value (X's search server will
  # decode the value and parse the internal syntax from it).
  encoded <- URLencode(raw, reserved = TRUE)

  paste0("https://x.com/search?q=", encoded)
}

#' Construct an X user timeline URL from a username.
#'
#' Takes a username (without the leading @) and returns a properly
#' formed X user timeline URL. Optional path and filter parameters
#' can modify the timeline view (e.g. media, with_replies).
#'
#' @param username A single non-empty character string with an X
#'   username (without the leading @).
#' @param path Optional path segment appended after the username,
#'   e.g. `"media"`, `"tweets_with_replies"`, `"following"`,
#'   `"followers"`. When NULL, the base timeline is returned.
#' @param filter Optional character string. Raw filter appended as a
#'   query parameter (e.g. `"tagged_media=true"`). The filter is
#'   URL-encoded via `URLencode(raw, reserved=TRUE)`.
#'
#' @return Character string with the full X user timeline URL.
#'
#' @examples
#'   # Internal use only — not exported.
#'   .rx_construct_user_timeline_url("hadleywickham")
#'   .rx_construct_user_timeline_url("hadleywickham", path = "media")
#'   .rx_construct_user_timeline_url("rstudio", path = "following")
#'
#' @noRd
.rx_construct_user_timeline_url <- function(username, path = NULL, filter = NULL) {
  # Validate username.
  if (!is.character(username) || length(username) != 1L || anyNA(username) || !nzchar(trimws(username))) {
    stop("username must be a single non-empty character string.", call. = FALSE)
  }

  user <- trimws(username)
  # Strip a leading @ if the caller included it (X URLs do not use @).
  user <- sub("^@", "", user)

  url <- paste0("https://x.com/", user)

  # Append an optional path segment (e.g. media, following).
  if (!is.null(path)) {
    if (!is.character(path) || length(path) != 1L || anyNA(path) || !nzchar(trimws(path))) {
      stop("path must be a single non-empty character string, or NULL.", call. = FALSE)
    }
    url <- paste0(url, "/", trimws(path))
  }

  # Append an optional raw filter as a query parameter.
  if (!is.null(filter)) {
    if (!is.character(filter) || length(filter) != 1L || anyNA(filter) || !nzchar(trimws(filter))) {
      stop("filter must be a single non-empty character string, or NULL.", call. = FALSE)
    }
    encoded_filter <- URLencode(trimws(filter), reserved = TRUE)
    url <- paste0(url, "?", encoded_filter)
  }

  url
}
