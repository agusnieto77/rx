# Tests for Lightpanda configuration discovery (Task 12)
# Verifies endpoint precedence: argument > LPD_ENDPOINT > local default.
# Also verifies LPD_TOKEN handling and that config is inspectable without
# starting a browser.

# Load the package in development mode so internal functions are available.
# This is needed when running via `R CMD check` or `test_file()` directly.
if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
}

# -- helpers ------------------------------------------------------------------

# -- precedence: argument > env > default -------------------------------------

test_that("argument takes precedence over env var", {
  withr::with_envvar(
    list(LPD_ENDPOINT = "ws://env:12345"),
    {
      result <- .rx_resolve_endpoint(endpoint = "ws://arg:54321")
      expect_equal(result$endpoint, "ws://arg:54321")
      expect_equal(result$source, "argument")
    }
  )
})

test_that("env var used when no argument provided", {
  withr::with_envvar(
    list(LPD_ENDPOINT = "ws://env:12345"),
    {
      result <- .rx_resolve_endpoint()
      expect_equal(result$endpoint, "ws://env:12345")
      expect_equal(result$source, "env")
    }
  )
})

test_that("local default used when no argument and no env var", {
  withr::with_envvar(
    list(LPD_ENDPOINT = ""),
    {
      result <- .rx_resolve_endpoint()
      expect_equal(result$endpoint, "ws://127.0.0.1:21111")
      expect_equal(result$source, "default")
    }
  )
})

test_that("empty string argument falls through to env var then default", {
  withr::with_envvar(
    list(LPD_ENDPOINT = "ws://env:12345"),
    {
      # Empty string treated as missing — falls to env
      result <- .rx_resolve_endpoint(endpoint = "")
      expect_equal(result$endpoint, "ws://env:12345")
      expect_equal(result$source, "env")
    }
  )
})

test_that("whitespace-only argument falls through to env var then default", {
  withr::with_envvar(
    list(LPD_ENDPOINT = "ws://env:12345"),
    {
      # Whitespace-only string treated as missing — falls to env
      result <- .rx_resolve_endpoint(endpoint = "   ")
      expect_equal(result$endpoint, "ws://env:12345")
      expect_equal(result$source, "env")
    }
  )
})

test_that("whitespace-only falls to default when no env var", {
  withr::with_envvar(
    list(LPD_ENDPOINT = "", LPD_TOKEN = ""),
    {
      result <- .rx_resolve_endpoint(endpoint = "\t\n")
      expect_equal(result$endpoint, "ws://127.0.0.1:21111")
      expect_equal(result$source, "default")
    }
  )
})

test_that("endpoint argument is trimmed", {
  result <- .rx_resolve_endpoint(endpoint = "  ws://trimmed:1234  ")
  expect_equal(result$endpoint, "ws://trimmed:1234")
  expect_equal(result$source, "argument")
})

# -- LPD_TOKEN ----------------------------------------------------------------

test_that("token is NULL when LPD_TOKEN is not set", {
  withr::with_envvar(
    list(LPD_TOKEN = ""),
    {
      result <- .rx_resolve_endpoint()
      expect_null(result$token)
    }
  )
})

test_that("token is returned when LPD_TOKEN is set", {
  withr::with_envvar(
    list(LPD_TOKEN = "secret123"),
    {
      result <- .rx_resolve_endpoint()
      expect_equal(result$token, "secret123")
    }
  )
})

test_that("token is independent of endpoint source", {
  withr::with_envvar(
    list(LPD_TOKEN = "tok", LPD_ENDPOINT = ""),
    {
      r1 <- .rx_resolve_endpoint()
      expect_equal(r1$token, "tok")
      r2 <- .rx_resolve_endpoint(endpoint = "ws://x:1")
      expect_equal(r2$token, "tok")
    }
  )
})

# -- inspectability without starting browser ----------------------------------

test_that("resolve_endpoint does not require sidecar or browser", {
  # This test passes by design — .rx_resolve_endpoint only reads env vars.
  # If the sidecar was required, this test would fail, which is the correct behavior.
  result <- .rx_resolve_endpoint()
  expect_true(is.character(result$endpoint))
  expect_true(nzchar(result$endpoint))
  expect_true(result$source %in% c("argument", "env", "default"))
})
