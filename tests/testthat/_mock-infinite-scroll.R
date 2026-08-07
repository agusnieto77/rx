# Internal mock infrastructure for infinite-scroll testing (Task 61)
#
# This module provides a reusable mock that simulates X/Twitter's
# infinite-scroll behavior for testing the collection engine without
# requiring a live browser or X access.
#
# The mock simulates:
#   - Multiple pages/batches of posts across sequential network calls
#   - Duplicated posts across batches (posts that appear in both initial
#     and scroll responses)
#   - Configurable response delays between batches
#   - End-of-results signals (empty batches after a finite number of
#     scroll iterations)
#
# Usage:
#   # Create batches of posts.
#   batch1 <- rx_mock_batch(id_start = 1, n = 5, prefix = "batch1")
#   batch2 <- rx_mock_batch(id_start = 4, n = 5, prefix = "batch2")
#   # batch2 has posts 4-5 duplicated with batch1.
#
#   # Build a mock session.
#   session <- rx_mock_session(
#     batches = list(batch1, batch2),
#     delays = list(0, 0.05),  # tiny delay on 2nd batch
#     end_at = 3  # after 3 calls, return empty (end of results)
#   )
#
#   # Pass to x_search() — deduplication and termination are verified.
#   result <- x_search(session, "mock query", max_scrolls = 5)
#

# ---------------------------------------------------------------------------
# Post fixture generator
# ---------------------------------------------------------------------------

