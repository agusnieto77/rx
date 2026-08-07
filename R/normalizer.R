# Internal: Canonical post normalizer and deduplication
#
# This module converts parsed raw posts (the list-of-vectors output from
# `.rx_parse_posts`) into one stable canonical schema.  The parser and
# normalizer are deliberately separate:
#
#   parser  -> list-of-vectors with post-level fields (+ cursors)
#   normalizer -> validates, coerces, and pads to the 24-field canonical schema
#   dedup   -> removes duplicate posts by post_id, first-seen order
#
#   Note: observation-level provenance fields (collected_at, collection_query,
#   collection_id) are injected by the search pipeline before normalization
#   (Task 46). The normalizer handles them as regular character fields.
#   dedup   -> removes duplicate posts by post_id, first-seen order
#
# Every output row (column in the list) has the same columns.
# Missing values are represented consistently:
#   - character fields: NA_character_
#   - integer fields:   0L
#   - logical fields:   FALSE
#
# @name normalizer
# @aliases normalizer
# @keywords internal
# @examples
#   # Internal use only — not exported.
#   # parsed <- xtweetsR:::.rx_parse_posts(response)
#   # normalized <- xtweetsR:::.rx_normalize_posts(parsed)
#   # posts <- xtweetsR:::.rx_normalized_to_tibble(normalized)
#   # deduped <- xtweetsR:::.rx_deduplicate_posts(posts)
NULL

#' Canonical field schema for post normalizer.
#'
# Defines the authoritative field order, types, and NA defaults used by
# `.rx_normalize_posts()`.  The normalizer enforces this schema.
#'
#' Fields:
#'   - post_id — character
#'   - text — character
#'   - author_id — character
#'   - username — character
#'   - display_name — character
#'   - created_at — character
#'   - reply_count — integer
#'   - repost_count — integer
#'   - like_count — integer
#'   - quote_count — integer
#'   - bookmark_count — integer
#'   - view_count — integer
#'   - conversation_id — character
#'   - is_reply — logical
#'   - is_repost — logical
#'   - is_quote — logical
#'   - reply_to_post_id — character
#'   - quoted_post_id — character
#'   - hashtags — list of character vectors (Task 56)
#'   - mentions — list of named character vectors (Task 56)
#'   - urls — list of character vectors (Task 56)
#'   - collected_at — character (ISO-8601 timestamp, Task 46)
#'   - collection_query — character (search query string, Task 46)
#'   - collection_id — character (UUID, Task 46)
#'
#' @return A character vector of 24 field names in canonical order.
#' @keywords internal
.rx_canonical_fields <- function() {
  c(
    "post_id", "text",
    "author_id", "username", "display_name",
    "created_at",
    "reply_count", "repost_count", "like_count", "quote_count",
    "bookmark_count", "view_count",
    "conversation_id",
    "is_reply", "is_repost", "is_quote",
    "reply_to_post_id", "quoted_post_id",
    # Entity fields (Task 56) — list-columns
    "hashtags", "mentions", "urls",
    # Observation-level provenance (Task 46)
    "collected_at", "collection_query", "collection_id"
  )
}

#' Type map for the canonical schema.
#'
# Returns a named character vector mapping each canonical field to its
# expected R type ("character", "integer", or "logical").
#'
#' @return A named character vector.
#' @noRd
.rx_type_map <- function() {
  c(
    post_id = "character", text = "character",
    author_id = "character", username = "character",
    display_name = "character", created_at = "character",
    reply_count = "integer", repost_count = "integer",
    like_count = "integer", quote_count = "integer",
    bookmark_count = "integer", view_count = "integer",
    conversation_id = "character",
    is_reply = "logical", is_repost = "logical", is_quote = "logical",
    reply_to_post_id = "character", quoted_post_id = "character",
    # Entity fields (Task 56) — list-columns
    hashtags = "list", mentions = "list", urls = "list",
    # Observation-level provenance (Task 46)
    collected_at = "character", collection_query = "character", collection_id = "character"
  )
}

