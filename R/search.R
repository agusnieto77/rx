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
# Observation-level provenance (Task 46):
#   Each post row includes `collected_at`, `collection_query`, and
#   `collection_id` — allowing per-row traceability to the collection
#   that produced it. These are injected before normalization.
#
# Collection provenance (Task 45, Task 64):
#   Each search result carries collection metadata as an attribute
#   (`rx_collection_provenance`). The metadata is a list with:
#   - collection_id, started_at, query, package_version, backend,
#     parser_version, schema_version, records
#   This makes the provenance auditable without changing the tibble
#   return type (backward-compatible).
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

# ---------------------------------------------------------------------------
# Progress output helper (Task 60)
# ---------------------------------------------------------------------------

#' Emit a progress message to the user.
#'
#' Prints a message via `message()` when not in quiet mode. Message
#' fragments are concatenated with `paste0()`, so callers can mix literal
#' strings and values freely.
#'
#' @param ... Character fragments of the progress message, concatenated
#'   with `paste0()`.
#' @param quiet Logical, when `TRUE` the message is suppressed.
#' @return Invisible `NULL`.
#' @noRd
.rx_progress <- function(..., quiet = FALSE) {
  if (isTRUE(quiet)) return(invisible(NULL))
  tryCatch(
    message("[xtweetsR] ", paste0(...)),
    error = function(e) NULL
  )
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Internal constants (Task 64, referenced by Task 45)
# ---------------------------------------------------------------------------

#' Parser version string.
#'
#' Bumped when the parser output schema changes (new fields, removed
#' fields, or field type changes).
#'
#' @return A single-element character vector with the version string.
#' @noRd
.rx_parser_version <- function() "0.1.0"

#' Schema version string.
#'
#' Bumped when the canonical field schema changes.
#'
#' @return A single-element character vector with the version string.
#' @noRd
.rx_schema_version <- function() "0.1.0"

#' Generate a version-4 UUID string.
#'
#' Uses `tools::UUIDgenerate()` when available (R >= 4.2.0), which draws
#' from the OS CSPRNG. Falls back to a `sample()` + `sprintf()` hex
#' generator for older R versions.
#'
#' @return A single-element character vector with a lowercase UUID string.
#' @noRd
.rx_generate_uuid <- function() {
  if (requireNamespace("tools", quietly = TRUE) &&
      exists("UUIDgenerate", envir = asNamespace("tools"))) {
    uuid_generate <- get("UUIDgenerate", envir = asNamespace("tools"))
    if (is.function(uuid_generate)) return(uuid_generate(FALSE))
  }

  # Fallback: UUID v4 generator using base-R CSPRNG via sample().
  # Uniform hex chars via sample() + sprintf("%x") to avoid
  # multi-digit decimal output (e.g. 10 -> "10" instead of "a").
  hex4 <- function() sprintf("%04x", sum(sample(0:15, 4, replace = TRUE) * 16^(3:0)))
  hex2 <- function() sprintf("%02x", sample(0:255, 1, replace = TRUE))
  hex3 <- function() sprintf("%03x", sum(sample(0:15, 3, replace = TRUE) * 16^(2:0)))
  # Version 4: 8-4-4-4-12 = 32 hex chars.
  # Byte 6 top nibble = 4. Variant: byte 8 top 2 bits = 10 (8-b).
  paste0(
    hex4(), hex4(), "-",
    hex4(), "-",
    "4", hex3(), "-",
    sprintf("%x", sample(8:11, 1, replace = TRUE)), hex3(), "-",
    hex4(), hex4(), hex4()
  )
}

# ---------------------------------------------------------------------------
# Collection provenance (Task 45)
# ---------------------------------------------------------------------------

#' Create collection metadata for a search result.
#'
#' Returns a list containing the provenance of a collection run.
#' The metadata is attached as an attribute to the result tibble so
#' that downstream code can audit how a result was produced without
#' changing the tibble return type.
#'
#' Fields:
#'   - `collection_id`: UUID string generated by `tools::UUIDgenerate()`.
#'   - `started_at`: POSIXct timestamp when the collection began
#'     (taken from the scroll state's `started_at`).
#'   - `query`: The search query string passed to `x_search()`.
#'   - `package_version`: Package version string from DESCRIPTION.
#'   - `backend`: Character description of the backend in use
#'     (e.g. "lightpanda").
#'   - `parser_version`: Internal parser version string.
#'   - `schema_version`: Internal canonical schema version string.
#'   - `records`: Named integer giving the total post count.
#'
#' @param collection_id Optional character string with a collection ID.
#'   When NULL, a new UUID is generated.
#' @param started_at Optional POSIXct timestamp. When NULL, `Sys.time()`
#'   is used.
#' @param query The search query string.
#' @param backend Character string describing the backend.
#' @param record_count Total number of records (posts) in the result.
#' @return A list of class `rx_collection_provenance`.
#'
#' @examples
#'   \dontrun{
#'     meta <- .rx_collection_metadata(
#'       started_at = Sys.time(),
#'       query = "r programming",
#'       backend = "lightpanda",
#'       record_count = 42
#'     )
#'   }
#'
#' @noRd
.rx_collection_metadata <- function(
  collection_id = NULL,
  started_at = Sys.time(),
  query = "",
  backend = "unknown",
  record_count = 0L
) {
  if (is.null(collection_id) || !is.character(collection_id) || length(collection_id) != 1L) {
    collection_id <- .rx_generate_uuid()
  }

  pkg_version <- tryCatch(
    as.character(utils::packageVersion("xtweetsR")),
    error = function(e) "unknown"
  )

  structure(
    list(
      collection_id   = collection_id,
      started_at      = started_at,
      query           = as.character(query),
      package_version = pkg_version,
      backend         = as.character(backend),
      parser_version  = .rx_parser_version(),
      schema_version  = .rx_schema_version(),
      records         = as.integer(record_count)
    ),
    class = "rx_collection_provenance"
  )
}

#' Print method for collection provenance.
#'
#' @param x The provenance list.
#' @param ... Ignored.
#' @noRd
#' @exportS3Method base::print
print.rx_collection_provenance <- function(x, ...) {
  cat("<xtweetsR Collection Provenance>\n")
  cat(sprintf("  collection_id : %s\n", x$collection_id))
  cat(sprintf("  started_at    : %s\n", format(x$started_at)))
  cat(sprintf("  query         : %s\n", x$query))
  cat(sprintf("  package_version: %s\n", x$package_version))
  cat(sprintf("  backend       : %s\n", x$backend))
  cat(sprintf("  parser_version: %s\n", x$parser_version))
  cat(sprintf("  schema_version: %s\n", x$schema_version))
  cat(sprintf("  records       : %d\n", x$records))
  invisible(x)
}

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
#' # Resume support (Task 49)
#' When \code{resume = TRUE} and a checkpoint file exists at
#' \code{checkpoint_path}, the collection restores the previous
#' \code{collection_id}, \code{seen_post_ids}, and cursor state so that
#' already-collected posts are not duplicated.  New posts discovered
#' during the resumed run are appended to the existing JSONL file at
#' \code{jsonl_path}.
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
#' @param resume Logical, default `FALSE`. When `TRUE` and
#'   \code{checkpoint_path} points to an existing checkpoint file,
#'   restore the previous collection state (seen IDs, collection ID,
#'   cursor) and continue from where it left off.
#' @param checkpoint_path Character string with the path to a JSON
#'   checkpoint file (written by \code{.rx_checkpoint_write()}).
#'   When \code{resume = TRUE} and the file exists, its state is loaded.
#'   Defaults to `paste0(query, ".checkpoint.json")` when resuming.
#' @param jsonl_path Character string with the path to the JSONL
#'   collection file. When \code{resume = TRUE}, new posts are appended
#'   to this file instead of overwriting it. Defaults to
#'   `paste0(query, ".jsonl")` when resuming.
#' @param quiet Logical, default `FALSE`. When `TRUE`, progress messages
#'   are suppressed. When `FALSE` (default), the function prints
#'   informational messages at each major step.
#' @param since Optional character string with a date (YYYY-MM-DD).
#'   When provided, restricts results to posts from this date onwards.
#'   Passed to the X search as `since:<date>`.
#' @param until Optional character string with a date (YYYY-MM-DD).
#'   When provided, restricts results to posts up to this date.
#'   Passed to the X search as `until:<date>`.
#' @param lang Optional character string with an ISO 639-1 language code
#'   (e.g. `"en"`, `"es"`, `"ja"`).  When provided, restricts results
#'   to posts written in that language.  Passed to the X search as
#'   `lang:<code>`.
#' @param mode Optional character string: `"latest"` or `"top"`.
#'   When provided, sets the X search mode to real-time (latest) or
#'   algorithmically-top (top).  Passed as `f=live` or `f=top`.
#'   Defaults to `"latest"` (equivalent to `f=live`).
#'
#' @return A tibble with the canonical post schema (26 columns) containing
#'   posts found during the search. Returns a zero-row tibble when no
#'   posts are captured.
#'
#' @examples
#' \dontrun{
#'   sess <- x_session()
#'   posts <- x_search(sess, "r programming", limit = 10)
#'   print(posts)
#'   x_close(sess)
#'   # Date-range search:
#'   posts <- x_search(sess, "AI", since = "2024-01-01", until = "2024-12-31")
#'   x_close(sess)
#' }
#'
#' @export
x_search <- function(session, query, limit = NULL, scroll = TRUE, max_scrolls = 5L,
                     resume = FALSE, checkpoint_path = NULL, jsonl_path = NULL,
                     quiet = FALSE, since = NULL, until = NULL, lang = NULL, mode = NULL) {
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
    stop("max_scrolls must be a non-negative integer.", call. = FALSE)
  }
  max_scrolls <- as.integer(max_scrolls)

  if (!is.logical(resume) || length(resume) != 1L || anyNA(resume)) {
    stop("resume must be a single logical value.", call. = FALSE)
  }
  if (!is.null(checkpoint_path)) {
    if (!is.character(checkpoint_path) || length(checkpoint_path) != 1L || anyNA(checkpoint_path) || !nzchar(checkpoint_path[[1L]])) {
      stop("checkpoint_path must be a single non-empty character string, or NULL.", call. = FALSE)
    }
  }
  if (!is.null(jsonl_path)) {
    if (!is.character(jsonl_path) || length(jsonl_path) != 1L || anyNA(jsonl_path) || !nzchar(jsonl_path[[1L]])) {
      stop("jsonl_path must be a single non-empty character string, or NULL.", call. = FALSE)
    }
  }

  if (!is.null(lang)) {
    if (!is.character(lang) || length(lang) != 1L || anyNA(lang)) {
      stop("lang must be a single character string with a language code, or NULL.", call. = FALSE)
    }
    code <- trimws(lang)
    if (!nzchar(code)) {
      stop("lang must be a single character string with a language code, or NULL.", call. = FALSE)
    }
    if (!grepl("^[A-Za-z]{2,3}$", code)) {
      stop("lang must be a valid language code (e.g. 'en', 'es', 'ja'): ", lang, call. = FALSE)
    }
  }
  if (!is.null(mode)) {
    if (!is.character(mode) || length(mode) != 1L || anyNA(mode)) {
      stop("mode must be 'latest', 'top', or NULL.", call. = FALSE)
    }
    mode <- tolower(trimws(mode))
    if (!nzchar(mode)) {
      stop("mode must be 'latest', 'top', or NULL.", call. = FALSE)
    }
    if (!mode %in% c("latest", "top")) {
      stop("mode must be 'latest' or 'top'.", call. = FALSE)
    }
  }

  # 1b. Resume handling (Task 49).
  resumed_checkpoint <- NULL
  if (isTRUE(resume)) {
    if (is.null(checkpoint_path)) {
      checkpoint_path <- paste0(gsub("[^A-Za-z0-9._-]", "_", query), ".checkpoint.json")
    }
    resumed_checkpoint <- .rx_checkpoint_read(checkpoint_path)
    if (!is.null(resumed_checkpoint)) {
      collection_id <- resumed_checkpoint$collection_id
    }
    if (is.null(jsonl_path)) {
      jsonl_path <- paste0(gsub("[^A-Za-z0-9._-]", "_", query), ".jsonl")
    }
  }

  # 1c. Capture collection start time and generate collection_id.
  collection_started_at <- Sys.time()
  if (is.null(resumed_checkpoint) || is.null(resumed_checkpoint$collection_id) || length(resumed_checkpoint$collection_id) == 0L) {
    collection_id <- .rx_generate_uuid()
  }
  backend_label <- "unknown"
  if (inherits(session$backend, "rx_lightpanda_backend")) {
    backend_label <- "lightpanda"
  } else if (inherits(session$backend, "rx_chromium_backend")) {
    backend_label <- "chromium"
  }

  # 2. Construct URL and delegate to shared pipeline.
  url <- .rx_construct_search_url(query, since = since, until = until, lang = lang, mode = mode)

  .rx_search_pipeline(
    session = session, url = url, query = query,
    collection_id = collection_id, limit = limit,
    scroll = scroll, max_scrolls = max_scrolls,
    resume = resume, resumed_checkpoint = resumed_checkpoint,
    checkpoint_path = checkpoint_path, jsonl_path = jsonl_path,
    quiet = quiet, collection_started_at = collection_started_at,
    backend_label = backend_label
  )
}

