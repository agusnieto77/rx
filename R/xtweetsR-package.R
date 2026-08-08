#' xtweetsR
#'
#' An R package that controls Lightpanda and collects structured post data
#' from X/Twitter, with network-first extraction, DOM fallback, deduplication,
#' checkpoints, persistence, and reproducible research metadata.
#'
#' @keywords internal
#' @importFrom utils packageVersion
"_PACKAGE"

# Null-coalescing operator: returns x if not NULL, otherwise y.
# Used throughout the package as a safer alternative to nested if/is.null checks.
`%||%` <- function(x, y) if (is.null(x)) y else x
