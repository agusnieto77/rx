# Internal: Lightpanda configuration discovery
#
# This module handles how the package finds a Lightpanda instance.
# Endpoint resolution follows strict precedence:
#   1. Explicit `endpoint` argument (highest priority)
#   2. `LPD_ENDPOINT` environment variable
#   3. Local default configuration (lowest priority)
#
# `LPD_TOKEN` is an optional environment variable for authentication tokens.
# No secrets are hardcoded anywhere.
#
# @name config
# @aliases config
# @keywords internal
# @examples
#   # Internal use only — not exported.
#   .rx_resolve_endpoint()
#   .rx_resolve_endpoint(endpoint = "ws://custom:21111")
NULL

#' Resolve Lightpanda connection endpoint.
#'
#' Returns a list with endpoint, token (if set), and source of the
#' endpoint value for debugging purposes.
#'
#' @param endpoint Optional character string. When provided, it takes
#'   precedence over all other sources.
#'
#' @return A list with elements:
#'   \describe{
#'     \item{endpoint}{The resolved endpoint URI string.}
#'     \item{token}{The token from \code{LPD_TOKEN}, or \code{NULL} if unset.}
#'     \item{source}{Character string describing where the endpoint came from
#'       ("argument", "env", or "default").}
#'   }
#'
#' @noRd
.rx_resolve_endpoint <- function(endpoint = NULL) {
  # 1. Explicit argument wins.
  if (!is.null(endpoint) && nzchar(endpoint)) {
    return(list(
      endpoint = endpoint,
      token    = .rx_get_token(),
      source   = "argument"
    ))
  }

  # 2. Environment variable.
  env_endpoint <- Sys.getenv("LPD_ENDPOINT")
  if (nzchar(env_endpoint)) {
    return(list(
      endpoint = env_endpoint,
      token    = .rx_get_token(),
      source   = "env"
    ))
  }

  # 3. Local default.
  list(
    endpoint = "http://127.0.0.1:21111",
    token    = .rx_get_token(),
    source   = "default"
  )
}

#' Read the optional Lightpanda token.
#'
#' @return Character string from \code{LPD_TOKEN}, or \code{NULL} if unset.
#' @noRd
.rx_get_token <- function() {
  token <- Sys.getenv("LPD_TOKEN", unset = "")
  if (nzchar(token)) {
    return(token)
  }
  NULL
}