# ---------------------------------------------------------------------------
# Shared search pipeline (deduplicates x_search / x_user_posts)
# ---------------------------------------------------------------------------

#' Core search pipeline: navigate, extract, scroll, merge, normalize, dedup.
#'
#' This is the shared backbone used by `x_search()` and `x_user_posts()`.
#' It encapsulates the common flow of session validation, network capture
#' setup, navigation, batch extraction with bounded scrolling, batch
#' merging (via `.rx_merge_batches()`), normalization, deduplication, and
#' provenance attachment.
#'
#' @param session An `xtweetsR_session` object.
#' @param url The fully constructed URL to navigate to.
#' @param query The query string for provenance metadata.
#' @param collection_id UUID for this collection run.
#' @param limit Maximum number of posts (optional).
#' @param scroll Whether to perform infinite scrolling (default `TRUE`).
#' @param max_scrolls Maximum scroll iterations.
#' @param resumed_checkpoint Previously restored checkpoint (or `NULL`).
#' @param checkpoint_path Path for checkpoint persistence (or `NULL`).
#' @param quiet Suppress progress messages.
#' @param collection_started_at Timestamp when the collection began.
#' @param backend_label Human-readable backend label.
#' @return A deduplicated post tibble with `rx_collection_provenance`
#'   and relational attributes attached.
#' @noRd
.rx_search_pipeline <- function(
  session, url, query, collection_id, limit,
  scroll = TRUE, max_scrolls = 5L,
  resume = FALSE, resumed_checkpoint = NULL, checkpoint_path = NULL,
  jsonl_path = NULL, quiet = FALSE, collection_started_at, backend_label
) {
  backend <- session$backend

  # 1. Enable network capture.
  tryCatch(
    backend$networkCaptureEnable(),
    error = function(e) {
      stop(.rx_error_network(
        paste0("Failed to enable network capture: ", e$message)
      ))
    }
  )

  # 2. Navigate.
  nav_result <- backend$navigate(url)
  if (is.null(nav_result$status) || nav_result$status == "error") {
    error_info <- if (!is.null(nav_result$error)) nav_result$error$code else "unknown"
    .rx_search_cleanup(backend)
    warning("Navigation failed (", error_info, "). No posts returned.")
    empty <- .rx_search_empty_tibble()
    empty <- .rx_relational_result(empty, list(post_id = character(0)))
    provenance <- .rx_collection_metadata(
      collection_id = collection_id,
      started_at = collection_started_at,
      query = query,
      backend = backend_label,
      record_count = 0L
    )
    attr(empty, "rx_collection_provenance") <- provenance
    return(empty)
  } else {
    .rx_progress("Navigated to ", nav_result$url, quiet = quiet)
  }

  # 3. Wait for initial content.
  Sys.sleep(3)

  # 4. Create scroll state and extract initial batch.
  if (!is.null(resumed_checkpoint) && length(resumed_checkpoint$seen_post_ids) > 0L) {
    state <- .rx_scroll_state_new(seen_post_ids = resumed_checkpoint$seen_post_ids)
  } else {
    state <- .rx_scroll_state_new()
  }

  initial_events <- tryCatch(
    backend$networkCaptureGet(),
    error = function(e) {
      .rx_search_cleanup(backend)
      warning("Failed to retrieve network events: ", e$message)
      return(list())
    }
  )

  initial_posts <- .rx_search_extract_from_events(initial_events, backend)
  state$add_posts(initial_posts, new_cursor = initial_posts$cursors)

  .rx_progress(
    "Extracted ", length(initial_posts$post_id), " post(s) from initial batch",
    quiet = quiet
  )

  # 5. Scroll loop.
  all_batches <- list()
  if (length(initial_posts$post_id) > 0L) {
    all_batches[[1L]] <- initial_posts
  } else {
    all_batches[[1L]] <- .rx_search_empty_batch()
  }

  if (isTRUE(scroll) && max_scrolls > 0L) {
    for (i in seq_len(max_scrolls)) {
      .rx_scroll_page(backend)
      state$advance_scroll()
      Sys.sleep(3)

      batch_events <- tryCatch(
        backend$networkCaptureGet(),
        error = function(e) list()
      )

      extracted <- .rx_search_extract_from_events(batch_events, backend)
      state$add_posts(extracted, new_cursor = extracted$cursors)

      .rx_progress(
        "Scroll iteration ", i, ": extracted ", length(extracted$post_id),
        " post(s)",
        quiet = quiet
      )

      if (length(extracted$post_id) > 0L) {
        all_batches[[length(all_batches) + 1L]] <- extracted
      } else {
        zero_batch <- .rx_search_empty_batch()
        all_batches[[length(all_batches) + 1L]] <- zero_batch
      }

      if (!is.null(limit) && state$current_count >= limit) {
        break
      }
      if (state$check_stalled(threshold = 2L)) {
        break
      }
    }
  }

  # 6. Merge, normalize, deduplicate.
  if (length(all_batches) == 0L) {
    merged_posts <- .rx_search_empty_batch()
    merged_posts$collected_at      <- character(0)
    merged_posts$collection_query  <- character(0)
    merged_posts$collection_id     <- character(0)
  } else {
    merged_posts <- .rx_merge_batches(all_batches)
  }

  n_merged <- if (length(merged_posts$post_id) > 0L) length(merged_posts$post_id) else 0L
  merged_posts$collected_at      <- rep(format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), n_merged)
  merged_posts$collection_query  <- rep(query, n_merged)
  merged_posts$collection_id     <- rep(collection_id, n_merged)

  normalized <- .rx_normalize_posts(merged_posts)
  tibble_posts <- .rx_normalized_to_tibble(normalized)
  deduped <- .rx_deduplicate_posts(tibble_posts)

  # 7. Apply limit.
  if (!is.null(limit) && nrow(deduped) > limit) {
    deduped <- deduped[seq_len(limit), , drop = FALSE]
  }

  if (!is.null(jsonl_path)) {
    persist <- deduped
    if (isTRUE(resume) && !is.null(resumed_checkpoint) &&
        length(resumed_checkpoint$seen_post_ids) > 0L && nrow(persist) > 0L) {
      persist <- persist[
        !persist$post_id %in% resumed_checkpoint$seen_post_ids,
        , drop = FALSE
      ]
    }

    tryCatch(
      {
        .rx_ensure_dir(dirname(jsonl_path), jsonl_path)
        if (nrow(persist) > 0L) {
          .rx_jsonl_write(
            jsonl_path,
            persist,
            append = isTRUE(resume) && file.exists(jsonl_path)
          )
        } else if (!file.exists(jsonl_path)) {
          .rx_truncate_file(jsonl_path)
        }
      },
      error = function(e) {
        warning("Failed to write JSONL collection to '", jsonl_path, "': ", e$message)
      }
    )
  }

  # 8. Clean up and persist checkpoint.
  .rx_search_cleanup(backend)

  if (isTRUE(resume) && !is.null(checkpoint_path)) {
    checkpoint <- .rx_checkpoint_from_state(state, collection_id, query)
    tryCatch(
      {
        .rx_checkpoint_write(checkpoint_path, checkpoint)
        .rx_progress("Checkpoint saved to ", checkpoint_path, quiet = quiet)
      },
      error = function(e) {
        warning("Failed to write checkpoint to '", checkpoint_path, "': ", e$message)
      }
    )
  }

  # 9. Attach provenance and return.
  provenance <- .rx_collection_metadata(
    collection_id = collection_id,
    started_at = collection_started_at,
    query = query,
    backend = backend_label,
    record_count = as.integer(nrow(deduped))
  )
  attr(deduped, "rx_collection_provenance") <- provenance

  .rx_progress(
    "Collection complete: ", nrow(deduped), " post(s) in ",
    round(as.numeric(difftime(Sys.time(), collection_started_at, units = "secs")), 1),
    "s",
    quiet = quiet
  )

  .rx_relational_result(deduped, merged_posts)
}

