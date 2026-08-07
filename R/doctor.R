# Public API: x_doctor()
#
# Provides deterministic environment diagnostics before attempting browser
# automation. Checks:
#   1. R version and minimum requirement
#   2. Node.js presence and version
#   3. Sidecar files (dist/index.js) accessibility
#   4. Sidecar compilation / runtime (attempt a ping)
#   5. Configured Lightpanda endpoint (resolution only, no connection attempt)
#
# Each check reports "ok", "missing", "error", or "n/a" so failures in
# early checks do not prevent reporting later independent checks.
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
#     \item{results}{Named character vector of status strings ("ok", "missing", "error", "n/a").}
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
  node_out <- system2("node", "--version", stdout = TRUE, stderr = TRUE)
  if (length(node_out) > 0 && nzchar(trimws(node_out[[1]]))) {
    results <- c(results, "ok")
    details <- c(details, trimws(node_out[[1]]))
  } else {
    results <- c(results, "missing")
    details <- c(details, "node command not found or did not produce output")
  }

  # -- 3. Sidecar files -------------------------------------------------------
  checks <- c(checks, "sidecar_files")
  sc_dir <- tryCatch(.rx_resolve_sidecar_path(), error = function(e) NULL)
  if (!is.null(sc_dir) && file.exists(file.path(sc_dir, "dist", "index.js"))) {
    results <- c(results, "ok")
    details <- c(details, normalizePath(file.path(sc_dir, "dist", "index.js"), mustWork = FALSE))
  } else {
    results <- c(results, "missing")
    details <- c(details, "sidecar dist/index.js not found (run npm run build in inst/node)")
  }

  # -- 4. Sidecar compilation / runtime (ping) --------------------------------
  checks <- c(checks, "sidecar_ping")
  if (is.null(sc_dir) || !file.exists(file.path(sc_dir, "dist", "index.js"))) {
    results <- c(results, "n/a")
    details <- c(details, "skipped -- sidecar files not present")
  } else {
    ping_result <- NULL
    tryCatch({
      proc <- .rx_start_sidecar(sidecar_path = sc_dir)
      if (proc$is_alive()) {
        resp <- tryCatch(
          .rx_send_request(proc, "ping", reqId = function() 1L),
          error = function(e) list(error = list(code = "PING_ERROR", message = e$message))
        )
        .rx_stop_sidecar(proc)
        ping_result <- resp
      } else {
        # processx segfault on some platforms — sidecar can't be started.
        ping_result <- list(error = list(code = "PROCESSX_UNAVAILABLE", message = "sidecar process could not start"))
      }
    }, error = function(e) {
      # processx segfault or other fatal error — treat as n/a.
      results <<- c(results, "n/a")
      details <<- c(details, paste0("sidecar ping unavailable: ", e$message))
      return(NULL)
    })
    if (!is.null(ping_result)) {
      if (!is.null(ping_result$error)) {
        results <- c(results, "error")
        details <- c(details, paste0("ping failed: ", ping_result$error$message))
      } else if (isTRUE(ping_result$result$pong)) {
        results <- c(results, "ok")
        details <- c(details, paste0("pong (sidecar version ", ping_result$result$version, ")"))
      } else {
        results <- c(results, "error")
        details <- c(details, "ping returned unexpected response")
      }
    }
  }

  # -- 5. Configured endpoint -------------------------------------------------
  checks <- c(checks, "endpoint")
  resolved <- .rx_resolve_endpoint()
  results <- c(results, "ok")
  details <- c(details, paste0(resolved$endpoint, " (", resolved$source, ")"))

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
  n_na <- sum(x$results == "n/a")
  cat(sprintf("\n  %d ok, %d issue(s), %d skipped\n", n_ok, n_issues, n_na))
  invisible(x)
}
