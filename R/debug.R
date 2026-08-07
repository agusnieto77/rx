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
#' @seealso \code{\link[=x_session]{x_session()}}, \code{\link[=x_debug_network]{x_debug_network()}}, \code{\link[=x_debug_dom]{x_debug_dom()}}
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

#' Debug: inspect the DOM of the current page.
#'
#' Returns the full HTML of the current page, or the outer HTML of
#' elements matching a CSS selector. Useful for development and
#' debugging — inspect what the page actually contains after
#' JavaScript has executed.
#'
#' This function is separate from network capture so that DOM
#' inspection can be used independently of the extraction pipeline.
#'
#' @param session An \code{xtweetsR_session} object returned by
#'   \code{\link[=x_session]{x_session()}}.
#' @param selector Optional character string. A CSS selector to query
#'   elements. When \code{NULL} (default), the full \code{<html>}
#'   document is returned.
#'
#' @return When \code{selector} is \code{NULL}: a single-row data frame
#'   with one column \code{html} containing the full page HTML.
#'
#'   When \code{selector} is provided: a data frame with one row per
#'   matched element. Columns are:
#'   \describe{
#'     \item{index}{0-based index in the match list (integer)}
#'     \item{tagName}{Element tag name, lowercased (character)}
#'     \item{id}{Element \code{id} attribute, or \code{NA} (character)}
#'     \item{className}{Element \code{class} attribute, or \code{NA} (character)}
#'     \item{outerHTML}{Full element markup (character)}
#'   }
#'
#' @examples
#' \dontrun{
#'   sess <- x_session()
#'   sess$backend$navigate("https://example.com")
#'   # Get full page HTML
#'   html <- x_debug_dom(sess)
#'   # Get specific elements
#'   posts <- x_debug_dom(sess, selector = "[data-post-id]")
#'   print(posts)
#'   x_close(sess)
#' }
#'
#' @seealso \code{\link[=x_session]{x_session()}}, \code{\link[=x_debug_network]{x_debug_network()}}
#' @export
x_debug_dom <- function(session, selector = NULL) {
  # Guard: validate session.
  if (is.null(session) || is.null(session$backend)) {
    stop("x_debug_dom requires a valid xtweetsR_session object.", call. = FALSE)
  }
  if (!session$connected) {
    stop("x_debug_dom requires an active session. Connect first with x_session().", call. = FALSE)
  }

  # Guard: validate selector type — must be NULL or a single non-empty string.
  # Non-string, empty, or multi-element selectors would silently fall back to
  # full HTML mode on the sidecar, which is confusing for debug users.
  if (!is.null(selector)) {
    if (!is.character(selector) || length(selector) != 1L || !nzchar(selector)) {
      stop(
        "selector must be a single non-empty character string, or NULL for full HTML.",
        call. = FALSE
      )
    }
  }

  # Call backend domInspect method.
  result <- session$backend$domInspect(selector = selector)

  # Handle backend-level error (e.g., CDP not connected).
  if (!is.null(result$error)) {
    stop(
      paste0("DOM inspection failed: ", result$error$message),
      call. = FALSE
    )
  }

  res <- result$result

  if (is.null(selector)) {
    # Full HTML mode: return a single-row data frame with the html column.
    data.frame(
      html = res$html %||% "",
      stringsAsFactors = FALSE
    )
  } else {
    # Selector mode: return a data frame of matched elements.
    matches <- res$found
    if (is.null(matches) || length(matches) == 0L) {
      return(
        data.frame(
          index     = integer(0L),
          tagName   = character(0L),
          id        = character(0L),
          className = character(0L),
          outerHTML = character(0L),
          stringsAsFactors = FALSE
        )
      )
    }

    n <- length(matches)
    index     <- integer(n)
    tagName   <- character(n)
    id        <- character(n)
    className <- character(n)
    outerHTML <- character(n)

    for (i in seq_len(n)) {
      node <- matches[[i]]
      index[i]     <- i - 1L
      tagName[i]   <- node$tagName %||% NA_character_
      id[i]        <- node$id %||% NA_character_
      className[i] <- node$className %||% NA_character_
      outerHTML[i] <- node$outerHTML %||% NA_character_
    }

    data.frame(
      index     = index,
      tagName   = tagName,
      id        = id,
      className = className,
      outerHTML = outerHTML,
      stringsAsFactors = FALSE
    )
  }
}
