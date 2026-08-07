test_that("package loads without error", {
  expect_true(requireNamespace("xtweetsR", quietly = TRUE))
})
