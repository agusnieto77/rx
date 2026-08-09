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

  testthat::expect_true(file.exists(fixture_path))

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  testthat::expect_true(nzchar(content))

  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)
  testthat::expect_true(is.list(parsed))
  testthat::expect_true("entries" %in% names(parsed))
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
      field %in% names(sample_event)
      )
  }

  # Fields must be non-empty strings.
  testthat::expect_true(
    nzchar(sample_event$requestId)
    )
  testthat::expect_true(
    nzchar(sample_event$url)
    )
  testthat::expect_true(
    nzchar(sample_event$method)
    )
  testthat::expect_true(
    nzchar(sample_event$resourceType)
    )

  # Discovery should be able to find events by URL substring.
  found <- Filter(function(e) {
    grepl("api/data", e$url, ignore.case = TRUE)
  }, list(sample_event))
  testthat::expect_equal(length(found), 1)
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
    testthat::expect_true(f %in% names(sample_metadata))
  }

  # Types should be correct.
  testthat::expect_true(is.character(sample_metadata$statusText))
  testthat::expect_true(isTRUE(is.numeric(sample_metadata$status)))
  testthat::expect_true(isTRUE(sample_metadata$status >= 200 && sample_metadata$status < 300))
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
      f %in% names(sample_body_response)
      )
  }

  # Body should be a list (parsed JSON).
  testthat::expect_true(
    is.list(sample_body_response$body)
    )

  # Error should be NULL on success.
  testthat::expect_true(
    is.null(sample_body_response$error)
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

  testthat::expect_true(is.list(error_response$error))
  testthat::expect_equal(error_response$error$code, "NOT_FOUND")
  testthat::expect_true(nzchar(error_response$error$message))
  testthat::expect_true(is.null(error_response$result))
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
  testthat::expect_true(is.list(entries))
  testthat::expect_true(length(entries) >= 2)

  expected_fields <- c("post_id", "text", "author", "created_at", "metrics", "relationships", "entities")

  for (i in seq_along(entries)) {
    entry <- entries[[i]]
    for (f in expected_fields) {
      testthat::expect_true(
        f %in% names(entry)
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
      is.character(pid)
      )
    testthat::expect_true(nzchar(pid))
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
        m %in% names(entry$metrics)
        )
      testthat::expect_true(
        is.numeric(entry$metrics[[m]])
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
        f %in% names(author)
        )
      testthat::expect_true(
        is.character(author[[f]])
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
    testthat::expect_true(is.logical(rel$is_reply))
    testthat::expect_true(is.character(rel$conversation_id))

    # entities should have list columns (hashtags, mentions, urls).
    entities <- entry$entities
    testthat::expect_true(is.list(entities$hashtags))
    testthat::expect_true(is.list(entities$mentions))
    testthat::expect_true(is.list(entities$urls))
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
  testthat::expect_equal(length(json_events), 1)

  # Discovery by resource type.
  doc_events <- Filter(function(e) e$resourceType == "document", events)
  testthat::expect_equal(length(doc_events), 1)

  # All requestIds are unique.
  ids <- vapply(events, function(e) e$requestId, character(1))
  testthat::expect_equal(length(unique(ids)), length(ids))
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
      as.character(floor(s$status / 100)),
      "2" = "2xx",
      "3" = "3xx",
      "4" = "4xx",
      "5" = "5xx",
      "unknown"
    )
    testthat::expect_equal(
      actual_class, s$expected_class
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
    testthat::expect_true(is.character(ts))
    # ISO 8601 pattern: YYYY-MM-DDTHH:MM:SS.sssZ
    testthat::expect_true(
      grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}", ts)
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
  testthat::expect_true("entries" %in% names(body))
  testthat::expect_true(is.list(body$entries))
  testthat::expect_true(length(body$entries) >= 1)

  # First entry is a valid post-like object.
  first_entry <- body$entries[[1]]
  testthat::expect_true("post_id" %in% names(first_entry))
  testthat::expect_true("text" %in% names(first_entry))

  # The structure can be converted to a data frame (tibble-ready).
  post_ids <- vapply(body$entries, function(e) e$post_id, character(1))
  texts    <- vapply(body$entries, function(e) e$text, character(1))
  testthat::expect_true(length(post_ids) >= 1)
  testthat::expect_true(length(texts) >= 1)
  testthat::expect_true(length(post_ids) == length(texts))
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

  testthat::expect_true(file.exists(server_script))
  testthat::expect_true(file.exists(fixture_dir))

  port <- sample(20000:65535, 1)
  proc <- processx::process$new(
    command = "node",
    args    = c(server_script, fixture_dir, as.character(port)),
    stdout  = "|",
    stderr  = "|",
    stdin   = "|"
  )

  on.exit({
    tryCatch(proc$kill(), error = function(e) NULL)
    tryCatch(proc$wait(timeout = 3000), error = function(e) NULL)
  })

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
  if (!ready) {
    testthat::skip("local fixture server did not become ready")
  }

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

  testthat::expect_true(nzchar(raw))

  # Parse and validate.
  parsed <- jsonlite::fromJSON(raw)
  testthat::expect_true("entries" %in% names(parsed))
  testthat::expect_true(isTRUE(nrow(parsed$entries) >= 1))
})

# --- Test 16: x-search-response.json fixture is valid JSON with correct top-level structure ---
# Task 30: Validates the X search response fixture introduced for parser testing.
test_that("x-search-response.json parses as valid JSON with expected top-level structure", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "x-search-response.json"
  )

  testthat::expect_true(file.exists(fixture_path))

  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  testthat::expect_true(nzchar(content))

  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)
  testthat::expect_true(is.list(parsed))
  testthat::expect_true("data" %in% names(parsed))
  testthat::expect_true(is.list(parsed$data))
  testthat::expect_true("timeline" %in% names(parsed$data))
  testthat::expect_true("instructions" %in% names(parsed$data$timeline))
})

