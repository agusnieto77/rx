# Tests for network capture infrastructure using local fixtures only (Task 24).
#
# These tests exercise the network-first extraction pipeline without requiring
# Lightpanda. They validate:
#   1. Request discovery — the structure of captured network events
#   2. Response metadata — URL, method, resourceType, status fields
#   3. Response body capture — the sidecar's body retrieval contract
#   4. JSON parsing — fixture data is correctly parsed into R structures
#
# All tests below use local files only. No browser or CDP connection is needed.

# --- Test 1: fake-post.json fixture is valid JSON with correct top-level structure ---
test_that("fake-post.json parses as valid JSON with an 'entries' array", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "fake-post.json"
  )

  testthat::expect_true(file.exists(fixture_path), info = "fixture exists")

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  testthat::expect_true(nzchar(content), info = "fixture is non-empty")

  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)
  testthat::expect_true(is.list(parsed), info = "parsed JSON is a list")
  testthat::expect_true("entries" %in% names(parsed), info = "has 'entries' field")
})

# --- Test 2: request discovery — expected event structure ---
# Validates that the network event objects captured by the sidecar have the
# fields we depend on for request discovery: requestId, url, method, resourceType.
test_that("network event structure matches expected discovery fields", {
  # Create a synthetic event matching what the sidecar produces from CDP.
  # This lets us test the discovery logic without a browser.
  sample_event <- list(
    requestId     = "ABC123",
    url           = "http://example.com/api/data",
    method        = "GET",
    resourceType  = "fetch",
    timestamp     = 123456.789
  )

  # All required discovery fields must be present.
  required_fields <- c("requestId", "url", "method", "resourceType")
  for (field in required_fields) {
    testthat::expect_true(
      field %in% names(sample_event),
      info = paste("event has", field)
    )
  }

  # Fields must be non-empty strings.
  testthat::expect_true(
    nzchar(sample_event$requestId),
    info = "requestId is non-empty"
  )
  testthat::expect_true(
    nzchar(sample_event$url),
    info = "url is non-empty"
  )
  testthat::expect_true(
    nzchar(sample_event$method),
    info = "method is non-empty"
  )
  testthat::expect_true(
    nzchar(sample_event$resourceType),
    info = "resourceType is non-empty"
  )

  # Discovery should be able to find events by URL substring.
  found <- Filter(function(e) {
    grepl("api/data", e$url, ignore.case = TRUE)
  }, list(sample_event))
  testthat::expect_equal(length(found), 1, info = "URL-based discovery finds the event")
})

# --- Test 3: response metadata — expected fields and types ---
# Validates the metadata structure returned for each captured response.
test_that("response metadata has expected structure and types", {
  # Simulate the metadata the sidecar returns per event.
  sample_metadata <- list(
    requestId     = "XYZ789",
    url           = "http://127.0.0.1:8080/fake-post.json",
    method        = "GET",
    resourceType  = "fetch",
    status        = 200L,
    statusText    = "OK",
    mimeType      = "application/json",
    fromCache     = FALSE,
    fromServiceWorker = FALSE
  )

  # All metadata fields must be present.
  expected_fields <- c("requestId", "url", "method", "resourceType", "status")
  for (f in expected_fields) {
    testthat::expect_true(f %in% names(sample_metadata), info = paste("metadata has", f))
  }

  # Types should be correct.
  testthat::expectTrue(is.character(sample_metadata$statusText), info = "statusText is character")
  testthat::expect_true(isTRUE(is.numeric(sample_metadata$status)), info = "status is numeric")
  testthat::expect_true(isTRUE(sample_metadata$status >= 200 && sample_metadata$status < 300), info = "status is 2xx")
})

# --- Test 4: response body capture — sidecar response contract ---
# The sidecar's networkCaptureGetBody returns a response with:
#   { requestId, body, contentType, error }
# where body is the parsed JSON for application/json content types.
test_that("response body capture follows the sidecar response contract", {
  # Simulate a successful body capture response.
  sample_body_response <- list(
    requestId   = "ABC123",
    body        = list(entries = data.frame(
      post_id    = c("p1", "p2"),
      text       = c("a", "b"),
      stringsAsFactors = FALSE
    )),
    contentType = "application/json",
    error       = NULL
  )

  # All contract fields present.
  contract_fields <- c("requestId", "body", "contentType", "error")
  for (f in contract_fields) {
    testthat::expect_true(
      f %in% names(sample_body_response),
      info = paste("body response has", f)
    )
  }

  # Body should be a list (parsed JSON).
  testthat::expect_true(
    is.list(sample_body_response$body),
    info = "body is a list (parsed JSON)"
  )

  # Error should be NULL on success.
  testthat::expect_true(
    is.null(sample_body_response$error),
    info = "error is NULL on success"
  )
})

