#' Debug: inspect captured network traffic.
#'
#' Returns a data frame of network requests captured during the current
#' session. Useful for development and debugging — inspect what URLs were
#' hit, which resource types were loaded, and whether responses succeeded.
#'
#' This function retrieves all events captured since the last call and
#' clears the buffer, so repeated calls only show new traffic.
#'
#' @param session An \code{xtweetsR_session} object returned by
#'   \code{\link[=x_session]{x_session()}}.
#'
#' @return A \link[base]{data.frame} with one row per captured network
#'   event. Columns include:
#'   \describe{
#'     \item{requestId}{CDP request identifier (character)}
#'     \item{url}{Full request URL (character)}
#'     \item{method}{HTTP method, e.g. "GET" (character, may be \code{NA})}
#'     \item{resourceType}{CDP resource type, e.g. "document", "xhr" (character, may be \code{NA})}
#'     \item{status}{HTTP status code, if available (integer, may be \code{NA})}
#'     \item{protocol}{Negotiated protocol, e.g. "h2" (character, may be \code{NA})}
#'     \item{fromDiskCache}{Whether the response came from disk cache (logical)}
#'     \item{fromServiceWorker}{Whether the response was served by a service worker (logical)}
#'     \item{fromPrefetchCache}{Whether the response came from prefetch cache (logical)}
#'     \item{timedOut}{Whether the request timed out (logical)}
#'     \item{contentType}{Response content type, media type only (character, may be \code{NA})}
#'   }
#'
#' @examples
#' \dontrun{
#'   sess <- x_session()
#'   sess$backend$networkCaptureEnable()
#'   sess$backend$navigate("https://example.com")
#'   df <- x_debug_network(sess)
#'   print(df)
#'   x_close(sess)
#' }
#'
#' @seealso \code{\link[=x_session]{x_session()}}, \code{\link[=x_debug_dom]{x_debug_dom()}}
#' @export
x_debug_network <- function(session) {
  if (is.null(session) || is.null(session$backend)) {
    stop("x_debug_network requires a valid xtweetsR_session object.", call. = FALSE)
  }
  if (!session$connected) {
    stop("x_debug_network requires an active session. Connect first with x_session().", call. = FALSE)
  }

  events <- session$backend$networkCaptureGet()

  # If nothing was captured, return an empty data frame with the correct schema.
  if (length(events) == 0L) {
    return(
      data.frame(
        requestId         = character(0L),
        url               = character(0L),
        method            = character(0L),
        resourceType      = character(0L),
        status            = integer(0L),
        protocol          = character(0L),
        fromDiskCache     = logical(0L),
        fromServiceWorker = logical(0L),
        fromPrefetchCache = logical(0L),
        timedOut          = logical(0L),
        contentType       = character(0L),
        stringsAsFactors  = FALSE
      )
    )
  }

  n <- length(events)
  requestId         <- character(n)
  url               <- character(n)
  method            <- character(n)
  resourceType      <- character(n)
  status            <- integer(n)
  protocol          <- character(n)
  fromDiskCache     <- logical(n)
  fromServiceWorker <- logical(n)
  fromPrefetchCache <- logical(n)
  timedOut          <- logical(n)
  contentType       <- character(n)

  for (i in seq_len(n)) {
    ev <- events[[i]]
    requestId[i]         <- ev$requestId         %||% ""
    url[i]               <- ev$url               %||% ""
    method[i]            <- ev$method            %||% NA_character_
    resourceType[i]      <- ev$resourceType      %||% NA_character_
    status[i]            <- as.integer(ev$status %||% NA_integer_)
    protocol[i]          <- ev$protocol          %||% NA_character_
    fromDiskCache[i]     <- as.logical(ev$fromDiskCache     %||% FALSE)
    fromServiceWorker[i] <- as.logical(ev$fromServiceWorker %||% FALSE)
    fromPrefetchCache[i] <- as.logical(ev$fromPrefetchCache %||% FALSE)
    timedOut[i]          <- as.logical(ev$timedOut          %||% FALSE)
    contentType[i]       <- ev$contentType       %||% NA_character_
  }

  data.frame(
    requestId         = requestId,
    url               = url,
    method            = method,
    resourceType      = resourceType,
    status            = status,
    protocol          = protocol,
    fromDiskCache     = fromDiskCache,
    fromServiceWorker = fromServiceWorker,
    fromPrefetchCache = fromPrefetchCache,
    timedOut          = timedOut,
    contentType       = contentType,
    stringsAsFactors  = FALSE
  )
}