#' Generate a batch of fake post fixture data.
#'
# Creates a JSON-serializable list that mimics an X/Twitter GraphQL search
# response containing `n` posts. Each post gets a unique `rest_id` based
# on `id_start` and `prefix`, making it easy to control which posts are
# duplicated across batches.
#'
#' @param id_start Integer, the starting post ID (inherited by `rest_id`).
#'   If `prefix` is provided, the ID becomes `paste0(prefix, "-", id_start)`.
#' @param n Integer, number of posts in the batch. Default `10L`.
#' @param prefix Optional character string prefix for post IDs. When
#'   provided, IDs are formatted as `"{prefix}-{id_start}"`, `"{prefix}-{id_start+1}"`, etc.
#' @param include_duplicates Logical, default `FALSE`. When `TRUE`, the
#   batch includes two extra posts with IDs `prefix "-dup-a"` and
#   `"prefix-dup-b"`, useful for testing deduplication within a single batch.
#' @param author_base Optional character string prefix for author usernames.
#'   Defaults to `prefix` when `prefix` is provided, otherwise `"user"`.
#' @return A list representing a parsed X GraphQL search response with
#'   `TimelineAddEntries` containing `n` tweet entries.
#'
#' @examples
#'   batch <- rx_mock_batch(id_start = 1, n = 3, prefix = "post")
#'   # Generates posts post-1, post-2, post-3.
#'
#' @noRd
rx_mock_batch <- function(id_start = 1L, n = 10L, prefix = NULL,
                           include_duplicates = FALSE, author_base = NULL) {
  if (is.null(prefix)) {
    prefix <- "post"
  }
  if (is.null(author_base)) {
    author_base <- prefix
  }

  make_tweet <- function(post_id, full_text, created_at, user_id,
                         screen_name, name, reply_count, retweet_count,
                         favorite_count, quote_count, bookmark_count,
                         conversation_id_str, in_reply_to_status_id_str,
                         is_quote_status) {
    list(
      `__typename` = "Tweet",
      rest_id = post_id,
      core = list(
        user_results = list(
          result = list(
            id = user_id,
            legacy = list(
              screen_name = screen_name,
              name = name
            )
          )
        )
      ),
      legacy = list(
        full_text = full_text,
        created_at = created_at,
        user_id_str = user_id,
        screen_name = screen_name,
        name = name,
        reply_count = reply_count,
        retweet_count = retweet_count,
        favorite_count = favorite_count,
        quote_count = quote_count,
        bookmark_count = bookmark_count,
        conversation_id_str = conversation_id_str,
        in_reply_to_status_id_str = in_reply_to_status_id_str,
        is_quote_status = is_quote_status
      )
    )
  }

  entries <- vector("list", n)
  for (i in seq_len(n)) {
    post_id <- paste0(prefix, "-", id_start + i - 1L)
    user_id <- paste0("author-", post_id)
    entries[[i]] <- list(
      entryId = paste0("tweet-", post_id),
      content = list(
        `__typename` = "TimelineTimelineItem",
        itemContent = list(
          tweet_results = list(
            result = make_tweet(
              post_id = post_id,
              full_text = paste0("Mock post ", post_id),
              created_at = paste0(
                "Mon Jul ", sprintf("%02d", 1 + (i %% 28)),
                " 00:00:00 +0000 2026"
              ),
              user_id = user_id,
              screen_name = paste0(author_base, i),
              name = paste("Author", i),
              reply_count = as.integer(i),
              retweet_count = as.integer(i) * 2L,
              favorite_count = as.integer(i) * 3L,
              quote_count = as.integer(i),
              bookmark_count = as.integer(i),
              conversation_id_str = post_id,
              in_reply_to_status_id_str = NA_character_,
              is_quote_status = FALSE
            )
          )
        )
      )
    )
  }

  # Add duplicates if requested.
  if (include_duplicates) {
    dup_id_1 <- paste0(prefix, "-dup-a")
    dup_id_2 <- paste0(prefix, "-dup-b")
    entries[[n + 1L]] <- list(
      entryId = paste0("tweet-", dup_id_1),
      content = list(
        `__typename` = "TimelineTimelineItem",
        itemContent = list(
          tweet_results = list(
            result = make_tweet(
              post_id = dup_id_1,
              full_text = paste0("Mock post ", dup_id_1),
              created_at = "Mon Jul 15 00:00:00 +0000 2026",
              user_id = paste0("author-", dup_id_1),
              screen_name = paste0(author_base, "dup-a"),
              name = paste("Author Dup A"),
              reply_count = 0L, retweet_count = 0L,
              favorite_count = 0L, quote_count = 0L,
              bookmark_count = 0L,
              conversation_id_str = dup_id_1,
              in_reply_to_status_id_str = NA_character_,
              is_quote_status = FALSE
            )
          )
        )
      )
    )
    entries[[n + 2L]] <- list(
      entryId = paste0("tweet-", dup_id_2),
      content = list(
        `__typename` = "TimelineTimelineItem",
        itemContent = list(
          tweet_results = list(
            result = make_tweet(
              post_id = dup_id_2,
              full_text = paste0("Mock post ", dup_id_2),
              created_at = "Mon Jul 16 00:00:00 +0000 2026",
              user_id = paste0("author-", dup_id_2),
              screen_name = paste0(author_base, "dup-b"),
              name = paste("Author Dup B"),
              reply_count = 0L, retweet_count = 0L,
              favorite_count = 0L, quote_count = 0L,
              bookmark_count = 0L,
              conversation_id_str = dup_id_2,
              in_reply_to_status_id_str = NA_character_,
              is_quote_status = FALSE
            )
          )
        )
      )
    )
  }

  list(
    TimelineResult = list(
      result = list(
        `__typename` = "TimelineTimelineItem",
        timeline_instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = entries
          )
        )
      )
    )
  )
}


# ---------------------------------------------------------------------------
# Mock session builder
# ---------------------------------------------------------------------------