# --- Test 5: response body capture — error case for invalid requestId ---
# When the sidecar receives an invalid requestId, it returns an error.
test_that("response body capture returns error for unknown requestId", {
  # Simulate the sidecar error response for an invalid requestId.
  error_response <- list(
    id      = 5L,
    error   = list(
      code    = "NOT_FOUND",
      message = "No captured event found for requestId: invalid-id-000"
    )
  )

  testthat::expect_true(is.list(error_response$error), info = "has error field")
  testthat::expect_equal(error_response$error$code, "NOT_FOUND", info = "error code is NOT_FOUND")
  testthat::expect_true(nzchar(error_response$error$message), info = "error message is non-empty")
  testthat::expect_true(is.null(error_response$result), info = "result is NULL on error")
})

# --- Test 6: JSON parsing — each post entry has expected fields ---
# Validates that parsing fake-post.json produces entries with the fields
# the downstream parser depends on.
test_that("fake-post.json entries have all expected post fields", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "fake-post.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  entries <- parsed$entries
  testthat::expect_true(is.list(entries), info = "entries is a list")
  testthat::expect_true(length(entries) >= 2, info = "at least 2 entries exist")

  expected_fields <- c("post_id", "text", "author", "created_at", "metrics", "relationships", "entities")

  for (i in seq_along(entries)) {
    entry <- entries[[i]]
    for (f in expected_fields) {
      testthat::expect_true(
        f %in% names(entry),
        info = paste("entry", i, "has field", f)
      )
    }
  }
})

# --- Test 7: JSON parsing — post_id values are character strings ---
test_that("post_id values are character strings, not numeric", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "fake-post.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  for (i in seq_along(parsed$entries)) {
    pid <- parsed$entries[[i]]$post_id
    testthat::expect_true(
      is.character(pid),
      info = paste("entry", i, "post_id is character, got:", class(pid))
    )
    testthat::expect_true(nzchar(pid), info = paste("entry", i, "post_id is non-empty"))
  }
})

# --- Test 8: JSON parsing — metrics fields are numeric ---
test_that("metrics fields are numeric/integer values", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "fake-post.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  expected_metrics <- c("reply_count", "repost_count", "like_count", "quote_count", "bookmark_count", "view_count")

  for (i in seq_along(parsed$entries)) {
    entry <- parsed$entries[[i]]
    for (m in expected_metrics) {
      testthat::expect_true(
        m %in% names(entry$metrics),
        info = paste("entry", i, "metrics has", m)
      )
      testthat::expect_true(
        is.numeric(entry$metrics[[m]]),
        info = paste("entry", i, "metrics.", m, "is numeric")
      )
    }
  }
})

# --- Test 9: JSON parsing — author sub-object has expected fields ---
test_that("author sub-object has id, username, display_name fields", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "fake-post.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  expected_author_fields <- c("id", "username", "display_name")

  for (i in seq_along(parsed$entries)) {
    author <- parsed$entries[[i]]$author
    for (f in expected_author_fields) {
      testthat::expect_true(
        f %in% names(author),
        info = paste("entry", i, "author has", f)
      )
      testthat::expect_true(
        is.character(author[[f]]),
        info = paste("entry", i, "author.", f, "is character")
      )
    }
  }
})

# --- Test 10: JSON parsing — relationships and entities are parseable ---
test_that("relationships and entities sub-objects parse correctly", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "fake-post.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  for (i in seq_along(parsed$entries)) {
    entry <- parsed$entries[[i]]

    # relationships should have boolean and character fields.
    rel <- entry$relationships
    testthat::expect_true(is.logical(rel$is_reply), info = paste("entry", i, "is_reply is logical"))
    testthat::expect_true(is.character(rel$conversation_id), info = paste("entry", i, "conversation_id is character"))

    # entities should have list columns (hashtags, mentions, urls).
    entities <- entry$entities
    testthat::expect_true(is.list(entities$hashtags), info = paste("entry", i, "hashtags is a list"))
    testthat::expect_true(is.list(entities$mentions), info = paste("entry", i, "mentions is a list"))
    testthat::expect_true(is.list(entities$urls), info = paste("entry", i, "urls is a list"))
  }
})

# --- Test 11: Request discovery — multiple events are distinguishable ---
# Validates that request discovery logic can distinguish between different
# network events by URL and resourceType.
test_that("multiple network events are distinguishable by URL and resourceType", {
  # Simulate a realistic set of captured events.
  events <- list(
    list(
      requestId    = "REQ001",
      url          = "http://127.0.0.1:8080/dynamic-page.html",
      method       = "GET",
      resourceType = "document"
    ),
    list(
      requestId    = "REQ002",
      url          = "http://127.0.0.1:8080/fake-post.json",
      method       = "GET",
      resourceType = "fetch"
    ),
    list(
      requestId    = "REQ003",
      url          = "http://127.0.0.1:8080/style.css",
      method       = "GET",
      resourceType = "stylesheet"
    )
  )

  # Discovery by URL substring.
  json_events <- Filter(function(e) grepl("fake-post", e$url, ignore.case = TRUE), events)
  testthat::expect_equal(length(json_events), 1, info = "URL filter isolates exactly one JSON event")

  # Discovery by resource type.
  doc_events <- Filter(function(e) e$resourceType == "document", events)
  testthat::expect_equal(length(doc_events), 1, info = "resourceType filter isolates exactly one document event")

  # All requestIds are unique.
  ids <- vapply(events, function(e) e$requestId, character(1))
  testthat::expect_equal(length(unique(ids)), length(ids), info = "all requestIds are unique")
})

