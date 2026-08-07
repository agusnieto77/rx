# Internal helpers for saving post tibbles to disk
#
# This module provides export functions for post collections.
# Supported formats:
#   - Parquet (via Arrow, optional — Task 50)
#   - DuckDB (via duckdb, optional — Task 51)
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
#' - `.parquetds` — writes a partitioned Arrow dataset of Parquet
#'   files (if Arrow is available).  Data is partitioned by
#'   `collection_id` and the date extracted from `collected_at`.
#' - `.duckdb` — writes using the DuckDB package (if available).
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
#' DuckDB support requires the `duckdb` package. If DuckDB is not
#' installed, calling `x_save()` on a `.duckdb` file falls back
#' to JSONL with a warning and a `.jsonl` extension.
#'
#' @param posts A tibble with the canonical post schema (as returned
#'   by [x_search()]).
#' @param path Character string with the output file path. The
#'   extension determines the format (`.parquet`, `.duckdb`, or `.jsonl`).
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
  } else if (ext == "parquetds") {
    .rx_save_partitioned(posts, path)
  } else if (ext == "duckdb") {
    .rx_save_duckdb(posts, path)
  } else if (ext == "jsonl") {
    .rx_jsonl_write(path, posts, append = FALSE)
  } else {
    stop(
      "Unsupported file extension '", ext, "'. ",
      "Use '.parquet', '.parquetds', '.duckdb', or '.jsonl'.",
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

#' Save a tibble as a DuckDB database.
#'
#' Writes a post tibble to a DuckDB database file containing a single
#' `posts` table.  This is an internal helper used by [x_save()] when
#' the target path ends with `.duckdb`.
#'
#' # Optional dependency
#' If the `duckdb` package is not installed, this function falls back
#' to writing JSONL with a `.jsonl` extension instead.  A warning is
#' issued to inform the user that DuckDB is missing.
#'
#' @param posts A tibble with the canonical post schema.
#' @param path Character string with the output `.duckdb` path.
#'
#' @return Invisible NULL.
#'
#' @noRd
.rx_save_duckdb <- function(posts, path) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    warning(
      "The 'duckdb' package is not installed. ",
      "Falling back to JSONL at '",
      sub("\\.duckdb$", ".jsonl", path),
      "'. Install duckdb for native DuckDB support.",
      call. = FALSE
    )
    .rx_jsonl_write(sub("\\.duckdb$", ".jsonl", path), posts, append = FALSE)
    return(invisible(NULL))
  }

  con <- tryCatch(
    duckdb::dbConnect(duckdb::DuckDB(), path),
    error = function(e) {
      stop(.rx_error_cdp(paste0("Failed to connect to DuckDB at '", path, "': ", e$message)))
    }
  )
  on.exit(duckdb::dbDisconnect(con), add = TRUE)

  # Guard: zero-row tibble — drop any existing table and create with canonical schema.
  if (nrow(posts) == 0L) {
    duckdb::dbExecute(con, "DROP TABLE IF EXISTS posts")
    fields <- .rx_canonical_fields()
    type_map <- .rx_type_map()
    col_defs <- paste(
      fields,
      sapply(fields, function(f) {
        switch(type_map[[f]],
          character = "VARCHAR",
          integer = "BIGINT",
          logical = "BOOLEAN",
          list = "JSON",
          "VARCHAR"
        )
      }),
      collapse = ", "
    )
    duckdb::dbExecute(con, paste0("CREATE TABLE posts (", col_defs, ")"))
    return(invisible(NULL))
  }

  # Write the posts table.
  # Drop existing table first to guarantee the canonical 26-column schema
  # regardless of what a previous export (possibly with fewer columns) left behind.
  duckdb::dbExecute(con, "DROP TABLE IF EXISTS posts")
  tryCatch(
    duckdb::dbWriteTable(con, "posts", posts, row.names = FALSE, overwrite = TRUE),
    error = function(e) {
      stop(.rx_error_cdp(paste0("Failed to write posts table: ", e$message)))
    }
  )

  invisible(NULL)
}

