# Internal helpers for x_search()
#
# This module implements `x_search()` and its supporting internal functions.
# The search pipeline:
#   1. Enable network capture on the session backend
#   2. Construct the X search URL and navigate
#   3. Wait for network responses to settle
#   4. Retrieve captured network events
#   5. Identify candidate JSON responses (X domain + application/json)
#   6. For each candidate, fetch the response body and parse posts
#   7. Normalize, convert to tibble, deduplicate
#   8. Apply limit and return
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
#' @param session An \code{xtweetsR_session} object returned by
#'   \code{\link[=x_session]{x_session()}}.
#' @param query A single non-empty character string with the search query.
#' @param limit Optional integer limiting the maximum number of posts
#'   returned. When \code{NULL} (default), no limit is applied.
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
x_search <- function(session, query, limit = NULL) {
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

  # 4. Wait for network responses to arrive (X search loads content
  #    asynchronously via XHR/GraphQL). A short wait is more reliable
  #    than polling for specific response types.
  Sys.sleep(3)

  # 5. Retrieve captured network events.
  events <- tryCatch(
    backend$networkCaptureGet(),
    error = function(e) {
      .rx_search_cleanup(backend)
      warning("Failed to retrieve network events: ", e$message)
      return(list())
    }
  )

  # 6. Identify candidate JSON responses and extract posts.
  posts <- .rx_search_extract_from_events(events, backend)

  # 7. Normalize, convert to tibble, deduplicate.
  normalized <- .rx_normalize_posts(posts)
  tibble_posts <- .rx_normalized_to_tibble(normalized)
  deduped <- .rx_deduplicate_posts(tibble_posts)

  # 8. Apply limit.
  if (!is.null(limit) && nrow(deduped) > limit) {
    deduped <- deduped[seq_len(limit), , drop = FALSE]
  }

  # 9. Clean up network capture.
  .rx_search_cleanup(backend)

  deduped
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
