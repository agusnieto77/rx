test_that("package loads without error", {
  expect_silent(requireNamespace("xtweetsR", quietly = TRUE))
})
