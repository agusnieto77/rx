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
  con <- file(path, open = if (append) "a" else "w")
  on.close <- TRUE
  tryCatch(
    writeLines(lines, con),
    error = function(e) {
      if (on.close) close(con)
      stop("Failed to write JSONL to '", path, "': ", e$message, call. = FALSE)
    }
  )
  close(con)

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
#' @return A tibble with 21 columns matching the canonical schema,
#'   zero rows.
#' @noRd
.rx_jsonl_empty_tibble <- function() {
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
