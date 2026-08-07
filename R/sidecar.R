#' @import jsonlite
#' @import processx
NULL

# Internal: shared path resolution for sidecar location
#
# Tries (in order):
#   1. Explicit path if it contains dist/index.js
#   2. Installed package via system.file("node", package = "xtweetsR")
#   3. Development layout relative to current working directory
#
# @param sidecar_path Optional explicit path to the sidecar directory.
# @return Character string with the resolved sidecar directory, or NULL if not found.
# @noRd
.rx_resolve_sidecar_path <- function(sidecar_path = NULL) {
  if (!is.null(sidecar_path) &&
      file.exists(file.path(sidecar_path, "dist", "index.js"))) {
    return(sidecar_path)
  }

  sc_dir <- system.file("node", package = "xtweetsR")
  if (sc_dir != "" && file.exists(file.path(sc_dir, "dist", "index.js"))) {
    return(sc_dir)
  }

  pkg_root <- normalizePath(".", mustWork = FALSE)
  dev_path <- file.path(pkg_root, "inst", "node")
  if (file.exists(file.path(dev_path, "dist", "index.js"))) {
    return(dev_path)
  }

  NULL
}

# Internal: R-sidecar communication layer
# Manages the TypeScript sidecar process and implements the JSONL
# request/response protocol defined in inst/node/src/index.ts.
#
# Protocol shape:
#   Request:  { "id": <number>, "method": string, "params": <any>? }
#   Response: { "id": <same>, "result": <any> }
#   Error:    { "id": <same>, "error": { "code": string, "message": string } }
#
# Request IDs are monotonic integers to prevent collisions between
# consecutive calls with the same method name.
#
# Response buffer — stores unmatched responses from the sidecar's stdout
# so that rapid fire-and-forget sequences (e.g. connect immediately followed
# by close) don't lose the non-matching response in a shared poll batch.
# Each entry is a list(id = ..., parsed = ...).
# Bounded to MAX_ENTRIES entries; oldest are evicted first to prevent unbounded
# growth from orphaned responses (e.g. stale sidecar messages).
.rx_response_buffer <- new.env(parent = emptyenv())
.rx_response_buffer$max_entries <- 50L
.rx_response_buffer$items <- list()

.rx_response_buffer$trim <- function() {
  while (length(.rx_response_buffer$items) > .rx_response_buffer$max_entries) {
    .rx_response_buffer$items <- .rx_response_buffer$items[-1]
  }
}

#' Start the TypeScript sidecar process.
#'
#' @return A `processx::process` object representing the running sidecar.
#' @noRd
.rx_request_id <- new.env(parent = emptyenv())
# Use numeric (double) instead of integer to avoid overflow at 2^31-1.
.rx_request_id$value <- 0

#' @noRd
.rx_start_sidecar <- function(sidecar_path = NULL) {
  sidecar_dir <- .rx_resolve_sidecar_path(sidecar_path)

  if (is.null(sidecar_dir)) {
    stop(
      "xtweetsR sidecar not found. Ensure the TypeScript sidecar is compiled (npm run build).",
      call. = FALSE
    )
  }

  js_path <- file.path(sidecar_dir, "dist", "index.js")

  p <- processx::process$new(
    command = "node",
    args = js_path,
    stdout = "|",
    stderr = "|",
    stdin = "|"
  )

  # Wait for the startup message on stderr.
  # The sidecar writes a JSONL startup line before it accepts requests.
  startup_ok <- FALSE
  startup_error <- NULL

  tryCatch(
    {
      timeout <- 10 # seconds
      start <- Sys.time()
      # Give the process a moment to start and write the startup message.
      Sys.sleep(0.1)
      while (Sys.time() - start < timeout) {
        if (!p$is_alive()) break
        # Read available stderr lines (startup log goes to stderr).
        lines <- tryCatch(p$read_error_lines(), error = function(e) character(0))
        if (length(lines) > 0) {
          for (line in lines) {
            line <- trimws(line)
            if (nzchar(line)) {
              parsed <- tryCatch(
                jsonlite::fromJSON(line, simplifyVector = FALSE),
                error = function(e) NULL
              )
              if (!is.null(parsed) && isTRUE(parsed$type == "startup")) {
                startup_ok <- TRUE
              }
            }
          }
        }
        if (startup_ok) break
        Sys.sleep(0.05)
      }
    },
    error = function(e) {
      startup_error <<- e$message
    }
  )

  if (!p$is_alive()) {
    stop("xtweetsR sidecar failed to start.", call. = FALSE)
  }

  if (!startup_ok) {
    # Kill the orphan process before propagating the error.
    tryCatch(p$kill(), error = function(e) NULL)
    msg <- "xtweetsR sidecar did not emit startup message within timeout"
    if (!is.null(startup_error)) {
      msg <- paste0(msg, " (startup read error: ", startup_error, ")")
    }
    stop(msg, call. = FALSE)
  }

  p
}

