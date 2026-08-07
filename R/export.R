# Internal helpers for saving post tibbles to disk
#
# This module provides export functions for post collections.
# Supported formats:
#   - Parquet (via Arrow, optional — Task 50)
#   - JSONL (via jsonlite, always available — Task 47)
#
# Each format is implemented behind an optional-dependency guard:
#   - If the required package is not installed, the function returns
#     a clear error explaining which package to install.
#
# @name export
# @aliases export
# @keywords internal
# @examples
#   # Internal use only — not exported.
#   # x_save(posts, "collection.parquet")
#   # x_save(posts, "collection.jsonl")
NULL

#' Save a post tibble to disk.
#'
#' Writes a post tibble (as returned by [x_search()]) to a file.
#' The file format is inferred from the file extension:
#'
#' - `.parquet` — writes using the Arrow package (if available).
#' - `.jsonl` — writes using jsonlite (always available, same as
#'   [`.rx_jsonl_write()`]).
#'
#' Unsupported or unrecognized extensions raise an error.
#'
#' # Optional dependencies
#'
#' Parquet support requires the `arrow` package. If Arrow is not
#' installed, calling `x_save()` on a `.parquet` file falls back
#' to JSONL with a warning and a `.jsonl` extension.
#'
#' @param posts A tibble with the canonical post schema (as returned
#'   by [x_search()]).
#' @param path Character string with the output file path. The
#'   extension determines the format (`.parquet` or `.jsonl`).
#'
#' @return Invisible NULL.
#'
#' @examples
#' \dontrun{
#'   sess <- x_session()
#'   posts <- x_search(sess, "r programming", limit = 10)
#'   x_save(posts, "results.parquet")
#'   x_close(sess)
#' }
#'
#' @export
x_save <- function(posts, path) {
  # Validate input.
  if (!is.data.frame(posts) || !inherits(posts, "tbl_df")) {
    stop("posts must be a tibble (as returned by x_search()).", call. = FALSE)
  }

  # Validate path.
  if (!is.character(path) || length(path) != 1L || anyNA(path) || !nzchar(path)) {
    stop("path must be a single non-empty character string.", call. = FALSE)
  }

  # Infer format from extension.
  ext <- tolower(sub("^.*\\.", "", path))

  if (ext == "parquet") {
    .rx_save_parquet(posts, path)
  } else if (ext == "jsonl") {
    .rx_jsonl_write(path, posts, append = FALSE)
  } else {
    stop(
      "Unsupported file extension '", ext, "'. ",
      "Use '.parquet' or '.jsonl'.",
      call. = FALSE
    )
  }

  invisible(NULL)
}

#' Save a tibble as Parquet using the Arrow package.
#'
#' Writes a post tibble to a Parquet file.  This is an internal helper
#' used by [x_save()] when the target path ends with `.parquet`.
#'
#' # Optional dependency
#' If the `arrow` package is not installed, this function falls back
#' to writing JSONL with a `.jsonl` extension instead.  A warning is
#' issued to inform the user that Arrow is missing.
#'
#' @param posts A tibble with the canonical post schema.
#' @param path Character string with the output `.parquet` path.
#'
#' @return Invisible NULL.
#'
#' @noRd
.rx_save_parquet <- function(posts, path) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    warning(
      "The 'arrow' package is not installed. ",
      "Falling back to JSONL at '",
      sub("\\.parquet$", ".jsonl", path),
      "'. Install arrow for native Parquet support.",
      call. = FALSE
    )
    .rx_jsonl_write(sub("\\.parquet$", ".jsonl", path), posts, append = FALSE)
    return(invisible(NULL))
  }

  # Guard: zero-row tibble — write an empty Parquet file.
  if (nrow(posts) == 0L) {
    arrow::write_parquet(
      arrow::as_arrow_table(posts),
      path
    )
    return(invisible(NULL))
  }

  # Convert tibble to Arrow table and write.
  # arrow::write_parquet handles the conversion automatically
  # for data frames / tibbles.
  arrow::write_parquet(posts, path)

  invisible(NULL)
}