#' NA defaults for the canonical schema.
#'
# Returns a named list mapping each canonical field to its default
# "empty" value when the input vector is shorter than expected.
#'
#' @return A named list of default values.
#' @noRd
.rx_na_defaults <- function() {
  c(
    post_id = NA_character_, text = NA_character_,
    author_id = NA_character_, username = NA_character_,
    display_name = NA_character_, created_at = NA_character_,
    reply_count = 0L, repost_count = 0L,
    like_count = 0L, quote_count = 0L,
    bookmark_count = 0L, view_count = 0L,
    conversation_id = NA_character_,
    is_reply = FALSE, is_repost = FALSE, is_quote = FALSE,
    reply_to_post_id = NA_character_, quoted_post_id = NA_character_,
    # Entity fields (Task 56) — list-columns use list(NULL) as NA
    hashtags = list(NULL), mentions = list(NULL), urls = list(NULL),
    # Observation-level provenance (Task 46)
    collected_at = NA_character_, collection_query = NA_character_, collection_id = NA_character_
  )
}

#' Normalize parsed posts into a canonical schema.
#'
# Takes the list-of-vectors output from `.rx_parse_posts()` and:
# 1. Validates that all canonical fields are present.
# 2. Coerces each field to its expected type.
# 3. Pads shorter vectors with consistent NA defaults.
# 4. Reorders fields to canonical order.
#
# This is the bridge between the parser's raw extraction and the tibble
# output expected by downstream code (Task 37).
#'
#' @param parsed A list as returned by `.rx_parse_posts()`.
#' @return A list with the same 21 fields in canonical order, each coerced
#'   to the expected type and padded to the longest length with NA defaults.
#'   Returns an empty normalized list (zero-length vectors) when `parsed`
#'   is NULL, empty, or contains no `post_id` field.
#'
#' @keywords internal
.rx_normalize_posts <- function(parsed) {
  fields <- .rx_canonical_fields()
  type_map <- .rx_type_map()
  na_defs <- .rx_na_defaults()

  # Handle NULL / empty / unexpected input early.
  if (!is.list(parsed) || length(parsed) == 0L) {
    return(.rx_empty_normalized(fields, na_defs))
  }

  # If the parser returned nothing meaningful, short-circuit.
  if (!"post_id" %in% names(parsed) || length(parsed$post_id) == 0L) {
    return(.rx_empty_normalized(fields, na_defs))
  }

  n <- length(parsed$post_id)

  # Build normalized output.
  result <- vector("list", length(fields))
  names(result) <- fields

  for (field in fields) {
    raw <- parsed[[field]]

    # Missing field -> fill with NA default.
    if (is.null(raw)) {
      result[[field]] <- .rx_fill(field, n, na_defs[[field]])
      next
    }

    # Coerce to expected type.
    coerced <- .rx_coerce(raw, type_map[[field]], n, na_defs[[field]])
    result[[field]] <- coerced
  }

  result
}

#' Create an empty normalized list with zero-length canonical fields.
#'
# @param fields The canonical field names.
# @param na_defs The NA defaults (unused here, but kept for symmetry).
#' @return A list with all fields set to zero-length vectors of the
#'   appropriate type.
#' @noRd
.rx_empty_normalized <- function(fields, na_defs) {
  result <- vector("list", length(fields))
  names(result) <- fields
  for (field in fields) {
    type <- .rx_type_map()[[field]]
    result[[field]] <- switch(type,
      character = character(0),
      integer = integer(0),
      logical = logical(0),
      list = list(),
      list()
    )
  }
  result
}

#' Coerce a raw vector to its expected type, padding to target length.
#'
# @param raw The raw vector from the parser.
# @param expected_type One of "character", "integer", "logical", "list".
# @param n The target length (from post_id count).
# @param na_val The NA default for padding (used only for character/integer/logical types).
#' @return A vector of the expected type, length `n`.
#' @noRd
.rx_coerce <- function(raw, expected_type, n, na_val) {
  # Truncate or pad to match post_id length.
  if (length(raw) > n) {
    raw <- raw[seq_len(n)]
  }
  if (length(raw) < n) {
    raw <- c(raw, rep(na_val, n - length(raw)))
  }

  switch(expected_type,
    character = {
      raw <- as.character(raw)
      raw[is.na(raw)] <- na_val
      raw
    },
    integer = {
      raw <- as.integer(raw)
      raw[is.na(raw)] <- na_val
      raw
    },
    logical = {
      raw <- as.logical(raw)
      raw[is.na(raw)] <- na_val
      raw
    },
    raw
  )
}

