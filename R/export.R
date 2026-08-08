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
#' @return Invisible NULL when the target format is written successfully,
#'   or the fallback `.jsonl` path (character) invisibly when an optional
#'   dependency is missing and data was written as JSONL instead.
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
  ext <- tolower(tools::file_ext(path))
  if (ext == "") {
    stop(
      "Unsupported file extension ''. ",
      "Use '.parquet', '.parquetds', '.duckdb', or '.jsonl'.",
      call. = FALSE
    )
  }

  # Dispatch to the appropriate save helper.
  # Each helper returns the fallback path invisibly when an optional
  # dependency is missing (and JSONL was written instead), or NULL.
  result <- NULL
  if (ext == "parquet") {
    result <- .rx_save_parquet(posts, path)
  } else if (ext == "parquetds") {
    result <- .rx_save_partitioned(posts, path)
  } else if (ext == "duckdb") {
    result <- .rx_save_duckdb(posts, path)
  } else if (ext == "jsonl") {
    jsonl_dir <- dirname(path)
    .rx_ensure_dir(jsonl_dir, path)
    # .rx_jsonl_write returns early for zero-row tibbles without writing;
    # truncate the file to avoid stale content on overwrite.
    if (nrow(posts) == 0L) {
      .rx_truncate_file(path)
      result <- invisible(NULL)
    } else {
      result <- .rx_jsonl_write(path, posts, append = FALSE)
    }
  } else {
    stop(
      "Unsupported file extension '", ext, "'. ",
      "Use '.parquet', '.parquetds', '.duckdb', or '.jsonl'.",
      call. = FALSE
    )
  }

  invisible(result)
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
#' @return Invisible fallback path (character) when the optional package
#'   is missing (and JSONL was written instead), otherwise invisible NULL.
#'
#' @noRd
.rx_save_parquet <- function(posts, path) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    fallback <- sub("(?i)\\.parquet$", ".jsonl", path, perl = TRUE)
    warning(
      "The 'arrow' package is not installed. ",
      "Falling back to JSONL at '",
      fallback,
      "'. Install arrow for native Parquet support.",
      call. = FALSE
    )
    fallback_dir <- dirname(fallback)
    .rx_ensure_dir(fallback_dir, fallback)
    if (nrow(posts) == 0L) {
      .rx_truncate_file(fallback)
    } else {
      .rx_jsonl_write(fallback, posts, append = FALSE)
    }
    return(invisible(fallback))
  }

  parent_dir <- dirname(path)
  .rx_ensure_dir(parent_dir, path)

  # Guard: zero-row tibble — write an empty Parquet file.
  if (nrow(posts) == 0L) {
    tryCatch(
      arrow::write_parquet(
        arrow::as_arrow_table(posts),
        path
      ),
      error = function(e) {
        stop(.rx_error(paste0("Failed to write empty Parquet file: ", e$message)))
      }
    )
    return(invisible(NULL))
  }

  # Convert tibble to Arrow table and write.
  # arrow::write_parquet handles the conversion automatically
  # for data frames / tibbles.
  tryCatch(
    arrow::write_parquet(posts, path),
    error = function(e) {
      stop(.rx_error(paste0("Failed to write Parquet file: ", e$message)))
    }
  )

  invisible(NULL)
}

