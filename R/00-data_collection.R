# 00 — Data collection
#
# Builds the raw layer of the project from the Transfermarkt JSON API:
#
# | step     | endpoint                     | result                        |
# |----------|------------------------------|-------------------------------|
# | fixtures | /competition/BRA1/fixtures   | 380 matches per season        |
# | matches  | /game/{id}                   | starters and substitutes      |
# | players  | /players, in batches of 100  | dates of birth                |
# | clubs    | /clubs, in one batch         | club names                    |
#
# Every response is stored unchanged in `data/raw/transfermarkt-api/`, with
# its URL and collection time. Re-running the script reads the cache and only
# downloads what is missing; set `refresh_raw <- TRUE` to collect again.

source("R/setup.R")
suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})

api_base <- "https://tmapi.transfermarkt.technology"
refresh_raw <- FALSE
batch_size <- 100


# 1. Cached requests -----------------------------------------------------------

read_cache <- function(path) {
  connection <- gzfile(path, open = "rt", encoding = "UTF-8")
  on.exit(close(connection))
  fromJSON(paste(readLines(connection, warn = FALSE), collapse = "\n"),
           simplifyVector = FALSE)
}

# Writes to a temporary file and renames it, so a cache file is never partial.
write_cache <- function(path, url, body) {
  fetched_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  record <- str_glue(
    '{{"source_url":{toJSON(url, auto_unbox = TRUE)},',
    '"fetched_at_utc":"{fetched_at}","payload":{body}}}'
  )
  temporary <- paste0(path, ".", Sys.getpid(), ".tmp")
  connection <- gzfile(temporary, open = "wt", encoding = "UTF-8")
  writeLines(record, connection)
  close(connection)
  file.rename(temporary, path)
}

is_waf_challenge <- function(resp) {
  resp_status(resp) == 202 || resp_header_exists(resp, "x-amzn-waf-action")
}

# Returns the `data` field of the response. At most 100 requests per minute,
# with retries and exponential backoff on temporary blocks and 5xx errors.
api_get <- function(path, cache_name, query = list()) {
  cache_path <- file.path(raw_dir, str_glue("{cache_name}.json.gz"))
  if (file.exists(cache_path) && !refresh_raw) {
    return(read_cache(cache_path)$payload$data)
  }

  resp <- request(api_base) |>
    req_url_path_append(path) |>
    req_url_query(!!!query, .multi = "explode") |>
    req_headers(Accept = "application/json") |>
    req_user_agent("academic-research/football-birthday-paradox") |>
    req_timeout(60) |>
    req_throttle(capacity = 100, fill_time_s = 60) |>
    req_retry(
      max_tries = 5,
      is_transient = \(resp) {
        is_waf_challenge(resp) || resp_status(resp) %in% c(429, 500:504)
      },
      backoff = \(attempt) min(30, 2^attempt)
    ) |>
    req_perform()

  if (is_waf_challenge(resp)) {
    stop(str_glue("Transfermarkt WAF challenge at {resp$url}"))
  }
  body <- resp_body_string(resp, encoding = "UTF-8")
  payload <- fromJSON(body, simplifyVector = FALSE)
  if (!isTRUE(payload$success) || is.null(payload$data)) {
    stop(str_glue("Unexpected Transfermarkt response at {resp$url}"))
  }
  write_cache(cache_path, resp$url, body)
  payload$data
}

# Endpoints that accept several IDs (`ids[]`) are queried in batches.
api_get_batched <- function(path, ids, cache_prefix) {
  ids <- sort(unique(as.integer(ids)))
  batches <- split(ids, ceiling(seq_along(ids) / batch_size))
  imap(batches, \(batch, number) {
    api_get(
      path,
      cache_name = str_glue("{cache_prefix}_{str_pad(number, 3, pad = '0')}"),
      query = list(`ids[]` = batch)
    )
  }) |>
    list_flatten()
}


# 2. Fixtures ------------------------------------------------------------------

# Nested fields are read with `pluck()`: R's `$` completes partial names, so a
# missing `position` would silently return `positionId`.
fixtures <- seasons |>
  pmap(\(season, transfermarkt_season_id) {
    data <- api_get(
      str_glue("/competition/{competition_id}/fixtures"),
      cache_name = str_glue("fixtures_{competition_id}_season_",
                            "{transfermarkt_season_id}"),
      query = list(season = transfermarkt_season_id)
    )
    map(data$fixtures, \(round) {
      map(round$games, \(game) {
        tibble(
          game_id = as.character(pluck(game, "id")),
          season = season,
          transfermarkt_season_id = transfermarkt_season_id,
          round = as.integer(pluck(round, "gameDay")),
          kickoff_utc = pluck(game, "baseDetails", "date", "dateTimeUTC"),
          home_club_id = as.character(pluck(game, "homeClub", "clubId")),
          away_club_id = as.character(pluck(game, "awayClub", "clubId")),
          home_goals = as.integer(pluck(game, "score", "home", .default = NA)),
          away_goals = as.integer(pluck(game, "score", "away", .default = NA)),
          is_finished = isTRUE(pluck(game, "isFinished"))
        )
      })
    })
  }) |>
  list_flatten() |>
  list_flatten() |>
  list_rbind() |>
  distinct(game_id, .keep_all = TRUE)

