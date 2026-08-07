# Internal: browser backend interface
#
# This module defines the backend contract that separates the public R API
# from Lightpanda-specific implementation details. All browser operations
# (connect, navigate, evaluate, close) go through a backend object that
# hides process management and CDP protocol specifics.
#
# Backend contract:
#   A backend is an R list with these elements:
#     $connected  - logical, whether a browser session is active
#     $connect()  - establish connection, return self (invisibly)
#     $navigate(url)     - navigate to URL, return list(url, status)
#     $evaluate(expr)    - evaluate JavaScript, return list(result, error)
#     $close()           - release browser resources, return invisible NULL
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
#' @return A list with `$connected` (logical) and the four contract methods.
#'
#' @seealso \code{\link{.rx_start_sidecar}}
#' @keywords internal
.rx_new_backend <- function(sidecar_path = NULL) {
  # Resolve sidecar path using the same logic as .rx_start_sidecar.
  if (!is.null(sidecar_path) && file.exists(file.path(sidecar_path, "dist", "index.js"))) {
    sc_dir <- sidecar_path
  } else {
    sc_dir <- system.file("node", package = "xtweetsR")
    if (sc_dir == "" || !file.exists(file.path(sc_dir, "dist", "index.js"))) {
      pkg_root <- normalizePath(".", mustWork = FALSE)
      dev_path <- file.path(pkg_root, "inst", "node")
      if (file.exists(file.path(dev_path, "dist", "index.js"))) {
        sc_dir <- dev_path
      } else {
        sc_dir <- NULL
      }
    }
  }

  # The backend object — a mutable closure over the process handle.
  state <- list(
    .proc     = NULL,
    .sidecar  = sc_dir,
    connected = FALSE
  )

  backend <- list(
    connected = FALSE,

    #' @description Connect to the sidecar and return the backend invisibly.
    connect = function() {
      if (state$.proc$is_alive()) {
        state$connected <- TRUE
        return(invisible(backend))
      }

      if (is.null(state$.sidecar)) {
        stop(
          "xtweetsR sidecar not found. Ensure the TypeScript sidecar is compiled (npm run build).",
          call. = FALSE
        )
      }

      proc <- .rx_start_sidecar(sidecar_path = state$.sidecar)
      state$.proc <- proc
      state$connected <- TRUE
      invisible(backend)
    },

    #' @description Navigate to a URL. Returns a list with url and status.
    navigate = function(url) {
      if (!state$connected) {
        stop("Backend not connected. Call connect() first.", call. = FALSE)
      }
      resp <- .rx_send_request(state$.proc, "navigate", list(url = url))
      if (!is.null(resp$error)) {
        list(url = url, status = "error", error = resp$error)
      } else {
        list(url = url, status = "ok", result = resp$result)
      }
    },

    #' @description Evaluate JavaScript in the current page. Returns list(result, error).
    evaluate = function(expr) {
      if (!state$connected) {
        stop("Backend not connected. Call connect() first.", call. = FALSE)
      }
      resp <- .rx_send_request(state$.proc, "evaluate", list(expr = expr))
      if (!is.null(resp$error)) {
        list(result = NULL, error = resp$error)
      } else {
        list(result = resp$result, error = NULL)
      }
    },

    #' @description Close the browser session and stop the sidecar.
    close = function() {
      invisible(.rx_stop_sidecar(state$.proc))
      state$.proc <- NULL
      state$connected <- FALSE
      invisible(NULL)
    }
  )

  backend
}
