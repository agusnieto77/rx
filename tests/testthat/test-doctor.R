# Tests for x_doctor() (Task 20 + Task 58)
# Verifies that environment diagnostics are deterministic and report missing
# dependencies clearly. Task 58 expanded checks from 5 to 8:
#   r, nodejs, sidecar, lightpanda_connection, cdp_connection,
#   javascript_evaluation, network_capture, x_navigation

if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
}

# -- general structure --------------------------------------------------------

test_that("x_doctor returns a list with checks, results, details", {
  out <- x_doctor()
  expect_type(out$checks, "character")
  expect_type(out$results, "character")
  expect_type(out$details, "character")
  expect_equal(length(out$checks), 8L)
  expect_equal(length(out$results), 8L)
  expect_equal(length(out$details), 8L)
  expect_equal(
    out$checks,
    c("r", "nodejs", "sidecar", "lightpanda_connection", "cdp_connection",
      "javascript_evaluation", "network_capture", "x_navigation")
  )
})

test_that("x_doctor returns a rx_doctor object", {
  out <- x_doctor()
  expect_s3_class(out, "rx_doctor")
})

test_that("x_doctor prints and returns invisibly", {
  expect_invisible(x_doctor())
})

# -- R check ------------------------------------------------------------------

test_that("R check reports ok when version >= 4.2.0", {
  out <- x_doctor()
  expect_equal(out$results[1], "ok")
  expect_true(grepl("^R \\d+\\.\\d+", out$details[1]))
})

# -- Node.js check ------------------------------------------------------------

test_that("Node.js check reports ok or missing", {
  out <- x_doctor()
  expect_true(out$results[2] %in% c("ok", "missing"))
})

# -- Sidecar check ------------------------------------------------------------

test_that("sidecar reports ok when dist/index.js exists", {
  out <- x_doctor()
  expect_equal(out$results[3], "ok")
  expect_true(grepl("pong", out$details[3], ignore.case = TRUE))
})

# -- Lightpanda connection check ----------------------------------------------

test_that("lightpanda_connection reports ok or error (not crash)", {
  out <- x_doctor()
  expect_true(out$results[4] %in% c("ok", "error", "n/a", "skipped"))
})

test_that("lightpanda_connection is n/a when sidecar is missing", {
  # Temporarily hide the sidecar by running in a directory without it.
  tmp <- tempdir()
  old_wd <- getwd()
  tryCatch({
    setwd(tmp)
    # Reload to pick up the new working directory.
    if (requireNamespace("pkgload", quietly = TRUE)) {
      pkgload::load_all(quiet = TRUE)
    }
    out <- x_doctor()
    expect_equal(out$results[3], "missing")
    expect_equal(out$results[4], "n/a")
  }, finally = {
    setwd(old_wd)
    if (requireNamespace("pkgload", quietly = TRUE)) {
      pkgload::load_all(quiet = TRUE)
    }
  })
})

# -- CDP connection check -----------------------------------------------------

test_that("cdp_connection reports ok or error (not crash)", {
  out <- x_doctor()
  expect_true(out$results[5] %in% c("ok", "error", "n/a", "skipped"))
})

# -- JavaScript evaluation check ----------------------------------------------

test_that("javascript_evaluation reports ok or error (not crash)", {
  out <- x_doctor()
  expect_true(out$results[6] %in% c("ok", "error", "n/a", "skipped"))
})

test_that("javascript_evaluation detail contains '1 + 1' when ok", {
  out <- x_doctor()
  if (out$results[6] == "ok") {
    expect_true(grepl("1 \\+ 1", out$details[6]))
  }
})

# -- Network capture check ----------------------------------------------------

test_that("network_capture reports ok or error (not crash)", {
  out <- x_doctor()
  expect_true(out$results[7] %in% c("ok", "error", "n/a", "skipped"))
})

# -- X navigation check -------------------------------------------------------

test_that("x_navigation reports ok or error (not crash)", {
  out <- x_doctor()
  # X navigation may succeed or fail (X blocks automated browsers) — both are valid.
  expect_true(out$results[8] %in% c("ok", "error", "n/a", "skipped"))
})

# -- No crashes on repeated calls ---------------------------------------------

test_that("x_doctor is safe to call multiple times", {
  for (i in 1:3) {
    expect_no_error(x_doctor())
  }
})

# -- Determinism ----------------------------------------------------------------

test_that("x_doctor results are deterministic across calls", {
  r1 <- x_doctor()
  r2 <- x_doctor()
  expect_equal(r1$results, r2$results)
  expect_equal(r1$checks, r2$checks)
})

# -- Check independence -------------------------------------------------------

test_that("all check results are valid status strings", {
  out <- x_doctor()
  expect_true(all(out$results %in% c("ok", "missing", "error", "n/a", "skipped")))
})

test_that("failed check does not prevent later independent checks from running", {
  out <- x_doctor()
  # Check 1 (R) must be ok in any working environment.
  expect_equal(out$results[1], "ok")
  # All 8 checks should have a result (no gaps).
  expect_false(any(is.na(out$results)))
  expect_false(any(out$results == ""))
})
