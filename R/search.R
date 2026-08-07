# Internal helpers for x_search()
#
# This module implements `x_search()` and its supporting internal functions.
# The search pipeline:
#   1. Enable network capture on the session backend
#   2. Construct the X search URL and navigate
#   3. Wait for network responses to settle
#   4. Retrieve captured network events and extract posts (initial batch)
#   5. Repeat: scroll, wait for new network responses, extract posts
#      — stop on limit, max_scrolls, or no-new-data cycles (Task 42)
#   6. Merge all batches, normalize, convert to tibble, deduplicate
#   7. Apply limit and return
#
# Scroll state (Task 41, Task 42):
#   A scroll state object tracks collection progress across batches.
#   It records seen post IDs, counts, cursors, scroll position, and timing
#   so that repeated-scrolling loops can detect termination conditions
#   (limit hit, max_scrolls exceeded, no-new-data stall) without relying
#   on implicit loop variables.
#
# @name search
# @aliases search
# @keywords internal
# @examples
#   # Public API:
#   # sess <- x_session()
#   # posts <- x_search(sess, "r programming")
#   # x_close(sess)
NULL

#' Search X/Twitter for posts matching a query.
#'
#' Navigates to an X search results page, captures structured network
#' responses, parses and normalizes post objects, deduplicates by
#' \code{post_id}, and returns a tibble of results.
#'
#' This is the first end-to-end search function. It connects the session
#' backend, network capture, post parser, normalizer, and deduplicator
#' into a single call.
#'
#' The collection uses bounded repeated scrolling (Task 42): after the
#' initial extraction, the page is scrolled and new content extracted in a
#' loop. The loop stops when any of the following conditions is met:
#' - the \code{limit} is reached,
#' - \code{max_scrolls} scroll iterations have been completed,
#' - no new data appears for two consecutive batches (stall detection).
#'
#' @param session An \code{xtweetsR_session} object returned by
#'   \code{\link[=x_session]{x_session()}}.
#' @param query A single non-empty character string with the search query.
#' @param limit Optional integer limiting the maximum number of posts
#'   returned. When \code{NULL} (default), no limit is applied.
#' @param scroll Logical, default `TRUE`. When `FALSE`, no scrolling is
#'   performed and only the initially visible content is captured.
#' @param max_scrolls Integer, default `5L`. When \code{scroll = TRUE},
#'   the maximum number of scroll+extract iterations to perform.
#'   The loop also stops earlier if the \code{limit} is reached or if
#'   no new data appears for two consecutive batches.
#'
#' @return A tibble with the canonical post schema (18 columns) containing
#'   posts found during the search. Returns a zero-row tibble when no
#'   posts are captured.
#'
#' @examples
#' \dontrun{
#'   sess <- x_session()
#'   posts <- x_search(sess, "r programming", limit = 10)
#'   print(posts)
#'   x_close(sess)
#' }
#'
#' @export
x_search <- function(session, query, limit = NULL, scroll = TRUE, max_scrolls = 5L) {
  # 1. Validate inputs.
  if (!inherits(session, "xtweetsR_session")) {
    stop("session must be an xtweetsR_session object.", call. = FALSE)
  }
  if (!session$connected) {
    stop("Session is not connected. Call x_session() first.", call. = FALSE)
  }
  if (!is.character(query) || length(query) != 1L || anyNA(query) || !nzchar(trimws(query))) {
    stop("query must be a single non-empty character string.", call. = FALSE)
  }
  if (!is.null(limit)) {
    if (!is.numeric(limit) || length(limit) != 1L || anyNA(limit) || limit < 1L) {
      stop("limit must be a positive integer, or NULL.", call. = FALSE)
    }
    limit <- as.integer(limit)
  }
  if (!is.numeric(max_scrolls) || length(max_scrolls) != 1L || anyNA(max_scrolls) || max_scrolls < 0L) {
    stop("max_scrolls must be a non-negative integer, or NULL.", call. = FALSE)
  }
  max_scrolls <- as.integer(max_scrolls)

  backend <- session$backend

  # 2. Enable network capture before navigation.
  tryCatch(
    backend$networkCaptureEnable(),
    error = function(e) {
      stop("Failed to enable network capture: ", e$message, call. = FALSE)
    }
  )

  # 3. Construct search URL and navigate.
  url <- .rx_construct_search_url(query)

  nav_result <- backend$navigate(url)
  if (is.null(nav_result$status) || nav_result$status == "error") {
    # Navigation failed — still try to return what we can.
    error_info <- if (!is.null(nav_result$error)) nav_result$error$code else "unknown"
    .rx_search_cleanup(backend)
    warning("Navigation failed (", error_info, "). No posts returned.")
    return(.rx_search_empty_tibble())
  }

  # 4. Wait for initial network responses to arrive (X search loads content
  #    asynchronously via XHR/GraphQL). A short wait is more reliable
  #    than polling for specific response types.
  Sys.sleep(3)

  # 5. Create scroll state and retrieve initial batch.
  state <- .rx_scroll_state_new()

  initial_events <- tryCatch(
    backend$networkCaptureGet(),
    error = function(e) {
      .rx_search_cleanup(backend)
      warning("Failed to retrieve network events: ", e$message)
      return(list())
    }
  )

  initial_posts <- .rx_search_extract_from_events(initial_events, backend)
  state$add_posts(initial_posts)

  # 6. Bounded repeated scroll+extract loop (Task 42).
  #
  #    The loop iterates at most max_scrolls times. After each iteration:
  #    - If the limit is reached, we stop.
  #    - If no new data appears for two consecutive batches, we stop.
  #    - After max_scrolls iterations, we stop.
  #
  #    Each iteration scrolls the page, waits for new network responses,
  #    extracts posts, and accumulates them into all_batches.
  all_batches <- list()
  if (isTRUE(scroll) && max_scrolls > 0L) {
    for (i in seq_len(max_scrolls)) {
      # Scroll the page.
      .rx_scroll_page(backend)
      state$advance_scroll()

      # Wait for new network responses triggered by the scroll.
      Sys.sleep(3)

      # Capture events and extract posts (new batch).
      batch_events <- tryCatch(
        backend$networkCaptureGet(),
        error = function(e) list()
      )

      extracted <- .rx_search_extract_from_events(batch_events, backend)

      # Record in scroll state (dedup, stall detection).
      state$add_posts(extracted)

      # Accumulate batch for later merging.
      if (length(extracted$post_id) > 0L) {
        all_batches[[length(all_batches) + 1L]] <- extracted
      } else {
        # Track zero-length batch to maintain consistent field structure.
        zero_batch <- .rx_search_empty_batch()
        all_batches[[length(all_batches) + 1L]] <- zero_batch
      }

      # Check termination conditions.
      if (!is.null(limit) && state$current_count >= limit) {
        break
      }
      if (state$check_stalled(threshold = 2L)) {
        break
      }
    }
  }

  # 7. Merge all batches (initial + scroll batches).
  if (length(all_batches) > 0L) {
    all_post_ids <- lapply(all_batches, `[[`, "post_id")
    all_texts <- lapply(all_batches, `[[`, "text")
    all_author_ids <- lapply(all_batches, `[[`, "author_id")
    all_usernames <- lapply(all_batches, `[[`, "username")
    all_display_names <- lapply(all_batches, `[[`, "display_name")
    all_created_at <- lapply(all_batches, `[[`, "created_at")
    all_reply_counts <- lapply(all_batches, `[[`, "reply_count")
    all_repost_counts <- lapply(all_batches, `[[`, "repost_count")
    all_like_counts <- lapply(all_batches, `[[`, "like_count")
    all_quote_counts <- lapply(all_batches, `[[`, "quote_count")
    all_bookmark_counts <- lapply(all_batches, `[[`, "bookmark_count")
    all_view_counts <- lapply(all_batches, `[[`, "view_count")
    all_conversation_ids <- lapply(all_batches, `[[`, "conversation_id")
    all_is_replies <- lapply(all_batches, `[[`, "is_reply")
    all_is_reposts <- lapply(all_batches, `[[`, "is_repost")
    all_is_quotes <- lapply(all_batches, `[[`, "is_quote")
    all_reply_to_ids <- lapply(all_batches, `[[`, "reply_to_post_id")
    all_quoted_ids <- lapply(all_batches, `[[`, "quoted_post_id")

    merged_posts <- list(
      post_id        = unlist(all_post_ids, use.names = FALSE),
      text           = unlist(all_texts, use.names = FALSE),
      author_id      = unlist(all_author_ids, use.names = FALSE),
      username       = unlist(all_usernames, use.names = FALSE),
      display_name   = unlist(all_display_names, use.names = FALSE),
      created_at     = unlist(all_created_at, use.names = FALSE),
      reply_count    = unlist(all_reply_counts, use.names = FALSE),
      repost_count   = unlist(all_repost_counts, use.names = FALSE),
      like_count     = unlist(all_like_counts, use.names = FALSE),
      quote_count    = unlist(all_quote_counts, use.names = FALSE),
      bookmark_count = unlist(all_bookmark_counts, use.names = FALSE),
      view_count     = unlist(all_view_counts, use.names = FALSE),
      conversation_id = unlist(all_conversation_ids, use.names = FALSE),
      is_reply       = unlist(all_is_replies, use.names = FALSE),
      is_repost      = unlist(all_is_reposts, use.names = FALSE),
      is_quote       = unlist(all_is_quotes, use.names = FALSE),
      reply_to_post_id = unlist(all_reply_to_ids, use.names = FALSE),
      quoted_post_id   = unlist(all_quoted_ids, use.names = FALSE)
    )
  } else {
    # No batches collected at all (scroll=FALSE, no initial posts).
    merged_posts <- list(
      post_id        = character(0),
      text           = character(0),
      author_id      = character(0),
      username       = character(0),
      display_name   = character(0),
      created_at     = character(0),
      reply_count    = integer(0),
      repost_count   = integer(0),
      like_count     = integer(0),
      quote_count    = integer(0),
      bookmark_count = integer(0),
      view_count     = integer(0),
      conversation_id = character(0),
      is_reply       = logical(0),
      is_repost      = logical(0),
      is_quote       = logical(0),
      reply_to_post_id = character(0),
      quoted_post_id   = character(0)
    )
  }

  # 8. Normalize, convert to tibble, deduplicate.
  normalized <- .rx_normalize_posts(merged_posts)
  tibble_posts <- .rx_normalized_to_tibble(normalized)
  deduped <- .rx_deduplicate_posts(tibble_posts)

  # 9. Apply limit.
  if (!is.null(limit) && nrow(deduped) > limit) {
    deduped <- deduped[seq_len(limit), , drop = FALSE]
  }

  # 10. Clean up network capture.
  .rx_search_cleanup(backend)

  deduped
}