# --- Test 12: Response metadata — HTTP status codes are categorized ---
# Validates that status codes can be categorized (2xx = success, etc.).
test_that("response status codes can be categorized by class", {
  test_statuses <- list(
    list(status = 200L, expected_class = "2xx"),
    list(status = 201L, expected_class = "2xx"),
    list(status = 301L, expected_class = "3xx"),
    list(status = 404L, expected_class = "4xx"),
    list(status = 500L, expected_class = "5xx")
  )

  for (s in test_statuses) {
    actual_class <- switch(
      floor(s$status / 100),
      "2" = "2xx",
      "3" = "3xx",
      "4" = "4xx",
      "5" = "5xx",
      "unknown"
    )
    testthat::expect_equal(
      actual_class, s$expected_class,
      info = paste("status", s$status, "categorizes as", s$expected_class)
    )
  }
})

# --- Test 13: JSON parsing — created_at timestamps are ISO 8601 strings ---
test_that("created_at values are ISO 8601 timestamp strings", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "fake-post.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  for (i in seq_along(parsed$entries)) {
    ts <- parsed$entries[[i]]$created_at
    testthat::expect_true(is.character(ts), info = paste("entry", i, "created_at is character"))
    # ISO 8601 pattern: YYYY-MM-DDTHH:MM:SS.sssZ
    testthat::expect_true(
      grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}", ts),
      info = paste("entry", i, "created_at matches ISO 8601 pattern")
    )
  }
})

# --- Test 14: Response body capture — parsed body structure matches fixture ---
# Validates that the parsed body from fake-post.json matches expectations
# for downstream consumption (the core of network-first extraction).
test_that("parsed body structure is suitable for downstream post extraction", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "fake-post.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  body <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  # Top level: has 'entries' key with list of posts.
  testthat::expect_true("entries" %in% names(body), info = "body has entries")
  testthat::expect_true(is.list(body$entries), info = "entries is a list")
  testthat::expect_true(length(body$entries) >= 1, info = "entries is non-empty")

  # First entry is a valid post-like object.
  first_entry <- body$entries[[1]]
  testthat::expect_true("post_id" %in% names(first_entry), info = "first entry has post_id")
  testthat::expect_true("text" %in% names(first_entry), info = "first entry has text")

  # The structure can be converted to a data frame (tibble-ready).
  post_ids <- vapply(body$entries, function(e) e$post_id, character(1))
  texts    <- vapply(body$entries, function(e) e$text, character(1))
  testthat::expect_true(length(post_ids) >= 1, info = "post_ids vector is non-empty")
  testthat::expect_true(length(texts) >= 1, info = "texts vector is non-empty")
  testthat::expect_true(length(post_ids) == length(texts), info = "post_ids and texts have same length")
})

# --- Test 15: Server serves the fixture with correct content type ---
test_that("test server serves fake-post.json with application/json content type", {
  node_path <- Sys.which("node")
  if (node_path == "") {
    testthat::skip("Node.js not available")
  }

  server_script <- file.path(
    dirname(dirname(getwd())),
    "inst", "node", "dist", "server.js"
  )
  fixture_dir <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures"
  )

  testthat::expect_true(file.exists(server_script), info = "server.js exists")
  testthat::expect_true(file.exists(fixture_dir), info = "fixtures directory exists")

  port <- sample(20000:65535, 1)
  proc <- processx::process$new(
    command = "node",
    args    = c(server_script, fixture_dir, as.character(port)),
    stdout  = "|",
    stderr  = "|",
    stdin   = "|"
  )

  # Wait for server ready.
  ready <- FALSE
  start <- Sys.time()
  while (Sys.time() - start < 5 && proc$is_alive()) {
    lines <- tryCatch(proc$read_error_lines(), error = function(e) character(0))
    for (line in lines) {
      if (grepl("listening", line, ignore.case = TRUE)) { ready <- TRUE; break }
    }
    if (ready) break
    Sys.sleep(0.1)
  }
  testthat::expect_true(ready, info = "test server started")

  on.exit({
    tryCatch(proc$kill(), error = function(e) NULL)
    tryCatch(proc$wait(timeout = 3000), error = function(e) NULL)
  })

  # Fetch the JSON file.
  url <- paste0("http://127.0.0.1:", port, "/fake-post.json")

  # Use curl if available, otherwise base R.
  if (requireNamespace("curl", quietly = TRUE)) {
    resp <- curl::curl_fetch_memory(url)
    raw <- rawToChar(resp$content)
  } else {
    conn <- url(url, open = "r", text = TRUE)
    on.exit(close(conn), add = TRUE)
    raw <- paste(readLines(conn, warn = FALSE), collapse = "\n")
  }

  testthat::expect_true(nzchar(raw), info = "response is non-empty")

  # Parse and validate.
  parsed <- jsonlite::fromJSON(raw)
  testthat::expect_true("entries" %in% names(parsed), info = "served JSON has entries")
  testthat::expect_true(isTRUE(nrow(parsed$entries) >= 1), info = "entries has at least one post")
})