#' Build a mock `xtweetsR_session` for infinite-scroll testing.
#'
#' Creates a mock session backed by a queue of post batches. Each call to
#' `networkCaptureGet()` advances to the next batch. Each call to
#' `networkCaptureGetBody()` returns the fixture data for the current batch.
#' After `end_at` total calls, empty responses are returned (simulating
#' end of results).
#'
#' @param batches A list of post batch fixtures (as returned by
#'   `rx_mock_batch()`). Each element is one batch. When `delays` is
#'   provided, the batches are returned in order across multiple calls.
#'   When `delays` is NULL, all batches are returned in a single call.
#' @param delays Numeric vector of delays in seconds before returning each
#'   batch. Must be the same length as `batches` (or length 1, recycled).
#'   Default `NULL` (no delay).
#' @param end_at Integer, the call number at which to start returning
#'   empty results (no more posts). Default `NULL` (never end).
#' @param include_cursor Logical, default `FALSE`. When `TRUE`, the mock
#'   adds a `TimelineAddToModule` entry with a fake cursor after each batch,
#'   simulating X's cursor-based pagination.
#' @return An environment of class `xtweetsR_session` with a backend that
#'   cycles through `batches`, applies `delays`, and returns empty results
#'   after `end_at` calls.
#'
#' @examples
#'   batch1 <- rx_mock_batch(id_start = 1, n = 3, prefix = "a")
#'   batch2 <- rx_mock_batch(id_start = 3, n = 3, prefix = "b")
#'   # batch2 starts at ID 3, so post "a-3" / "b-3" is duplicated.
#'   session <- rx_mock_session(list(batch1, batch2),
#'                              delays = c(0, 0.01), end_at = 4)
#'   # session can be passed to x_search().
#'
#' @noRd
rx_mock_session <- function(batches, delays = NULL, end_at = NULL,
                              include_cursor = FALSE) {
  n_batches <- length(batches)
  if (n_batches == 0L) {
    stop("batches must contain at least one element", call. = FALSE)
  }

  # Recycle delays if length 1.
  if (length(delays) == 1L) {
    delays <- rep(delays, n_batches)
  }
  if (is.null(delays)) {
    delays <- rep(0, n_batches)
  }

  # Pre-serialize all batches to JSON strings for consistent body returns.
  serialized <- lapply(batches, function(b) {
    jsonlite::toJSON(b, auto_unbox = TRUE, simplifyVector = FALSE, digits = 15)
  })

  # State: which batch index to serve next.
  batch_idx <- 0L
  call_count <- 0L

  backend <- new.env(parent = emptyenv())
  backend$networkCaptureEnable <- function() invisible(TRUE)

  backend$networkCaptureGet <- function() {
    call_count <<- call_count + 1L

    # Check if we've exceeded end_at.
    if (!is.null(end_at) && call_count > end_at) {
      return(list())
    }

    # Determine which batch index to serve.
    if (n_batches > 1L) {
      # Multi-batch mode: each call advances.
      batch_idx <<- batch_idx + 1L
      if (batch_idx > n_batches) {
        return(list())
      }
    } else {
      # Single batch: always return the same event.
      batch_idx <<- 1L
    }

    req_id <- paste0("req-", call_count)
    list(
      requestId = req_id,
      url = "https://x.com/graphql/TestQuery",
      contentType = "application/json"
    )
  }

  backend$networkCaptureGetBody <- function(requestId) {
    # Apply delay if configured.
    delay <- delays[[batch_idx]]
    if (is.numeric(delay) && delay > 0) {
      Sys.sleep(delay)
    }

    # If we've exceeded batch count, return empty.
    if (batch_idx < 1L || batch_idx > n_batches) {
      return(list(requestId = requestId, body = list(),
                  contentType = "application/json", error = NULL))
    }

    # Add cursor if requested.
    body <- jsonlite::fromJSON(serialized[[batch_idx]],
                               simplifyVector = FALSE)
    if (include_cursor) {
      cursor_val <- paste0("cursor-batch-", batch_idx)
      body$TimelineResult$result$timeline_instructions[[1L]] <-
        c(body$TimelineResult$result$timeline_instructions[[1L]], list(
          list(
            type = "TimelineAddToModule",
            moduleItems = list(
              list(
                entryId = paste0("cursor-bottom-", batch_idx),
                sortIndex = as.character(Sys.time()),
                content = list(
                  `__typename` = "TimelineTimelineModuleItemCursor",
                  cursorType = "Bottom",
                  value = cursor_val
                )
              )
            )
          )
        ))
    }

    list(
      requestId = requestId,
      body = body,
      contentType = "application/json",
      error = NULL
    )
  }

  backend$networkCaptureClear <- function() invisible(TRUE)

  backend$evaluate <- function(expr) {
    invisible(NULL)
  }

  backend$navigate <- function(url) {
    list(status = "ok", url = url)
  }

  session <- new.env(parent = emptyenv())
  session$connected <- TRUE
  session$backend <- backend
  class(session) <- "xtweetsR_session"
  session
}


