# 02 — Poster
#
# A landscape chart (16:10, the format of the work-gallery covers) built from
# the tables in `data/processed/`:
#
# | panel | question                                                     |
# |-------|--------------------------------------------------------------|
# | left  | how many matches had a shared birthday, vs 22 random people? |
# | right | when are the starters born?                                  |
#
# One export: 32 × 20 cm at 300 dpi. Titles use ggtext; paragraphs use
# marquee, which can justify them.

source("R/setup.R")
suppressPackageStartupMessages({
  library(ggplot2)
  library(ggtext)
  library(marquee)
  library(patchwork)
  library(systemfonts)
  library(scales)
})

author <- "Gabriel Carbinatto"
poster_width <- 32
poster_height <- 20


# 1. Fonts, palette and labels -------------------------------------------------

# OFL fonts stored in `assets/fonts/`, registered for the ragg device.
register_font(
  "Libre Baskerville",
  plain = file.path(font_dir, "LibreBaskerville-Regular.ttf"),
  bold = file.path(font_dir, "LibreBaskerville-Bold.ttf"),
  italic = file.path(font_dir, "LibreBaskerville-Italic.ttf")
)

# Blue for random people, red for football starters, grey for months
# below the even-births line.
pal <- list(
  background = "#FFFFFF",
  ink = "#111111",
  muted = "#6B6B6B",
  rule = "#DCDCDC",
  random = "#0F3A7D",
  random_light = "#B9CAE6",
  players = "#A33A3F",
  below = "#C4C4C4"
)

pct <- label_percent(accuracy = 0.1)
num <- label_comma()
one_decimal <- label_number(accuracy = 0.1)
serif <- "Libre Baskerville"

# Marquee markup: `{#hex text}` colours a span.
color_text <- function(text, color) str_glue("{{{color} **{text}**}}")

# Paragraphs are justified. Line height is set in the style only, since
# marquee multiplies it by the element's or geom's own line height. Only `p` is justified: textshaping crashes when
# it justifies the empty root block that marquee always creates.
text_style <- function(align = "justified-left", lineheight = 1.35) {
  classic_style(body_font = serif, lineheight = lineheight) |>
    modify_style("p", align = align, lineheight = lineheight,
                 margin = trbl(0))
}

text_element <- function(size, color = pal$ink, margin = margin(),
                         align = "justified-left", lineheight = 1.35) {
  element_marquee(family = serif, size = size, colour = color,
                  lineheight = 1, width = unit(1, "npc"),
                  margin = margin, style = text_style(align, lineheight))
}

title_element <- function(size, margin = margin()) {
  element_markdown(family = serif, size = size, color = pal$ink,
                   margin = margin)
}


# 2. Data ----------------------------------------------------------------------

summary <- read_processed("summary")
birth_months <- read_processed("birth_months")
birth_days <- read_processed("birth_days")
seasons_covered <- read_processed("match_results") |>
  summarise(first = min(season), last = max(season))

observed <- summary$observed
observed_matches <- summary$matches_with_shared_birthday
random_expected <- round(summary$random_expected)
extra_matches <- observed_matches - random_expected

