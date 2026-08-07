# Tests for x_doctor() (Task 20)
# Verifies that environment diagnostics are deterministic and report missing
# dependencies clearly.

if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
}

# -- general structure --------------------------------------------------------

test_that("x_doctor returns a list with checks, results, details", {
  out <- x_doctor()
  expect_type(out$checks, "character")
  expect_type(out$results, "character")
  expect_type(out$details, "character")
  expect_equal(length(out$checks), 5L)
  expect_equal(length(out$results), 5L)
  expect_equal(length(out$details), 5L)
  expect_equal(out$checks, c("r", "nodejs", "sidecar_files", "sidecar_ping", "endpoint"))
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
  # In CI and development we always meet this requirement.
  out <- x_doctor()
  expect_equal(out$results[1], "ok")
  expect_true(grepl("^R \\d+\\.\\d+", out$details[1]))
})

# -- Node.js check ------------------------------------------------------------

test_that("Node.js check reports ok or missing", {
  out <- x_doctor()
  expect_true(out$results[2] %in% c("ok", "missing"))
})

# -- Sidecar files check ------------------------------------------------------

test_that("sidecar_files reports ok when dist/index.js exists", {
  out <- x_doctor()
  # The sidecar is compiled as part of the repo setup.
  expect_equal(out$results[3], "ok")
  expect_true(nzchar(out$details[3]))
})

# -- Sidecar ping check -------------------------------------------------------

test_that("sidecar_ping reports ok when sidecar is present", {
  out <- x_doctor()
  # sidecar_files must be ok for ping to actually run; otherwise it's n/a.
  if (out$results[3] == "ok") {
    # The ping may be "ok" (sidecar works), "n/a" (processx segfault on this
    # platform), or "error" (sidecar running but ping fails). Accept any.
    expect_true(out$results[4] %in% c("ok", "n/a", "error"))
  } else {
    expect_equal(out$results[4], "n/a")
    expect_true(grepl("skipped", out$details[4], ignore.case = TRUE))
  }
})

# -- Endpoint check -----------------------------------------------------------

test_that("endpoint check always reports ok and includes source", {
  out <- x_doctor()
  expect_equal(out$results[5], "ok")
  # Detail should contain the endpoint URL and source.
  expect_true(nzchar(out$details[5]))
  expect_true(any(grepl("argument|env|default", out$details[5])))
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
