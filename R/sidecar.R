#' @import jsonlite
#' @import processx
NULL

# Internal: R-sidecar communication layer
# Manages the TypeScript sidecar process and implements the JSONL
# request/response protocol defined in inst/node/src/index.ts.
#
# Protocol shape:
#   Request:  { "id": <any>, "method": string, "params": <any>? }
#   Response: { "id": <same>, "result": <any> }
#   Error:    { "id": <same>, "error": { "code": string, "message": string } }

#' Start the TypeScript sidecar process.
#'
#' @return A `processx::process` object representing the running sidecar.
#' @noRd
.rx_start_sidecar <- function(sidecar_path = NULL) {
  # Allow override for tests (e.g., pointing to source tree).
  if (!is.null(sidecar_path) && file.exists(file.path(sidecar_path, "dist", "index.js"))) {
    sidecar_dir <- sidecar_path
  } else {
    sidecar_dir <- system.file("node", package = "xtweetsR")
    if (sidecar_dir == "" || !file.exists(file.path(sidecar_dir, "dist", "index.js"))) {
      # Look relative to the running R session's working directory
      # (useful during development before `R CMD INSTALL`).
      pkg_root <- normalizePath(".", mustWork = FALSE)
      dev_path <- file.path(pkg_root, "inst", "node")
      if (file.exists(file.path(dev_path, "dist", "index.js"))) {
        sidecar_dir <- dev_path
      }
    }
  }

  js_path <- file.path(sidecar_dir, "dist", "index.js")

  if (!file.exists(js_path)) {
    stop(
      "xtweetsR sidecar not found at ", js_path,
      ". Ensure the TypeScript sidecar is compiled (npm run build).",
      call. = FALSE
    )
  }

  p <- processx::process$new(
    command = "node",
    args = js_path,
    stdout = "|",
    stderr = "|",
    stdin = "|"
  )

  # Wait for the startup message on stderr.
  # The sidecar writes a JSONL startup line before it accepts requests.
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
              if (!is.null(parsed) && parsed$type == "startup") {
                return(p)
              }
            }
          }
        }
        Sys.sleep(0.05)
      }
    },
    error = function(e) {
      # If reading the startup line fails, the process may still be alive.
    }
  )

  # Fallback: if we couldn't read the startup line, just check if alive.
  if (!p$is_alive()) {
    stop("xtweetsR sidecar failed to start.", call. = FALSE)
  }

  p
}

#' Send a JSONL request to the sidecar and return the response.
#'
#' @param proc A `processx::process` object (the running sidecar).
#' @param method Character string, the method name (e.g. `"ping"`).
#' @param params Optional list, the request parameters.
#' @param id Optional identifier echoed in the response. Defaults to `method`.
#' @return A list with either `$result` (success) or `$error` (failure).
#' @noRd
.rx_send_request <- function(proc, method, params = NULL, id = method) {
  if (!proc$is_alive()) {
    stop("Sidecar process is not running.", call. = FALSE)
  }

  req <- list(id = id, method = method)
  if (!is.null(params)) {
    req$params <- params
  }

  json_req <- jsonlite::toJSON(req, auto_unbox = TRUE, pretty = FALSE)
  proc$write_input(paste0(json_req, "\n"))

  # Read the response line from stdout.
  # Timeout after 30 seconds.
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
          if (!is.null(parsed)) {
            return(parsed)
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

  list(closed = isTRUE(resp$result$closed), reason = if (!isTRUE(resp$result$closed)) resp$result$reason else NULL)
}
