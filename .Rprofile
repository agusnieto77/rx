# Skip R-sidecar protocol tests when processx is broken (e.g., some
# Windows/WSL environments where processx::process$new segfaults).
# Set SKIP_PROTOCOL_TESTS=true to force-skip them.
if (nzchar(Sys.getenv("SKIP_PROTOCOL_TESTS", unset = ""))) {
  options(testthat.default_reporter = "summary")
}
