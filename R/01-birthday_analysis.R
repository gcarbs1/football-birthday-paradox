# 01 — Birthday paradox
#
# The classic paradox assumes independent birthdays spread evenly over 365
# days: with 23 people, the chance of at least one shared birthday is above
# 50%. A football match starts with 22 players on the pitch. This script
# counts the matches in which two starters share a birthday (day and month)
# and compares that share with three references:
#
# | reference   | assumption                                                |
# |-------------|-----------------------------------------------------------|
# | uniform     | all 365 days equally likely (the classic paradox)         |
# | starters    | real birthdays of the starters, 22 different players      |
# | permutation | real birthdays reshuffled among players, real lineups     |
#
# The permutation keeps who played with whom. It tests whether there are more
# coincidences than the birth distribution and the repetition of the same
# players across matches would produce on their own.

source("R/setup.R")

group_size <- 22
n_permutations <- 2000
max_group_size <- 60
set.seed(20260101)


# 1. Starters ------------------------------------------------------------------

matches <- read_processed("matches")
lineups <- read_processed("lineups")
players <- read_processed("players") |>
  mutate(birth_day = format(birth_date, "%m-%d"))

starters <- lineups |>
  filter(role == "starter") |>
  left_join(players, by = "player_id")

# A match is analysed when it has 22 starters, all with a known birth date.
complete_ids <- starters |>
  group_by(game_id) |>
  filter(n() == group_size, all(!is.na(birth_date))) |>
  distinct(game_id) |>
  pull(game_id)

starters <- filter(starters, game_id %in% complete_ids)


# 2. Shared birthdays per match ------------------------------------------------

shared_days <- starters |>
  group_by(game_id, birth_day) |>
  filter(n() >= 2) |>
  summarise(
    players = n(),
    same_club = n_distinct(club_id) == 1,
    names = str_c(player_name, collapse = " · "),
    .groups = "drop"
  )

match_results <- matches |>
  filter(game_id %in% complete_ids) |>
  select(game_id, season, round, date, home_club, away_club,
         home_goals, away_goals) |>
  left_join(
    shared_days |>
      group_by(game_id) |>
      summarise(shared_days = n(), shared_pairs = sum(choose(players, 2))),
    by = "game_id"
  ) |>
  mutate(
    across(c(shared_days, shared_pairs), \(x) coalesce(x, 0L)),
    shared_birthday = shared_days > 0
  )


# 3. Theoretical references ----------------------------------------------------

uniform_probability <- function(n, days = 365) {
  1 - prod((days - seq_len(n) + 1) / days)
}

# Drawing n different people from a pool where c_d were born on day d, the
# chance that all birthdays differ is n! · e_n(c) / (N (N - 1) ... (N - n + 1)),
# with e_n the elementary symmetric polynomial of degree n and N = Σ c_d.
# Dynamic programming gets e_1, ..., e_N in one pass, without Monte Carlo
# noise. Drawing without replacement matters: with replacement, the same
# player could appear twice in a group and "share" a birthday with himself,
# which inflates the result. With equal counts on 365 days and a large pool,
# the formula converges to the classic paradox.
collision_curve <- function(counts, max_n) {
  pool <- sum(counts)
  shares <- counts / pool
  coefficients <- c(1, rep(0, max_n))
  for (p in shares) {
    coefficients[-1] <- coefficients[-1] + p * coefficients[-(max_n + 1)]
  }
  n <- seq_len(max_n)
  # N^n / (N (N - 1) ... (N - n + 1)), on the log scale.
  correction <- exp(cumsum(log(pool) - log(pool - n + 1)))
  pmin(pmax(1 - factorial(n) * coefficients[-1] * correction, 0), 1)
}

# Each starter counts once, on the day and month of birth.
unique_starters <- starters |>
  distinct(player_id, birth_date, birth_day) |>
  mutate(month = as.integer(format(birth_date, "%m")))
day_counts <- count(unique_starters, birth_day)

birthday_curve <- tibble(
  group_size = seq_len(max_group_size),
  uniform = map_dbl(group_size, uniform_probability),
  starters = collision_curve(day_counts$n, max_group_size)
)

# 95% Wilson interval. It is descriptive: matches repeat players and are not
# independent observations; the permutation handles that dependence.
wilson_interval <- function(successes, n, z = qnorm(0.975)) {
  p <- successes / n
  center <- (p + z^2 / (2 * n)) / (1 + z^2 / n)
  margin <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / (1 + z^2 / n)
  c(low = center - margin, high = center + margin)
}