# ---------------------------------------------------------------------------
# x_post() — Individual post navigation (Task 54)
# ---------------------------------------------------------------------------

#' Fetch a single post by its URL or post ID.
#'
#' Navigates to an X post URL (or a bare post ID), captures structured
#' network responses from that single post page, parses and normalizes
#' the post object, and returns a one-row tibble.
#'
#' This is the simplest entry point for post-level data collection.
#' Unlike \code{\link[=x_search]{x_search()}} or \code{\link[=x_user_posts]{x_user_posts()}},
#' it does not scroll — it captures whatever structured data is
#' available on the single post page.
#'
#' @param session An \code{xtweetsR_session} object returned by
#'   \code{\link[=x_session]{x_session()}}.
#' @param post_id A single character string that is either a full X
#'   post URL (e.g. `https://x.com/rstudio/status/1234567890`) or a
#'   bare post ID (e.g. `1234567890123456789`).
#' @param limit Optional integer limiting the maximum number of posts
#'   returned. Default `1L` — a single post page should yield at most
#'   one post.
#' @param quiet Logical, default `FALSE`. When `TRUE`, progress messages
#'   are suppressed.
#'
#' @return A tibble with the canonical post schema (26 columns)
#'   containing zero or one row. Returns a zero-row tibble when no
#'   post data is captured.
#'
#' @examples
#' \dontrun{
#'   sess <- x_session()
#'   post <- x_post(sess, "1234567890123456789")
#'   print(post)
#'   x_close(sess)
#' }
#'
#' @export
x_post <- function(session, post_id, limit = 1L, quiet = FALSE) {
  # 1. Validate inputs.
  if (!inherits(session, "xtweetsR_session")) {
    stop("session must be an xtweetsR_session object.", call. = FALSE)
  }
  if (!session$connected) {
    stop("Session is not connected. Call x_session() first.", call. = FALSE)
  }
  if (!is.character(post_id) || length(post_id) != 1L || anyNA(post_id) || !nzchar(trimws(post_id))) {
    stop("post_id must be a single non-empty character string (URL or post ID).", call. = FALSE)
  }
  if (!is.numeric(limit) || length(limit) != 1L || anyNA(limit) || limit < 1L) {
    stop("limit must be a positive integer.", call. = FALSE)
  }
  limit <- as.integer(limit)

  backend <- session$backend

  # 1b. Normalize the post identifier to a canonical URL.
  url <- .rx_normalize_post_url(post_id)

  # 1c. Capture collection start time and generate collection_id for provenance.
  collection_started_at <- Sys.time()
  collection_id <- .rx_generate_uuid()
  backend_label <- "unknown"
  if (inherits(session$backend, "rx_lightpanda_backend")) {
    backend_label <- "lightpanda"
  } else if (inherits(session$backend, "rx_chromium_backend")) {
    backend_label <- "chromium"
  }

  # 2. Enable network capture before navigation.
  tryCatch(
    backend$networkCaptureEnable(),
    error = function(e) {
      stop(.rx_error_network(
        paste0("Failed to enable network capture: ", e$message)
      ))
    }
  )

  # 3. Navigate to the post.
  nav_result <- backend$navigate(url)
  if (is.null(nav_result$status) || nav_result$status == "error") {
    # Navigation failed — return empty tibble.
    error_info <- if (!is.null(nav_result$error)) nav_result$error$code else "unknown"
    .rx_search_cleanup(backend)
    warning("Navigation failed (", error_info, "). No post returned.")
    empty <- .rx_search_empty_tibble()
    empty <- .rx_relational_result(empty, list(post_id = character(0)))
    provenance <- .rx_collection_metadata(
      collection_id = collection_id,
      started_at = collection_started_at,
      query = paste0("post:", trimws(post_id)),
      backend = backend_label,
      record_count = 0L
    )
    attr(empty, "rx_collection_provenance") <- provenance
    return(empty)
  } else {
    .rx_progress("Navigated to ", nav_result$url, quiet = quiet)
  }

  # 4. Wait for network responses to arrive (post pages load asynchronously).
  Sys.sleep(3)

  # 5. Capture events and extract posts from the single post page.
  events <- tryCatch(
    backend$networkCaptureGet(),
    error = function(e) {
      .rx_search_cleanup(backend)
      warning("Failed to retrieve network events: ", e$message)
      return(list())
    }
  )

  posts <- .rx_search_extract_from_events(events, backend)

  # 5b. Observation-level provenance.
  n_posts <- if (length(posts$post_id) > 0L) length(posts$post_id) else 0L
  posts$collected_at     <- rep(format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), n_posts)
  posts$collection_query <- rep(paste0("post:", trimws(post_id)), n_posts)
  posts$collection_id    <- rep(collection_id, n_posts)

  # 6. Normalize, convert to tibble, deduplicate.
  normalized <- .rx_normalize_posts(posts)
  tibble_posts <- .rx_normalized_to_tibble(normalized)
  deduped <- .rx_deduplicate_posts(tibble_posts)

  # 7. Apply limit (should be 1 by default).
  if (nrow(deduped) > limit) {
    deduped <- deduped[seq_len(limit), , drop = FALSE]
  }

  # 8. Clean up network capture.
  .rx_search_cleanup(backend)

  # 9. Attach collection provenance metadata.
  provenance <- .rx_collection_metadata(
    collection_id = collection_id,
    started_at = collection_started_at,
    query = paste0("post:", trimws(post_id)),
    backend = backend_label,
    record_count = as.integer(nrow(deduped))
  )
  attr(deduped, "rx_collection_provenance") <- provenance

  .rx_progress(
    "Post lookup complete: ", nrow(deduped), " post(s)",
    quiet = quiet
  )

  .rx_relational_result(deduped, posts)
}

