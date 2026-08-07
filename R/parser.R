# Internal: X search response post parser
#
# This module parses the X/Twitter GraphQL search response structure
# to discover post objects. The X timeline response nests tweet data
# inside a multi-level hierarchy:
#
#   data > timeline > instructions > entries[] > content > itemContent >
#     tweet_results > result > { rest_id, legacy{ full_text, ... } }
#
# Task 31 scope: extract only post_id (rest_id) and text (full_text).
# Later tasks will add author, timestamps, metrics, etc.
#
# @name parser
# @aliases parser
# @keywords internal
# @examples
#   # Internal use only — not exported.
#   # parsed <- jsonlite::fromJSON(file, simplifyVector = FALSE)
#   # .rx_parse_posts(parsed)
NULL

#' Parse post objects from an X search response.
#'
# Takes a parsed X GraphQL search response (the shape produced by
# `jsonlite::fromJSON(..., simplifyVector = FALSE)` on the timeline JSON)
# and walks the instruction/entry tree to find tweet entries.
#'
#' Returns a list with two character vectors:
#'   - `post_id` — the tweet `rest_id`
#'   - `text` — the tweet `full_text`
#'
#' Only entries that contain a valid `rest_id` are included.
#' Entries that lack the expected nesting (e.g. cursor entries,
#' promotional content, or malformed responses) are silently skipped.
#'
#' @param response A list, the parsed JSON response from X's GraphQL
#'   timeline endpoint. Expected structure: `data$timeline$instructions`.
#'
#' @return A list with:
#'   \itemize{
#'     \item `post_id` — character vector of tweet IDs
#'     \item `text` — character vector of tweet texts
#'   }
#'
#' @noRd
.rx_parse_posts <- function(response) {
  # Guard against non-list input.
  if (!is.list(response)) {
    return(list(post_id = character(0), text = character(0)))
  }

  # Navigate to the instructions array.
  instructions <- response$data$timeline$instructions
  if (is.null(instructions) || !is.list(instructions)) {
    return(list(post_id = character(0), text = character(0)))
  }

  # Collect posts across all instructions (there may be multiple
  # TimelineAddEntries blocks when pagination entries are merged).
  post_ids <- character(0)
  texts <- character(0)

  for (inst in instructions) {
    # Only process TimelineAddEntries instructions.
    if (is.null(inst$type) || inst$type != "TimelineAddEntries") {
      next
    }

    entries <- inst$entries
    if (is.null(entries) || !is.list(entries)) {
      next
    }

    for (entry in entries) {
      # Navigate the nesting: entry > content > itemContent > tweet_results > result
      result <- .rx_find_tweet_result(entry)
      if (is.null(result)) {
        next
      }

      # Extract rest_id (post_id).
      rest_id <- result$rest_id
      if (is.null(rest_id) || !is.character(rest_id) || !nzchar(rest_id)) {
        next
      }

      # Extract full_text.
      legacy <- result$legacy
      full_text <- if (is.list(legacy)) legacy$full_text else NULL
      if (is.null(full_text)) {
        full_text <- ""
      }

      post_ids <- c(post_ids, rest_id)
      texts <- c(texts, as.character(full_text))
    }
  }

  list(post_id = post_ids, text = texts)
}

#' Find the tweet result object inside an entry.
#'
#' Returns `entry$content$itemContent$tweet_results$result` when the
#' expected nesting is present, or `NULL` otherwise.
#'
#' @param entry A list, one element from an instructions$entries array.
#' @return A list (the result object) or NULL.
#' @noRd
.rx_find_tweet_result <- function(entry) {
  if (!is.list(entry)) return(NULL)

  content <- entry$content
  if (is.null(content)) return(NULL)

  item_content <- content$itemContent
  if (is.null(item_content)) return(NULL)

  tweet_results <- item_content$tweet_results
  if (is.null(tweet_results)) return(NULL)

  result <- tweet_results$result
  if (is.null(result)) return(NULL)

  result
}
