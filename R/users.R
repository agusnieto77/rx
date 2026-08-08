# Internal: Canonical user extraction and representation
#
# This module extracts unique user records from parsed post data and
# represents them as a separate relational table. The users table
# complements the posts tibble without changing its structure.
#
#   posts   -> tibble with 26 columns (canonical post schema)
#   users   -> tibble with 3 columns (canonical user schema)
#   relation -> posts rows reference users via author_id
#
# The simple tibble API is preserved: existing code that only needs
# posts continues to work unchanged. The users table is available
# through the relational result object returned by search functions.
#
# @name users
# @aliases users
# @keywords internal
# @examples
#   # Internal use only — not exported.
#   # parsed <- xtweetsR:::.rx_parse_posts(response)
#   # users <- xtweetsR:::.rx_extract_users(parsed)
#   # user_tibble <- xtweetsR:::.rx_users_to_tibble(users)
NULL

#' Canonical field schema for the users table.
#'
# Defines the authoritative field order, types, and NA defaults for
# the relational users representation. Each user is uniquely
# identified by `user_id` (the X user ID, base64-encoded as returned
# by X's API).
#'
#' Fields:
#'   - user_id — character (unique identifier, X user ID)
#'   - username — character (screen name, lowercase)
#'   - display_name — character (display name, may be empty)
#'
#' @return A character vector of 3 field names in canonical order.
#' @keywords internal
.rx_users_fields <- function() {
  c("user_id", "username", "display_name")
}

#' Extract unique users from parsed post data.
#'
# Takes the list-of-vectors output from `.rx_parse_posts()` and
# extracts one row per unique author (deduplicated by `author_id`).
# The order of users follows first-seen ordering from the posts.
#'
#' @param parsed A list as returned by `.rx_parse_posts()`.
#' @return A list with three character vectors (`user_id`, `username`,
#'   `display_name`), one row per unique author. Zero rows when
#'   `parsed` is NULL or empty.
#'
#' @noRd
.rx_extract_users <- function(parsed) {
  fields <- .rx_users_fields()

  # Handle NULL / empty / unexpected input.
  if (!is.list(parsed) || !is.list(parsed$post_id) || length(parsed$post_id) == 0L) {
    result <- vector("list", length(fields))
    names(result) <- fields
    for (field in fields) {
      result[[field]] <- character(0)
    }
    return(result)
  }

  author_ids <- parsed$author_id
  usernames  <- parsed$username
  names      <- parsed$display_name
  n          <- length(author_ids)

  if (n == 0L) {
    result <- vector("list", length(fields))
    names(result) <- fields
    for (field in fields) {
      result[[field]] <- character(0)
    }
    return(result)
  }

  # Deduplicate by author_id, preserving first-seen order.
  seen <- character(0)
  user_ids <- character(0)
  user_names <- character(0)
  user_disp_names <- character(0)

  for (i in seq_len(n)) {
    aid <- author_ids[i]
    if (is.na(aid) || !nzchar(trimws(as.character(aid)))) {
      next
    }
    aid_str <- as.character(aid)
    if (aid_str %in% seen) {
      next
    }
    seen <- c(seen, aid_str)
    user_ids   <- c(user_ids, aid_str)
    user_names <- c(user_names, if (is.character(usernames[i]) && length(usernames[i]) == 1L && !is.na(usernames[i])) usernames[i] else NA_character_)
    user_disp_names <- c(user_disp_names, if (is.character(names[i]) && length(names[i]) == 1L && !is.na(names[i])) names[i] else NA_character_)
  }

  list(
    user_id      = user_ids,
    username     = user_names,
    display_name = user_disp_names
  )
}

#' Convert a users list to a tibble.
#'
# Takes the list output from `.rx_extract_users()` and builds
# a `tibble` with one row per unique user. Column types are
# preserved (all character).
#'
#' @param users A list as returned by `.rx_extract_users()`.
#' @return A `tibble` with 3 columns matching the canonical user schema.
#'   Zero rows when `users` is empty.
#'
#' @noRd
.rx_users_to_tibble <- function(users) {
  if (!is.list(users) || length(users) == 0L) {
    return(tibble::tibble(
      user_id = character(0),
      username = character(0),
      display_name = character(0)
    ))
  }

  # Guard: not enough fields.
  fields <- .rx_users_fields()
  if (!all(fields %in% names(users))) {
    return(tibble::tibble(
      user_id = character(0),
      username = character(0),
      display_name = character(0)
    ))
  }

  # Detect row count.
  n <- length(users$user_id)
  if (n == 0L) {
    return(tibble::tibble(
      user_id = character(0),
      username = character(0),
      display_name = character(0)
    ))
  }

  tibble::tibble(
    user_id      = as.character(users$user_id),
    username     = as.character(users$username),
    display_name = as.character(users$display_name)
  )
}
