# Keep source-checkout fixture paths available during installed-package checks.
# The package installer moves inst/tests to tests, while several legacy tests
# still resolve paths from the package root.
.rx_prepare_fixture_compat <- function() {
  package_root <- normalizePath(
    testthat::test_path("..", ".."),
    mustWork = FALSE
  )
  expected_root <- file.path(package_root, "inst", "tests", "fixtures")

  installed_root <- system.file("tests", "fixtures", package = "xtweetsR")
  if (!nzchar(installed_root) || !dir.exists(installed_root)) {
    installed_root <- file.path(package_root, "tests", "fixtures")
  }

  if (!dir.exists(expected_root) && dir.exists(installed_root)) {
    dir.create(expected_root, recursive = TRUE, showWarnings = FALSE)
    files <- list.files(installed_root, full.names = TRUE, recursive = FALSE)
    if (length(files) > 0L) {
      file.copy(files, expected_root, overwrite = TRUE)
    }
  }

  installed_node <- system.file("node", package = "xtweetsR")
  if (!nzchar(installed_node) || !dir.exists(installed_node)) {
    installed_node <- file.path(package_root, "node")
  }
  expected_node <- file.path(package_root, "inst", "node")
  if (nzchar(installed_node) && dir.exists(installed_node) &&
      !dir.exists(expected_node)) {
    dir.create(dirname(expected_node), recursive = TRUE, showWarnings = FALSE)
    file.copy(installed_node, dirname(expected_node), recursive = TRUE)
  }

  invisible(NULL)
}

.rx_prepare_fixture_compat()

rx_fixture_path <- function(...) {
  relative <- file.path(...)
  roots <- c(
    file.path(testthat::test_path("..", ".."), "inst", "tests", "fixtures"),
    file.path(testthat::test_path("..", ".."), "tests", "fixtures"),
    system.file("tests", "fixtures", package = "xtweetsR")
  )
  for (root in roots) {
    candidate <- file.path(root, relative)
    if (file.exists(candidate)) return(candidate)
  }
  ""
}