#' Send a JSONL request to the sidecar and return the response.
#'
#' @param proc A `processx::process` object (the running sidecar).
#' @param method Character string, the method name (e.g. `"ping"`).
#' @param params Optional list, the request parameters.
#' @return A list with either `$result` (success) or `$error` (failure).
#' @noRd
.rx_send_request <- function(proc, method, params = NULL) {
  .rx_request_id$value <- .rx_request_id$value + 1
  id <- .rx_request_id$value

  if (!proc$is_alive()) {
    stop("Sidecar process is not running.", call. = FALSE)
  }

  req <- list(id = id, method = method)
  if (!is.null(params)) {
    req$params <- params
  }

  json_req <- jsonlite::toJSON(req, auto_unbox = TRUE, pretty = FALSE)
  n_written <- proc$write_input(paste0(json_req, "\n"))
  if (is.null(n_written) || (is.numeric(n_written) && n_written <= 0)) {
    stop("Sidecar process is not accepting input (stdin pipe closed).", call. = FALSE)
  }

  # Read the response line from stdout, matching by request `id`.
  # This is important because async handlers (connect, navigate, evaluate)
  # may send responses out of order relative to the request dispatch.
  # Timeout after 30 seconds.
  # Check the buffered responses before reading new output.
  for (i in seq_along(.rx_response_buffer$items)) {
    buf_entry <- .rx_response_buffer$items[[i]]
    if (isTRUE(buf_entry$id == id)) {
      # Remove from buffer and return.
      .rx_response_buffer$items <- .rx_response_buffer$items[-i]
      return(buf_entry$parsed)
    }
  }

  timeout <- 30
  start <- Sys.time()
  while (Sys.time() - start < timeout) {
    if (!proc$is_alive()) {
      stop("Sidecar process died while waiting for response.", call. = FALSE)
    }
    # read_output_lines returns all available lines from stdout.
    lines <- tryCatch(proc$read_output_lines(), error = function(e) character(0))
    if (length(lines) > 0) {
      for (line in lines) {
        if (nzchar(line)) {
          parsed <- tryCatch(
            jsonlite::fromJSON(line, simplifyVector = FALSE),
            error = function(e) NULL
          )
          if (!is.null(parsed) && isTRUE(parsed$id == id)) {
            return(parsed)
          }
          # Store unmatched responses in the buffer for future requests.
          # This prevents rapid fire-and-forget sequences from losing responses.
          # Skip entries with NULL id (e.g., PARSE_ERROR from sidecar's
          # respondError(null, ...)) — they can never match a real request
          # and would cause unbounded buffer growth if buffered.
          if (!is.null(parsed) && !is.null(parsed$id)) {
            .rx_response_buffer$items <- append(
              .rx_response_buffer$items,
              list(list(id = parsed$id, parsed = parsed))
            )
            .rx_response_buffer$trim()
          }
        }
      }
    }
    Sys.sleep(0.05)
  }

  stop("Sidecar did not respond within timeout.", call. = FALSE)
}

#' Stop the sidecar process cleanly.
#'
#' @param proc A `processx::process` object.
#' @return Invisible `NULL`.
#' @noRd
.rx_stop_sidecar <- function(proc) {
  if (is.null(proc)) return(invisible(NULL))
  if (!proc$is_alive()) return(invisible(NULL))
  tryCatch(proc$kill(), error = function(e) NULL)
  tryCatch(proc$wait(timeout = 5000), error = function(e) NULL)
  if (proc$is_alive()) {
    # Process still alive — escalate to SIGKILL (forceful termination).
    tryCatch(proc$kill(signal = 9), error = function(e) NULL)
  }
  tryCatch(proc$wait(timeout = 2000), error = function(e) NULL)
  invisible(NULL)
}

#' Close the browser session on the sidecar.
#'
#' Sends a `close` method request to the sidecar to cleanly release
#' the CDP connection. Safe to call multiple times — repeated calls
#' return a `not_connected` result without crashing.
#'
#' @param proc A `processx::process` object (the running sidecar).
#' @return A list with `$closed` (logical) and optionally `$reason`.
#' @noRd
.rx_close_browser <- function(proc) {
  if (is.null(proc)) return(list(closed = FALSE, reason = "no_process"))
  if (!proc$is_alive()) return(list(closed = FALSE, reason = "process_dead"))

  resp <- .rx_send_request(proc, "close")

  # If the sidecar returned an error, treat as not closed.
  if (!is.null(resp$error)) {
    return(list(closed = FALSE, reason = resp$error$code))
  }

  # Guard against malformed response lacking a $result field.
  if (is.null(resp$result)) {
    return(list(closed = FALSE, reason = "malformed_response"))
  }

  list(closed = isTRUE(resp$result$closed), reason = if (!isTRUE(resp$result$closed)) resp$result$reason else NULL)
}
