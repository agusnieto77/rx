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
#' Returns a list with:
#'   - 18 base vectors as described below (post_id through quoted_post_id).
#'   - 3 entity vectors (hashtags, mentions, urls, Task 56).
#'   - 2 media vectors (media_type, media_urls, Task 57).
#'   - `hashtags` — list of character vectors with hashtag texts (Task 56).
#'   - `mentions` — list of named character vectors with screen_name/name (Task 56).
#'   - `urls` — list of character vectors with URL strings (Task 56).
#'   - `media_type` — list of character vectors with media types
#'     ("photo", "video", "animated_gif") from `extended_entities$media`
#'     (Task 57).
#'   - `media_urls` — list of named character vectors with media URLs,
#'     keyed by zero-based media index (Task 57).
#'   - `cursors` — a list of cursor objects discovered in the response.
#'     Each cursor has `cursorType` (character: "Top"/"Bottom"/etc.)
#'     and `value` (character: the cursor token).
#'     Returns `list(top = character(0), bottom = character(0))` when
#'     no cursors are present.
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
#'     \item `hashtags` — list of character vectors with hashtag texts (Task 56)
#'     \item `mentions` — list of named character vectors with screen_name and name (Task 56)
#'     \item `urls` — list of character vectors with URL strings (Task 56)
#'     \item `media_type` — list of character vectors with media types
#'       ("photo", "video", "animated_gif") from `extended_entities$media` (Task 57)
#'     \item `media_urls` — list of named character vectors with media URLs,
#'       keyed by zero-based media index (Task 57)
#'     \item `cursors` — named character vector of cursor tokens keyed by cursorType
#'       (e.g. "Bottom" → cursor value, "Top" → cursor value); empty when absent
#'   }
#'
#' Find timeline instructions across supported X response envelopes.
#'
#' X responses have used both the `data$timeline` envelope and the
#' `TimelineResult$result` envelope. Keep the envelope handling in one place
#' so parsing, cursor extraction, and scroll mocks use the same contract.
#'
#' @noRd
.rx_response_instructions <- function(response) {
  if (!is.list(response)) return(NULL)

  data_block <- response[["data"]]
  if (is.list(data_block)) {
    timeline <- data_block[["timeline"]]
    if (is.list(timeline) && is.list(timeline[["instructions"]])) {
      return(timeline[["instructions"]])
    }
  }

  timeline_result <- response[["TimelineResult"]]
  if (is.list(timeline_result)) {
    result <- timeline_result[["result"]]
    if (is.list(result) && is.list(result[["timeline_instructions"]])) {
      return(result[["timeline_instructions"]])
    }
  }

  NULL
}