#' Save a tibble as a partitioned Arrow dataset.
#'
#' Writes a post tibble to a directory of Parquet files using Arrow's
#' partitioned dataset writer.  Data is partitioned by \code{collection_id}
#' and the date extracted from \code{collected_at}.  This creates a
#' directory structure such as:
#' \preformatted{
#'   collection_id=<id>/collected_at_date=2025-01-01/part-0.parquet
#'   collection_id=<id>/collected_at_date=2025-01-02/part-0.parquet
#' }
#'
#' The resulting directory can be read back with
#' \code{arrow::open_dataset()}.
#'
#' # Optional dependency
#' If the \code{arrow} package is not installed, this function falls back
#' to writing JSONL with a \code{.jsonl} extension instead.  A warning is
#' issued to inform the user that Arrow is missing.
#'
#' @param posts A tibble with the canonical post schema.
#' @param path Character string with the output directory path.
#'   The directory is created if it does not exist.
#'
#' @return Invisible NULL.
#'
#' @noRd
.rx_save_partitioned <- function(posts, path) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    warning(
      "The 'arrow' package is not installed. ",
      "Falling back to JSONL at '",
      path, ".jsonl",
      "'. Install arrow for partitioned dataset support.",
      call. = FALSE
    )
    .rx_jsonl_write(paste0(path, ".jsonl"), posts, append = FALSE)
    return(invisible(NULL))
  }

  # Guard: zero-row tibble — write nothing (an empty directory).
  if (nrow(posts) == 0L) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
    return(invisible(NULL))
  }

  # Extract collected_at date for partitioning.
  # collected_at is in ISO 8601 format "YYYY-MM-DDTHH:MM:SSZ".
  # We extract the YYYY-MM-DD portion for the date partition column.
  collected_at_dates <- tryCatch(
    substr(posts$collected_at, 1L, 10L),
    error = function(e) rep(NA_character_, nrow(posts))
  )

  # Build a data frame that arrow::write_dataset can work with.
  # Partition columns must be present in the table.
  df <- posts
  df$collected_at_date <- collected_at_dates

  # Determine partition columns: use collection_id and the extracted date.
  # Only partition by columns that have more than one distinct non-NA value.
  partition_cols <- c("collection_id", "collected_at_date")
  partition_cols <- Filter(function(col) {
    vals <- unique(df[[col]])
    length(vals[!is.na(vals)]) > 1L
  }, partition_cols)

  if (length(partition_cols) == 0L) {
    # If there's only one distinct value (or all NA), fall back to a single
    # Parquet file (non-partitioned) for simplicity.
    arrow::write_parquet(df, file.path(path, "posts.parquet"))
    return(invisible(NULL))
  }

  # Ensure the target directory exists.
  dir.create(path, recursive = TRUE, showWarnings = FALSE)

  # Write partitioned dataset.
  # partition = TRUE uses the column names as directory names.
  arrow::write_dataset(
    arrow::as_arrow_table(df),
    path = path,
    partition = partition_cols
  )

  invisible(NULL)
}

#' Read a partitioned Arrow dataset back into a tibble.
#'
#' Opens a directory of partitioned Parquet files (as written by
#' [.rx_save_partitioned()]) and returns the combined result as a tibble.
#'
#' @param path Character string with the directory containing the partitioned
#'   Parquet files.
#' @return A tibble with columns matching the canonical post schema.
#'
#' @noRd
.rx_read_partitioned <- function(path) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    return(.rx_jsonl_empty_tibble())
  }

  if (!dir.exists(path)) {
    return(.rx_jsonl_empty_tibble())
  }

  ds <- tryCatch(
    arrow::open_dataset(path),
    error = function(e) NULL
  )

  if (is.null(ds)) {
    return(.rx_jsonl_empty_tibble())
  }

  on.exit(arrow::dataset_close(ds), add = TRUE)

  result <- tryCatch(
    arrow::collect(ds),
    error = function(e) NULL
  )

  if (is.null(result) || !is.data.frame(result)) {
    return(.rx_jsonl_empty_tibble())
  }

  tibble::as_tibble(result)
}

#' Read a DuckDB database back into a tibble.
#'
#' Opens a DuckDB database file, queries the `posts` table, and
#' returns the result as a tibble.  If the file does not exist
#' or DuckDB is not available, returns an empty canonical tibble.
#'
#' @param path Character string with the `.duckdb` file path.
#' @return A tibble with columns matching the canonical post schema.
#'
#' @noRd
.rx_duckdb_read <- function(path) {
  # Guard: file does not exist.
  if (!file.exists(path)) {
    return(.rx_jsonl_empty_tibble())
  }

  if (!requireNamespace("duckdb", quietly = TRUE)) {
    return(.rx_jsonl_empty_tibble())
  }

  con <- tryCatch(
    duckdb::dbConnect(duckdb::DuckDB(), path),
    error = function(e) {
      warning("Failed to connect to DuckDB at '", path, "': ", e$message)
      return(NULL)
    }
  )

  if (is.null(con)) {
    return(.rx_jsonl_empty_tibble())
  }

  on.exit(duckdb::dbDisconnect(con), add = TRUE)

  result <- tryCatch(
    duckdb::dbGetQuery(con, "SELECT * FROM posts"),
    error = function(e) {
      warning("Failed to query DuckDB: ", e$message)
      return(NULL)
    }
  )

  if (is.null(result) || !is.data.frame(result)) {
    return(.rx_jsonl_empty_tibble())
  }

  tibble::as_tibble(result)
}