# Starters born per day in each month: dividing by the month length removes
# the difference between 28- and 31-day months, so the even-births
# reference is a single value for every month.
days_in_month <- c(31, 28.25, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
expected_per_day <- sum(birth_days$players) / sum(days_in_month)

months <- birth_months |>
  mutate(
    month_label = factor(month.abb[month], levels = month.abb),
    per_day = players / days_in_month[month],
    above = per_day > expected_per_day
  )
busiest <- slice_max(months, share, n = 1)
quietest <- slice_min(months, share, n = 1)
month_ratio <- busiest$players / quietest$players
first_half <- sum(months$players[months$month <= 6]) / sum(months$players)


# 3. Shared theme --------------------------------------------------------------

theme_panel <- function() {
  theme_void(base_family = serif) +
    theme(
      plot.background = element_rect(fill = pal$background, color = NA),
      plot.title = title_element(12.5, margin = margin(b = 6)),
      plot.subtitle = text_element(9.5, pal$muted, margin = margin(b = 18)),
      plot.title.position = "plot",
      axis.text.x = element_text(family = serif, face = "bold", size = 9,
                                 color = pal$ink, margin = margin(t = 6))
    )
}

# Text annotation; with `width` (cm) the text wraps. Short notes in narrow
# boxes are aligned towards what they label, since justifying them leaves
# wide gaps between words.
note <- function(x, y, label, hjust = 0, vjust = 0.5, size = 3.3,
                 color = pal$ink, width = NA,
                 align = if (hjust == 1) "right" else "left") {
  annotate("marquee", x = x, y = y, label = label, hjust = hjust,
           vjust = vjust, size = size, colour = color, family = serif,
           lineheight = 1, width = if (is.na(width)) NA else unit(width, "cm"),
           style = text_style(align, 1.3))
}
arrow_style <- arrow(length = unit(1.6, "mm"), type = "closed")


# 4. Left: matches with a shared birthday --------------------------------------

x_range <- c(1240, 1710)
random_matches <- read_processed("random_matches") |>
  filter(between(matches_with_shared_birthday, x_range[1], x_range[2]))
peak <- max(random_matches$probability)

matches_plot <- ggplot(random_matches,
                       aes(x = matches_with_shared_birthday, y = probability)) +
  geom_area(fill = pal$random_light, color = pal$random, linewidth = 0.6) +
  annotate("segment", x = x_range[1], xend = x_range[2], y = 0, yend = 0,
           color = pal$ink, linewidth = 0.5) +
  # Random people.
  note(random_expected - 40, peak * 0.66, width = 4, hjust = 1,
       str_glue("{color_text('22 random people', pal$random)} per match: ",
                "mean of **{num(random_expected)}** matches, 95% interval ",
                "from {num(summary$random_low)} to ",
                "{num(summary$random_high)}.")) +
  # What happened.
  annotate("segment", x = observed_matches, xend = observed_matches,
           y = 0, yend = peak * 1.02, color = pal$players, linewidth = 1.1) +
  annotate("point", x = observed_matches, y = peak * 1.02,
           color = pal$players, size = 3.4) +
  annotate("text", x = observed_matches - 9, y = peak * 1.03,
           label = num(observed_matches), hjust = 1, vjust = 1,
           family = serif, fontface = "bold", size = 7.4,
           color = pal$players) +
  note(observed_matches - 9, peak * 0.9, width = 4.2, hjust = 1, vjust = 1,
       str_glue("matches observed ({pct(observed)} of the total).")) +
  # The gap.
  annotate("segment", x = random_expected, xend = observed_matches - 6,
           y = peak * 1.16, yend = peak * 1.16, color = pal$ink,
           linewidth = 0.4, arrow = arrow_style) +
  annotate("segment", x = random_expected, xend = random_expected,
           y = peak * 1.02, yend = peak * 1.16, color = pal$ink,
           linewidth = 0.4) +
  note((random_expected + observed_matches) / 2, peak * 1.19,
       str_glue("Difference: **{num(extra_matches)}** matches"),
       hjust = 0.5, vjust = 0) +
  scale_x_continuous(breaks = seq(1300, 1700, 50), labels = num,
                     limits = x_range, expand = expansion(0)) +
  scale_y_continuous(limits = c(0, peak * 1.3), expand = expansion(0)) +
  coord_cartesian(clip = "off") +
  labs(
    title = "**Matches with two starters born on the same day**",
    subtitle = str_glue(
      "Observed count (red) and distribution expected for 22 random people ",
      "per match (blue), out of {num(summary$matches)} matches."
    )
  ) +
  theme_panel()


# 5. Right: births per month ---------------------------------------------------

months_plot <- ggplot(months, aes(x = month_label, y = per_day)) +
  geom_col(aes(fill = above), color = pal$ink, linewidth = 0.25,
           width = 0.68) +
  annotate("segment", x = 0.5, xend = 12.5, y = expected_per_day,
           yend = expected_per_day, color = pal$ink, linewidth = 0.4,
           linetype = "22") +
  geom_label(aes(label = one_decimal(per_day), color = above), vjust = -0.45,
             family = serif, fontface = "bold", size = 3.2,
             fill = pal$background, linewidth = 0,
             label.padding = unit(1.5, "pt")) +
  annotate("segment", x = 0.5, xend = 12.5, y = 0, yend = 0,
           color = pal$ink, linewidth = 0.5) +
  note(12.5, expected_per_day + 0.12, hjust = 1, vjust = 0, size = 3,
       str_glue("**{one_decimal(expected_per_day)}** per day under a ",
                "uniform distribution")) +
  note(12.5, 9.2, hjust = 1, vjust = 1, size = 3.2,
       str_glue("{month.name[busiest$month]} has **",
                "{one_decimal(month_ratio)}×** as many  \nbirths as ",
                "{month.name[quietest$month]}")) +
  scale_fill_manual(values = c(`TRUE` = pal$players, `FALSE` = pal$below),
                    guide = "none") +
  scale_color_manual(values = c(`TRUE` = pal$players, `FALSE` = pal$muted),
                     guide = "none") +
  scale_y_continuous(limits = c(0, 9.6), expand = expansion(0)) +
  coord_cartesian(clip = "off") +
  labs(
    title = "**Starters born per day, by month**",
    subtitle = str_glue(
      "Mean number of births per day in each month among the ",
      "{num(summary$unique_players)} starters, each counted once. ",
      "{label_percent(accuracy = 1)(first_half)} were born between January ",
      "and June."
    )
  ) +
  theme_panel()


# 6. Composition and export ----------------------------------------------------

# Footer: source and a note on the bias at the left, author at the right.
footer <- ggplot() +
  note(0, 0, vjust = 0, size = 3, width = 24,
       str_glue(
         "**Data**: Transfermarkt (Brazilian League, ",
         "{seasons_covered$first}–{seasons_covered$last})\n\n",
         "**Note**: matches are not independent observations. A birthday ",
         "shared by two teammates is counted in every match they start ",
         "together."
       )) +
  annotate("text", x = 1, y = 0, label = author, hjust = 1, vjust = 0,
           family = serif, fontface = "bold", size = 3, color = pal$ink) +
  scale_x_continuous(limits = c(0, 1), expand = expansion(0)) +
  scale_y_continuous(limits = c(0, 1), expand = expansion(0)) +
  coord_cartesian(clip = "off") +
  theme_void() +
  theme(plot.margin = margin(t = 26))

# Equal panel widths around a blank gap keep the split at the page centre.
panels <- matches_plot + plot_spacer() + months_plot +
  plot_layout(widths = c(1, 0.08, 1))

poster <- panels / footer +
  plot_layout(heights = c(1, 0.06)) +
  plot_annotation(
    title = "The birthday paradox among Brasileirão starters",
    subtitle = str_glue(
      "In a group of 22 people with birthdays spread evenly over the year, ",
      "the probability that at least two share a birthday is ",
      "{pct(summary$uniform)}. The chart applies this reference to the 22 ",
      "starters of each of the {num(summary$matches)} Série A matches ",
      "played between {seasons_covered$first} and {seasons_covered$last}. ",
      "The starters' births are concentrated in the first half of the ",
      "year, a pattern associated with the relative age effect, and a less ",
      "even distribution of birthdays increases the probability of ",
      "coincidences."
    ),
    theme = theme(
      plot.background = element_rect(fill = pal$background, color = NA),
      plot.title = title_element(24, margin = margin(b = 12)),
      plot.subtitle = text_element(11, pal$muted, lineheight = 1.45,
                                   margin = margin(b = 26)),
      plot.margin = margin(34, 40, 24, 40)
    )
  )

poster_path <- file.path(viz_dir,
                         str_glue("{file_prefix}_birthday_paradox.png"))
ggsave(poster_path, poster, device = ragg::agg_png, width = poster_width,
       height = poster_height, units = "cm", dpi = 300, bg = pal$background)
message(str_glue("Poster saved to {poster_path}"))
