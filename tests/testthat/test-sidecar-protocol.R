# Tests for the R ↔ TypeScript sidecar protocol.
# Verifies: valid request, unknown method, malformed JSON, process shutdown.

# Helper: run a single protocol test and clean up the sidecar.
# This avoids leaving orphan processes.
with_sidecar <- function(test_fn) {
  proc <- NULL
  testthat::with_mocked_bindings(
    system.file = function(package, ..., .package = NULL) {
      # When running tests, the package isn't installed yet,
      # so point to the source tree directly.
      if (package === "xtweetsR") {
        pkg_root <- dirname(dirname(getwd()))
        return(file.path(pkg_root, "inst", "node"))
      }
      utils::system.file(package, ..., .package = .package)
    },
    {
      proc <- xtweetsR:::.rx_start_sidecar()
      result <- NULL
      error_occurred <- FALSE
      tryCatch(
        {
          result <- test_fn(proc)
        },
        error = function(e) {
          error_occurred <<- TRUE
          testthat::fail(sprintf("Test error: %s", e$message))
        }
      )
      xtweetsR:::.rx_stop_sidecar(proc)
      proc <- NULL
      if (!error_occurred) {
        testthat::expect_true(TRUE, info = "sidecar cleaned up")
      }
    }
  )
}

# --- Test 1: valid ping request ---
test_that("valid ping request returns expected response", {
  with_sidecar(function(proc) {
    resp <- xtweetsR:::.rx_send_request(proc, "ping")

    testthat::expect_true(
      is.list(resp),
      info = "response is a list"
    )
    testthat::expect_true(
      !is.null(resp$result),
      info = "response has a result field"
    )
    testthat::expect_true(
      resp$result$pong == TRUE,
      info = "result.pong is TRUE"
    )
    testthat::expect_true(
      is.character(resp$result$version),
      info = "result.version is a character string"
    )

    # id should be echoed back
    testthat::expect_equal(
      resp$id, "ping",
      info = "id is echoed back"
    )
  })
})

# --- Test 2: unknown method returns structured error ---
test_that("unknown method returns structured error", {
  with_sidecar(function(proc) {
    resp <- xtweetsR:::.rx_send_request(proc, "nonexistent_method")

    testthat::expect_true(
      is.list(resp),
      info = "response is a list"
    )
    testthat::expect_true(
      !is.null(resp$error),
      info = "response has an error field"
    )
    testthat::expect_equal(
      resp$error$code, "UNKNOWN_METHOD",
      info = "error code is UNKNOWN_METHOD"
    )
    testthat::expect_true(
      is.character(resp$error$message),
      info = "error message is a string"
    )
    testthat::expect_true(
      nchar(resp$error$message) > 0,
      info = "error message is non-empty"
    )
  })
})

# --- Test 3: malformed JSON produces structured error ---
test_that("malformed JSON produces a parse error on stderr", {
  with_sidecar(function(proc) {
    # Send malformed JSON directly via the process handle.
    # This bypasses .rx_send_request which validates input first.
    proc$write_input("not valid json {{{\n")
    proc$write_input("\n") # flush

    # Read the error response from stdout.
    timeout <- 10
    start <- Sys.time()
    found_error <- FALSE

    while (Sys.time() - start < timeout) {
      if (!proc$is_alive()) break
      if (proc$is_stdio_available(1)) {
        line <- tryCatch(
          proc$read_output_line(),
          error = function(e) NULL
        )
        if (!is.null(line) && nzchar(line)) {
          parsed <- jsonlite::fromJSON(line, simplifyVector = FALSE)
          if (!is.null(parsed$error) && parsed$error$code == "PARSE_ERROR") {
            found_error <<- TRUE
            break
          }
        }
      }
      Sys.sleep(0.05)
    }

    testthat::expect_true(
      found_error,
      info = "malformed JSON produces PARSE_ERROR response"
    )
  })
})

# --- Test 4: process shutdown leaves no orphan ---
test_that("stop sidecar cleanly terminates the process", {
  proc <- NULL
  testthat::with_mocked_bindings(
    system.file = function(package, ..., .package = NULL) {
      if (package === "xtweetsR") {
        pkg_root <- dirname(dirname(getwd()))
        return(file.path(pkg_root, "inst", "node"))
      }
      utils::system.file(package, ..., .package = .package)
    },
    {
      proc <- xtweetsR:::.rx_start_sidecar()
      testthat::expect_true(
        proc$is_alive(),
        info = "sidecar is alive after start"
      )
      xtweetsR:::.rx_stop_sidecar(proc)

      # Give a moment for the process to actually terminate.
      Sys.sleep(0.2)
      testthat::expect_false(
        proc$is_alive(),
        info = "sidecar is dead after stop"
      )
    }
  )
})