# ---------------------------------------------------------------------------
# Convenience: realistic multi-batch scenario
# ---------------------------------------------------------------------------

#' Create a realistic infinite-scroll scenario.
#'
#' Generates 3 batches of posts simulating X's infinite scroll:
#' - Batch 1: 5 unique posts (initial load)
#' - Batch 2: 4 new + 2 duplicated posts (scroll 1)
#' - Batch 3: 3 new + 1 duplicated post (scroll 2)
#' - Batch 4: empty (end of results)
#'
#' The total unique posts across all batches is 15. After batch 3,
#' batch 4 returns empty to simulate the end of scrollable content.
#'
#' @param delay_between_batches Numeric, seconds to delay between each
#'   batch response. Default `0.01` (10ms — fast for tests).
#' @param include_cursor Logical, default `TRUE`. Adds fake cursor entries
#'   to batches 1-3 so that cursor extraction can be tested alongside
#'   scroll behavior.
#' @return An `xtweetsR_session` mock ready for `x_search()`.
#'
#' @examples
#'   \dontrun{
#'     session <- rx_mock_realistic_scenario()
#'     result <- x_search(session, "test", max_scrolls = 10, scroll = TRUE)
#'     # Should return 15 unique posts, then stop on stall detection.
#'   }
#'
#' @noRd
rx_mock_realistic_scenario <- function(delay_between_batches = 0.01,
                                         include_cursor = TRUE) {
  # Batch 1: 5 posts (IDs 1-5).
  batch1 <- rx_mock_batch(id_start = 1L, n = 5L, prefix = "b1")

  # Batch 2: 6 posts, 4 new (IDs 6-10) + 2 duplicated from batch1 (IDs 4-5).
  batch2 <- rx_mock_batch(id_start = 4L, n = 6L, prefix = "b2")
  # Override IDs 1-2 of batch2 to be duplicates of b1-4 and b1-5.
  batch2$TimelineResult$result$timeline_instructions[[1L]]$entries[[1L]]$content$itemContent$
    tweet_results$result$rest_id <- "b1-4"
  batch2$TimelineResult$result$timeline_instructions[[1L]]$entries[[1L]]$content$itemContent$
    tweet_results$result$legacy$full_text <- "Mock post b1-4"
  batch2$TimelineResult$result$timeline_instructions[[1L]]$entries[[1L]]$entryId <- "tweet-b1-4"
  batch2$TimelineResult$result$timeline_instructions[[1L]]$entries[[2L]]$content$itemContent$
    tweet_results$result$rest_id <- "b1-5"
  batch2$TimelineResult$result$timeline_instructions[[1L]]$entries[[2L]]$content$itemContent$
    tweet_results$result$legacy$full_text <- "Mock post b1-5"
  batch2$TimelineResult$result$timeline_instructions[[1L]]$entries[[2L]]$entryId <- "tweet-b1-5"

  # Batch 3: 4 posts, 3 new (IDs 11-13) + 1 duplicated (ID 9).
  batch3 <- rx_mock_batch(id_start = 9L, n = 4L, prefix = "b3")
  batch3$TimelineResult$result$timeline_instructions[[1L]]$entries[[1L]]$content$itemContent$
    tweet_results$result$rest_id <- "b2-6"
  batch3$TimelineResult$result$timeline_instructions[[1L]]$entries[[1L]]$content$itemContent$
    tweet_results$result$legacy$full_text <- "Mock post b2-6"
  batch3$TimelineResult$result$timeline_instructions[[1L]]$entries[[1L]]$entryId <- "tweet-b2-6"

  # Batch 4: empty (end of results).
  batch4 <- list(
    TimelineResult = list(
      result = list(
        `__typename` = "TimelineTimelineItem",
        timeline_instructions = list(
          list(
            type = "TimelineAddEntries",
            entries = list()
          )
        )
      )
    )
  )

  rx_mock_session(
    batches = list(batch1, batch2, batch3, batch4),
    delays = rep(delay_between_batches, 4),
    end_at = 4L,
    include_cursor = include_cursor
  )
}
