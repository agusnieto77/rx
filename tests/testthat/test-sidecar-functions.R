# Verify that the sidecar client functions exist and have the right signatures.
# Actual process-spawning tests are in test-sidecar-protocol.R.

test_that("sidecar client functions exist", {
  # Check that the internal functions are defined.
  testthat::expect_true(
    is.function(xtweetsR:::.rx_start_sidecar),
    info = ".rx_start_sidecar exists"
  )
  testthat::expect_true(
    is.function(xtweetsR:::.rx_send_request),
    info = ".rx_send_request exists"
  )
  testthat::expect_true(
    is.function(xtweetsR:::.rx_stop_sidecar),
    info = ".rx_stop_sidecar exists"
  )
})

test_that(".rx_stop_sidecar handles NULL gracefully", {
  testthat::expect_null(
    xtweetsR:::.rx_stop_sidecar(NULL),
    info = ".rx_stop_sidecar(NULL) returns NULL"
  )
})

test_that(".rx_start_sidecar has sidecar_path parameter", {
  formals_list <- formals(xtweetsR:::.rx_start_sidecar)
  testthat::expect_true(
    "sidecar_path" %in% names(formals_list),
    info = ".rx_start_sidecar accepts sidecar_path parameter"
  )
})
