# Internal: structured error classes for actionable failures
#
# Every error uses an S3 class chain so callers can catch broadly
# (class "rx_error") or narrowly (e.g. "rx_lpd_connection_error").
#
# Error types (matching TypeScript sidecar codes):
#   LPD_CONNECTION_ERROR — CDP / Lightpanda connection failures
#   CDP_ERROR            — CDP protocol errors (already connected, not connected)
#   PAGE_LOAD_ERROR      — navigation failed
#   NETWORK_ERROR        — response body / network capture failures
#   PARSER_ERROR         — malformed or incompatible post data
#   TIMEOUT              — sidecar did not respond within timeout
#   NO_NEW_DATA          — collection stalled with no new posts
#
# Usage:
#   stop(.rx_error("message", class = "rx_lpd_connection_error"))
#
# @name errors
# @keywords internal
NULL

#' Create a structured xtweetsR error condition.
#'
#' Wraps a message in a `simpleError` and attaches an `rx_error` class
#' chain so that `tryCatch(..., error = function(e) ...)` can match
#' specific failure modes.
#'
#' The class chain is:
#'   c("<specific>", "rx_error", "error", "condition")
#'
#' @param message Character string with the error message.
#' @param class A character vector giving the specific error class
#'   (e.g. `"rx_lpd_connection_error"`). The class is appended to the
#'   standard `"rx_error"` chain.
#' @param code Optional character string with the machine-readable
#'   error code (matches the TypeScript sidecar error codes).
#' @param call The original call, passed to `simpleError`. Default `NULL`.
#' @return A structured error condition. Callers must invoke `stop()` on
#'   the return value to actually throw the error.
#'
#' @examples
#'   \dontrun{
#'     tryCatch(
#'       stop(.rx_error("not connected", class = "rx_cdp_error")),
#'       error = function(e) cat(class(e)[1], "\n")
#'     )
#'   }
#'
#' @noRd
.rx_error <- function(message, class = "rx_error", code = NULL, call = NULL) {
  err <- simpleError(message, call)
  class(err) <- c(paste0("rx_", class), "rx_error", "error", "condition")
  attr(err, "rx_error_code") <- code
  invisible(err)
}

# ---------------------------------------------------------------------------
# Error constructors — each throws immediately with a structured class.
# ---------------------------------------------------------------------------

#' Throw an LPD_CONNECTION_ERROR.
#'
#' Used when the CDP / Lightpanda connection handshake fails.
#'
#' @param message Character string.
#' @noRd
.rx_error_lpd_connection <- function(message) {
  .rx_error(message, class = "lpd_connection_error", code = "LPD_CONNECTION_ERROR")
}

#' Throw a CDP_ERROR.
#'
#' Used when a CDP-level operation fails (already connected, not
#' connected, protocol mismatch).
#'
#' @param message Character string.
#' @noRd
.rx_error_cdp <- function(message) {
  .rx_error(message, class = "cdp_error", code = "CDP_ERROR")
}

#' Throw a PAGE_LOAD_ERROR.
#'
#' Used when `Page.navigate` fails or the page never finishes loading.
#'
#' @param message Character string.
#' @noRd
.rx_error_page_load <- function(message) {
  .rx_error(message, class = "page_load_error", code = "PAGE_LOAD_ERROR")
}

#' Throw a NETWORK_ERROR.
#'
#' Used when response body retrieval or network capture fails.
#'
#' @param message Character string.
#' @noRd
.rx_error_network <- function(message) {
  .rx_error(message, class = "network_error", code = "NETWORK_ERROR")
}

#' Throw a PARSER_ERROR.
#'
#' Used when the response body is not parseable as a valid X
#' structured response (e.g. unexpected schema, missing timeline).
#'
#' @param message Character string.
#' @noRd
.rx_error_parser <- function(message) {
  .rx_error(message, class = "parser_error", code = "PARSER_ERROR")
}

#' Throw a TIMEOUT error.
#'
#' Used when the sidecar does not respond within the configured
#' timeout window.
#'
#' @param message Character string.
#' @noRd
.rx_error_timeout <- function(message) {
  .rx_error(message, class = "timeout", code = "TIMEOUT")
}

#' Throw a NO_NEW_DATA error.
#'
#' Used when the collection loop has exhausted all scroll iterations
#' without finding any new posts.
#'
#' @param message Character string.
#' @noRd
.rx_error_no_new_data <- function(message) {
  .rx_error(message, class = "no_new_data", code = "NO_NEW_DATA")
}