# 4. Birthday permutation ------------------------------------------------------

# Each player receives the birthday of another player drawn without
# replacement; the lineups of every match stay fixed.
player_pool <- distinct(starters, player_id, birth_day)
day_levels <- sort(unique(player_pool$birth_day))
pool_days <- match(player_pool$birth_day, day_levels)
pool_index <- match(starters$player_id, player_pool$player_id)
match_index <- match(starters$game_id, match_results$game_id)

share_with_shared_birthday <- function(days) {
  key <- match_index * 400L + days
  length(unique(match_index[duplicated(key)])) / nrow(match_results)
}

permutation <- map_dbl(seq_len(n_permutations), \(i) {
  share_with_shared_birthday(sample(pool_days)[pool_index])
})


# 5. Summary -------------------------------------------------------------------

observed <- mean(match_results$shared_birthday)
interval <- wilson_interval(sum(match_results$shared_birthday),
                            nrow(match_results))
summary <- tibble(
  group_size = group_size,
  matches = nrow(match_results),
  matches_with_shared_birthday = sum(match_results$shared_birthday),
  observed = observed,
  observed_low = interval[["low"]],
  observed_high = interval[["high"]],
  uniform = uniform_probability(group_size),
  starters = birthday_curve$starters[group_size],
  permutation_mean = mean(permutation),
  permutation_low = quantile(permutation, 0.025, names = FALSE),
  permutation_high = quantile(permutation, 0.975, names = FALSE),
  permutation_p_value = (1 + sum(abs(permutation - mean(permutation)) >=
                                   abs(observed - mean(permutation)))) /
    (1 + n_permutations),
  unique_players = nrow(unique_starters)
)

# With 22 random people in every match, matches are independent, so the
# number of matches with a shared birthday follows a binomial distribution.
random_matches <- tibble(
  matches_with_shared_birthday = 0:summary$matches,
  probability = dbinom(matches_with_shared_birthday, summary$matches,
                       summary$uniform)
) |>
  filter(probability > 1e-9)

summary <- summary |>
  mutate(
    random_expected = matches * uniform,
    random_low = qbinom(0.025, matches, uniform),
    random_high = qbinom(0.975, matches, uniform)
  )


# 6. Birth distribution --------------------------------------------------------

# Each player counts once; the expected share per month follows a year of
# 365.25 days, in which 29 February weighs a quarter of a day.
days_in_month <- c(31, 28.25, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
calendar <- tibble(date = seq(as.Date("2024-01-01"), as.Date("2024-12-31"),
                              by = "day")) |>
  mutate(birth_day = format(date, "%m-%d"))

birth_months <- unique_starters |>
  count(month, name = "players") |>
  mutate(
    share = players / sum(players),
    expected_share = days_in_month[month] / sum(days_in_month),
    difference = share - expected_share
  )

birth_days <- calendar |>
  left_join(count(unique_starters, birth_day, name = "players"),
            by = "birth_day") |>
  mutate(players = coalesce(players, 0L)) |>
  select(birth_day, players)

regular_days <- filter(birth_days, birth_day != "02-29")
uniformity_tests <- tibble(
  scale = c("day of year (365)", "month (12)"),
  test = list(
    chisq.test(regular_days$players),
    chisq.test(birth_months$players, p = birth_months$expected_share)
  )
) |>
  mutate(
    statistic = map_dbl(test, "statistic"),
    df = map_dbl(test, "parameter"),
    p_value = map_dbl(test, "p.value")
  ) |>
  select(-test)


# 7. Output --------------------------------------------------------------------

shared_birthdays <- shared_days |>
  left_join(select(match_results, game_id, season, round, date, home_club,
                   away_club), by = "game_id") |>
  relocate(season, round, date, home_club, away_club, .after = game_id) |>
  arrange(season, round, date, game_id, birth_day)

write_processed(match_results, "match_results")
write_processed(shared_birthdays, "shared_birthdays")
write_processed(summary, "summary")
write_processed(birthday_curve, "birthday_curve")
write_processed(random_matches, "random_matches")
write_processed(birth_months, "birth_months")
write_processed(birth_days, "birth_days")
write_processed(uniformity_tests, "uniformity_tests")
write_processed(tibble(share = permutation), "permutation")

summary |>
  mutate(across(where(is.double), \(x) round(x, 4))) |>
  print(width = Inf)
print(uniformity_tests)
