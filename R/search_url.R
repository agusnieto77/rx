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
#' Build an X/Twitter date-range filter string.
#'
#' Takes optional `since` and `until` date arguments and returns a
#' single X search filter string such as `"since:2024-01-01 until:2024-12-31"`.
#' Only non-NULL, non-empty dates are included.
#'
#' # Date format
#' X search accepts dates in `YYYY-MM-DD` format. This function validates
#' that each date is parseable as `as.Date()` before including it.
#'
#' @param since Optional character string with a date (YYYY-MM-DD).
#'   When provided, appends `since:<date>` to the filter.
#' @param until Optional character string with a date (YYYY-MM-DD).
#'   When provided, appends `until:<date>` to the filter.
#'
#' @return A character string with the combined date-range filter,
#'   or `NULL` when neither argument is provided.
#'
#' @examples
#'   # Internal use only — not exported.
#'   .rx_build_date_range_filter(since = "2024-01-01")
#'   .rx_build_date_range_filter(since = "2024-01-01", until = "2024-12-31")
#'   .rx_build_date_range_filter()
#'
#' @noRd
.rx_build_date_range_filter <- function(since = NULL, until = NULL) {
  parts <- character(0L)

  if (!is.null(since)) {
    if (!is.character(since) || length(since) != 1L || anyNA(since)) {
      stop("since must be a single character string with a date (YYYY-MM-DD), or NULL.", call. = FALSE)
    }
    d <- trimws(since)
    if (!nzchar(d)) {
      stop("since must be a single character string with a date (YYYY-MM-DD), or NULL.", call. = FALSE)
    }
    if (is.na(as.Date(d))) {
      stop("since is not a valid date (YYYY-MM-DD): ", since, call. = FALSE)
    }
    parts <- c(parts, paste0("since:", d))
  }

  if (!is.null(until)) {
    if (!is.character(until) || length(until) != 1L || anyNA(until)) {
      stop("until must be a single character string with a date (YYYY-MM-DD), or NULL.", call. = FALSE)
    }
    d <- trimws(until)
    if (!nzchar(d)) {
      stop("until must be a single character string with a date (YYYY-MM-DD), or NULL.", call. = FALSE)
    }
    if (is.na(as.Date(d))) {
      stop("until is not a valid date (YYYY-MM-DD): ", until, call. = FALSE)
    }
    parts <- c(parts, paste0("until:", d))
  }

  if (length(parts) == 0L) {
    return(NULL)
  }

  paste(parts, collapse = " ")
}

#' Build an X language filter string.
#'
#' Takes a language code and returns a single X search filter string such as
#' `"lang:en"`.  X uses ISO 639-1 two-letter language codes, but also
#' recognises a few three-letter codes (e.g. `tl` for Tagalog).
#'
#' @param lang Optional character string with a language code
#'   (e.g. `"en"`, `"es"`, `"ja"`).  When provided, returns
#'   `paste0("lang:", lang)`.
#'
#' @return A character string with the language filter, or `NULL` when
#'   `lang` is `NULL` or empty.
#'
#' @examples
#'   # Internal use only — not exported.
#'   .rx_build_language_filter("en")
#'   .rx_build_language_filter("es")
#'   .rx_build_language_filter()
#'
#' @noRd
.rx_build_language_filter <- function(lang = NULL) {
  if (is.null(lang)) {
    return(NULL)
  }
  if (!is.character(lang) || length(lang) != 1L || anyNA(lang)) {
    stop("lang must be a single character string with a language code, or NULL.", call. = FALSE)
  }
  code <- trimws(lang)
  if (!nzchar(code)) {
    stop("lang must be a single character string with a language code, or NULL.", call. = FALSE)
  }
  # X accepts ISO 639-1 codes (2 letters) and a few 3-letter codes.
  # We keep validation light: only letters, 2-3 characters.
  if (!grepl("^[A-Za-z]{2,3}$", code)) {
    stop("lang must be a valid language code (e.g. 'en', 'es', 'ja'): ", lang, call. = FALSE)
  }
  paste0("lang:", code)
}

