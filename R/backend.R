# Internal: browser backend interface
#
# This module defines the backend contract that separates the public R API
# from Lightpanda-specific implementation details. All browser operations
# (connect, navigate, evaluate, close) go through a backend object that
# hides process management and CDP protocol specifics.
#
# Backend contract:
#   A backend is an R environment with these elements:
#     $connected           - logical, whether a browser session is active
#     $connect()           - establish connection, return self (invisibly)
#     $navigate(url)       - navigate to URL, return list(url, status)
#     $evaluate(expr)      - evaluate JavaScript, return list(result, error)
#     $networkCaptureEnable() - enable CDP network event capture
#     $networkCaptureGet()     - retrieve captured network events, clear buffer
#     $networkCaptureGetBody() - retrieve response body for a captured event
#     $networkCaptureClear()   - clear captured network events
#     $close()                 - release browser resources, return invisible NULL
#
#   An environment is used instead of a list so that $<- mutations (e.g.
#   $connected <- TRUE) propagate to the caller-visible reference.
#
# The current implementation uses the TypeScript sidecar as the backend.
# Future backends (e.g., Chromium via puppeteer) would implement the same
# contract, allowing the public API to remain unchanged.
#
# @name backend
# @aliases backend
# @keywords internal
# @examples
#   # This is an internal interface — not exported.
#   # See R/sidecar.R for the sidecar client it wraps.
NULL

