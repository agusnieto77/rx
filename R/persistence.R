# Internal helpers for JSONL incremental persistence
#
# This module provides append-only JSONL (JSON Lines) read/write support
# for post collections.  It is deliberately independent from Arrow/DuckDB
# (Tasks 50-51) and works with base R + jsonlite only.
#
# Design:
#   - Each JSONL line is a single JSON object representing one post row.
#   - The writer appends lines to a file; the reader reconstructs a tibble.
#   - Column types are preserved by reading the first line as a schema
#     hint and coercing subsequent rows accordingly.
#   - Duplicate writing (appending the same post_id twice) is NOT
#     deduplicated by the reader — callers must deduplicate after read.
#     This matches the append-only philosophy: the file is an immutable
#     log; deduplication is a separate concern handled by the normalizer.
#
# @name persistence
# @aliases persistence
# @keywords internal
# @examples
#   # Internal use only — not exported.
#   # tmp <- tempfile(fileext = ".jsonl")
#   # .rx_jsonl_write(tmp, sample_tibble, append = FALSE)
#   # .rx_jsonl_write(tmp, another_batch, append = TRUE)
#   # loaded <- .rx_jsonl_read(tmp)
#   # file.remove(tmp)
NULL

#' Write a tibble to a JSONL file.
#'
#' Serializes each row of a tibble as a JSON object and writes it to
# a file.  The default mode is append (`append = TRUE`); set
# `append = FALSE` to overwrite the file.
#'
#' # Duplicate writing behavior
#' This function does NOT deduplicate.  If the same `post_id` appears
#' in multiple batches and both are written (first batch with
#' `append = FALSE`, second with `append = TRUE`), the resulting file
#' will contain duplicate rows.  Callers should deduplicate after
#' reading using `.rx_deduplicate_posts()`.
#'
#' Column types are preserved by converting each row to a JSON object
#' via `jsonlite::toJSON()` with `row.names = FALSE` and
#' `auto_unbox = TRUE`.
#'
#' @param path Character string with the file path.
#' @param posts A tibble with the canonical post schema.
#' @param append Logical, default `TRUE`. When `FALSE`, the file is
#'   overwritten.
#'
#' @return Invisible NULL, invisibly.
#'
#' @examples
#'   \dontrun{
#'     tmp <- tempfile(fileext = ".jsonl")
#'     .rx_jsonl_write(tmp, posts, append = FALSE)
#'     .rx_jsonl_write(tmp, more_posts, append = TRUE)
#'   }
#'
#' @noRd
.rx_jsonl_write <- function(path, posts, append = TRUE) {
  # Guard: not a tibble or data frame.
  if (!is.data.frame(posts) || nrow(posts) == 0L) {
    return(invisible(NULL))
  }

  lines <- character(nrow(posts))
  for (i in seq_len(nrow(posts))) {
    # Extract the row as a named list and serialize to JSON.
    row_list <- as.list(posts[i, , drop = FALSE])
    # Convert NA to null (jsonlite handles this by default).
    lines[i] <- jsonlite::toJSON(row_list, row.names = FALSE, auto_unbox = TRUE, na = "null")
  }

  # Write (or append) the lines to the file.
  # Use writeLines which handles newlines correctly across platforms.
  con <- file(path, open = if (append) "a" else "w", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  tryCatch(
    writeLines(lines, con, useBytes = TRUE),
    error = function(e) {
      stop("Failed to write JSONL to '", path, "': ", e$message, call. = FALSE)
    }
  )

  invisible(NULL)
}

#' Read a JSONL file back into a tibble.
#'
#' Reads each line of a JSONL file, parses it as a JSON object, and
#' reconstructs a tibble.  Column types are inferred from the first
#' non-empty line and enforced for all subsequent rows.
#'
#' # Duplicate handling
#' This function does NOT deduplicate.  If the JSONL file contains
#' duplicate `post_id` values (from multiple append operations),
#' all rows are returned and the caller must deduplicate using
#' `.rx_deduplicate_posts()` before downstream use.
#'
#' @param path Character string with the JSONL file path.
#' @return A tibble with columns matching the canonical post schema.
#'   Returns an empty tibble when the file does not exist or contains
#'   no valid JSON lines.
#'
#' @examples
#'   \dontrun{
#'     loaded <- .rx_jsonl_read("path/to/collection.jsonl")
#'   }
#'
#' @noRd
.rx_jsonl_read <- function(path) {
  # Guard: file does not exist.
  if (!file.exists(path)) {
    return(.rx_jsonl_empty_tibble())
  }

  # Read all lines.
  lines <- tryCatch(
    readLines(path, warn = FALSE),
    error = function(e) {
      warning("Failed to read JSONL file '", path, "': ", e$message)
      return(character(0))
    }
  )

  # Filter out empty lines.
  lines <- lines[nzchar(trimws(lines))]

  if (length(lines) == 0L) {
    return(.rx_jsonl_empty_tibble())
  }

  # Parse all lines as JSON.
  parsed <- lapply(lines, function(line) {
    tryCatch(
      jsonlite::fromJSON(line, simplifyVector = FALSE, simplifyMatrix = FALSE),
      error = function(e) NULL
    )
  })

  # Filter out failed parses.
  parsed <- Filter(Negate(is.null), parsed)

  if (length(parsed) == 0L) {
    return(.rx_jsonl_empty_tibble())
  }

  # Convert list-of-lists to tibble.
  # jsonlite::rbind.fill.data.frame handles rows with different columns.
  tryCatch(
    {
      df <- do.call(rbind, lapply(parsed, as.data.frame.stringsAsFactors = FALSE))
      # Preserve column order and types.
      as_tibble(df)
    },
    error = function(e) {
      warning("Failed to parse JSONL file '", path, "': ", e$message)
      .rx_jsonl_empty_tibble()
    }
  )
}

#' Return an empty tibble with the canonical post schema.
#'
#' @return A tibble with 26 columns matching the canonical schema,
#'   zero rows.
#' @noRd
.rx_jsonl_empty_tibble <- function() {
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

# ---------------------------------------------------------------------------
# Checkpoint state persistence (Task 48)
# ---------------------------------------------------------------------------

#' Create a checkpoint state object from a scroll state.
#'
#' Converts an `rx_scroll_state` object (from the search pipeline) into
#' a serializable checkpoint list containing only the fields needed to
#' resume a collection run.
#'
#' Fields:
#'   - `collection_id`: UUID string identifying this collection.
#'   - `query`: The search query string.
#'   - `seen_post_ids`: Character vector of unique post IDs collected so far.
#'   - `last_cursor`: Cursor from the last network response.
#'   - `last_post_id`: post_id of the first post in the latest batch.
#'   - `records_collected`: Integer count of unique records collected.
#'
#' @param state An `rx_scroll_state` object (from the search pipeline).
#' @param collection_id Character string with the collection UUID.
#' @param query Character string with the search query.
#' @return A list of class `rx_checkpoint`.
#' @noRd
.rx_checkpoint_from_state <- function(state, collection_id, query) {
  structure(
    list(
      collection_id   = as.character(collection_id),
      query           = as.character(query),
      seen_post_ids   = as.character(state$seen_post_ids),
      last_cursor     = as.character(state$last_cursor),
      last_post_id    = as.character(state$last_post_id),
      records_collected = as.integer(state$current_count)
    ),
    class = "rx_checkpoint"
  )
}

#' Write a checkpoint state to disk as JSON.
#'
#' Serializes a checkpoint object to a single JSON file.  The file
#' is always overwritten (not appended) since a checkpoint represents
#' the latest state.
#'
#' @param path Character string with the file path.
#' @param checkpoint An `rx_checkpoint` object from `.rx_checkpoint_from_state()`.
#'
#' @return Invisible NULL, invisibly.
#'
#' @noRd
.rx_checkpoint_write <- function(path, checkpoint) {
  if (is.null(checkpoint) || !inherits(checkpoint, "rx_checkpoint")) {
    return(invisible(NULL))
  }

  # Convert to a plain list with the required fields.
  data <- list(
    collection_id   = checkpoint$collection_id,
    query           = checkpoint$query,
    seen_post_ids   = checkpoint$seen_post_ids,
    last_cursor     = checkpoint$last_cursor,
    last_post_id    = checkpoint$last_post_id,
    records_collected = checkpoint$records_collected
  )

  con <- file(path, open = "w", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)

  tryCatch(
    writeLines(jsonlite::toJSON(data, auto_unbox = TRUE, pretty = TRUE), con, useBytes = TRUE),
    error = function(e) {
      stop("Failed to write checkpoint to '", path, "': ", e$message, call. = FALSE)
    }
  )

  invisible(NULL)
}

#' Read a checkpoint state from disk.
#'
#' Parses a JSON checkpoint file and returns an `rx_checkpoint` object.
#' If the file does not exist, returns NULL.
#'
#' @param path Character string with the checkpoint file path.
#' @return An `rx_checkpoint` object, or NULL when the file does not exist.
#'
#' @noRd
.rx_checkpoint_read <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }

  content <- tryCatch(
    readLines(path, warn = FALSE),
    error = function(e) {
      warning("Failed to read checkpoint file '", path, "': ", e$message)
      return(character(0))
    }
  )

  content <- content[nzchar(trimws(content))]

  if (length(content) == 0L) {
    return(NULL)
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(content, simplifyVector = FALSE),
    error = function(e) {
      warning("Failed to parse checkpoint file '", path, "': ", e$message)
      return(NULL)
    }
  )

  if (is.null(parsed) || !is.list(parsed)) {
    return(NULL)
  }

  # Validate required fields are present.
  required_fields <- c("collection_id", "query", "seen_post_ids",
                       "last_cursor", "last_post_id", "records_collected")
  if (!all(required_fields %in% names(parsed))) {
    missing <- setdiff(required_fields, names(parsed))
    warning("Checkpoint file '", path, "' is missing fields: ",
            paste(missing, collapse = ", "))
    return(NULL)
  }

  # seen_post_ids is written as a JSON array and read back as a list;
  # unlist it to a character vector.
  seen <- parsed$seen_post_ids
  if (is.list(seen) && !is.null(names(seen))) seen <- unlist(seen, use.names = FALSE)
  seen_post_ids <- as.character(seen)

  # Validate records_collected is a real non-negative integer.
  rec <- parsed$records_collected
  if (is.null(rec) ||
      (length(rec) == 1 && is.na(as.integer(rec))) ||
      (length(rec) == 1L && as.integer(rec) < 0L)) {
    warning("Checkpoint has invalid records_collected; treating as 0")
    rec <- 0L
  } else {
    rec <- as.integer(rec)
  }

  structure(
    list(
      collection_id   = as.character(parsed$collection_id),
      query           = as.character(parsed$query),
      seen_post_ids   = seen_post_ids,
      last_cursor     = as.character(parsed$last_cursor),
      last_post_id    = as.character(parsed$last_post_id),
      records_collected = rec
    ),
    class = "rx_checkpoint"
  )
}