# Every season has 38 rounds of 10 matches.
fixture_counts <- count(fixtures, season)
stopifnot(all(fixture_counts$n == 380), all(fixtures$is_finished))
message(str_glue("Fixtures: {nrow(fixtures)} matches in ",
                 "{nrow(fixture_counts)} seasons"))


# 3. Match lineups -------------------------------------------------------------

parse_lineup <- function(club, game_id, team_side) {
  groups <- list(starter = pluck(club, "lineup", "players"),
                 substitute = pluck(club, "lineup", "substitutes"))
  imap(groups, \(players, role) {
    map(players, \(player) {
      tibble(
        game_id = game_id,
        club_id = as.character(pluck(club, "clubId")),
        team_side = team_side,
        role = role,
        player_id = as.character(pluck(player, "id")),
        shirt_number = as.integer(pluck(player, "shirtNumber", .default = NA)),
        position = pluck(player, "position", "name", .default = NA_character_)
      )
    })
  }) |>
    list_flatten() |>
    list_rbind()
}

# Download every match first, then parse the lineups from the cache.
game_payloads <- map(fixtures$game_id, \(game_id) {
  api_get(str_glue("/game/{game_id}"), cache_name = str_glue("game_{game_id}"))
}, .progress = "Matches") |>
  set_names(fixtures$game_id)

lineups <- imap(game_payloads, \(game, game_id) {
  bind_rows(
    parse_lineup(pluck(game, "homeClub"), game_id, "home"),
    parse_lineup(pluck(game, "awayClub"), game_id, "away")
  )
}) |>
  list_rbind() |>
  distinct(game_id, player_id, .keep_all = TRUE)


# 4. Players and dates of birth ------------------------------------------------

players <- api_get_batched("/players", lineups$player_id, "players") |>
  map(\(profile) {
    tibble(
      player_id = as.character(pluck(profile, "id")),
      player_name = pluck(profile, "name", .default = NA_character_),
      birth_date = pluck(profile, "lifeDates", "dateOfBirth",
                         .default = NA_character_)
    )
  }) |>
  list_rbind() |>
  mutate(birth_date = as.Date(birth_date)) |>
  distinct(player_id, .keep_all = TRUE) |>
  arrange(as.integer(player_id))


# 5. Clubs ---------------------------------------------------------------------

club_ids <- c(fixtures$home_club_id, fixtures$away_club_id)
clubs <- api_get_batched("/clubs", club_ids, "clubs") |>
  map(\(club) {
    name <- pluck(club, "name", .default = NA_character_)
    tibble(
      club_id = as.character(pluck(club, "id")),
      club_name = name,
      club_short_name = pluck(club, "baseDetails", "shortName", .default = name)
    )
  }) |>
  list_rbind() |>
  arrange(club_short_name)

# Match dates are local (Brasília time), not UTC.
matches <- fixtures |>
  mutate(
    date = as.Date(as.POSIXct(kickoff_utc, format = "%Y-%m-%dT%H:%M:%S",
                              tz = "UTC"), tz = "America/Sao_Paulo")
  ) |>
  left_join(select(clubs, home_club_id = club_id, home_club = club_short_name),
            by = "home_club_id") |>
  left_join(select(clubs, away_club_id = club_id, away_club = club_short_name),
            by = "away_club_id") |>
  select(game_id, season, transfermarkt_season_id, round, date, kickoff_utc,
         home_club_id, home_club, away_club_id, away_club, home_goals,
         away_goals) |>
  arrange(season, round, date, game_id)


# 6. Audit and output ----------------------------------------------------------

collection_audit <- lineups |>
  filter(role == "starter") |>
  left_join(players, by = "player_id") |>
  group_by(game_id) |>
  summarise(starters = n(), starters_known_birth = sum(!is.na(birth_date))) |>
  right_join(select(matches, game_id, season), by = "game_id") |>
  group_by(season) |>
  summarise(
    matches = n(),
    matches_with_22_starters = sum(starters == 22, na.rm = TRUE),
    matches_with_22_known_births = sum(starters_known_birth == 22,
                                       na.rm = TRUE)
  )

write_processed(matches, "matches")
write_processed(lineups, "lineups")
write_processed(players, "players")
write_processed(clubs, "clubs")
write_processed(collection_audit, "collection_audit")

print(collection_audit)
message(str_glue("Players: {nrow(players)} ",
                 "({sum(is.na(players$birth_date))} without date of birth)"))