#' Return an empty batch with the canonical field structure.
#'
#' Used to maintain consistent field structure when a scroll iteration
#' produces zero posts (no-new-data cycle).
#'
#' @return A list with 18 canonical fields, all empty vectors.
#' @noRd
.rx_search_empty_batch <- function() {
  list(
    post_id        = character(0),
    text           = character(0),
    author_id      = character(0),
    username       = character(0),
    display_name   = character(0),
    created_at     = character(0),
    reply_count    = integer(0),
    repost_count   = integer(0),
    like_count     = integer(0),
    quote_count    = integer(0),
    bookmark_count = integer(0),
    view_count     = integer(0),
    conversation_id = character(0),
    is_reply       = logical(0),
    is_repost      = logical(0),
    is_quote       = logical(0),
    reply_to_post_id = character(0),
    quoted_post_id   = character(0)
  )
}

#' Clean up network capture resources after a search.
#'
#' @param backend The backend object.
#' @noRd
.rx_search_cleanup <- function(backend) {
  tryCatch(backend$networkCaptureClear(), error = function(e) NULL)
}

#' Create an empty tibble with zero rows and the canonical schema.
#'
#' @return A tibble with 18 columns matching the canonical schema,
#'   zero rows.
#' @noRd
.rx_search_empty_tibble <- function() {
  fields <- .rx_canonical_fields()
  type_map <- .rx_type_map()
  cols <- lapply(fields, function(f) {
    switch(type_map[[f]],
      character = character(0),
      integer = integer(0),
      logical = logical(0)
    )
  })
  names(cols) <- fields
  tibble::as_tibble(cols)
}