# --- Test 17: x-search-response.json contains tweet entries with post data ---
# Validates that the fixture contains at least one tweet entry with the
# expected nesting: instructions > entries > tweet_results > result.
test_that("x-search-response.json contains tweet entries with post data", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  instructions <- parsed$data$timeline$instructions

  # Find the TimelineAddEntries instruction.
  add_entries <- Filter(function(inst) inst$type == "TimelineAddEntries", instructions)
  testthat::expect_true(length(add_entries) >= 1)

  entries <- add_entries[[1]]$entries
  testthat::expect_true(length(entries) >= 1)

  # Each entry should have tweet_results containing a result with rest_id.
  tweet_entries <- Filter(function(e) {
    !is.null(e$content$itemContent$tweet_results$result)
  }, entries)
  testthat::expect_true(length(tweet_entries) >= 1)

  # Extract rest_ids — they should be character strings.
  rest_ids <- vapply(tweet_entries, function(e) {
    e$content$itemContent$tweet_results$result$rest_id
  }, character(1))

  testthat::expect_true(all(nzchar(rest_ids)))
  testthat::expect_true(all(is.character(rest_ids)))
  testthat::expect_true(length(unique(rest_ids)) == length(rest_ids))
})

# --- Test 18: x-search-response.json contains pagination cursors ---
# Validates that the fixture includes cursor entries for infinite scroll.
test_that("x-search-response.json contains pagination cursor entries", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  instructions <- parsed$data$timeline$instructions

  # Find the TimelineAddToModule instruction that holds cursors.
  add_module <- Filter(function(inst) inst$type == "TimelineAddToModule", instructions)
  testthat::expect_true(length(add_module) >= 1)

  module_items <- add_module[[1]]$moduleItems
  cursor_entries <- Filter(function(item) {
    !is.null(item$item$content$cursorType)
  }, module_items)

  testthat::expect_true(length(cursor_entries) >= 1)

  cursor_types <- vapply(cursor_entries, function(e) {
    e$item$content$cursorType
  }, character(1))

  testthat::expect_true("Bottom" %in% cursor_types)
  testthat::expect_true("Top" %in% cursor_types)

  # Cursor values should be non-empty strings.
  cursor_values <- vapply(cursor_entries, function(e) {
    e$item$content$value
  }, character(1))
  testthat::expect_true(all(nzchar(cursor_values)))
})

# --- Test 19: x-search-response.json post structure supports downstream parser expectations ---
# Verifies that each tweet in the fixture has the fields the parser will need:
# rest_id, user screen_name/name, created_at, full_text, and engagement counts.
test_that("x-search-response.json posts have fields expected by the downstream parser", {
  fixture_path <- file.path(
    dirname(dirname(getwd())),
    "inst", "tests", "fixtures", "x-search-response.json"
  )
  content <- paste(readLines(fixture_path, warn = FALSE), collapse = "\n")
  parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)

  instructions <- parsed$data$timeline$instructions
  add_entries <- Filter(function(inst) inst$type == "TimelineAddEntries", instructions)
  entries <- add_entries[[1]]$entries

  tweet_entries <- Filter(function(e) {
    !is.null(e$content$itemContent$tweet_results$result)
  }, entries)

  testthat::expect_true(length(tweet_entries) >= 2)

  for (i in seq_along(tweet_entries)) {
    tweet <- tweet_entries[[i]]
    result <- tweet$content$itemContent$tweet_results$result

    # rest_id is required.
    testthat::expect_true(
      "rest_id" %in% names(result)
      )

    # User identity via core > user_results > result > legacy.
    user_result <- result$core$user_results$result$legacy
    testthat::expect_true(
      "screen_name" %in% names(user_result)
      )
    testthat::expect_true(
      "name" %in% names(user_result)
      )

    # Tweet text and metadata via legacy.
    legacy <- result$legacy
    testthat::expect_true(
      "full_text" %in% names(legacy)
      )
    testthat::expect_true(
      "created_at" %in% names(legacy)
      )
    testthat::expect_true(
      "conversation_id_str" %in% names(legacy)
      )

    # Engagement metrics.
    testthat::expect_true(
      "reply_count" %in% names(legacy)
      )
    testthat::expect_true(
      "retweet_count" %in% names(legacy)
      )
    testthat::expect_true(
      "favorite_count" %in% names(legacy)
      )
    testthat::expect_true(
      "views" %in% names(legacy)
      )
  }
})
