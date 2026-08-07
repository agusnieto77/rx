# Public API: x_session()
#
# Creates a new browser session by starting the TypeScript sidecar,
# resolving the Lightpanda endpoint, connecting the backend, and
# returning a session object that holds all state needed for the
# public API (navigate, evaluate, search, close, etc.).
#
# Session object structure:
#   $backend     - the backend object (connect, navigate, evaluate, close)
#   $endpoint    - character string, the resolved endpoint
#   $connected   - logical, whether the backend is connected
#   $close()     - clean up session resources
#   (print)      - shows backend type, endpoint, and connection status

#' Create a new browser session.
#'
#' Starts the TypeScript sidecar process, resolves the Lightpanda CDP
#' endpoint, and connects the backend. Returns a session object that
#' holds the connection state and provides a \code{close()} method for
#' cleanup.
#'
#' @param endpoint Optional character string with the CDP endpoint URL
#'   (e.g. \code{"ws://127.0.0.1:21111"}). If \code{NULL}, the
#'   endpoint is resolved using the same precedence as the internal config module
#'   (argument > \code{LPD_ENDPOINT} env var > local default).
#' @param sidecar_path Optional character string pointing to the sidecar
#'   directory (the one containing \code{dist/index.js}). If \code{NULL},
#'   the installed package's sidecar is used.
#'
#' @return A list with class \code{"xtweetsR_session"} containing:
#'   \itemize{
#'     \item \code{backend} - the backend object
#'     \item \code{endpoint} - the resolved endpoint URL
#'     \item \code{connected} - logical, whether connected
#'     \item \code{close} - method to clean up resources
#'   }
#'   The object has a \code{print} method that displays backend and
#'   connection status.
#'
#' @examples
#' \dontrun{
#'   sess <- x_session()
#'   print(sess)
#'   # ... use the session ...
#'   sess$close()
#' }
#'
#' @export
x_session <- function(endpoint = NULL, sidecar_path = NULL) {
  # Resolve endpoint using the same precedence as the config module.
  resolved <- .rx_resolve_endpoint(endpoint)

  # Create the backend (this starts the sidecar internally when connect() is called).
  backend <- .rx_new_backend(sidecar_path = sidecar_path)

  # Connect the backend.
  backend$connect()

  # Build the session object.
  session <- list(
    backend    = backend,
    endpoint   = resolved$endpoint,
    connected  = backend$connected,

    #' @description Close the session, releasing all resources.
    close = function() {
      if (is.null(session$backend)) {
        return(invisible(NULL))
      }
      session$backend$close()
      session$backend <- NULL
      session$connected <- FALSE
      invisible(NULL)
    }
  )

  class(session) <- "xtweetsR_session"
  session
}

#' Print method for xtweetsR_session objects.
#'
#' Displays the backend type, resolved endpoint, and connection status.
#'
#' @param x The session object.
#' @param ... Ignored.
#'
#' @exportS3Method base::print
#' @rdname x_session
#' @keywords internal
print.xtweetsR_session <- function(x, ...) {
  cat("<xtweetsR_session>\n")
  cat("  backend:   ", if (!is.null(x$backend)) "sidecar (lightpanda)" else "none", "\n", sep = "")
  cat("  endpoint:  ", x$endpoint, "\n", sep = "")
  cat("  connected: ", if (x$connected) "yes" else "no", "\n", sep = "")
  invisible(x)
}