#' Extract posts from captured network events.
#'
#' Walks the network events, identifies candidate JSON responses
#' (X domain + application/json), fetches their bodies, parses
#' JSON, extracts posts, and accumulates them.
#'
#' @param events A list of network event records.
#' @param backend The backend object for fetching response bodies.
#' @return A parsed posts list (as from `.rx_parse_posts()`).
#' @noRd
.rx_search_extract_from_events <- function(events, backend) {
  all_parsed <- list(
    post_id = character(0), text = character(0),
    author_id = character(0), username = character(0),
    display_name = character(0), created_at = character(0),
    reply_count = integer(0), repost_count = integer(0),
    like_count = integer(0), quote_count = integer(0),
    bookmark_count = integer(0), view_count = integer(0),
    conversation_id = character(0),
    is_reply = logical(0), is_repost = logical(0), is_quote = logical(0),
    reply_to_post_id = character(0), quoted_post_id = character(0)
  )

  # Collect candidate event IDs: X domain + JSON content type.
  candidate_ids <- character(0)
  for (evt in events) {
    if (!.rx_search_is_candidate(evt)) {
      next
    }
    candidate_ids <- c(candidate_ids, evt$requestId)
  }

  # For each candidate, fetch the response body and parse.
  for (req_id in candidate_ids) {
    body_result <- tryCatch(
      backend$networkCaptureGetBody(req_id),
      error = function(e) list(error = e$message)
    )

    # Skip if body fetch failed.
    if (!is.null(body_result$error)) {
      next
    }

    # body may already be a parsed list (sidecar auto-parses JSON).
    body <- body_result$body

    # Attempt to parse if it's a string.
    if (is.character(body) && length(body) == 1L && nzchar(body[[1]])) {
      parsed_json <- tryCatch(
        jsonlite::fromJSON(body[[1]], simplifyVector = FALSE),
        error = function(e) NULL
      )
      if (!is.null(parsed_json)) {
        body <- parsed_json
      }
    }

    # Skip if not a list.
    if (!is.list(body)) {
      next
    }

    # Try to extract posts from this response.
    parsed <- .rx_parse_posts(body)
    if (length(parsed$post_id) == 0L) {
      next
    }

    # Append to accumulated results.
    all_parsed$post_id      <- c(all_parsed$post_id,      parsed$post_id)
    all_parsed$text         <- c(all_parsed$text,         parsed$text)
    all_parsed$author_id    <- c(all_parsed$author_id,    parsed$author_id)
    all_parsed$username     <- c(all_parsed$username,     parsed$username)
    all_parsed$display_name <- c(all_parsed$display_name, parsed$display_name)
    all_parsed$created_at   <- c(all_parsed$created_at,   parsed$created_at)
    all_parsed$reply_count  <- c(all_parsed$reply_count,  parsed$reply_count)
    all_parsed$repost_count <- c(all_parsed$repost_count, parsed$repost_count)
    all_parsed$like_count   <- c(all_parsed$like_count,   parsed$like_count)
    all_parsed$quote_count  <- c(all_parsed$quote_count,  parsed$quote_count)
    all_parsed$bookmark_count <- c(all_parsed$bookmark_count, parsed$bookmark_count)
    all_parsed$view_count   <- c(all_parsed$view_count,   parsed$view_count)
    all_parsed$conversation_id <- c(all_parsed$conversation_id, parsed$conversation_id)
    all_parsed$is_reply     <- c(all_parsed$is_reply,     parsed$is_reply)
    all_parsed$is_repost    <- c(all_parsed$is_repost,    parsed$is_repost)
    all_parsed$is_quote     <- c(all_parsed$is_quote,     parsed$is_quote)
    all_parsed$reply_to_post_id <- c(all_parsed$reply_to_post_id, parsed$reply_to_post_id)
    all_parsed$quoted_post_id   <- c(all_parsed$quoted_post_id,   parsed$quoted_post_id)
  }

  all_parsed
}

