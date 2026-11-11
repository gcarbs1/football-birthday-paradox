# Shared configuration for the numbered scripts.
# Every script starts with `source("R/setup.R")` and runs from the project
# root, for example: `Rscript R/00-data_collection.R`.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(readr)
  library(stringr)
})

if (!file.exists("R/setup.R")) {
  stop("Run the scripts from the project root.")
}

# Study scope. Transfermarkt's technical season ID is one year behind the
# displayed label: the 2025 Brasileirão has `seasonId` 2024.
competition_id <- "BRA1"
seasons <- tibble(
  season = 2018:2025,
  transfermarkt_season_id = season - 1L
)

# Project folders.
raw_dir <- file.path("data", "raw", "transfermarkt-api")
processed_dir <- file.path("data", "processed")
viz_dir <- "viz"
font_dir <- file.path("assets", "fonts")
for (directory in c(raw_dir, processed_dir, viz_dir)) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
}

file_prefix <- "brasileirao_2018_2025"

processed_path <- function(name) {
  file.path(processed_dir, str_glue("{file_prefix}_{name}.csv"))
}

write_processed <- function(data, name) {
  write_csv(data, processed_path(name), na = "")
  invisible(data)
}

read_processed <- function(name) {
  path <- processed_path(name)
  if (!file.exists(path)) {
    stop(str_glue("Missing file: {path}. Run the previous scripts first."))
  }
  # Transfermarkt identifiers are read as text.
  columns <- names(read_csv(path, n_max = 0, show_col_types = FALSE))
  id_columns <- columns[str_ends(columns, "_id")]
  id_types <- rep(list(col_character()), length(id_columns))
  types <- do.call(
    cols,
    c(set_names(id_types, id_columns), list(.default = col_guess()))
  )
  read_csv(path, col_types = types)
}