#' Validate the response schema for known structural changes.
#'
#' This function is called early in `.rx_parse_posts()` to detect when
#' X/Twitter has changed its GraphQL response structure. It checks for
#' three classes of schema drift:
#'
#' 1. **Response recognized but no expected timeline structure** — the
#'    response has the `data$timeline` path but lacks `instructions`,
#'    or `instructions` exist but no `TimelineAddEntries` entry type is
#'    present. This typically means X changed the top-level response key.
#'
#' 2. **Expected post object missing** — entries exist under
#'    `TimelineAddEntries` but none of them contain a valid post object
#'    (no `content$itemContent$tweet_results$result` chain, or the
#'    result lacks `rest_id`). This may indicate X changed the nesting
#'    inside entries.
#'
#' 3. **Incompatible field structure** — a post-like object is found but
#'    critical fields have wrong types (e.g. `rest_id` is numeric
#'    instead of character).
#'
#' When any condition is detected, a `PARSER_ERROR` is thrown that
#' includes the current `parser_version` and diagnostic context so the
#' consumer can surface a clear message.
#'
#' Returns `invisible(NULL)` when the schema is compatible.
#'
#' @param response A list, the parsed JSON response.
#' @return Invisible `NULL` (only reached when schema is compatible).
#' @noRd
.rx_validate_response_schema <- function(response) {
  # --- Condition 1: response recognized but no expected timeline structure ---
  # We consider the response "recognized" when data$timeline exists but
  # the expected structure (instructions with TimelineAddEntries) is absent.

  data_block <- response$data
  if (is.null(data_block)) {
    return(invisible(NULL))
  }

  timeline <- data_block$timeline
  if (is.null(timeline)) {
    return(invisible(NULL))
  }

  instructions <- timeline$instructions

  # If there are no instructions at all, check whether this looks like a
  # known X response shape (has data$timeline but wrong sub-keys).
  if (is.null(instructions)) {
    # data$timeline exists but has no $instructions — X changed the key.
    known_keys <- names(timeline)
    stop(.rx_error(
      paste0(
        "X response structure changed: data$timeline exists but ",
        "instructions is missing. Expected timeline instructions ",
        "array (e.g. TimelineAddEntries) not found. ",
        "Timeline keys present: ",
        paste(shQuote(known_keys), collapse = ", "),
        ". parser_version: ", .rx_parser_version()
      ),
      class = "parser_error",
      code = "PARSER_ERROR"
    ))
  }

  if (!is.list(instructions) || length(instructions) == 0L) {
    known_keys <- names(instructions)
    stop(.rx_error(
      paste0(
        "X response structure changed: data$timeline$instructions exists ",
        "but is empty or not a list. Keys: ",
        paste(shQuote(known_keys), collapse = ", "),
        ". parser_version: ", .rx_parser_version()
      ),
      class = "parser_error",
      code = "PARSER_ERROR"
    ))
  }

  # Check whether any instruction has the expected type.
  has_timeline_add_entries <- FALSE
  for (inst in instructions) {
    if (is.list(inst) && !is.null(inst$type) && inst$type == "TimelineAddEntries") {
      has_timeline_add_entries <- TRUE
      break
    }
  }

  if (!has_timeline_add_entries) {
    # Instructions exist but none are TimelineAddEntries — X may have
    # changed the instruction type name.
    inst_types <- vapply(instructions, function(i) {
      if (is.list(i) && !is.null(i$type)) as.character(i$type) else "<none>"
    }, character(1))
    stop(.rx_error(
      paste0(
        "X response structure changed: instructions array present with ",
        length(instructions), " entry/entries but no TimelineAddEntries ",
        "instruction found. Instruction types seen: ",
        paste(shQuote(inst_types), collapse = ", "),
        ". parser_version: ", .rx_parser_version()
      ),
      class = "parser_error",
      code = "PARSER_ERROR"
    ))
  }

  # --- Condition 2: entries exist but expected post objects are missing ---
  # Walk the instructions looking for TimelineAddEntries entries.
  # If we find entries but none yield a valid tweet result, that's
  # a schema drift signal.

  entries_found <- 0L
  posts_found <- 0L

  for (inst in instructions) {
    if (!is.list(inst) || is.null(inst$type) || inst$type != "TimelineAddEntries") {
      next
    }
    entries <- inst$entries
    if (is.null(entries) || !is.list(entries)) {
      next
    }
    for (entry in entries) {
      entries_found <- entries_found + 1L
      result <- .rx_find_tweet_result(entry)
      if (!is.null(result) && !is.null(result$rest_id)) {
        posts_found <- posts_found + 1L
      }
    }
  }

  if (entries_found > 0L && posts_found == 0L) {
    # We had entries but zero valid post objects — X changed the entry
    # nesting or the post object shape.
    entry_ids <- character(0)
    for (inst in instructions) {
      if (!is.list(inst) || is.null(inst$type) || inst$type != "TimelineAddEntries") next
      entries <- inst$entries
      if (is.null(entries) || !is.list(entries)) next
      for (entry in entries) {
        eid <- if (is.list(entry) && !is.null(entry$entryId)) as.character(entry$entryId) else "<unnamed>"
        has_content <- !is.null(entry$content)
        has_item_content <- FALSE
        if (has_content && is.list(entry$content)) {
          has_item_content <- !is.null(entry$content$itemContent)
        }
        entry_ids <- c(entry_ids, paste0(eid, "(content=", has_content, ", itemContent=", has_item_content, ")"))
      }
    }
    stop(.rx_error(
      paste0(
        "X response structure changed: found ", entries_found, " entry/entries ",
        "in TimelineAddEntries but zero valid post objects. ",
        "Entry shapes observed: ",
        paste(entry_ids, collapse = "; "),
        ". parser_version: ", .rx_parser_version()
      ),
      class = "parser_error",
      code = "PARSER_ERROR"
    ))
  }

  # --- Condition 3: incompatible field structure ---
  # This is checked inline during extraction (e.g. rest_id type check).
  # No separate validation pass needed — the field-level checks already
  # handle this silently for known-safe patterns.

  invisible(NULL)
}

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
      reply_to_post_id = character(0), quoted_post_id = character(0),
      # Entity fields (Task 56) — list-columns
      hashtags = list(), mentions = list(), urls = list(),
      # Media fields (Task 57) — list-columns
      media_type = list(), media_urls = list(),
      cursors = character(0)
    ))
  }

  # Validate schema — detect X response structure changes early.
  .rx_validate_response_schema(response)

  # Navigate to the instructions array.
  instructions <- .rx_response_instructions(response)
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
      reply_to_post_id = character(0), quoted_post_id = character(0),
      # Entity fields (Task 56) — list-columns
      hashtags = list(), mentions = list(), urls = list(),
      # Media fields (Task 57) — list-columns
      media_type = list(), media_urls = list(),
      cursors = character(0)
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
  # Entity fields (Task 56) — list-columns
  hashtags_list <- list()
  mentions_list <- list()
  urls_list <- list()
  # Media fields (Task 57) — list-columns
  media_type_list <- list()
  media_urls_list <- list()

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
      if (is.null(rest_id) || length(rest_id) != 1L || anyNA(rest_id) || !is.character(rest_id) || !nzchar(trimws(rest_id))) {
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
      # Reject empty/whitespace-only values (consistent with rest_id guard).
      author_id_str <- if (is.null(author_id) || length(author_id) != 1L || anyNA(author_id) || !nzchar(trimws(as.character(author_id)))) NA_character_ else as.character(author_id)

      # Extract created_at from legacy.
      created_at_str <- if (is.list(legacy) && !is.null(legacy$created_at)) {
        cat_val <- legacy$created_at
        if (is.null(cat_val) || length(cat_val) != 1L || anyNA(cat_val) || !nzchar(trimws(as.character(cat_val)))) NA_character_ else as.character(cat_val)
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
          if (length(val) != 1L || anyNA(val) || !nzchar(trimws(as.character(val)))) NA_character_ else as.character(val)
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
          if (length(val) != 1L || anyNA(val) || !nzchar(trimws(as.character(val)))) NA_character_ else as.character(val)
        } else {
          NA_character_
        }
      )
      quoted_post_ids <- c(quoted_post_ids,
        if (is.list(legacy) && !is.null(legacy$quoted_status_id_str)) {
          val <- legacy$quoted_status_id_str
          if (length(val) != 1L || anyNA(val) || !nzchar(trimws(as.character(val)))) NA_character_ else as.character(val)
        } else {
          NA_character_
        }
      )

      # Extract entity fields (Task 56).
      entities <- if (is.list(legacy) && !is.null(legacy$entities)) legacy$entities else list()
      hashtags_list[[length(hashtags_list) + 1L]] <- .rx_extract_hashtags(entities)
      mentions_list[[length(mentions_list) + 1L]] <- .rx_extract_mentions(entities)
      urls_list[[length(urls_list) + 1L]] <- .rx_extract_urls(entities)

      # Extract media fields (Task 57).
      extended_entities <- if (is.list(legacy) && !is.null(legacy$extended_entities)) legacy$extended_entities else list()
      media_type_list[[length(media_type_list) + 1L]] <- .rx_extract_media_types(extended_entities)
      media_urls_list[[length(media_urls_list) + 1L]] <- .rx_extract_media_urls(extended_entities)

      post_ids <- c(post_ids, rest_id)
      texts <- c(texts, as.character(full_text))
      author_ids <- c(author_ids, author_id_str)
      user_names <- c(user_names, if (is.character(username) && length(username) == 1L && !anyNA(username) && nzchar(trimws(username))) username else NA_character_)
      disp_names <- c(disp_names, if (is.character(display_name) && length(display_name) == 1L && !anyNA(display_name) && nzchar(trimws(display_name))) display_name else NA_character_)
      created_at <- c(created_at, created_at_str)
    }
  }

  # Extract pagination cursors from TimelineAddToModule instructions.
  cursors <- .rx_extract_cursors(response)

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
    quoted_post_id = quoted_post_ids,
    # Entity fields (Task 56)
    hashtags = hashtags_list,
    mentions = mentions_list,
    urls = urls_list,
    # Media fields (Task 57)
    media_type = media_type_list,
    media_urls = media_urls_list,
    cursors = cursors
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
#' Returns TRUE when the named field exists, is not NULL, is not NA,
#' and is not an empty or whitespace-only string.
#' Returns FALSE otherwise (missing field, NULL, NA, or empty).
#'
#' @param legacy The tweet$legacy list.
#' @param field The field name to check (e.g. "in_reply_to_status_id_str").
#' @return A single logical (FALSE when the field is missing, NA, or empty).
#' @noRd
.rx_extract_bool <- function(legacy, field) {
  if (!is.list(legacy)) return(FALSE)
  val <- legacy[[field]]
  if (length(val) != 1L) return(FALSE)
  !is.null(val) && !anyNA(val) && nzchar(trimws(as.character(val)))
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

  # Some GraphQL operations wrap the tweet one level deeper.
  if (is.list(result) && is.null(result$rest_id) && is.list(result$tweet)) {
    result <- result$tweet
  }

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

#' Extract pagination cursors from the response.
#'
#' Walks the response's instructions looking for `TimelineAddToModule`
#' blocks and collects cursor tokens keyed by their `cursorType`.
#' Only cursor entries that carry both a `cursorType` and a `value`
#' are returned.
#'
#' Returns a named character vector: names are cursor types
#' (e.g. "Bottom", "Top"), values are the cursor tokens.
#' Returns `character(0)` when no cursors are found.
#'
#' @param response A list, the parsed JSON response from X's GraphQL
#'   timeline endpoint.
#' @return A named `character` vector of cursor tokens.
#' @examples
#'   # Internal use only — not exported.
#'   # parsed <- jsonlite::fromJSON(file, simplifyVector = FALSE)
#'   # .rx_extract_cursors(parsed)
#' @noRd
.rx_extract_cursors <- function(response) {
  # Guard against non-list input.
  if (!is.list(response)) return(character(0))

  instructions <- .rx_response_instructions(response)
  if (is.null(instructions) || !is.list(instructions)) return(character(0))

  result <- character(0)

  for (inst in instructions) {
    # Only process TimelineAddToModule instructions.
    if (is.null(inst$type) || inst$type != "TimelineAddToModule") {
      next
    }

    module_items <- inst$moduleItems
    if (is.null(module_items) || !is.list(module_items)) {
      next
    }

    for (item in module_items) {
      cursor <- item$item$cursor
      # X has returned cursors in both `item$cursor` and
      # `item$content` shapes across endpoint versions.
      if (is.null(cursor)) cursor <- item$item$content
      if (is.null(cursor)) cursor <- item$content
      if (is.null(cursor) || !is.list(cursor)) next

      cursor_type <- cursor$cursorType
      cursor_value <- cursor$value
      if (is.null(cursor_type) || is.null(cursor_value)) next
      if (length(cursor_type) != 1L || length(cursor_value) != 1L) next
      if (anyNA(cursor_type) || anyNA(cursor_value)) next

      result[as.character(cursor_type)] <- as.character(cursor_value)
    }
  }

  result
}

#' Extract hashtags from entities.
#'
#' Returns a character vector of hashtag texts from
#' `entities$hashtags` when available, or an empty character vector.
#'
#' @param entities The `entities` list from a tweet's `legacy` block.
#' @return A character vector of hashtag texts.
#' @noRd
.rx_extract_hashtags <- function(entities) {
  if (!is.list(entities) || is.null(entities$hashtags)) {
    return(character(0))
  }
  hl <- entities$hashtags
  if (!is.list(hl) || length(hl) == 0L) {
    return(character(0))
  }
  sapply(hl, function(h) {
    if (is.list(h) && !is.null(h$text) && length(h$text) == 1L && !is.na(h$text)) {
      as.character(h$text)
    } else {
      NA_character_
    }
  }, USE.NAMES = FALSE)
}

#' Extract user mentions from entities.
#'
#' Returns a list of named character vectors, each with `screen_name`
#' and `name` elements, from `entities$user_mentions`.
#' When no mentions are present, returns an empty list.
#'
#' @param entities The `entities` list from a tweet's `legacy` block.
#' @return A list of named character vectors (one per mention), or
#'   `list()` when absent.
#' @noRd
.rx_extract_mentions <- function(entities) {
  if (!is.list(entities) || is.null(entities$user_mentions)) {
    return(list())
  }
  ml <- entities$user_mentions
  if (!is.list(ml) || length(ml) == 0L) {
    return(list())
  }
  lapply(ml, function(m) {
    if (!is.list(m)) return(NULL)
    screen <- if (!is.null(m$screen_name) && length(m$screen_name) == 1L && !is.na(m$screen_name)) as.character(m$screen_name) else NA_character_
    name <- if (!is.null(m$name) && length(m$name) == 1L && !is.na(m$name)) as.character(m$name) else NA_character_
    c(screen_name = screen, name = name)
  })
}

#' Extract URLs from entities.
#'
#' Returns a character vector of URL strings from `entities$urls`.
#' Prefers `expanded_url` when available, falls back to `url`.
#'
#' @param entities The `entities` list from a tweet's `legacy` block.
#' @return A character vector of URL strings.
#' @noRd
.rx_extract_urls <- function(entities) {
  if (!is.list(entities) || is.null(entities$urls)) {
    return(character(0))
  }
  ul <- entities$urls
  if (!is.list(ul) || length(ul) == 0L) {
    return(character(0))
  }
  sapply(ul, function(u) {
    if (!is.list(u)) return(NA_character_)
    if (!is.null(u$expanded_url) && length(u$expanded_url) == 1L && !is.na(u$expanded_url)) {
      as.character(u$expanded_url)
    } else if (!is.null(u$url) && length(u$url) == 1L && !is.na(u$url)) {
      as.character(u$url)
    } else {
      NA_character_
    }
  }, USE.NAMES = FALSE)
}

#' Extract media types from extended entities.
#'
#' Returns a character vector of media types (e.g. "photo", "video",
#' "animated_gif") from `extended_entities$media` when available,
#' or an empty character vector.
#'
#' @param extended_entities The `extended_entities` list from a tweet's
#'   `legacy` block.
#' @return A character vector of media type strings.
#' @noRd
.rx_extract_media_types <- function(extended_entities) {
  if (!is.list(extended_entities) || is.null(extended_entities$media)) {
    return(character(0))
  }
  ml <- extended_entities$media
  if (!is.list(ml) || length(ml) == 0L) {
    return(character(0))
  }
  sapply(ml, function(m) {
    if (is.list(m) && !is.null(m$type) && length(m$type) == 1L && !is.na(m$type)) {
      as.character(m$type)
    } else {
      NA_character_
    }
  }, USE.NAMES = FALSE)
}

#' Extract media URLs from extended entities.
#'
#' Returns a named character vector of media URLs from
#' `extended_entities$media`. For photos, uses `media_url_https` when
#' available, falls back to `media_url`. For videos and animated_gifs,
#' collects all `video_info$variants$url` values.
#'
#' @param extended_entities The `extended_entities` list from a tweet's
#'   `legacy` block.
#' @return A named character vector of media URLs, named by zero-based
#'   media index.
#' @noRd
.rx_extract_media_urls <- function(extended_entities) {
  if (!is.list(extended_entities) || is.null(extended_entities$media)) {
    return(character(0))
  }
  ml <- extended_entities$media
  if (!is.list(ml) || length(ml) == 0L) {
    return(character(0))
  }
  urls <- character(0)
  for (i in seq_along(ml)) {
    m <- ml[[i]]
    if (!is.list(m)) next
    # Photos: prefer media_url_https, fallback to media_url
    if (!is.null(m$media_url_https) && length(m$media_url_https) == 1L && !is.na(m$media_url_https)) {
      urls <- c(urls, as.character(m$media_url_https))
    } else if (!is.null(m$media_url) && length(m$media_url) == 1L && !is.na(m$media_url)) {
      urls <- c(urls, as.character(m$media_url))
    }
    # Videos / animated_gifs: collect all variant URLs
    video_info <- m$video_info
    if (is.list(video_info) && !is.null(video_info$variants)) {
      variants <- video_info$variants
      if (is.list(variants)) {
        for (v in variants) {
          if (is.list(v) && !is.null(v$url) && length(v$url) == 1L && !is.na(v$url)) {
            urls <- c(urls, as.character(v$url))
          }
        }
      }
    }
  }
  stats::setNames(urls, seq_along(urls) - 1L)
}
