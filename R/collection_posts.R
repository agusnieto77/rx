# Internal: Canonical collection-post relation representation
#
# This module extracts collection-post relations from parsed post data and
# represents them as a separate relational table. Each row records that a
# specific post was found during a specific collection run, along with the
# query that produced it.
#
#   posts        -> tibble with 26 columns (canonical post schema)
#   users        -> tibble with 3 columns (user lookup table)
#   media        -> tibble with 4 columns (media lookup table)
#   collection_posts -> tibble with 4 columns (post-collection relation)
#
# The relation table enables tracking which posts appeared in multiple
# queries or collection runs, supporting deduplication across collections
# and provenance auditing.
#
# @name collection_posts
# @aliases collection_posts
# @keywords internal
# @examples
#   # Internal use only — not exported.
#   # parsed <- xtweetsR:::.rx_parse_posts(response)
#   # relations <- xtweetsR:::.rx_extract_collection_posts(parsed)
#   # relations_tbl <- xtweetsR:::.rx_collection_posts_to_tibble(relations)
NULL

#' Canonical field schema for the collection-post relation table.
#'
# Defines the authoritative field order for the relation table. Each row
# uniquely identifies that a specific post was observed during a specific
# collection, along with the query that found it and the timestamp.
#'
#' Fields:
#'   - post_id — character (the post ID, foreign key to posts)
#'   - collection_id — character (UUID of the collection, foreign key to collections)
#'   - collection_query — character (the search query that found this post)
#'   - collected_at — character (ISO-8601 timestamp of collection)
#'
#' @return A character vector of 4 field names in canonical order.
#' @keywords internal
.rx_collection_posts_fields <- function() {
  c("post_id", "collection_id", "collection_query", "collected_at")
}

#' Extract collection-post relations from parsed post data.
#'
# Takes the list-of-vectors output from `.rx_parse_posts()` and extracts
# the observation-level provenance fields (post_id, collection_id,
# collection_query, collected_at) as a relation table. Each post row
# becomes one relation row, recording which collection and query produced it.
#'
#' This enables tracking posts across multiple collection runs and queries,
# supporting cross-collection deduplication and provenance auditing.
#'
#' @param parsed A list as returned by `.rx_parse_posts()`.
#' @return A list with four character vectors
#'   (`post_id`, `collection_id`, `collection_query`, `collected_at`),
#'   one row per post. Zero rows when `parsed` is empty.
#'
#' @noRd
.rx_extract_collection_posts <- function(parsed) {
  fields <- .rx_collection_posts_fields()

  # Handle NULL / empty / unexpected input.
  if (!is.list(parsed) || is.null(parsed$post_id) || length(parsed$post_id) == 0L) {
    result <- vector("list", length(fields))
    names(result) <- fields
    for (field in fields) {
      result[[field]] <- character(0)
    }
    return(result)
  }

  post_ids      <- parsed$post_id
  collection_ids <- parsed$collection_id
  queries       <- parsed$collection_query
  timestamps    <- parsed$collected_at
  n             <- length(post_ids)

  if (n == 0L) {
    result <- vector("list", length(fields))
    names(result) <- fields
    for (field in fields) {
      result[[field]] <- character(0)
    }
    return(result)
  }

  # Build relation rows: one per post.
  # Preserve observed values; fill missing provenance with NA.
  rel_post_ids <- character(n)
  rel_cids     <- character(n)
  rel_queries  <- character(n)
  rel_times    <- character(n)

  for (i in seq_len(n)) {
    rel_post_ids[i] <- if (is.character(post_ids[i]) && length(post_ids[i]) == 1L && !is.na(post_ids[i])) as.character(post_ids[i]) else NA_character_
    rel_cids[i]     <- if (is.character(collection_ids[i]) && length(collection_ids[i]) == 1L && !is.na(collection_ids[i])) as.character(collection_ids[i]) else NA_character_
    rel_queries[i]  <- if (is.character(queries[i]) && length(queries[i]) == 1L && !is.na(queries[i])) as.character(queries[i]) else NA_character_
    rel_times[i]    <- if (is.character(timestamps[i]) && length(timestamps[i]) == 1L && !is.na(timestamps[i])) as.character(timestamps[i]) else NA_character_
  }

  list(
    post_id          = rel_post_ids,
    collection_id    = rel_cids,
    collection_query = rel_queries,
    collected_at     = rel_times
  )
}

#' Convert a collection-post relations list to a tibble.
#'
# Takes the list output from `.rx_extract_collection_posts()` and builds
# a `tibble` with one row per post. Column types are all character.
#'
#' @param relations A list as returned by `.rx_extract_collection_posts()`.
#' @return A `tibble` with 4 columns matching the canonical relation schema.
#'   Zero rows when `relations` is empty.
#'
#' @noRd
.rx_collection_posts_to_tibble <- function(relations) {
  if (!is.list(relations) || length(relations) == 0L) {
    return(tibble::tibble(
      post_id          = character(0),
      collection_id    = character(0),
      collection_query = character(0),
      collected_at     = character(0)
    ))
  }

  # Guard: not enough fields.
  fields <- .rx_collection_posts_fields()
  if (!all(fields %in% names(relations))) {
    return(tibble::tibble(
      post_id          = character(0),
      collection_id    = character(0),
      collection_query = character(0),
      collected_at     = character(0)
    ))
  }

  # Detect row count.
  n <- length(relations$post_id)
  if (n == 0L) {
    return(tibble::tibble(
      post_id          = character(0),
      collection_id    = character(0),
      collection_query = character(0),
      collected_at     = character(0)
    ))
  }

  tibble::tibble(
    post_id          = as.character(relations$post_id),
    collection_id    = as.character(relations$collection_id),
    collection_query = as.character(relations$collection_query),
    collected_at     = as.character(relations$collected_at)
  )
}
