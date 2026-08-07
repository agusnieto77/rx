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
#'   query (e.g. `"lang:en"` or `"until:2026-01-01"`). The filter itself
#'   is NOT URL-encoded — it is expected to be valid X search syntax.
#'
#' @return Character string with the full X search URL.
#'
#' @noRd
.rx_construct_search_url <- function(query, from_user = NULL, filter = NULL) {
  # Use trimws so whitespace-only strings are rejected (nzchar("  ") is TRUE).
  if (!is.character(query) || length(query) != 1L || !nzchar(trimws(query))) {
    stop("query must be a single non-empty character string.", call. = FALSE)
  }

  # Build the raw query string that X's search expects.
  raw <- query

  # X search syntax: `from:username` restricts to a specific user.
  if (!is.null(from_user) && nzchar(from_user)) {
    raw <- paste0(raw, " from:", from_user)
  }

  # Append an arbitrary filter (caller is responsible for valid syntax).
  if (!is.null(filter) && nzchar(filter)) {
    raw <- paste0(raw, " ", filter)
  }

  # URL-encode the full query string.
  # reserved = TRUE ensures characters like & and : are percent-encoded,
  # which is correct for a URL parameter value (X's search server will
  # decode the value and parse the internal syntax from it).
  encoded <- URLencode(raw, reserved = TRUE)

  paste0("https://x.com/search?q=", encoded)
}
