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
# Task 33 scope: add timestamp (created_at).
# Task 34 scope: add engagement metrics (reply_count, repost_count, like_count, quote_count, bookmark_count, view_count).
# Task 35 scope: add relationship fields (conversation_id, is_reply, is_repost, is_quote, reply_to_post_id, quoted_post_id).
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
#' Returns a list with eighteen vectors:
#'   - `post_id` — the tweet `rest_id`
#'   - `text` — the tweet `full_text`
#'   - `author_id` — the user `id` from core.user_results.result.id
#'   - `username` — the user `screen_name` from core.user_results.result.legacy
#'   - `display_name` — the user `name` from core.user_results.result.legacy
#'   - `created_at` — the tweet `created_at` string from legacy (NA when unavailable)
#'   - `reply_count` — integer count of replies
#'   - `repost_count` — integer count of reposts (from `retweet_count`)
#'   - `like_count` — integer count of likes (from `favorite_count`)
#'   - `quote_count` — integer count of quotes
#'   - `bookmark_count` — integer count of bookmarks
#'   - `view_count` — integer count of views (from `views.count`)
#'   - `conversation_id` — the tweet `conversation_id_str` (character, NA when unavailable)
#'   - `is_reply` — logical, TRUE when `in_reply_to_status_id_str` is present
#'   - `is_repost` — logical, TRUE when `retweeted_status_id_str` is present
#'   - `is_quote` — logical, TRUE when `quoted_status_id_str` is present
#'   - `reply_to_post_id` — the tweet `in_reply_to_status_id_str` (character, NA when not a reply)
#'   - `quoted_post_id` — the tweet `quoted_status_id_str` (character, NA when not a quote)
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
#'     \item `created_at` — character vector of raw timestamp strings (NA when unavailable)
#'     \item `reply_count` — integer count of replies
#'     \item `repost_count` — integer count of reposts
#'     \item `like_count` — integer count of likes
#'     \item `quote_count` — integer count of quotes
#'     \item `bookmark_count` — integer count of bookmarks
#'     \item `view_count` — integer count of views
#'     \item `conversation_id` — character vector of conversation IDs (NA when unavailable)
#'     \item `is_reply` — logical vector, TRUE when the post is a reply
#'     \item `is_repost` — logical vector, TRUE when the post is a repost
#'     \item `is_quote` — logical vector, TRUE when the post is a quote
#'     \item `reply_to_post_id` — character vector of the post being replied to (NA when not a reply)
#'     \item `quoted_post_id` — character vector of the quoted post ID (NA when not a quote)
#'   }
#'
#' @noRd
.rx_parse_posts <- function(response) {
  # Guard against non-list input.
  if (!is.list(response)) {
    return(list(
      post_id = character(0), text = character(0),
      author_id = character(0), username = character(0),
      display_name = character(0), created_at = character(0),
      reply_count = integer(0), repost_count = integer(0),
      like_count = integer(0), quote_count = integer(0),
      bookmark_count = integer(0), view_count = integer(0),
      conversation_id = character(0),
      is_reply = logical(0), is_repost = logical(0), is_quote = logical(0),
      reply_to_post_id = character(0), quoted_post_id = character(0)
    ))
  }

  # Navigate to the instructions array.
  instructions <- response$data$timeline$instructions
  if (is.null(instructions) || !is.list(instructions)) {
    return(list(
      post_id = character(0), text = character(0),
      author_id = character(0), username = character(0),
      display_name = character(0), created_at = character(0),
      reply_count = integer(0), repost_count = integer(0),
      like_count = integer(0), quote_count = integer(0),
      bookmark_count = integer(0), view_count = integer(0),
      conversation_id = character(0),
      is_reply = logical(0), is_repost = logical(0), is_quote = logical(0),
      reply_to_post_id = character(0), quoted_post_id = character(0)
    ))
  }

  # Collect posts across all instructions (there may be multiple
  # TimelineAddEntries blocks when pagination entries are merged).
  post_ids <- character(0)
  texts <- character(0)
  author_ids <- character(0)
  user_names <- character(0)
  disp_names <- character(0)
  created_at <- character(0)
  reply_count <- integer(0)
  repost_count <- integer(0)
  like_count <- integer(0)
  quote_count <- integer(0)
  bookmark_count <- integer(0)
  view_count <- integer(0)
  conversation_ids <- character(0)
  is_reply <- logical(0)
  is_repost <- logical(0)
  is_quote <- logical(0)
  reply_to_post_ids <- character(0)
  quoted_post_ids <- character(0)

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

      # Extract created_at from legacy.
      created_at_str <- if (is.list(legacy) && !is.null(legacy$created_at)) {
        cat_val <- legacy$created_at
        if (is.null(cat_val) || anyNA(cat_val)) NA_character_ else as.character(cat_val)
      } else {
        NA_character_
      }

      # Extract engagement metrics.
      reply_count <- c(reply_count, .rx_extract_int(legacy, "reply_count"))
      repost_count <- c(repost_count, .rx_extract_int(legacy, "retweet_count"))
      like_count <- c(like_count, .rx_extract_int(legacy, "favorite_count"))
      quote_count <- c(quote_count, .rx_extract_int(legacy, "quote_count"))
      bookmark_count <- c(bookmark_count, .rx_extract_int(legacy, "bookmark_count"))
      view_count <- c(view_count, .rx_extract_view_count(legacy))

      # Extract relationship fields from legacy.
      conversation_ids <- c(conversation_ids,
        if (is.list(legacy) && !is.null(legacy$conversation_id_str)) {
          val <- legacy$conversation_id_str
          if (is.null(val) || anyNA(val)) NA_character_ else as.character(val)
        } else {
          NA_character_
        }
      )
      is_reply <- c(is_reply, .rx_extract_bool(legacy, "in_reply_to_status_id_str"))
      is_repost <- c(is_repost, .rx_extract_bool(legacy, "retweeted_status_id_str"))
      is_quote <- c(is_quote, .rx_extract_bool(legacy, "quoted_status_id_str"))
      reply_to_post_ids <- c(reply_to_post_ids,
        if (is.list(legacy) && !is.null(legacy$in_reply_to_status_id_str)) {
          val <- legacy$in_reply_to_status_id_str
          if (is.null(val) || anyNA(val)) NA_character_ else as.character(val)
        } else {
          NA_character_
        }
      )
      quoted_post_ids <- c(quoted_post_ids,
        if (is.list(legacy) && !is.null(legacy$quoted_status_id_str)) {
          val <- legacy$quoted_status_id_str
          if (is.null(val) || anyNA(val)) NA_character_ else as.character(val)
        } else {
          NA_character_
        }
      )

      post_ids <- c(post_ids, rest_id)
      texts <- c(texts, as.character(full_text))
      author_ids <- c(author_ids, author_id_str)
      user_names <- c(user_names, if (is.character(username)) username else NA_character_)
      disp_names <- c(disp_names, if (is.character(display_name)) display_name else NA_character_)
      created_at <- c(created_at, created_at_str)
    }
  }

  list(
    post_id = post_ids,
    text = texts,
    author_id = author_ids,
    username = user_names,
    display_name = disp_names,
    created_at = created_at,
    reply_count = reply_count,
    repost_count = repost_count,
    like_count = like_count,
    quote_count = quote_count,
    bookmark_count = bookmark_count,
    view_count = view_count,
    conversation_id = conversation_ids,
    is_reply = is_reply,
    is_repost = is_repost,
    is_quote = is_quote,
    reply_to_post_id = reply_to_post_ids,
    quoted_post_id = quoted_post_ids
  )
}

