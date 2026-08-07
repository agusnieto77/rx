# xtweetsR

Lightpanda browser automation for X/Twitter data collection.

An R package that controls Lightpanda (a headless browser with CDP support) and collects structured post data from X/Twitter, with network-first extraction, DOM fallback, deduplication, checkpoints, and reproducible research metadata.

## Installation

Prerequisites:

- **R >= 4.2.0**
- **Node.js >= 18** (for the TypeScript sidecar)
- **Lightpanda** running locally or reachable at a configured endpoint

```r
# Install from source (after cloning this repository)
devtools::install(".")

# Or build and install the package tarball
R CMD build .
R CMD install xtweetsR_0.1.0.tar.gz
```

Optional dependencies (for export formats):

- **arrow** -- Parquet export
- **duckdb** -- DuckDB database export

## Configuration

Lightpanda is discovered through this precedence:

1. `endpoint` argument in `x_session()`
2. `LPD_ENDPOINT` environment variable
3. Default: `ws://127.0.0.1:21111`

Authentication token (optional):

```r
Sys.setenv(LPD_TOKEN = "your-token")
```

No secrets are hardcoded.

## Quickstart

### 1. Check your environment

```r
library(xtweetsR)

x_doctor()
#> 1. R .................... OK  (4.4.2)
#> 2. Node.js .............. OK  (v22.x.x)
#> 3. Sidecar .............. OK
#> 4. Lightpanda ........... OK
#> 5. CDP .................. OK
#> 6. JavaScript ........... OK  (1 + 1 = 2)
#> 7. Network capture ...... OK
#> 8. X navigation ......... OK
```

Each check runs independently. A failure in one does not prevent later checks from running.

### 2. Create a session

```r
session <- x_session()

# With a custom Lightpanda endpoint:
session <- x_session(endpoint = "ws://192.168.1.100:21111")
```

### 3. Search for posts

```r
results <- x_search(session, query = "rstats", limit = 10)

results
#> # A tibble: 10 x 26
#>    post_id      text                    username  like_count  reply_count
#>    <chr>        <chr>                   <chr>          <int>        <int>
#>  1 19000000...  New release of the tid... rstudio       152            5
#>  2 19000000...  Announcing R 4.5.0      rstats         89            3
#>  ...
```

### 4. Explore results

The returned tibble has 26 columns covering post content, author identity, engagement metrics, relationships, media, and collection provenance.

```r
# Basic filtering with dplyr
library(dplyr)

results %>%
  filter(like_count > 50) %>%
  arrange(desc(like_count))

# Inspect collection provenance
attr(results, "rx_collection_provenance")
#> Collection provenance:
#>   collection_id : abc123...
#>   started_at    : 2026-08-07 14:30:00
#>   query         : rstats
#>   backend       : lightpanda
#>   records       : 10
#>   package_ver   : 0.1.0
#>   parser_ver    : 0.1.0
#>   schema_ver    : 0.1.0
```

### 5. Collect from a user timeline

```r
rstudio_posts <- x_user_posts(session, username = "rstudio", limit = 20)
```

### 6. Fetch a single post

```r
post <- x_post(session, post_id = "1900000000000000001")
```

### 7. Save your collection

```r
# Parquet (requires arrow)
x_save(results, "collection.parquet")

# DuckDB (requires duckdb)
x_save(results, "collection.duckdb")

# JSONL (always available)
x_save(results, "collection.jsonl")
```

### 8. Close the session

```r
x_close(session)
```

## Checkpoint & Resume

For long collections, save state and resume later:

```r
# First run -- saves checkpoint
results1 <- x_search(session, query = "rstats", limit = 100,
                     checkpoint_path = "checkpoint.json",
                     jsonl_path = "posts.jsonl")

# Resume -- skips already-seen posts
results2 <- x_search(session, query = "rstats", limit = 100,
                     resume = TRUE,
                     checkpoint_path = "checkpoint.json",
                     jsonl_path = "posts.jsonl")
```

## Debug Tools

Inspect captured network events:

```r
x_debug_network(session)
```

Inspect page DOM:

```r
x_debug_dom(session, selector = "article")
```

## Returned Data Schema

Every search function returns a tibble with 26 columns:

| Column | Type | Description |
|--------|------|-------------|
| `post_id` | character | Unique post identifier |
| `text` | character | Post content |
| `author_id` | character | Author's user ID |
| `username` | character | Author's username |
| `display_name` | character | Author's display name |
| `created_at` | character | Timestamp |
| `reply_count` | integer | Number of replies |
| `repost_count` | integer | Number of reposts |
| `like_count` | integer | Number of likes |
| `quote_count` | integer | Number of quotes |
| `bookmark_count` | integer | Number of bookmarks |
| `view_count` | integer | Number of views |
| `conversation_id` | character | Conversation/thread ID |
| `is_reply` | logical | Whether post is a reply |
| `is_repost` | logical | Whether post is a repost |
| `is_quote` | logical | Whether post is a quote |
| `reply_to_post_id` | character | ID of post being replied to |
| `quoted_post_id` | character | ID of quoted post |
| `hashtags` | list | Extracted hashtags |
| `mentions` | list | Extracted mentions |
| `urls` | list | Extracted URLs |
| `media_type` | list | Media types |
| `media_urls` | list | Media URLs |
| `collected_at` | character | ISO-8601 collection timestamp |
| `collection_query` | character | Search query or username |
| `collection_id` | character | UUID collection identifier |

## Architecture

```
R (xtweetsR) --> TypeScript sidecar --> Lightpanda (CDP) --> X/Twitter
     |                  |                        |
     |             JSON over                  Chrome Dev
     |             stdin/stdout               Protocol
     |
  tibble output
  collection provenance
  checkpoint/resume
```

The package uses a TypeScript sidecar that communicates with R via JSON Lines over stdin/stdout. The sidecar connects to Lightpanda using the Chrome DevTools Protocol (CDP). Data extraction is network-first (capturing structured API responses from X's GraphQL endpoints) with DOM fallback.