#' Check whether a network event is a candidate post-bearing response.
#'
#' A candidate is an event from the X/Twitter domain with a JSON
#' content type. This is a heuristic filter — not all JSON responses
#' from X contain posts, but post-bearing responses will match.
#'
#' @param evt A network event record (from `networkCaptureGet()`).
#' @return Logical, TRUE when the event is a candidate.
#' @noRd
.rx_search_is_candidate <- function(evt) {
  if (!is.list(evt)) return(FALSE)

  url <- evt$url
  if (is.null(url) || !is.character(url) || length(url) != 1L) return(FALSE)

  # Must be from the X/Twitter domain.
  if (!grepl("x\\.com|twitter\\.com", url, ignore.case = TRUE)) {
    return(FALSE)
  }

  # Must have a JSON content type (check contentType or inferred from URL).
  content_type <- evt$contentType
  if (!is.null(content_type) && is.character(content_type) && length(content_type) == 1L) {
    if (grepl("application/json|text/json", content_type, ignore.case = TRUE)) {
      return(TRUE)
    }
  }

  # Also check if the URL path looks like an API/GraphQL endpoint.
  if (grepl("/graphql|/internal\\.alg\\.com", url, ignore.case = TRUE)) {
    return(TRUE)
  }

  FALSE
}

#' Scroll the page downward to trigger loading of more content.
#'
#' Executes a JavaScript scroll expression in the current page.
#' This is the standard pattern for infinite-scroll pages like X/Twitter:
#' scroll down by a large amount, wait for content to load.
#'
#' The scroll is wrapped in `tryCatch` so that scroll failures are
#' non-fatal — the search returns whatever was captured before the scroll.
#'
#' @param backend The backend object (must support `$evaluate()`).
#' @noRd
.rx_scroll_page <- function(backend) {
  tryCatch(
    backend$evaluate(
      # Scroll by 4000px; X/Twitter uses IntersectionObserver-based lazy
      # loading, so scrolling far enough triggers new content requests.
      "window.scrollBy(0, 4000)"
    ),
    error = function(e) {
      # Scroll is best-effort — a failed evaluation (e.g. page closed)
      # should not break the search pipeline.
      invisible(NULL)
    }
  )
}