#' Extract an integer metric from legacy data.
#'
#' Returns the value as an integer when available, or 0L when missing.
#' X may return numeric or character — coerce safely.
#'
#' @param legacy The tweet$legacy list.
#' @param field The field name to extract (e.g. "reply_count").
#' @return An integer (0L when the field is missing or NA).
#' @noRd
.rx_extract_int <- function(legacy, field) {
  if (!is.list(legacy)) return(0L)
  val <- legacy[[field]]
  if (is.null(val) || anyNA(val)) return(0L)
  as.integer(val)
}

#' Extract view count from legacy data.
#'
#' Views are nested under legacy$views$count in X's response.
#' Returns 0L when the full nesting is absent.
#'
#' @param legacy The tweet$legacy list.
#' @return An integer (0L when views are missing).
#' @noRd
.rx_extract_view_count <- function(legacy) {
  if (!is.list(legacy)) return(0L)
  views <- legacy$views
  if (is.null(views) || !is.list(views)) return(0L)
  count <- views$count
  if (is.null(count) || anyNA(count)) return(0L)
  as.integer(count)
}

#' Extract a boolean flag from legacy data.
#'
#' Returns TRUE when the named field exists, is not NULL, and is not NA.
#' Returns FALSE otherwise (missing field, NULL, or NA).
#'
#' @param legacy The tweet$legacy list.
#' @param field The field name to check (e.g. "in_reply_to_status_id_str").
#' @return A single logical (FALSE when the field is missing or NA).
#' @noRd
.rx_extract_bool <- function(legacy, field) {
  if (!is.list(legacy)) return(FALSE)
  val <- legacy[[field]]
  isTRUE(val)
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
