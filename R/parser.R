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
# Task 32 scope: add author identity fields (author_id, username, display_name).
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
#' Returns a list with five character vectors:
#'   - `post_id` — the tweet `rest_id`
#'   - `text` — the tweet `full_text`
#'   - `author_id` — the user `id` from core.user_results.result.id
#'   - `username` — the user `screen_name` from core.user_results.result.legacy
#'   - `display_name` — the user `name` from core.user_results.result.legacy
#'
#' Only entries that contain a valid `rest_id` are included.
#' Entries that lack the expected nesting (e.g. cursor entries,
#' promotional content, or malformed responses) are silently skipped.
#'
#' Missing author fields return `NA` rather than dropping the post.
#'
#' @param response A list, the parsed JSON response from X's GraphQL
#'   timeline endpoint. Expected structure: `data$timeline$instructions`.
#'
#' @return A list with:
#'   \itemize{
#'     \item `post_id` — character vector of tweet IDs
#'     \item `text` — character vector of tweet texts
#'     \item `author_id` — character vector of author IDs (NA when unavailable)
#'     \item `username` — character vector of usernames (NA when unavailable)
#'     \item `display_name` — character vector of display names (NA when unavailable)
#'   }
#'
#' @noRd
.rx_parse_posts <- function(response) {
  # Guard against non-list input.
  if (!is.list(response)) {
    return(list(
      post_id = character(0), text = character(0),
      author_id = character(0), username = character(0),
      display_name = character(0)
    ))
  }

  # Navigate to the instructions array.
  instructions <- response$data$timeline$instructions
  if (is.null(instructions) || !is.list(instructions)) {
    return(list(
      post_id = character(0), text = character(0),
      author_id = character(0), username = character(0),
      display_name = character(0)
    ))
  }

  # Collect posts across all instructions (there may be multiple
  # TimelineAddEntries blocks when pagination entries are merged).
  post_ids <- character(0)
  texts <- character(0)
  author_ids <- character(0)
  user_names <- character(0)
  disp_names <- character(0)

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
      if (is.null(rest_id) || anyNA(rest_id) || !is.character(rest_id) || !nzchar(rest_id)) {
        next
      }

      # Extract full_text.
      legacy <- result$legacy
      full_text <- if (is.list(legacy)) legacy$full_text else NULL
      if (is.null(full_text)) {
        full_text <- ""
      }

      # Extract author identity from core.user_results.result.
      author_id <- .rx_extract_author_id(result)
      username <- .rx_extract_username(result)
      display_name <- .rx_extract_display_name(result)

      # Coerce to character — X may return numeric ids; preserve as string.
      author_id_str <- if (is.null(author_id) || anyNA(author_id)) NA_character_ else as.character(author_id)

      post_ids <- c(post_ids, rest_id)
      texts <- c(texts, as.character(full_text))
      author_ids <- c(author_ids, author_id_str)
      user_names <- c(user_names, if (is.character(username)) username else NA_character_)
      disp_names <- c(disp_names, if (is.character(display_name)) display_name else NA_character_)
    }
  }

  list(
    post_id = post_ids,
    text = texts,
    author_id = author_ids,
    username = user_names,
    display_name = disp_names
  )
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

#' Extract author_id from a tweet result.
#'
#' Returns the user id from core.user_results.result.id, or NULL.
#'
#' @param result The tweet result list.
#' @return A character string or NULL.
#' @noRd
.rx_extract_author_id <- function(result) {
  if (!is.list(result)) return(NULL)
  core <- result$core
  if (is.null(core)) return(NULL)
  user_results <- core$user_results
  if (is.null(user_results)) return(NULL)
  user_result <- user_results$result
  if (is.null(user_result)) return(NULL)
  user_result$id
}

#' Extract username from a tweet result.
#'
#' Returns the screen_name from core.user_results.result.legacy, or NULL.
#'
#' @param result The tweet result list.
#' @return A character string or NULL.
#' @noRd
.rx_extract_username <- function(result) {
  if (!is.list(result)) return(NULL)
  core <- result$core
  if (is.null(core)) return(NULL)
  user_results <- core$user_results
  if (is.null(user_results)) return(NULL)
  user_result <- user_results$result
  if (is.null(user_result)) return(NULL)
  legacy <- user_result$legacy
  if (is.list(legacy)) legacy$screen_name else NULL
}

#' Extract display_name from a tweet result.
#'
#' Returns the name from core.user_results.result.legacy, or NULL.
#'
#' @param result The tweet result list.
#' @return A character string or NULL.
#' @noRd
.rx_extract_display_name <- function(result) {
  if (!is.list(result)) return(NULL)
  core <- result$core
  if (is.null(core)) return(NULL)
  user_results <- core$user_results
  if (is.null(user_results)) return(NULL)
  user_result <- user_results$result
  if (is.null(user_result)) return(NULL)
  legacy <- user_result$legacy
  if (is.list(legacy)) legacy$name else NULL
}