#' Fetch all posts in a reply thread.
#'
#' Navigates to an X post URL and returns every post visible in the thread
#' (the original post plus all its replies).  Internally this reuses the
#' same network-capture → parse → normalize → deduplicate pipeline as
#' [x_search()] and [x_post()].
#'
#' @param session An `xtweetsR_session` object returned by [x_session()].
#' @param post_id A character string with a bare post ID or a full
#'   X/Twitter post URL.
#' @param quiet Logical, default `FALSE`. When `TRUE`, progress messages
#'   are suppressed.
#'
#' @return A tibble with the canonical post schema (26 columns)
#'   containing the root post and all visible replies.
#'   Returns a zero-row tibble when no thread data is captured.
#'
#' @examples
#' \dontrun{
#'   sess <- x_session()
#'   thread <- x_thread(sess, "1234567890123456789")
#'   print(thread)
#'   x_close(sess)
#' }
#'
#' @export
x_thread <- function(session, post_id, quiet = FALSE) {
  # 1. Validate inputs.
  if (!inherits(session, "xtweetsR_session")) {
    stop("session must be an xtweetsR_session object.", call. = FALSE)
  }
  if (!session$connected) {
    stop("Session is not connected. Call x_session() first.", call. = FALSE)
  }
  if (!is.character(post_id) || length(post_id) != 1L || anyNA(post_id) || !nzchar(trimws(post_id))) {
    stop("post_id must be a single non-empty character string (URL or post ID).", call. = FALSE)
  }

  backend <- session$backend

  # 1b. Normalize the post identifier to a canonical URL.
  url <- .rx_normalize_post_url(post_id)

  # 1c. Capture collection start time and generate collection_id for provenance.
  collection_started_at <- Sys.time()
  collection_id <- .rx_generate_uuid()
  backend_label <- "unknown"
  if (inherits(session$backend, "rx_lightpanda_backend")) {
    backend_label <- "lightpanda"
  } else if (inherits(session$backend, "rx_chromium_backend")) {
    backend_label <- "chromium"
  }

  # 2. Enable network capture before navigation.
  tryCatch(
    backend$networkCaptureEnable(),
    error = function(e) {
      stop(.rx_error_network(
        paste0("Failed to enable network capture: ", e$message)
      ))
    }
  )

  # 3. Navigate to the post.
  nav_result <- backend$navigate(url)
  if (is.null(nav_result$status) || nav_result$status == "error") {
    # Navigation failed — return empty tibble.
    error_info <- if (!is.null(nav_result$error)) nav_result$error$code else "unknown"
    .rx_search_cleanup(backend)
    warning("Navigation failed (", error_info, "). No thread returned.")
    empty <- .rx_search_empty_tibble()
    empty <- .rx_relational_result(empty, list(post_id = character(0)))
    provenance <- .rx_collection_metadata(
      collection_id = collection_id,
      started_at = collection_started_at,
      query = paste0("thread:", trimws(post_id)),
      backend = backend_label,
      record_count = 0L
    )
    attr(empty, "rx_collection_provenance") <- provenance
    return(empty)
  } else {
    .rx_progress("Navigated to ", nav_result$url, quiet = quiet)
  }

  # 4. Wait for network responses to arrive (thread pages load asynchronously).
  Sys.sleep(3)

  # 5. Capture events and extract posts from the thread page.
  events <- tryCatch(
    backend$networkCaptureGet(),
    error = function(e) {
      .rx_search_cleanup(backend)
      warning("Failed to retrieve network events: ", e$message)
      return(list())
    }
  )

  posts <- .rx_search_extract_from_events(events, backend)

  # 5b. Observation-level provenance.
  n_posts <- if (length(posts$post_id) > 0L) length(posts$post_id) else 0L
  posts$collected_at     <- rep(format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), n_posts)
  posts$collection_query <- rep(paste0("thread:", trimws(post_id)), n_posts)
  posts$collection_id    <- rep(collection_id, n_posts)

  # 6. Normalize, convert to tibble, deduplicate.
  normalized <- .rx_normalize_posts(posts)
  tibble_posts <- .rx_normalized_to_tibble(normalized)
  deduped <- .rx_deduplicate_posts(tibble_posts)

  # 7. Clean up network capture.
  .rx_search_cleanup(backend)

  # 8. Attach collection provenance metadata.
  provenance <- .rx_collection_metadata(
    collection_id = collection_id,
    started_at = collection_started_at,
    query = paste0("thread:", trimws(post_id)),
    backend = backend_label,
    record_count = as.integer(nrow(deduped))
  )
  attr(deduped, "rx_collection_provenance") <- provenance

  .rx_progress(
    "Thread collected: ", nrow(deduped), " post(s)",
    quiet = quiet
  )

  .rx_relational_result(deduped, posts)
}

# ---------------------------------------------------------------------------
# x_replies() — Posts where a user is mentioned and is a reply (Iteration 83)
# ---------------------------------------------------------------------------