# ---------------------------------------------------------------------------
# Scroll state object (Task 41)
# ---------------------------------------------------------------------------

#' Create a scroll state object.
#'
#' Tracks collection progress across batches so that repeated-scrolling loops
#' can make data-driven decisions about termination, deduplication, and
#' pacing. This replaces implicit loop variables with an explicit state
#' record that can be inspected, serialized, and extended.
#'
#' The state object is a plain list with the following fields:
#' \describe{
#'   \item{seen_post_ids}{Character vector of all unique post IDs seen so far.}
#'   \item{current_count}{Integer, total unique posts collected.}
#'   \item{previous_count}{Integer, unique post count before the last batch.}
#'   \item{no_new_data_cycles}{Integer, consecutive batches with zero new posts.}
#'   \item{scroll_position}{Numeric, cumulative scroll offset in pixels.}
#'   \item{last_post_id}{Character, post_id of the first post in the latest batch (empty string if none).}
#'   \item{last_cursor}{Character, cursor from the latest network response (empty string if none).}
#'   \item{started_at}{POSIXct, collection start time.}
#'   \item{elapsed_time}{Numeric, seconds since collection started.}
#' }
#'
#' @return A list of class `rx_scroll_state`.
#'
#' @examples
#' \dontrun{
#'   state <- .rx_scroll_state_new()
#'   state$add_posts(list(post_id = c("1", "2", "3")))
#'   state$check_stalled()
#' }
#'
#' @noRd
.rx_scroll_state_new <- function() {
  list(
    seen_post_ids     = character(0),
    current_count     = 0L,
    previous_count    = 0L,
    no_new_data_cycles = 0L,
    scroll_position   = 0,
    last_post_id      = "",
    last_cursor       = "",
    started_at        = Sys.time(),
    elapsed_time      = 0
  ) -> state
  class(state) <- "rx_scroll_state"
  state
}

