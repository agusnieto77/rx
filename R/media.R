# Internal: Canonical media extraction and representation
#
# This module extracts unique media records from parsed post data and
# represents them as a separate relational table. The media table
# complements the posts tibble without changing its structure.
#
#   posts   -> tibble with 26 columns (canonical post schema)
#   media   -> tibble with 4 columns (canonical media schema)
#   relation -> media rows reference posts via post_id
#
# Each post can have zero or more media items (photos, videos, gifs).
# The media table "explodes" the one-to-many relationship: a post with
# 2 photos becomes 2 rows in the media table, both referencing the
# same post_id.
#
# The simple tibble API is preserved: existing code that only needs
# posts continues to work unchanged. The media table is available
# through the relational result object returned by search functions.
#
# @name media
# @aliases media
# @keywords internal
# @examples
#   # Internal use only — not exported.
#   # parsed <- xtweetsR:::.rx_parse_posts(response)
#   # media <- xtweetsR:::.rx_extract_media(parsed)
#   # media_tibble <- xtweetsR:::.rx_media_to_tibble(media)
NULL

#' Canonical field schema for the media table.
#'
# Defines the authoritative field order for the relational media
# representation. Each media row uniquely identifies one media item
# attached to a post.
#'
#' Fields:
#'   - media_id — character (post_id of the source post; acts as primary key per post)
#'   - media_type — character (media type: "photo", "video", "animated_gif")
#'   - media_url — character (primary media URL)
#'   - post_id — character (foreign key back to the posts table)
#'
#' @return A character vector of 4 field names in canonical order.
#' @keywords internal
.rx_media_fields <- function() {
  c("media_id", "media_type", "media_url", "post_id")
}

#' Extract media records from parsed post data.
#'
# Takes the list-of-vectors output from `.rx_parse_posts()` and
# expands the per-post `media_type` and `media_urls` list-columns
# into one row per media item. Posts with no media are omitted.
#'
#' @param parsed A list as returned by `.rx_parse_posts()`.
#' @return A list with four character vectors
#'   (`media_id`, `media_type`, `media_url`, `post_id`), one row per
#'   media item. Zero rows when `parsed` has no media.
#'
#' @noRd
.rx_extract_media <- function(parsed) {
  fields <- .rx_media_fields()

  # Handle NULL / empty / unexpected input.
  if (!is.list(parsed) || !is.list(parsed$post_id) || length(parsed$post_id) == 0L) {
    result <- vector("list", length(fields))
    names(result) <- fields
    for (field in fields) {
      result[[field]] <- character(0)
    }
    return(result)
  }

  post_ids     <- parsed$post_id
  media_types  <- parsed$media_type
  media_urls   <- parsed$media_urls
  n            <- length(post_ids)

  if (n == 0L) {
    result <- vector("list", length(fields))
    names(result) <- fields
    for (field in fields) {
      result[[field]] <- character(0)
    }
    return(result)
  }

  # Expand: one row per media item per post.
  media_id_vec  <- character(0)
  media_type_vec <- character(0)
  media_url_vec  <- character(0)
  post_id_vec   <- character(0)

  for (i in seq_len(n)) {
    pid <- as.character(post_ids[i])
    mt  <- media_types[[i]]
    mu  <- media_urls[[i]]

    # Skip posts with no media.
    if (is.null(mt) || length(mt) == 0L || !is.character(mt)) {
      next
    }

    # Build URL fallback: prefer mu[idx], fallback to NA.
    n_media <- length(mt)
    for (j in seq_len(n_media)) {
      mtype <- mt[j]
      if (is.na(mtype) || !nzchar(mtype)) {
        mtype <- NA_character_
      }
      if (is.list(mu) && length(mu) >= j && !is.null(mu[[j]])) {
        murl <- as.character(mu[[j]])
      } else {
        murl <- NA_character_
      }
      if (is.na(murl)) {
        murl <- NA_character_
      }
      media_id_vec   <- c(media_id_vec, pid)
      media_type_vec <- c(media_type_vec, mtype)
      media_url_vec  <- c(media_url_vec, murl)
      post_id_vec    <- c(post_id_vec, pid)
    }
  }

  list(
    media_id   = media_id_vec,
    media_type = media_type_vec,
    media_url  = media_url_vec,
    post_id    = post_id_vec
  )
}

#' Convert a media list to a tibble.
#'
# Takes the list output from `.rx_extract_media()` and builds
# a `tibble` with one row per media item. Column types are
# all character.
#'
#' @param media A list as returned by `.rx_extract_media()`.
#' @return A `tibble` with 4 columns matching the canonical media schema.
#'   Zero rows when `media` is empty.
#'
#' @noRd
.rx_media_to_tibble <- function(media) {
  if (!is.list(media) || length(media) == 0L) {
    return(tibble::tibble(
      media_id   = character(0),
      media_type = character(0),
      media_url  = character(0),
      post_id    = character(0)
    ))
  }

  # Guard: not enough fields.
  fields <- .rx_media_fields()
  if (!all(fields %in% names(media))) {
    return(tibble::tibble(
      media_id   = character(0),
      media_type = character(0),
      media_url  = character(0),
      post_id    = character(0)
    ))
  }

  # Detect row count.
  n <- length(media$media_id)
  if (n == 0L) {
    return(tibble::tibble(
      media_id   = character(0),
      media_type = character(0),
      media_url  = character(0),
      post_id    = character(0)
    ))
  }

  tibble::tibble(
    media_id   = as.character(media$media_id),
    media_type = as.character(media$media_type),
    media_url  = as.character(media$media_url),
    post_id    = as.character(media$post_id)
  )
}