#' Fetch replies to a specific user.
#'
#' Searches X for posts mentioning a user (via `@username`) and returns only
#' the posts that are actual replies.  Internally this reuses the same
#' network-capture → parse → normalize → deduplicate pipeline as
#' [x_search()] and [x_post()].
#'
#' Unlike [x_search()], which returns all matching posts, this function
#' filters the result set to include only posts where `is_reply` is `TRUE`.
#' This makes it useful for tracking conversations where a specific user
#' is being replied to.
#'
#' @param session An `xtweetsR_session` object returned by [x_session()].
#' @param username A single non-empty character string with an X
#'   username (without the leading @).
#' @param limit Optional integer limiting the maximum number of reply posts
#'   returned. When \code{NULL} (default), no limit is applied.
#' @param mode Optional character string: `"latest"` or `"top"`.
#'   When provided, sets the X search mode. Defaults to `"latest"`
#'   (equivalent to `f=live`).
#' @param quiet Logical, default `FALSE`. When `TRUE`, progress messages
#'   are suppressed.
#'
#' @return A tibble with the canonical post schema (26 columns)
#'   containing only reply posts where the specified user was mentioned.
#'   Returns a zero-row tibble when no replies are found.
#'
#' @examples
#' \dontrun{
#'   sess <- x_session()
#'   replies <- x_replies(sess, "rstudio")
#'   replies_top <- x_replies(sess, "rstudio", mode = "top")
#'   print(replies)
#'   x_close(sess)
#' }
#'
#' @export
x_replies <- function(session, username, limit = NULL, mode = "latest", quiet = FALSE) {
  # 1. Validate inputs.
  if (!inherits(session, "xtweetsR_session")) {
    stop("session must be an xtweetsR_session object.", call. = FALSE)
  }
  if (!session$connected) {
    stop("Session is not connected. Call x_session() first.", call. = FALSE)
  }
  if (!is.character(username) || length(username) != 1L || anyNA(username) || !nzchar(trimws(username))) {
    stop("username must be a single non-empty character string.", call. = FALSE)
  }
  if (!is.null(limit)) {
    if (!is.numeric(limit) || length(limit) != 1L || anyNA(limit) || limit < 1L) {
      stop("limit must be a positive integer, or NULL.", call. = FALSE)
    }
    limit <- as.integer(limit)
  }

  # Validate mode.
  if (!is.character(mode) || length(mode) != 1L || anyNA(mode)) {
    stop("mode must be 'latest', 'top', or NULL.", call. = FALSE)
  }
  mode <- tolower(trimws(mode))
  if (!nzchar(mode)) {
    stop("mode must be 'latest', 'top', or NULL.", call. = FALSE)
  }
  if (!mode %in% c("latest", "top")) {
    stop("mode must be 'latest' or 'top'.", call. = FALSE)
  }

  backend <- session$backend

  # 1b. Capture collection start time and generate collection_id for provenance.
  collection_started_at <- Sys.time()
  collection_id <- .rx_generate_uuid()
  backend_label <- "unknown"
  if (inherits(session$backend, "rx_lightpanda_backend")) {
    backend_label <- "lightpanda"
  } else if (inherits(session$backend, "rx_chromium_backend")) {
    backend_label <- "chromium"
  }

  # 2. Enable network capture before navigation.
  tryCatch(
    backend$networkCaptureEnable(),
    error = function(e) {
      stop(.rx_error_network(
        paste0("Failed to enable network capture: ", e$message)
      ))
    }
  )

  # 3. Construct search URL: posts mentioning the user (@username).
  # Use .rx_construct_search_url() for consistent URL building with mode support.
  query_str <- paste0("@", trimws(username))
  url <- .rx_construct_search_url(query_str, mode = mode)

  nav_result <- backend$navigate(url)
  if (is.null(nav_result$status) || nav_result$status == "error") {
    # Navigation failed — return empty tibble.
    error_info <- if (!is.null(nav_result$error)) nav_result$error$code else "unknown"
    .rx_search_cleanup(backend)
    warning("Navigation failed (", error_info, "). No replies returned.")
    empty <- .rx_search_empty_tibble()
    empty <- .rx_relational_result(empty, list(post_id = character(0)))
    provenance <- .rx_collection_metadata(
      collection_id = collection_id,
      started_at = collection_started_at,
      query = paste0("replies:", trimws(username)),
      backend = backend_label,
      record_count = 0L
    )
    attr(empty, "rx_collection_provenance") <- provenance
    return(empty)
  } else {
    .rx_progress("Navigated to ", nav_result$url, quiet = quiet)
  }

  # 4. Wait for network responses to arrive (search results load asynchronously).
  Sys.sleep(3)

  # 5. Capture events and extract posts.
  events <- tryCatch(
    backend$networkCaptureGet(),
    error = function(e) {
      .rx_search_cleanup(backend)
      warning("Failed to retrieve network events: ", e$message)
      return(list())
    }
  )

  posts <- .rx_search_extract_from_events(events, backend)

  # 5b. Observation-level provenance.
  n_posts <- if (length(posts$post_id) > 0L) length(posts$post_id) else 0L
  posts$collected_at     <- rep(format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), n_posts)
  posts$collection_query <- rep(paste0("replies:", trimws(username)), n_posts)
  posts$collection_id    <- rep(collection_id, n_posts)

  # 6. Normalize, convert to tibble, deduplicate.
  normalized <- .rx_normalize_posts(posts)
  tibble_posts <- .rx_normalized_to_tibble(normalized)
  deduped <- .rx_deduplicate_posts(tibble_posts)

  # 7. Filter to only reply posts (is_reply == TRUE).
  reply_mask <- deduped$is_reply == TRUE
  replies <- deduped[reply_mask, , drop = FALSE]

  # 7b. Observation-level provenance for filtered results.
  n_replies <- if (nrow(replies) > 0L) nrow(replies) else 0L
  replies$collected_at     <- rep(format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), n_replies)
  replies$collection_query <- rep(paste0("replies:", trimws(username)), n_replies)
  replies$collection_id    <- rep(collection_id, n_replies)

  # 8. Apply limit.
  if (!is.null(limit) && nrow(replies) > limit) {
    replies <- replies[seq_len(limit), , drop = FALSE]
  }

  # 9. Clean up network capture.
  .rx_search_cleanup(backend)

  # 10. Attach collection provenance metadata.
  provenance <- .rx_collection_metadata(
    collection_id = collection_id,
    started_at = collection_started_at,
    query = paste0("replies:", trimws(username)),
    backend = backend_label,
    record_count = as.integer(nrow(replies))
  )
  attr(replies, "rx_collection_provenance") <- provenance

  .rx_progress(
    "Found ", nrow(deduped), " post(s), ", nrow(replies), " reply(ies)",
    quiet = quiet
  )

  .rx_progress(
    "Replies collected: ", nrow(replies), " post(s) in ",
    round(as.numeric(difftime(Sys.time(), collection_started_at, units = "secs")), 1),
    "s",
    quiet = quiet
  )

  # Build a parsed-list from filtered results for user extraction.
  # Includes all fields needed by .rx_extract_users(), .rx_extract_media(),
  # and .rx_extract_collection_posts() for complete relational output.
  replies_parsed <- list(
    post_id          = replies$post_id,
    author_id        = replies$author_id,
    username         = replies$username,
    display_name     = replies$display_name,
    media_type       = replies$media_type,
    media_urls       = replies$media_urls,
    collection_id    = replies$collection_id,
    collection_query = replies$collection_query,
    collected_at     = replies$collected_at
  )
  .rx_relational_result(replies, replies_parsed)
}

# ---------------------------------------------------------------------------
# x_quotes() — Quote tweets of a specific post (Iteration 84)
# ---------------------------------------------------------------------------