#' Add a batch of posts to the scroll state.
#'
#' Updates `seen_post_ids`, `current_count`, `previous_count`,
#' `no_new_data_cycles`, `last_post_id`, and `elapsed_time` based on
#' the new batch content. Called after each batch extraction.
#'
#' @param state An `rx_scroll_state` object (modified in place).
#' @param posts A list of post fields with at least a `post_id` element,
#'   as returned by `.rx_parse_posts()`.
#' @param new_cursor Optional character string with a cursor extracted from
#'   the network response that produced this batch.
#' @return The modified state object (in place; returned for chaining).
#'
#' @examples
#' \dontrun{
#'   state <- .rx_scroll_state_new()
#'   state$add_posts(list(post_id = c("1", "2")))
#'   state$add_posts(list(post_id = c("2", "3")), new_cursor = "cursor-abc")
#' }
#'
#' @noRd
.rx_scroll_state_add_posts <- function(state, posts, new_cursor = "") {
  # Update elapsed time.
  state$elapsed_time <- as.numeric(difftime(Sys.time(), state$started_at, units = "secs"))

  # Save previous count before updating.
  state$previous_count <- state$current_count

  # Extract post IDs from the batch.
  batch_ids <- if (is.list(posts) && !is.null(posts$post_id)) {
    posts$post_id
  } else {
    character(0)
  }

  # Filter to only IDs we haven't seen yet.
  new_ids <- batch_ids[!batch_ids %in% state$seen_post_ids]

  # Update seen_post_ids and count.
  if (length(new_ids) > 0L) {
    state$seen_post_ids <- c(state$seen_post_ids, new_ids)
    state$current_count <- length(state$seen_post_ids)
    # Reset stall counter on new data.
    state$no_new_data_cycles <- 0L
    # Track first post ID of this batch.
    state$last_post_id <- new_ids[[1L]]
  } else {
    # No new data — increment stall counter.
    state$no_new_data_cycles <- state$no_new_data_cycles + 1L
  }

  # Update cursor if provided.
  if (is.character(new_cursor) && length(new_cursor) == 1L && nzchar(new_cursor)) {
    state$last_cursor <- new_cursor
  }

  invisible(state)
}

#' Check whether the collection has stalled.
#'
#' Returns TRUE when `no_new_data_cycles` exceeds the given threshold.
#' This is the primary termination signal for repeated-scrolling loops.
#'
#' @param state An `rx_scroll_state` object.
#' @param threshold Integer, maximum allowed consecutive no-new-data cycles
#'   before considering the collection stalled. Default is 2L.
#' @return Logical, TRUE when the collection should stop scrolling.
#' @noRd
#'
#' @examples
#' \dontrun{
#'   state <- .rx_scroll_state_new()
#'   state$add_posts(list(post_id = c("1")))
#'   state$check_stalled()              # FALSE
#'   state$add_posts(list(post_id = c("1")))  # duplicate only
#'   state$check_stalled()              # FALSE
#'   state$add_posts(list(post_id = character(0)))
#'   state$check_stalled(threshold = 1) # TRUE
#' }
#'
#' @noRd
.rx_scroll_state_check_stalled <- function(state, threshold = 2L) {
  state$no_new_data_cycles >= threshold
}

#' Check whether the collection has reached the limit.
#'
#' Returns TRUE when `current_count` is at or above the given limit.
#'
#' @param state An `rx_scroll_state` object.
#' @param limit Integer limit on the number of posts to collect.
#' @return Logical, TRUE when the limit has been reached.
#' @noRd
#'
#' @examples
#' \dontrun{
#'   state <- .rx_scroll_state_new()
#'   state$add_posts(list(post_id = c("1", "2", "3")))
#'   state$check_limit(3)  # TRUE
#'   state$check_limit(2)  # FALSE
#' }
#'
#' @noRd
.rx_scroll_state_check_limit <- function(state, limit) {
  !is.null(limit) && state$current_count >= limit
}

#' Advance the scroll position in the state.
#'
#' Increments `scroll_position` by the given pixel amount.
#'
#' @param state An `rx_scroll_state` object.
#' @param pixels Numeric pixel offset to add. Default is 4000 (standard scroll).
#' @return The modified state object (in place).
#' @noRd
#'
#' @examples
#' \dontrun{
#'   state <- .rx_scroll_state_new()
#'   state$advance_scroll(1000)
#'   state$advance_scroll(3000)
#'   state$scroll_position  # 4000
#' }
#'
#' @noRd
.rx_scroll_state_advance_scroll <- function(state, pixels = 4000) {
  state$scroll_position <- state$scroll_position + pixels
  invisible(state)
}