#' Create a new browser backend instance.
#'
#' Returns a backend object implementing the minimal contract:
#' \code{connect()}, \code{navigate()}, \code{evaluate()}, \code{close()}.
#'
#' The default backend is the TypeScript sidecar.
#'
#' @param sidecar_path Optional character string pointing to the sidecar
#'   directory (the one containing `dist/index.js`). If `NULL`, the
#'   installed package's sidecar is used.
#'
#' @return An environment with `$connected` (logical) and the four contract methods.
#'
#' @seealso The sidecar client in \code{R/sidecar.R}
#' @keywords internal
.rx_new_backend <- function(sidecar_path = NULL) {
  # Resolve sidecar path using the shared resolver.
  sc_dir <- .rx_resolve_sidecar_path(sidecar_path)

  # The backend state — use environment for proper mutable closure semantics.
  # In R, `<-` inside a closure creates a local shadow; `<<-` or `environment`
  # is required for mutations to persist to the enclosing scope.
  state <- new.env(parent = emptyenv())
  state$.proc <- NULL
  state$.sidecar <- sc_dir
  state$connected <- FALSE
  state$endpoint <- NULL

  # Per-backend request ID counter — avoids shared global state between
  # backends and makes tests deterministic.
  state$.reqId <- function() {
    state$.reqId_counter <- state$.reqId_counter + 1
    state$.reqId_counter
  }
  state$.reqId_counter <- 0

  # Use an environment for the backend so that $<- mutations propagate to
  # the caller-visible reference. A list would copy-on-modify and the caller
  # would never see $connected change.
  backend <- new.env(parent = emptyenv())
  backend$connected <- FALSE

  #' Connect to the sidecar and establish the CDP connection.
  backend$connect <- function(endpoint = NULL) {
    if (!is.null(state$.proc) && state$.proc$is_alive() && state$connected) {
      ep <- if (!is.null(endpoint)) endpoint else state$endpoint
      if (!is.null(ep) && !identical(ep, state$endpoint)) {
        cur <- if (is.null(state$endpoint)) "default endpoint (ws://127.0.0.1:21111)" else state$endpoint
        warning("Already connected to ", cur, ". Call close() first to reconnect with a different endpoint.")
      }
      return(invisible(backend))
    }

    if (is.null(state$.sidecar)) {
      stop(
        "xtweetsR sidecar not found. Ensure the TypeScript sidecar is compiled (npm run build).",
        call. = FALSE
      )
    }

    # Use provided endpoint, or fall back to stored endpoint, or let the
    # sidecar use its default (LPD_ENDPOINT env var / ws://127.0.0.1:21111).
    ep <- if (!is.null(endpoint)) endpoint else state$endpoint

    # Guard against leaking a previous process when connect() is called
    # with connected==FALSE but the old proc is still alive (e.g. connect
    # failed without full cleanup).
    if (!is.null(state$.proc) && state$.proc$is_alive()) {
      tryCatch(.rx_stop_sidecar(state$.proc), error = function(e) NULL)
      state$.proc <- NULL
    }

    proc <- .rx_start_sidecar(sidecar_path = state$.sidecar)
    state$.proc <- proc

    # Wrap in tryCatch so that a thrown error (timeout, process death)
    # still triggers cleanup instead of leaking the sidecar process.
    resp <- tryCatch(
      .rx_send_request(proc, "connect", list(endpoint = ep), reqId = state$.reqId),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      .rx_stop_sidecar(proc)
      state$.proc <- NULL
      state$connected <- FALSE
      state$endpoint <- NULL
      backend$connected <- FALSE
      stop(
        paste0("CDP connection failed: ", resp$error$message),
        call. = FALSE
      )
    }

    # Guard against malformed response lacking a $result field.
    if (is.null(resp$result)) {
      .rx_stop_sidecar(proc)
      state$.proc <- NULL
      state$connected <- FALSE
      state$endpoint <- NULL
      backend$connected <- FALSE
      stop("Malformed connect response from sidecar (missing result field)", call. = FALSE)
    }

    state$connected <- TRUE
    state$endpoint <- ep
    backend$connected <- TRUE
  }

  #' Navigate to a URL. Returns a list with url and status.
  backend$navigate <- function(url) {
    if (!state$connected) {
      stop("Backend not connected. Call connect() first.", call. = FALSE)
    }
    resp <- tryCatch(
      .rx_send_request(state$.proc, "navigate", list(url = url), reqId = state$.reqId),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      list(url = url, status = "error", error = resp$error)
    } else {
      list(url = url, status = "ok", result = resp$result)
    }
  }

  #' Evaluate JavaScript in the current page. Returns list(result, error).
  backend$evaluate <- function(expr) {
    if (!state$connected) {
      stop("Backend not connected. Call connect() first.", call. = FALSE)
    }
    resp <- tryCatch(
      .rx_send_request(state$.proc, "evaluate", list(expr = expr), reqId = state$.reqId),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      list(result = NULL, error = resp$error)
    } else {
      list(result = resp$result, error = NULL)
    }
  }

  #' Enable CDP Network domain event capture.
  #'
  #' Tells the sidecar to start listening for network events
  #' (requests, responses) over CDP. Events are stored in the
  #' sidecar and can be retrieved with `$networkCaptureGet()`.
  #'
  #' @return Invisible `TRUE` on success.
  #' @noRd
  backend$networkCaptureEnable <- function() {
    if (!state$connected) {
      stop("Backend not connected. Call connect() first.", call. = FALSE)
    }
    resp <- tryCatch(
      .rx_send_request(state$.proc, "networkCaptureEnable", list(), reqId = state$.reqId),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      stop(
        paste0("Network capture enable failed: ", resp$error$message),
        call. = FALSE
      )
    }
    invisible(TRUE)
  }

  #' Get captured network events and clear the buffer.
  #'
  #' Returns all network events captured since the last call,
  #' then clears the internal buffer so subsequent calls only
  #' return events captured after this point.
  #'
  #' @return A list of network event records, each with
  #'   `requestId`, `url`, `method`, `resourceType`, `status`, etc.
  #' @noRd
  backend$networkCaptureGet <- function() {
    if (!state$connected) {
      stop("Backend not connected. Call connect() first.", call. = FALSE)
    }
    resp <- tryCatch(
      .rx_send_request(state$.proc, "networkCaptureGet", list(), reqId = state$.reqId),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      stop(
        paste0("Network capture get failed: ", resp$error$message),
        call. = FALSE
      )
    }
    if (is.null(resp$result$events)) {
      return(list())
    }
    resp$result$events
  }

  #' Clear captured network events (internal housekeeping).
  #'
  #' @return Invisible `TRUE`.
  #' @noRd
  backend$networkCaptureClear <- function() {
    if (!state$connected) {
      return(invisible(TRUE))
    }
    resp <- tryCatch(
      .rx_send_request(state$.proc, "networkCaptureClear", list(), reqId = state$.reqId),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      stop(
        paste0("Network capture clear failed: ", resp$error$message),
        call. = FALSE
      )
    }
    invisible(TRUE)
  }

  #' Get the response body for a captured network event.
  #'
  #' Uses the CDP \code{Network.getResponseBody} method to retrieve the
  #' full response body for a specific \code{requestId}.  For JSON responses,
  #' the body is returned as a parsed R list (via jsonlite).  For other
  #' content types, the raw decoded string is returned.
  #'
  #' @param requestId Character string, the CDP request ID to retrieve.
  #' @return A list with:
  #'   \itemize{
  #'     \item \code{requestId} — the request ID
  #'     \item \code{body} — parsed JSON list / decoded string, or \code{NULL} on error
  #'     \item \code{contentType} — the response content type
  #'     \item \code{error} — error code string, or \code{NULL} on success
  #'   }
  #' @noRd
  backend$networkCaptureGetBody <- function(requestId) {
    if (!state$connected) {
      stop("Backend not connected. Call connect() first.", call. = FALSE)
    }
    resp <- tryCatch(
      .rx_send_request(state$.proc, "networkCaptureGetBody", list(requestId = requestId), reqId = state$.reqId),
      error = function(e) list(error = list(code = "SEND_REQUEST_ERROR", message = e$message))
    )
    if (!is.null(resp$error)) {
      stop(
        paste0("Network body capture failed: ", resp$error$message),
        call. = FALSE
      )
    }
    list(
      requestId     = resp$result$requestId,
      body          = resp$result$body,
      contentType   = resp$result$contentType,
      error         = resp$result$error
    )
  }

  #' Close the browser session and stop the sidecar.
  #'
  #' First sends a `close` request to the sidecar to cleanly release
  #' the CDP connection. Then stops the sidecar process.
  #' Safe to call multiple times.
  backend$close <- function() {
    # Always attempt browser cleanup — .rx_close_browser is safe when not
    # connected (returns closed=FALSE). This prevents leaking an open browser
    # when close() is called after a failed connect where state$connected is
    # FALSE but the sidecar process may still be running.
    tryCatch(
      {
        .rx_close_browser(state$.proc)
      },
      error = function(e) {
        warning("Failed to close browser session: ", e$message, call. = FALSE)
      }
    )
    invisible(.rx_stop_sidecar(state$.proc))
    state$.proc <- NULL
    state$connected <- FALSE
    backend$connected <- FALSE
    invisible(NULL)
  }

  backend
}