#' Fetch quote tweets of a specific post.
#'
#' Searches X for posts that quote a given post (by post ID or URL) and
#' returns only the posts that are actual quote tweets.  Internally this
#' reuses the same network-capture → parse → normalize → deduplicate
#' pipeline as [x_search()], [x_post()], [x_thread()], and [x_replies()].
#'
#' Unlike [x_search()], which returns all matching posts, this function
#' filters the result set to include only posts where `is_quote` is `TRUE`
#' and `quoted_post_id` matches the target post.  This makes it useful for
#' tracking how a specific post is being quoted across the platform.
#'
#' @param session An `xtweetsR_session` object returned by [x_session()].
#' @param post_id A character string with a bare post ID or a full
#'   X/Twitter post URL.
#' @param limit Optional integer limiting the maximum number of quote posts
#'   returned. When \code{NULL} (default), no limit is applied.
#' @param mode Optional character string: `"latest"` or `"top"`.
#'   When provided, sets the X search mode. Defaults to `"latest"`
#'   (equivalent to `f=live`).
#' @param quiet Logical, default `FALSE`. When `TRUE`, progress messages
#'   are suppressed.
#'
#' @return A tibble with the canonical post schema (26 columns)
#'   containing only quote tweets of the specified post.
#'   Returns a zero-row tibble when no quotes are found.
#'
#' @examples
#' \dontrun{
#'   sess <- x_session()
#'   quotes <- x_quotes(sess, "1234567890123456789")
#'   quotes_top <- x_quotes(sess, "1234567890123456789", mode = "top")
#'   print(quotes)
#'   x_close(sess)
#' }
#'
#' @export
x_quotes <- function(session, post_id, limit = NULL, mode = "latest", quiet = FALSE) {
  # 1. Validate inputs.
  if (!inherits(session, "xtweetsR_session")) {
    stop("session must be an xtweetsR_session object.", call. = FALSE)
  }
  if (!session$connected) {
    stop("Session is not connected. Call x_session() first.", call. = FALSE)
  }
  if (!is.character(post_id) || length(post_id) != 1L || anyNA(post_id) || !nzchar(trimws(post_id))) {
    stop("post_id must be a single non-empty character string (URL or post ID).", call. = FALSE)
  }
  if (!is.null(limit)) {
    if (!is.numeric(limit) || length(limit) != 1L || anyNA(limit) || limit < 1L) {
      stop("limit must be a positive integer, or NULL.", call. = FALSE)
    }
    limit <- as.integer(limit)
  }

  # Validate mode.
  if (!is.character(mode) || length(mode) != 1L || anyNA(mode)) {
    stop("mode must be 'latest', 'top', or NULL.", call. = FALSE)
  }
  mode <- tolower(trimws(mode))
  if (!nzchar(mode)) {
    stop("mode must be 'latest', 'top', or NULL.", call. = FALSE)
  }
  if (!mode %in% c("latest", "top")) {
    stop("mode must be 'latest' or 'top'.", call. = FALSE)
  }

  backend <- session$backend

  # 1b. Normalize the post identifier to a canonical URL.
  canonical_url <- .rx_normalize_post_url(post_id)

  # 1c. Capture collection start time and generate collection_id for provenance.
  collection_started_at <- Sys.time()
  collection_id <- .rx_generate_uuid()
  backend_label <- "unknown"
  if (inherits(session$backend, "rx_lightpanda_backend")) {
    backend_label <- "lightpanda"
  } else if (inherits(session$backend, "rx_chromium_backend")) {
    backend_label <- "chromium"
  }

  # 2. Enable network capture before navigation.
  tryCatch(
    backend$networkCaptureEnable(),
    error = function(e) {
      stop(.rx_error_network(
        paste0("Failed to enable network capture: ", e$message)
      ))
    }
  )

  # 3. Construct search URL: search for the post URL to find quote tweets.
  # Use .rx_construct_search_url() for consistent URL building with mode support.
  url <- .rx_construct_search_url(canonical_url, mode = mode)

  nav_result <- backend$navigate(url)
  if (is.null(nav_result$status) || nav_result$status == "error") {
    # Navigation failed — return empty tibble.
    error_info <- if (!is.null(nav_result$error)) nav_result$error$code else "unknown"
    .rx_search_cleanup(backend)
    warning("Navigation failed (", error_info, "). No quotes returned.")
    empty <- .rx_search_empty_tibble()
    empty <- .rx_relational_result(empty, list(post_id = character(0)))
    provenance <- .rx_collection_metadata(
      collection_id = collection_id,
      started_at = collection_started_at,
      query = paste0("quotes:", trimws(post_id)),
      backend = backend_label,
      record_count = 0L
    )
    attr(empty, "rx_collection_provenance") <- provenance
    return(empty)
  } else {
    .rx_progress("Navigated to ", nav_result$url, quiet = quiet)
  }

  # 4. Wait for network responses to arrive (search results load asynchronously).
  Sys.sleep(3)

  # 5. Capture events and extract posts.
  events <- tryCatch(
    backend$networkCaptureGet(),
    error = function(e) {
      .rx_search_cleanup(backend)
      warning("Failed to retrieve network events: ", e$message)
      return(list())
    }
  )

  posts <- .rx_search_extract_from_events(events, backend)

  # 5b. Observation-level provenance.
  n_posts <- if (length(posts$post_id) > 0L) length(posts$post_id) else 0L
  posts$collected_at     <- rep(format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), n_posts)
  posts$collection_query <- rep(paste0("quotes:", trimws(post_id)), n_posts)
  posts$collection_id    <- rep(collection_id, n_posts)

  # 6. Normalize, convert to tibble, deduplicate.
  normalized <- .rx_normalize_posts(posts)
  tibble_posts <- .rx_normalized_to_tibble(normalized)
  deduped <- .rx_deduplicate_posts(tibble_posts)

  # 7. Filter to only quote tweets of the target post.
  # Extract bare post ID from canonical URL for comparison (quoted_post_id
  # in the parsed data is always a bare numeric string, not a URL).
  canonical_post_id <- regmatches(canonical_url, regexec("/status/(\\d+)", canonical_url))[[1L]][2L]
  if (is.na(canonical_post_id)) {
    # URL could not be parsed (e.g. t.co short links). Clean up network
    # capture before returning to avoid leaking networkEvents accumulation.
    .rx_search_cleanup(backend)
    provenance <- .rx_collection_metadata(
      collection_id = collection_id,
      started_at = collection_started_at,
      query = paste0("quotes:", trimws(post_id)),
      backend = backend_label,
      record_count = 0L
    )
    empty <- .rx_relational_result(.rx_search_empty_tibble(), list(post_id = character(0)))
    attr(empty, "rx_collection_provenance") <- provenance
    return(empty)
  }
  quote_mask <- !is.na(deduped$is_quote) & deduped$is_quote == TRUE &
    !is.na(deduped$quoted_post_id) & deduped$quoted_post_id == canonical_post_id
  quotes <- deduped[quote_mask, , drop = FALSE]

  # 7b. Observation-level provenance for filtered results.
  n_quotes <- if (nrow(quotes) > 0L) nrow(quotes) else 0L
  quotes$collected_at     <- rep(format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), n_quotes)
  quotes$collection_query <- rep(paste0("quotes:", trimws(post_id)), n_quotes)
  quotes$collection_id    <- rep(collection_id, n_quotes)

  # 8. Apply limit.
  if (!is.null(limit) && nrow(quotes) > limit) {
    quotes <- quotes[seq_len(limit), , drop = FALSE]
  }

  # 9. Clean up network capture.
  .rx_search_cleanup(backend)

  # 10. Attach collection provenance metadata.
  provenance <- .rx_collection_metadata(
    collection_id = collection_id,
    started_at = collection_started_at,
    query = paste0("quotes:", trimws(post_id)),
    backend = backend_label,
    record_count = as.integer(nrow(quotes))
  )
  attr(quotes, "rx_collection_provenance") <- provenance

  .rx_progress(
    "Found ", nrow(deduped), " post(s), ", nrow(quotes), " quote(s)",
    quiet = quiet
  )

  .rx_progress(
    "Quotes collected: ", nrow(quotes), " post(s) in ",
    round(as.numeric(difftime(Sys.time(), collection_started_at, units = "secs")), 1),
    "s",
    quiet = quiet
  )

  # Build a parsed-list from filtered results for user extraction.
  # Includes all fields needed by .rx_extract_users(), .rx_extract_media(),
  # and .rx_extract_collection_posts() for complete relational output.
  quotes_parsed <- list(
    post_id          = quotes$post_id,
    author_id        = quotes$author_id,
    username         = quotes$username,
    display_name     = quotes$display_name,
    media_type       = quotes$media_type,
    media_urls       = quotes$media_urls,
    collection_id    = quotes$collection_id,
    collection_query = quotes$collection_query,
    collected_at     = quotes$collected_at
  )
  .rx_relational_result(quotes, quotes_parsed)
}

#' Merge all collected batches into a single post list.
#'
#' Takes a list of batch lists (each with the canonical field structure)
#' and merges them by concatenating each field. List fields use
#' `recursive = FALSE` to flatten nested lists; atomic fields use
#' plain `unlist()`. This replaces the 26-field hardcoded merge
#' previously used in `x_search()` and `x_user_posts()`.
#'
#' @param batches A list of batch lists, each with fields matching
#'   `.rx_canonical_fields()`.
#' @return A list with one element per canonical field, each a
#'   concatenated vector of the corresponding batch field values.
#' @noRd
.rx_merge_batches <- function(batches) {
  fields <- .rx_canonical_fields()
  type_map <- .rx_type_map()

  merged <- vector("list", length(fields))
  names(merged) <- fields

  for (f in fields) {
    field_batches <- lapply(batches, `[[`, f)
    if (type_map[[f]] == "list") {
      merged[[f]] <- unlist(field_batches, recursive = FALSE)
    } else {
      merged[[f]] <- unlist(field_batches, use.names = FALSE)
    }
  }

  merged
}