#' Construct an X search URL from a query string.
#'
#' Takes a search query and returns a properly URL-encoded X search URL.
#' Query terms are separated by spaces (X's default search behaviour).
#' Optional filters can be appended as URL parameters (e.g. `from_user`).
#'
#' @param query Character string, the search query. Must be non-empty.
#' @param from_user Optional character string. When provided, appends
#'   `from:<username>` to the query before encoding (X search syntax).
#' @param since Optional character string with a date (YYYY-MM-DD).
#'   When provided, appends `since:<date>` to the query before encoding.
#' @param until Optional character string with a date (YYYY-MM-DD).
#'   When provided, appends `until:<date>` to the query before encoding.
#' @param lang Optional character string with an ISO 639-1 language code
#'   (e.g. `"en"`, `"es"`, `"ja"`).  When provided, appends
#'   `lang:<code>` to the query before encoding.
#' @param filter Optional character string. Raw filter appended after the
#'   query (e.g. `"result_type:recent"`). The filter is
#'   URL-encoded via `URLencode(raw, reserved=TRUE)`.
#'
#' @return Character string with the full X search URL.
#'
#' @examples
#'   # Internal use only — not exported.
#'   .rx_construct_search_url("r programming")
#'   .rx_construct_search_url("climate change", from_user = "alice")
#'   .rx_construct_search_url("AI", since = "2024-01-01", until = "2024-12-31")
#'   .rx_construct_search_url("hello", lang = "es")
#'
#' @noRd
.rx_construct_search_url <- function(query, from_user = NULL, since = NULL, until = NULL, lang = NULL, filter = NULL) {
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

  # Append date-range filters (since/until).
  # Validate each date individually, then build the filter.
  date_filter <- .rx_build_date_range_filter(since = since, until = until)
  if (!is.null(date_filter)) {
    raw <- paste0(raw, " ", date_filter)
  }

  # Append language filter.
  lang_filter <- .rx_build_language_filter(lang = lang)
  if (!is.null(lang_filter)) {
    raw <- paste0(raw, " ", lang_filter)
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

#' Normalize a post identifier to a canonical X post URL.
#'
#' Accepts either a full X/Twitter post URL or a bare post ID string.
#' When given a URL, extracts the numeric post ID and rewrites it to
#' the canonical `https://x.com/<username>/status/<id>` form.
#' When given a bare ID, returns `https://x.com/status/<id>`.
#'
#' # Supported URL patterns
#' - `https://x.com/<user>/status/<id>` — canonical form
#' - `https://x.com/<user>/status/<id>/` — trailing slash
#' - `https://t.co/<shortlink>` — X short link (bare ID returned)
#' - `https://twitter.com/<user>/status/<id>` — legacy domain
#' - Any other URL — returned unchanged (caller should validate)
#'
#' @param url_or_id A character string that is either a full post URL
#'   or a bare post ID (numeric string).
#' @return A character string with the canonical X post URL, or the
#'   original input when it cannot be parsed.
#'
#' @examples
#'   # Internal use only — not exported.
#'   .rx_normalize_post_url("https://x.com/rstudio/status/1234567890123456789")
#'   .rx_normalize_post_url("1234567890123456789")
#'   .rx_normalize_post_url("https://t.co/abc123")
#'
#' @noRd
.rx_normalize_post_url <- function(url_or_id) {
  if (!is.character(url_or_id) || length(url_or_id) != 1L || anyNA(url_or_id)) {
    return(url_or_id)
  }

  input <- trimws(url_or_id)

  # If it looks like a numeric post ID (15-20 digits), return canonical URL.
  if (grepl("^\\d{15,20}$", input)) {
    return(paste0("https://x.com/status/", input))
  }

  # Try to parse as a URL and extract the post ID.
  # Supported patterns:
  #   https://x.com/USER/status/ID
  #   https://x.com/USER/status/ID/
  #   https://twitter.com/USER/status/ID
  #   https://t.co/SHORTLINK  -> returns bare ID? No, we can't extract ID from t.co
  #                             without resolving. Return as-is for now.

  # Match x.com or twitter.com post URLs.
  m <- regmatches(input, regexec(
    "^https?://(?:x|twitter)\\.com/([^/]+)/status/(\\d+)",
    input,
    perl = TRUE
  ))

  if (length(m[[1L]]) > 0L) {
    # regexec returns list of character vectors; m[[1]] has the full match + groups.
    id <- m[[1L]][2L]
    return(paste0("https://x.com/status/", id))
  }

  # t.co short links: we cannot extract the post ID without resolving,
  # so return the URL as-is. The caller should try navigating to it.
  # Handle both x.com/shortlink and t.co patterns.
  if (grepl("^https?://t\\.co/", input, ignore.case = TRUE)) {
    return(input)
  }

  # Any other URL: return as-is. Caller validates.
  input
}

#' Construct an X post URL from a post ID.
#'
#' Takes a post ID (numeric string) and returns the canonical
#' X post URL: `https://x.com/status/<id>`.
#'
#' @param post_id A single character string with a numeric post ID
#'   (15-20 digits).
#' @return Character string with the full X post URL.
#'
#' @examples
#'   # Internal use only — not exported.
#'   .rx_construct_post_url("1234567890123456789")
#'
#' @noRd
.rx_construct_post_url <- function(post_id) {
  if (!is.character(post_id) || length(post_id) != 1L || anyNA(post_id)) {
    stop("post_id must be a single non-empty character string.", call. = FALSE)
  }
  id <- trimws(post_id)
  if (!grepl("^\\d+$", id)) {
    stop("post_id must be a numeric string (15-20 digits).", call. = FALSE)
  }
  paste0("https://x.com/status/", id)
}

#' Construct an X user timeline URL from a username.
#'
#' Takes a username (without the leading @) and returns a properly
#' formed X user timeline URL. Optional path, date range, and filter
#' parameters can modify the timeline view (e.g. media, with_replies).
#'
#' @param username A single non-empty character string with an X
#'   username (without the leading @).
#' @param path Optional path segment appended after the username,
#'   e.g. `"media"`, `"tweets_with_replies"`, `"following"`,
#'   `"followers"`. When NULL, the base timeline is returned.
#' @param since Optional character string with a date (YYYY-MM-DD).
#'   When provided, appends `since:<date>` to the timeline query filter.
#' @param until Optional character string with a date (YYYY-MM-DD).
#'   When provided, appends `until:<date>` to the timeline query filter.
#' @param lang Optional character string with an ISO 639-1 language code
#'   (e.g. `"en"`, `"es"`, `"ja"`).  When provided, appends
#'   `lang:<code>` to the timeline query filter.
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
#'   .rx_construct_user_timeline_url("rstudio", since = "2024-01-01")
#'   .rx_construct_user_timeline_url("rstudio", lang = "en")
#'
#' @noRd
.rx_construct_user_timeline_url <- function(username, path = NULL, since = NULL, until = NULL, lang = NULL, filter = NULL) {
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

  # Build combined query filter from date range + language + optional raw filter.
  date_filter <- .rx_build_date_range_filter(since = since, until = until)
  lang_filter <- .rx_build_language_filter(lang = lang)
  combined_parts <- c(date_filter, lang_filter, filter)
  combined_parts <- combined_parts[!is.na(combined_parts) & nzchar(combined_parts)]

  if (length(combined_parts) > 0L) {
    combined_filter <- paste(combined_parts, collapse = " ")
    encoded_filter <- URLencode(combined_filter, reserved = TRUE)
    url <- paste0(url, "?", encoded_filter)
  }

  url
}
