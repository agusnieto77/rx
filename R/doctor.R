# Public API: x_doctor()
#
# Provides deterministic environment diagnostics before attempting browser
# automation. Checks (in order):
#   1. R version and minimum requirement
#   2. Node.js presence and version
#   3. TypeScript sidecar (start + ping)
#   4. Lightpanda connection (start sidecar + connect request)
#   5. CDP connection (browser close proves CDP session alive)
#   6. JavaScript evaluation (Runtime.evaluate via sidecar)
#   7. Network capture (CDP Network domain enable)
#   8. X navigation (page navigation attempt)
#
# Each check reports "ok", "missing", "error", "n/a", or "skipped".
# Checks 4-8 are skipped (n/a) when check 3 fails because they require
# a working sidecar. Checks 4-8 are "skipped" when LPD_ENDPOINT is not
# set (no Lightpanda instance to test). Checks 4-8 each start their own
# sidecar instance.
#
# @name doctor
# @aliases x_doctor
# @examples
#   \dontrun{
#     x_doctor()
#   }
# @return A list with class "rx_doctor" containing:
#   \describe{
#     \item{checks}{Named character vector of check names.}
#     \item{results}{Named character vector of status strings ("ok", "missing", "error", "n/a", "skipped").}
#     \item{details}{Named character vector of human-readable details.}
#   }
#   Prints a deterministic summary and invisibly returns the list.
# @export
x_doctor <- function() {
  checks <- character(0)
  results <- character(0)
  details <- character(0)

  # -- 1. R version -----------------------------------------------------------
  checks <- c(checks, "r")
  r_ver <- R.version$major
  r_sub <- R.version$minor
  r_full <- paste0(r_ver, ".", r_sub)
  # R 4.2.0 is the declared minimum — compare as numeric_version.
  r_ok <- as.numeric_version(r_full) >= as.numeric_version("4.2.0")
  if (r_ok) {
    results <- c(results, "ok")
    details <- c(details, paste0("R ", r_full))
  } else {
    results <- c(results, "error")
    details <- c(details, paste0("R ", r_full, " (minimum 4.2.0 required)"))
  }

  # -- 2. Node.js -------------------------------------------------------------
  checks <- c(checks, "nodejs")
  node_out <- tryCatch(
    system2("node", "--version", stdout = TRUE, stderr = TRUE),
    error = function(e) character(0)
  )
  if (length(node_out) > 0 && nzchar(trimws(node_out[[1]]))) {
    results <- c(results, "ok")
    details <- c(details, trimws(node_out[[1]]))
  } else {
    results <- c(results, "missing")
    details <- c(details, "node command not found or did not produce output")
  }

  # -- 3. TypeScript sidecar (start + ping) -----------------------------------
  checks <- c(checks, "sidecar")
  sc_dir <- tryCatch(.rx_resolve_sidecar_path(), error = function(e) NULL)
  if (is.null(sc_dir) || !file.exists(file.path(sc_dir, "dist", "index.js"))) {
    results <- c(results, "missing")
    details <- c(details, "sidecar dist/index.js not found (run npm run build in inst/node)")
    # Checks 4-8 require a working sidecar — mark them as skipped.
    results <- c(results, rep("n/a", 5L))
    checks <- c(checks, c("lightpanda_connection", "cdp_connection",
                           "javascript_evaluation", "network_capture", "x_navigation"))
    details <- c(details, rep("n/a -- sidecar not available", 5L))
    out <- list(checks = checks, results = results, details = details)
    class(out) <- "rx_doctor"
    print(out)
    return(invisible(out))
  }

  ping_result <- NULL
  proc <- NULL
  tryCatch({
    proc <- .rx_start_sidecar(sidecar_path = sc_dir)
    if (proc$is_alive()) {
      resp <- tryCatch(
        .rx_send_request(proc, "ping", reqId = function() 1L),
        error = function(e) list(error = list(code = "PING_ERROR", message = e$message))
      )
      ping_result <<- resp
    } else {
      ping_result <<- list(error = list(code = "PROCESSX_UNAVAILABLE",
                                        message = "sidecar process could not start"))
    }
  }, error = function(e) {
    ping_result <<- list(error = list(code = "SIDECAR_START_ERROR", message = e$message))
    proc <<- NULL
  }, finally = {
    tryCatch(.rx_stop_sidecar(proc), error = function(e) NULL)
  })
  if (!is.null(ping_result$error)) {
    results <- c(results, "error")
    details <- c(details, paste0("sidecar ping failed: ", ping_result$error$message))
    results <- c(results, rep("n/a", 5L))
    checks <- c(checks, c("lightpanda_connection", "cdp_connection",
                           "javascript_evaluation", "network_capture", "x_navigation"))
    details <- c(details, rep("n/a -- sidecar ping failed", 5L))
    out <- list(checks = checks, results = results, details = details)
    class(out) <- "rx_doctor"
    print(out)
    return(invisible(out))
  }
  if (isTRUE(ping_result$result$pong)) {
    results <- c(results, "ok")
    details <- c(details, paste0("pong (sidecar version ", ping_result$result$version, ")"))
  } else {
    results <- c(results, "error")
    details <- c(details, "sidecar ping returned unexpected response")
    results <- c(results, rep("n/a", 5L))
    checks <- c(checks, c("lightpanda_connection", "cdp_connection",
                           "javascript_evaluation", "network_capture", "x_navigation"))
    details <- c(details, rep("n/a -- sidecar ping failed", 5L))
    out <- list(checks = checks, results = results, details = details)
    class(out) <- "rx_doctor"
    print(out)
    return(invisible(out))
  }

  # -- 4. Lightpanda connection -----------------------------------------------
  # If LPD_ENDPOINT is not configured, skip checks 4-8 — there is no
  # Lightpanda instance to test.
  lpd_ep <- trimws(Sys.getenv("LPD_ENDPOINT"))
  if (lpd_ep == "") {
    results <- c(results, rep("skipped", 5L))
    details <- c(details, rep("LPD_ENDPOINT not set — Lightpanda not configured", 5L))
    checks <- c(checks, c("lightpanda_connection", "cdp_connection",
                           "javascript_evaluation", "network_capture", "x_navigation"))
  } else {
    checks <- c(checks, "lightpanda_connection")
    lp_result <- NULL
    proc <- NULL
    tryCatch({
    proc <- .rx_start_sidecar(sidecar_path = sc_dir)
    if (proc$is_alive()) {
      resp <- tryCatch(
        .rx_send_request(proc, "connect", list(endpoint = NULL), reqId = function() 1L),
        error = function(e) list(error = list(code = "CONNECT_ERROR", message = e$message))
      )
      lp_result <<- resp
    } else {
      lp_result <<- list(error = list(code = "PROCESS_START_FAILED",
                                      message = "sidecar process could not start"))
    }
  }, error = function(e) {
    lp_result <<- list(error = list(code = "CONNECT_ERROR", message = e$message))
    proc <<- NULL
  }, finally = {
    tryCatch(.rx_stop_sidecar(proc), error = function(e) NULL)
  })
  if (!is.null(lp_result$error)) {
    results <- c(results, "error")
    details <- c(details, paste0("connect failed: ", lp_result$error$message))
  } else if (isTRUE(lp_result$result$connected)) {
    results <- c(results, "ok")
    details <- c(details, "connected")
  } else {
    results <- c(results, "error")
    details <- c(details, "connect returned unexpected response")
  }

  # -- 5. CDP connection ------------------------------------------------------
  checks <- c(checks, "cdp_connection")
  cdp_result <- NULL
  proc <- NULL
  tryCatch({
    proc <- .rx_start_sidecar(sidecar_path = sc_dir)
    if (proc$is_alive()) {
      # Connect to create a CDP session, then close it — a successful close
      # proves the CDP session was alive.
      .rx_send_request(proc, "connect", list(endpoint = NULL), reqId = function() 1L)
      close_resp <- tryCatch(
        .rx_send_request(proc, "close", reqId = function() 2L),
        error = function(e) list(error = list(code = "CLOSE_ERROR", message = e$message))
      )
      if (!is.null(close_resp$error)) {
        cdp_result <<- close_resp
      } else if (isTRUE(close_resp$result$closed)) {
        cdp_result <<- list(result = list(closed = TRUE))
      } else {
        cdp_result <<- list(error = list(code = "CLOSE_FAILED",
                                        message = "browser close returned unexpected response"))
      }
    } else {
      cdp_result <<- list(error = list(code = "PROCESS_START_FAILED",
                                      message = "sidecar process could not start"))
    }
  }, error = function(e) {
    cdp_result <<- list(error = list(code = "CDP_ERROR", message = e$message))
    proc <<- NULL
  }, finally = {
    tryCatch(.rx_stop_sidecar(proc), error = function(e) NULL)
  })
  if (!is.null(cdp_result$error)) {
    results <- c(results, "error")
    details <- c(details, paste0("CDP session failed: ", cdp_result$error$message))
  } else if (isTRUE(cdp_result$result$closed)) {
    results <- c(results, "ok")
    details <- c(details, "CDP session opened and closed successfully")
  } else {
    results <- c(results, "error")
    details <- c(details, "CDP close returned unexpected response")
  }

  # -- 6. JavaScript evaluation -----------------------------------------------
  checks <- c(checks, "javascript_evaluation")
  js_result <- NULL
  proc <- NULL
  tryCatch({
    proc <- .rx_start_sidecar(sidecar_path = sc_dir)
    if (proc$is_alive()) {
      # Connect and evaluate "1+1" to prove JS execution works.
      .rx_send_request(proc, "connect", list(endpoint = NULL), reqId = function() 1L)
      eval_resp <- tryCatch(
        .rx_send_request(proc, "evaluate", list(expr = "1 + 1"), reqId = function() 2L),
        error = function(e) list(error = list(code = "EVAL_ERROR", message = e$message))
      )
      js_result <<- eval_resp
    } else {
      js_result <<- list(error = list(code = "PROCESS_START_FAILED",
                                      message = "sidecar process could not start"))
    }
  }, error = function(e) {
    js_result <<- list(error = list(code = "EVAL_ERROR", message = e$message))
    proc <<- NULL
  }, finally = {
    tryCatch(.rx_stop_sidecar(proc), error = function(e) NULL)
  })
  if (!is.null(js_result$error)) {
    results <- c(results, "error")
    details <- c(details, paste0("evaluation failed: ", js_result$error$message))
  } else if (!is.null(js_result$result$value) && as.numeric(js_result$result$value) == 2) {
    results <- c(results, "ok")
    details <- c(details, "1 + 1 = 2")
  } else {
    results <- c(results, "error")
    details <- c(details, "evaluation returned unexpected result")
  }

  # -- 7. Network capture -----------------------------------------------------
  checks <- c(checks, "network_capture")
  nc_result <- NULL
  proc <- NULL
  tryCatch({
    proc <- .rx_start_sidecar(sidecar_path = sc_dir)
    if (proc$is_alive()) {
      .rx_send_request(proc, "connect", list(endpoint = NULL), reqId = function() 1L)
      nc_result <<- tryCatch(
        .rx_send_request(proc, "networkCaptureEnable", list(), reqId = function() 2L),
        error = function(e) list(error = list(code = "NETWORK_ENABLE_ERROR",
                                               message = e$message))
      )
    } else {
      nc_result <<- list(error = list(code = "PROCESS_START_FAILED",
                                      message = "sidecar process could not start"))
    }
  }, error = function(e) {
    nc_result <<- list(error = list(code = "NETWORK_ERROR", message = e$message))
    proc <<- NULL
  }, finally = {
    tryCatch(.rx_stop_sidecar(proc), error = function(e) NULL)
  })
  if (!is.null(nc_result$error)) {
    results <- c(results, "error")
    details <- c(details, paste0("network capture enable failed: ", nc_result$error$message))
  } else if (isTRUE(nc_result$result$enabled)) {
    results <- c(results, "ok")
    details <- c(details, "network capture enabled")
  } else {
    results <- c(results, "error")
    details <- c(details, "network capture returned unexpected response")
  }

  # -- 8. X navigation --------------------------------------------------------
  checks <- c(checks, "x_navigation")
  nav_result <- NULL
  proc <- NULL
  tryCatch({
    proc <- .rx_start_sidecar(sidecar_path = sc_dir)
    if (proc$is_alive()) {
      .rx_send_request(proc, "connect", list(endpoint = NULL), reqId = function() 1L)
      nav_result <<- tryCatch(
        .rx_send_request(proc, "navigate", list(url = "https://x.com"), reqId = function() 2L),
        error = function(e) list(error = list(code = "NAV_ERROR", message = e$message))
      )
    } else {
      nav_result <<- list(error = list(code = "PROCESS_START_FAILED",
                                      message = "sidecar process could not start"))
    }
  }, error = function(e) {
    nav_result <<- list(error = list(code = "NAV_ERROR", message = e$message))
    proc <<- NULL
  }, finally = {
    tryCatch(.rx_stop_sidecar(proc), error = function(e) NULL)
  })
  if (!is.null(nav_result$error)) {
    results <- c(results, "error")
    details <- c(details, paste0("navigation failed: ", nav_result$error$message))
  } else {
    results <- c(results, "ok")
    details <- c(details, "navigated to x.com")
  }
  }  # end else: LPD_ENDPOINT was set

  out <- list(
    checks  = checks,
    results = results,
    details = details
  )
  class(out) <- "rx_doctor"
  print(out)
  invisible(out)
}

#' @export
print.rx_doctor <- function(x, ...) {
  cat("=== xtweetsR Doctor ===\n")
  for (i in seq_along(x$checks)) {
    status <- x$results[i]
    cat(sprintf("  %-20s [%-6s] %s\n", x$checks[i], status, x$details[i]))
  }
  n_ok <- sum(x$results == "ok")
  n_issues <- sum(x$results %in% c("missing", "error"))
  n_skipped <- sum(x$results %in% c("n/a", "skipped"))
  cat(sprintf("\n  %d ok, %d issue(s), %d skipped\n", n_ok, n_issues, n_skipped))
  invisible(x)
}