#' Return an empty batch with the canonical field structure.
#'
#' Used to maintain consistent field structure when a scroll iteration
#' produces zero posts (no-new-data cycle).
#'
#' @return A list with 26 canonical fields, all empty vectors.
#' @noRd
.rx_search_empty_batch <- function() {
  fields <- .rx_canonical_fields()
  type_map <- .rx_type_map()
  out <- lapply(fields, function(f) {
    switch(type_map[[f]],
      character = character(0),
      integer   = integer(0),
      logical   = logical(0),
      list      = list(),
      character(0)
    )
  })
  names(out) <- fields
  out
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
#' @return A tibble with 26 columns matching the canonical schema,
#'   zero rows.
#' @noRd
.rx_search_empty_tibble <- function() {
  fields <- .rx_canonical_fields()
  type_map <- .rx_type_map()
  cols <- lapply(fields, function(f) {
    switch(type_map[[f]],
      character = character(0),
      integer = integer(0),
      logical = logical(0),
      list      = list()
    )
  })
  names(cols) <- fields
  tibble::as_tibble(cols)
}

#' Wrap posts and related tables into a relational result object.
#'
#' Takes a post tibble and the parsed posts list, extracts users,
#' media, and collection-post relations, and returns an `rx_relational`
#' object that holds all of them. The object inherits from `tbl_df`
#' so that existing code that treats the result as a tibble continues
#' to work.
#'
#' Tables:
#'   - `rx_users` — unique users (via `rx_users()` accessor)
#'   - `rx_media` — attached media (via `rx_media()` accessor)
#'   - `rx_collection_posts` — collection-post relations
#'     (via `rx_collection_posts()` accessor)
#'
#' @param posts A tibble of posts (from `.rx_deduplicate_posts()`).
#' @param parsed The parsed posts list (from `.rx_search_extract_from_events()`),
#'   used to extract users, media, and collection-post relations.
#' @return An `rx_relational` object: a tibble with additional
#'   `rx_users`, `rx_media`, and `rx_collection_posts` attributes.
#'
#' @noRd
.rx_relational_result <- function(posts, parsed) {
  users <- .rx_extract_users(parsed)
  users_tbl <- .rx_users_to_tibble(users)
  attr(posts, "rx_users") <- users_tbl

  media <- .rx_extract_media(parsed)
  media_tbl <- .rx_media_to_tibble(media)
  attr(posts, "rx_media") <- media_tbl

  relations <- .rx_extract_collection_posts(parsed)
  relations_tbl <- .rx_collection_posts_to_tibble(relations)
  attr(posts, "rx_collection_posts") <- relations_tbl

  class(posts) <- c("rx_relational", class(posts))
  posts
}

#' Extract the users tibble from a relational result.
#'
#' @param x An `rx_relational` object (or any object).
#' @return A tibble with user columns when `x` is an `rx_relational`,
#'   otherwise `tibble::tibble()`.
#' @export
rx_users <- function(x) {
  users <- attr(x, "rx_users")
  if (is.null(users)) {
    return(tibble::tibble(
      user_id = character(0),
      username = character(0),
      display_name = character(0)
    ))
  }
  users
}

#' Extract the media tibble from a relational result.
#'
#' @param x An `rx_relational` object (or any object).
#' @return A tibble with media columns when `x` is an `rx_relational`,
#'   otherwise `tibble::tibble()`.
#' @export
rx_media <- function(x) {
  media <- attr(x, "rx_media")
  if (is.null(media)) {
    return(tibble::tibble(
      media_id = character(0),
      media_type = character(0),
      media_url = character(0),
      post_id = character(0)
    ))
  }
  media
}

#' Extract the collection-post relations tibble from a relational result.
#'
#' Each row records that a specific post was found during a specific
#' collection run, along with the query and timestamp. This enables
#' tracking posts across multiple queries or collection runs.
#'
#' @param x An `rx_relational` object (or any object).
#' @return A tibble with 4 columns (post_id, collection_id,
#'   collection_query, collected_at) when `x` is an `rx_relational`,
#'   otherwise `tibble::tibble()`.
#' @export
rx_collection_posts <- function(x) {
  rels <- attr(x, "rx_collection_posts")
  if (is.null(rels)) {
    return(tibble::tibble(
      post_id = character(0),
      collection_id = character(0),
      collection_query = character(0),
      collected_at = character(0)
    ))
  }
  rels
}

#' Print method for `rx_relational` objects.
#'
#' Prints the posts tibble and the users tibble side by side.
#'
#' @param x An `rx_relational` object.
#' @param ... Further arguments passed to `print()`.
#'
#' @return Invisible `x`.
#'
#' @noRd
#' @exportS3Method base::print
print.rx_relational <- function(x, ...) {
  cat("# Posts (", nrow(x), " row(s))\n", sep = "")
  print(as.data.frame(x), ...)
  users <- attr(x, "rx_users")
  if (!is.null(users) && nrow(users) > 0L) {
    cat("\n# Users (", nrow(users), " unique user(s))\n", sep = "")
    print(as.data.frame(users), ...)
  }
  media <- attr(x, "rx_media")
  if (!is.null(media) && nrow(media) > 0L) {
    cat("\n# Media (", nrow(media), " media item(s))\n", sep = "")
    print(as.data.frame(media), ...)
  }
  rels <- attr(x, "rx_collection_posts")
  if (!is.null(rels) && nrow(rels) > 0L) {
    cat("\n# Collection-Post Relations (", nrow(rels), " row(s))\n", sep = "")
    print(as.data.frame(rels), ...)
  }
  invisible(x)
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
  # Some backends return one event record instead of a list of records when
  # only one response was captured. Normalize that shape before iterating.
  if (is.list(events) && !is.null(events$requestId) && !is.null(events$url)) {
    events <- list(events)
  }

  # Accumulate parsed results in a list; merge via canonical helper below.
  batches <- list()

  # Accumulate the last-extracted cursor (scalar, for scroll state).
  # Cursors from the parser are a named character vector; we keep the
  # "Bottom" cursor (used for infinite-scroll pagination) or, if absent,
  # the last available cursor value.
  last_cursor <- ""

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

    # Accumulate parsed results; merge via canonical helper at the end.
    batches <- c(batches, list(parsed))

    # Capture the last cursor for scroll state tracking.
    # Prefer the "Bottom" cursor (infinite-scroll pagination key).
    if (is.null(parsed$cursors) || !is.character(parsed$cursors) || length(parsed$cursors) == 0L) {
      next
    }
    if ("Bottom" %in% names(parsed$cursors) && nzchar(parsed$cursors[["Bottom"]])) {
      last_cursor <- parsed$cursors[["Bottom"]]
    } else if (length(parsed$cursors) > 0L && nzchar(parsed$cursors[[length(parsed$cursors)]])) {
      last_cursor <- parsed$cursors[[length(parsed$cursors)]]
    }
  }

  # Merge accumulated batches using the canonical field helper.
  # `.rx_merge_batches(list())` returns all-empty canonical fields, which is correct.
  result <- .rx_merge_batches(batches)
  result$cursors <- last_cursor
  result
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
#' The state object is an environment (reference semantics) so method calls
#' mutate in place without needing reassignment. Fields are stored directly
#' on the environment; methods are closures that close over it.
#'
#' @param seen_post_ids Optional character vector of post IDs already seen.
#'   When provided (e.g. from a checkpoint during resume), the state is
#'   initialized with these IDs and `current_count` reflects them.
#' @param last_cursor Optional character string with the cursor from the
#'   last network response. Used to continue cursor-based pagination.
#' @param records_collected Optional integer count of records already
#'   collected. When resuming from a checkpoint, this reflects the
#'   persisted count.
#' @return An environment of class `rx_scroll_state` with method functions
#'   attached (`add_posts`, `advance_scroll`, `check_stalled`, `check_limit`).
#'
#' @examples
#' \dontrun{
#'   state <- .rx_scroll_state_new()
#'   state$add_posts(list(post_id = c("1", "2", "3")))
#'   state$check_stalled()
#' }
#'
#' @noRd
.rx_scroll_state_new <- function(seen_post_ids = character(0), last_cursor = "", records_collected = NULL) {
  count <- if (is.null(records_collected) || !is.numeric(records_collected)) {
    length(seen_post_ids)
  } else {
    as.integer(records_collected)
  }

  # Environment gives reference semantics: method closures mutate the
  # same object instead of working on a copy-by-value list.
  env <- new.env(parent = emptyenv())

  # State fields.
  env$seen_post_ids     <- as.character(seen_post_ids)
  env$current_count     <- as.integer(count)
  env$previous_count    <- 0L
  env$no_new_data_cycles <- 0L
  env$scroll_position   <- 0
  env$last_post_id      <- ""
  env$last_cursor       <- as.character(last_cursor)
  env$started_at        <- Sys.time()
  env$elapsed_time      <- 0

  # Methods — closures that close over `env`, so every mutation is visible
  # to callers without needing reassignment.

  env$add_posts <- function(posts, new_cursor = "") {
    .rx_scroll_state_add_posts(env, posts, new_cursor)
    invisible(env)
  }

  env$advance_scroll <- function(pixels = 4000) {
    .rx_scroll_state_advance_scroll(env, pixels)
    invisible(env)
  }

  env$check_stalled <- function(threshold = 2L) {
    .rx_scroll_state_check_stalled(env, threshold)
  }

  env$check_limit <- function(limit) {
    .rx_scroll_state_check_limit(env, limit)
  }

  class(env) <- "rx_scroll_state"
  env
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

# ---------------------------------------------------------------------------
# x_user_posts() — User timeline navigation layer (Task 52)
# ---------------------------------------------------------------------------

#' Fetch posts from a specific user's timeline.
#'
#' Navigates to an X user timeline page, captures structured network
#' responses, parses and normalizes post objects, deduplicates by
#' \code{post_id}, and returns a tibble of results.
#'
#' This is the user-timeline equivalent of \code{\link[=x_search]{x_search()}}.
#' It reuses the same session/backend, network capture, parser, normalizer,
#' and deduplicator — only the navigation target differs.
#'
#' @param session An \code{xtweetsR_session} object returned by
#'   \code{\link[=x_session]{x_session()}}.
#' @param username A single non-empty character string with an X
#'   username (without the leading @).
#' @param limit Optional integer limiting the maximum number of posts
#'   returned. When \code{NULL} (default), no limit is applied.
#' @param path Optional path segment appended after the username,
#'   e.g. `"media"`, `"tweets_with_replies"`, `"following"`,
#'   `"followers"`. When \code{NULL}, the base timeline is used.
#' @param scroll Logical, default `TRUE`. When `FALSE`, no scrolling
#'   is performed and only the initially visible content is captured.
#' @param max_scrolls Integer, default `5L`. When \code{scroll = TRUE},
#'   the maximum number of scroll+extract iterations to perform.
#' @param resume Logical, default `FALSE`. When `TRUE` and
#'   \code{checkpoint_path} points to an existing checkpoint file,
#'   restore the previous collection state.
#' @param checkpoint_path Character string with the path to a JSON
#'   checkpoint file. Defaults to
#'   `paste0(gsub("[^A-Za-z0-9._-]", "_", username), ".checkpoint.json")`
#'   when resuming.
#' @param jsonl_path Character string with the path to the JSONL
#'   collection file. Defaults to
#'   `paste0(gsub("[^A-Za-z0-9._-]", "_", username), ".jsonl")`
#'   when resuming.
#' @param quiet Logical, default `FALSE`. When `TRUE`, progress messages
#'   are suppressed. When `FALSE` (default), the function prints
#'   informational messages at each major step.
#' @param since Optional character string with a date (YYYY-MM-DD).
#'   When provided, restricts results to posts from this date onwards.
#' @param until Optional character string with a date (YYYY-MM-DD).
#'   When provided, restricts results to posts up to this date.
#' @param lang Optional character string with an ISO 639-1 language code
#'   (e.g. `"en"`, `"es"`, `"ja"`).  When provided, restricts results
#'   to posts written in that language.
#' @param mode Optional character string: `"latest"` or `"top"`.
#'   When provided, sets the X search mode to real-time (latest) or
#'   algorithmically-top (top).  Passed as `f=live` or `f=top`.
#'
#' @return A tibble with the canonical post schema (26 columns) containing
#'   posts found on the user's timeline. Returns a zero-row tibble when
#'   no posts are captured.
#'
#' @examples
#' \dontrun{
#'   sess <- x_session()
#'   posts <- x_user_posts(sess, "hadleywickham", limit = 10)
#'   print(posts)
#'   x_close(sess)
#' }
#'
#' @export
x_user_posts <- function(session, username, limit = NULL, path = NULL,
                         scroll = TRUE, max_scrolls = 5L,
                         resume = FALSE, checkpoint_path = NULL, jsonl_path = NULL,
                         quiet = FALSE, since = NULL, until = NULL, lang = NULL, mode = NULL) {
  # 1. Validate inputs.
  if (!inherits(session, "xtweetsR_session")) {
    stop("session must be an xtweetsR_session object.", call. = FALSE)
  }
  if (!session$connected) {
    stop("Session is not connected. Call x_session() first.", call. = FALSE)
  }
  if (!is.character(username) || length(username) != 1L || anyNA(username) || !nzchar(trimws(username))) {
    stop("username must be a single non-empty character string.", call. = FALSE)
  }
  if (!is.null(limit)) {
    if (!is.numeric(limit) || length(limit) != 1L || anyNA(limit) || limit < 1L) {
      stop("limit must be a positive integer, or NULL.", call. = FALSE)
    }
    limit <- as.integer(limit)
  }
  if (!is.numeric(max_scrolls) || length(max_scrolls) != 1L || anyNA(max_scrolls) || max_scrolls < 0L) {
    stop("max_scrolls must be a non-negative integer.", call. = FALSE)
  }
  max_scrolls <- as.integer(max_scrolls)

  if (!is.logical(resume) || length(resume) != 1L || anyNA(resume)) {
    stop("resume must be a single logical value.", call. = FALSE)
  }
  if (!is.null(checkpoint_path)) {
    if (!is.character(checkpoint_path) || length(checkpoint_path) != 1L || anyNA(checkpoint_path) || !nzchar(checkpoint_path[[1L]])) {
      stop("checkpoint_path must be a single non-empty character string, or NULL.", call. = FALSE)
    }
  }
  if (!is.null(jsonl_path)) {
    if (!is.character(jsonl_path) || length(jsonl_path) != 1L || anyNA(jsonl_path) || !nzchar(jsonl_path[[1L]])) {
      stop("jsonl_path must be a single non-empty character string, or NULL.", call. = FALSE)
    }
  }

  if (!is.null(lang)) {
    if (!is.character(lang) || length(lang) != 1L || anyNA(lang)) {
      stop("lang must be a single character string with a language code, or NULL.", call. = FALSE)
    }
    code <- trimws(lang)
    if (!nzchar(code)) {
      stop("lang must be a single character string with a language code, or NULL.", call. = FALSE)
    }
    if (!grepl("^[A-Za-z]{2,3}$", code)) {
      stop("lang must be a valid language code (e.g. 'en', 'es', 'ja'): ", lang, call. = FALSE)
    }
  }
  if (!is.null(mode)) {
    if (!is.character(mode) || length(mode) != 1L || anyNA(mode)) {
      stop("mode must be 'latest', 'top', or NULL.", call. = FALSE)
    }
    mode <- tolower(trimws(mode))
    if (!nzchar(mode)) {
      stop("mode must be 'latest', 'top', or NULL.", call. = FALSE)
    }
    if (!mode %in% c("latest", "top")) {
      stop("mode must be 'latest' or 'top'.", call. = FALSE)
    }
  }

  # 1b. Resume handling.
  resumed_checkpoint <- NULL
  if (isTRUE(resume)) {
    if (is.null(checkpoint_path)) {
      checkpoint_path <- paste0(gsub("[^A-Za-z0-9._-]", "_", username), ".checkpoint.json")
    }
    resumed_checkpoint <- .rx_checkpoint_read(checkpoint_path)
    if (!is.null(resumed_checkpoint)) {
      collection_id <- resumed_checkpoint$collection_id
    }
    if (is.null(jsonl_path)) {
      jsonl_path <- paste0(gsub("[^A-Za-z0-9._-]", "_", username), ".jsonl")
    }
  }

  # 1c. Capture collection start time and generate collection_id.
  collection_started_at <- Sys.time()
  if (is.null(resumed_checkpoint) || is.null(resumed_checkpoint$collection_id) || length(resumed_checkpoint$collection_id) == 0L) {
    collection_id <- .rx_generate_uuid()
  }
  backend_label <- "unknown"
  if (inherits(session$backend, "rx_lightpanda_backend")) {
    backend_label <- "lightpanda"
  } else if (inherits(session$backend, "rx_chromium_backend")) {
    backend_label <- "chromium"
  }

  # 2. Construct URL and delegate to shared pipeline.
  query_str <- paste0("@", trimws(username))
  url <- .rx_construct_user_timeline_url(username, path = path, since = since, until = until, lang = lang, mode = mode)

  .rx_search_pipeline(
    session = session, url = url, query = query_str,
    collection_id = collection_id, limit = limit,
    scroll = scroll, max_scrolls = max_scrolls,
    resume = resume, resumed_checkpoint = resumed_checkpoint,
    checkpoint_path = checkpoint_path, jsonl_path = jsonl_path,
    quiet = quiet, collection_started_at = collection_started_at,
    backend_label = backend_label
  )
}