#' Save a tibble as a DuckDB database.
#'
#' Writes a post tibble to a DuckDB database file containing a `posts`
#' table.  When the tibble carries an `rx_relational` attribute
#' (`rx_collection_provenance` or `rx_collection_posts`), the function
#' also writes `collections` and `post_collection_relations` tables so
#' the full relational result can be read back with
#' [.rx_duckdb_tables()].
#'
#' This is an internal helper used by [x_save()] when the target path
#' ends with `.duckdb`.
#'
#' # Optional dependency
#' If the `duckdb` package is not installed, this function falls back
#' to writing JSONL with a `.jsonl` extension instead.  A warning is
#' issued to inform the user that DuckDB is missing.
#'
#' @param posts A tibble with the canonical post schema (and optionally
#'   `rx_collection_provenance` / `rx_collection_posts` attributes).
#' @param path Character string with the output `.duckdb` path.
#'
#' @return Invisible fallback path (character) when the optional package
#'   is missing (and JSONL was written instead), otherwise invisible NULL.
#'
#' @noRd
.rx_save_duckdb <- function(posts, path) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    fallback <- sub("(?i)\\.duckdb$", ".jsonl", path, perl = TRUE)
    warning(
      "The 'duckdb' package is not installed. ",
      "Falling back to JSONL at '",
      fallback,
      "'. Install duckdb for native DuckDB support.",
      call. = FALSE
    )
    fallback_dir <- dirname(fallback)
    .rx_ensure_dir(fallback_dir, fallback)
    if (nrow(posts) == 0L) {
      .rx_truncate_file(fallback)
    } else {
      .rx_jsonl_write(fallback, posts, append = FALSE)
    }
    return(invisible(fallback))
  }

  parent_dir <- dirname(path)
  .rx_ensure_dir(parent_dir, path)

  con <- tryCatch(
    duckdb::dbConnect(duckdb::DuckDB(), path),
    error = function(e) {
      stop(.rx_error(paste0("Failed to connect to DuckDB at '", path, "': ", e$message)))
    }
  )
  on.exit(duckdb::dbDisconnect(con), add = TRUE)

  # Guard: zero-row tibble — drop any existing tables and create with canonical schema.
  # Drop ALL tables unconditionally to prevent stale data from a previous
  # export that had collections/relations when the current tibble does not.
  if (nrow(posts) == 0L) {
    duckdb::dbExecute(con, "DROP TABLE IF EXISTS posts")
    duckdb::dbExecute(con, "DROP TABLE IF EXISTS collections")
    duckdb::dbExecute(con, "DROP TABLE IF EXISTS post_collection_relations")
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
    tryCatch(
      duckdb::dbExecute(con, paste0("CREATE TABLE posts (", col_defs, ")")),
      error = function(e) {
        stop(.rx_error(paste0("Failed to create empty posts table: ", e$message)))
      }
    )

    # Write collections table from provenance (if present).
    provenance <- attr(posts, "rx_collection_provenance")
    if (!is.null(provenance) && is.list(provenance)) {
      collections_df <- data.frame(
        collection_id   = as.character(provenance$collection_id),
        started_at      = as.character(format(provenance$started_at)),
        query           = as.character(provenance$query),
        package_version = as.character(provenance$package_version),
        backend         = as.character(provenance$backend),
        parser_version  = as.character(provenance$parser_version),
        schema_version  = as.character(provenance$schema_version),
        records         = as.integer(provenance$records),
        stringsAsFactors = FALSE
      )
      tryCatch(
        duckdb::dbWriteTable(con, "collections", collections_df, row.names = FALSE, overwrite = TRUE),
        error = function(e) {
          warning("Failed to write collections table: ", e$message)
        }
      )
    }

    # Write post_collection_relations table (if present).
    rels_attr <- attr(posts, "rx_collection_posts")
    if (!is.null(rels_attr) && is.data.frame(rels_attr) && nrow(rels_attr) > 0L) {
      tryCatch(
        duckdb::dbWriteTable(
          con, "post_collection_relations",
          rels_attr, row.names = FALSE, overwrite = TRUE
        ),
        error = function(e) {
          warning("Failed to write post_collection_relations table: ", e$message)
        }
      )
    }

    return(invisible(NULL))
  }

  # Write the posts table.
  # Drop existing tables first to guarantee the canonical 26-column schema
  # regardless of what a previous export (possibly with fewer columns) left behind.
  # Drop ALL tables unconditionally to prevent stale collections/relations data.
  duckdb::dbExecute(con, "DROP TABLE IF EXISTS posts")
  duckdb::dbExecute(con, "DROP TABLE IF EXISTS collections")
  duckdb::dbExecute(con, "DROP TABLE IF EXISTS post_collection_relations")
  tryCatch(
    duckdb::dbWriteTable(con, "posts", posts, row.names = FALSE, overwrite = TRUE),
    error = function(e) {
      stop(.rx_error(paste0("Failed to write posts table: ", e$message)))
    }
  )

  # Write collections table from provenance (if present).
  provenance <- attr(posts, "rx_collection_provenance")
  if (!is.null(provenance) && is.list(provenance)) {
    collections_df <- data.frame(
      collection_id   = as.character(provenance$collection_id),
      started_at      = as.character(format(provenance$started_at)),
      query           = as.character(provenance$query),
      package_version = as.character(provenance$package_version),
      backend         = as.character(provenance$backend),
      parser_version  = as.character(provenance$parser_version),
      schema_version  = as.character(provenance$schema_version),
      records         = as.integer(provenance$records),
      stringsAsFactors = FALSE
    )
    tryCatch(
      duckdb::dbWriteTable(con, "collections", collections_df, row.names = FALSE, overwrite = TRUE),
      error = function(e) {
        warning("Failed to write collections table: ", e$message)
      }
    )
  }

  # Write post_collection_relations table (if present).
  rels_attr <- attr(posts, "rx_collection_posts")
  if (!is.null(rels_attr) && is.data.frame(rels_attr) && nrow(rels_attr) > 0L) {
    tryCatch(
      duckdb::dbWriteTable(
        con, "post_collection_relations",
        rels_attr, row.names = FALSE, overwrite = TRUE
      ),
      error = function(e) {
        warning("Failed to write post_collection_relations table: ", e$message)
      }
    )
  }

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
#' @return Invisible NULL when the target format is written successfully,
#'   or the fallback `.jsonl` path (character) invisibly when the optional
#'   package is missing (and JSONL was written instead).
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
    fallback_path <- paste0(path, ".jsonl")
    fallback_dir <- dirname(fallback_path)
    .rx_ensure_dir(fallback_dir, fallback_path)
    if (nrow(posts) == 0L) {
      .rx_truncate_file(fallback_path)
    } else {
      .rx_jsonl_write(fallback_path, posts, append = FALSE)
    }
    return(invisible(fallback_path))
  }

  # Guard: zero-row tibble — clean any existing partition data, then
  # return.  unlink + recreate prevents stale parquet files from a
  # previous non-zero write.
  if (nrow(posts) == 0L) {
    if (dir.exists(path)) {
      unlink(path, recursive = TRUE)
    }
    .rx_ensure_dir(path, path)
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
  # Ensure df is an independent copy so we don't mutate the caller's
  # tibble when adding the partition column below.
  # Use the data.frame constructor which copies all columns.
  df <- as.data.frame(posts, stringsAsFactors = FALSE)
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
    parent_dir <- dirname(path)
    .rx_ensure_dir(parent_dir, path)
    # Clean existing parquet files from the target directory.
    if (dir.exists(path)) {
      unlink(path, recursive = TRUE)
    }
    .rx_ensure_dir(path, path)
    tryCatch(
      arrow::write_parquet(df, file.path(path, "posts.parquet")),
      error = function(e) {
        stop(.rx_error(paste0("Failed to write partitioned Parquet file: ", e$message)))
      }
    )
    return(invisible(NULL))
  }

  # Clean existing partition data, then create a fresh directory.
  if (dir.exists(path)) {
    unlink(path, recursive = TRUE)
  }
  parent_dir <- dirname(path)
  .rx_ensure_dir(parent_dir, path)
  .rx_ensure_dir(path, path)

  # Write partitioned dataset.
  # partition = TRUE uses the column names as directory names.
  tryCatch(
    arrow::write_dataset(
      arrow::as_arrow_table(df),
      path = path,
      partition = partition_cols
    ),
    error = function(e) {
      stop(.rx_error(paste0("Failed to write partitioned dataset: ", e$message)))
    }
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

#' Read all tables from a DuckDB database and reconstruct a relational result.
#'
#' Opens a DuckDB database file, reads the `posts`, `collections`,
#' and `post_collection_relations` tables, and reassembles them into
#' an `rx_relational` object (a tibble with `rx_users`, `rx_media`,
#' and `rx_collection_posts` attributes).
#'
#' When collections or relations tables are missing, the corresponding
#' attributes are omitted.  This function is the counterpart to
#' [.rx_save_duckdb()] when the full relational result was saved.
#'
#' @param path Character string with the `.duckdb` file path.
#' @return An `rx_relational` tibble (posts with relational attributes).
#'   Returns an empty canonical tibble when the file does not exist
#'   or DuckDB is unavailable.
#'
#' @noRd
.rx_duckdb_tables <- function(path) {
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

  # Read posts table.
  posts <- tryCatch(
    duckdb::dbGetQuery(con, "SELECT * FROM posts"),
    error = function(e) {
      warning("Failed to query DuckDB posts table: ", e$message)
      return(NULL)
    }
  )

  if (is.null(posts) || !is.data.frame(posts) || nrow(posts) == 0L) {
    return(.rx_jsonl_empty_tibble())
  }

  posts <- tibble::as_tibble(posts)

  # Read collections table (if present).
  collections <- tryCatch({
    collections_df <- duckdb::dbGetQuery(con, "SELECT * FROM collections")
    if (is.data.frame(collections_df) && nrow(collections_df) > 0L) {
      collections_df <- collections_df[1L, ]
      structure(
        list(
          collection_id   = as.character(collections_df$collection_id),
          started_at      = as.POSIXct(collections_df$started_at, tz = "UTC"),
          query           = as.character(collections_df$query),
          package_version = as.character(collections_df$package_version),
          backend         = as.character(collections_df$backend),
          parser_version  = as.character(collections_df$parser_version),
          schema_version  = as.character(collections_df$schema_version),
          records         = {
            v <- collections_df$records
            if (is.null(v) || !is.numeric(v) || length(v) != 1L || is.na(v) ||
                !is.finite(v) || v < 0 || v > .Machine$integer.max) {
              warning("Collection has invalid records count; treating as 0")
              0L
            } else if (v != trunc(v)) {
              warning("Collection has non-integer records count; truncating to ", trunc(v))
              as.integer(trunc(v))
            } else {
              as.integer(v)
            }
          }
        ),
        class = "rx_collection_provenance"
      )
    } else {
      NULL
    }
  }, error = function(e) NULL)

  if (!is.null(collections)) {
    attr(posts, "rx_collection_provenance") <- collections
  }

  # Read post_collection_relations table (if present).
  relations <- tryCatch({
    rels_df <- duckdb::dbGetQuery(con, "SELECT * FROM post_collection_relations")
    if (is.data.frame(rels_df) && nrow(rels_df) > 0L) {
      tibble::as_tibble(rels_df)
    } else {
      NULL
    }
  }, error = function(e) NULL)

  if (!is.null(relations)) {
    attr(posts, "rx_collection_posts") <- relations
  }

  class(posts) <- c("rx_relational", class(posts))
  posts
}

# --- Internal helpers used across export paths ---

#' Ensure a directory exists (TOCTOU-safe).
#'
#' Checks whether [dir.exists] reports the directory, creates it if not,
#' and re-checks to avoid a race with another process.
#'
#' @param dir Character string with the directory path.
#' @param path Contextual file path for the error message.
#'
#' @return Invisible TRUE when the directory exists afterwards;
#'   raises an error on failure.
#'
#' @noRd
.rx_ensure_dir <- function(dir, path) {
  if (dir.exists(dir)) return(invisible(TRUE))
  if (!isTRUE(dir.create(dir, recursive = TRUE, showWarnings = FALSE)) &&
      !dir.exists(dir)) {
    stop("Failed to create directory for '", path, "'", call. = FALSE)
  }
  invisible(TRUE)
}

#' Truncate a file to zero bytes.
#'
#' Opens the file in write mode and immediately closes it, producing
#' an empty file.  No on.exit is needed because the handle is closed
#' in the same expression.
#'
#' @param path Character string with the file path.
#'
#' @return Invisible NULL.
#'
#' @noRd
.rx_truncate_file <- function(path) {
  con <- file(path, open = "w", encoding = "UTF-8")
  close(con)
  invisible(NULL)
}