#' Convert a normalized post list to a tibble.
#'
#' Takes the list-of-vectors output from `.rx_normalize_posts()` and
#' builds a `tibble` with one row per post. Column types are preserved:
#' character IDs stay character, integers stay integers, logicals stay logical.
#'
#' This is the final step in the parser->normalizer->tibble pipeline
#' that Task 37 introduces.
#'
#' @param normalized A list as returned by `.rx_normalize_posts()`.
#' @return A `tibble` with 24 columns matching the canonical schema.
#'   Zero rows when `normalized` is empty.
#'
#' @examples
#'   # Internal use only — not exported.
#'   # parsed <- xtweetsR:::.rx_parse_posts(response)
#'   # normalized <- xtweetsR:::.rx_normalize_posts(parsed)
#'   # posts <- xtweetsR:::.rx_normalized_to_tibble(normalized)
#'
#' @noRd
.rx_normalized_to_tibble <- function(normalized) {
  # Guard: not a list or no fields at all.
  if (!is.list(normalized) || length(normalized) == 0L) {
    return(tibble::tibble())
  }

  # Detect the row count from the first field (post_id).
  n <- length(normalized[[1]])
  if (n == 0L) {
    # Empty result — return a tibble with the right columns but zero rows.
    # Preserve each field's type.
    type_map <- .rx_type_map()
    cols <- lapply(names(normalized), function(f) {
      switch(type_map[[f]],
        character = character(0),
        integer = integer(0),
        logical = logical(0)
      )
    })
    names(cols) <- names(normalized)
    return(tibble::as_tibble(cols))
  }

  # Build the tibble directly from the list.
  # The normalizer already guarantees consistent lengths and correct types.
  tibble::as_tibble(normalized)
}

#' Deduplicate posts by `post_id`, preserving first-seen order.
#'
#' Takes a normalized post list (as returned by `.rx_normalize_posts()`)
#' or a tibble (as returned by `.rx_normalized_to_tibble()`) and removes
#' rows where `post_id` has already been seen. The first occurrence of
#' each `post_id` is kept; subsequent duplicates are dropped.
#'
#' This function deduplicates by `post_id` only. Two posts that share the
#' same text but have different `post_id` values are NOT deduplicated.
#'
#' @param posts A normalized post list or a tibble.
#' @return The same type as the input, with duplicate `post_id` rows removed.
#'   When the input has zero rows, the output is returned unchanged.
#'
#' @examples
#'   # Internal use only — not exported.
#'   # parsed <- xtweetsR:::.rx_parse_posts(response)
#'   # normalized <- xtweetsR:::.rx_normalize_posts(parsed)
#'   # deduped <- xtweetsR:::.rx_deduplicate_posts(normalized)
#'
#' @noRd
.rx_deduplicate_posts <- function(posts) {
  # If it's already a tibble, work on it directly.
  if (inherits(posts, "tbl_df")) {
    return(.rx_deduplicate_tibble(posts))
  }

  # Otherwise treat it as a normalized list and convert first.
  if (is.list(posts) && length(posts) > 0L && !is.null(posts$post_id)) {
    tbl <- .rx_normalized_to_tibble(posts)
    return(.rx_deduplicate_tibble(tbl))
  }

  # Fallback: return as-is (empty input).
  posts
}

#' Internal: deduplicate a post tibble by `post_id`.
#'
#' @param tbl A tibble with at least a `post_id` column.
#' @return A tibble with duplicate `post_id` rows removed (first-seen kept).
#' @noRd
.rx_deduplicate_tibble <- function(tbl) {
  n <- nrow(tbl)
  if (n == 0L) {
    return(tbl)
  }

  # Use match to keep only the first occurrence of each post_id.
  # `match` returns the index of the first match; we keep rows whose
  # index equals the match result — i.e. the first time each value appears.
  keep <- !duplicated(tbl$post_id)
  tbl[keep, , drop = FALSE]
}
