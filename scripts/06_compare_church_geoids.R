# Ad hoc QA: check church parquet GEOIDs against the census extraction.
#
# data/SG_data/church_2026_form_wide_annotated_08.16.2026.parquet is SG's
# annotated church/religious-organization panel (one row per ABI), with
# geoid_2000/2010/2020 (block-group level, independently spatially joined
# per decennial year) and zcta_2000/2010/2020 columns. There are no separate
# tract/county/state GEOID columns -- those are derived here by truncating
# the block-group GEOID (state = first 2 digits, county = first 5, tract =
# first 11), since Census GEOIDs are hierarchically nested.
#
# This script checks whether each of those GEOIDs -- at all 5 geography
# levels -- appears in our own data/processed/census_<year>.csv for that
# same year, following the same shape as 05_compare_sg_geoids.R (per-year
# match rate + a cross-year diagnostic for mismatches), generalized across
# geography levels instead of just county.
#
# Only rows the church data itself flags geoid_match == "Matched" are used;
# rows SG's own process already flagged as not properly geocoded would
# otherwise dilute the comparison with known-bad GEOIDs.

source("scripts/00_setup.R")

# arrow is only needed by this one ad hoc script, not the core pipeline, so
# it's checked/installed here rather than added to 00_setup.R's shared
# required_packages.
if (!requireNamespace("arrow", quietly = TRUE)) {
  install.packages("arrow", repos = "https://cloud.r-project.org")
}
library(arrow)

church_path <- "data/SG_data/church_2026_form_wide_annotated_08.16.2026.parquet"

# ---- Load only the columns needed (the file has ~90 columns total; addresses,
# SIC codes, religion-type flags, and yearly presence columns are irrelevant here) ----
church_raw <- read_parquet(church_path, col_select = c(
  "geoid_2000", "geoid_2010", "geoid_2020",
  "zcta_2000", "zcta_2010", "zcta_2020",
  "geoid_match"
))
message("Loaded ", nrow(church_raw), " church rows.")

church <- church_raw %>% filter(geoid_match == "Matched")
message(
  "Retained ", nrow(church), " rows flagged \"Matched\" (dropped ",
  nrow(church_raw) - nrow(church), " unmatched/uncertain rows)."
)

# ---- Derive state/county/tract from the block-group GEOID; block group and
# zcta are already at the right grain ----
derive_geoids <- function(df, year) {
  bg <- df[[paste0("geoid_", year)]]
  tibble(
    state = substr(bg, 1, 2),
    county = substr(bg, 1, 5),
    tract = substr(bg, 1, 11),
    `block group` = bg,
    zcta = df[[paste0("zcta_", year)]]
  )
}

geo_levels <- c("state", "county", "tract", "block group", "zcta")

# ---- Load our own processed census GEOIDs, per year x geography_level ----
census_ids <- lapply(c(`2000` = 2000, `2010` = 2010, `2020` = 2020), function(yr) {
  d <- read_csv(sprintf("data/processed/census_%d.csv", yr), show_col_types = FALSE)
  lapply(split(d$GEOID, d$geography_level), unique)
})

# ---- Per (year, geography_level) comparison + cross-year diagnostic ----
# 05_compare_sg_geoids.R's per-row purrr::map_chr + %in% lookup is fine at
# 847 counties, but block group here can have on the order of 10^4-10^5
# unique church-side GEOIDs -- so the cross-year check precomputes one
# vectorized %in% membership vector per other-year first, instead of calling
# %in% fresh for every single GEOID.
results <- bind_rows(lapply(c(2000, 2010, 2020), function(yr) {
  church_geo <- derive_geoids(church, yr)
  other_years <- setdiff(c(2000, 2010, 2020), yr)

  bind_rows(lapply(geo_levels, function(lvl) {
    church_ids <- unique(na.omit(church_geo[[lvl]]))
    this_year_ids <- census_ids[[as.character(yr)]][[lvl]]

    message(sprintf(
      "=== %d %s: %d / %d church geoids matched in census_%d.csv ===",
      yr, lvl, sum(church_ids %in% this_year_ids), length(church_ids), yr
    ))

    hits_by_year <- lapply(other_years, function(y) {
      church_ids %in% census_ids[[as.character(y)]][[lvl]]
    })

    matched_other_years <- vapply(seq_along(church_ids), function(i) {
      yrs <- other_years[vapply(hits_by_year, `[[`, logical(1), i)]
      if (length(yrs) == 0) NA_character_ else paste(yrs, collapse = ";")
    }, character(1))

    tibble(
      church_geoid = church_ids,
      geography_level = lvl,
      church_year = yr,
      matched_same_year = church_ids %in% this_year_ids,
      matched_other_years = matched_other_years
    )
  }))
}))

mismatches <- results %>% filter(!matched_same_year)
if (nrow(mismatches) > 0) {
  message(nrow(mismatches), " total mismatched geoid/year/level rows across all three years:")
  wrong_label <- mismatches %>% filter(!is.na(matched_other_years))
  no_match_any_year <- mismatches %>% filter(is.na(matched_other_years))
  message("  ", nrow(wrong_label), " match a DIFFERENT year's census data (possible mislabeled vintage).")
  message("  ", nrow(no_match_any_year), " match NO year's census data (retired/renamed FIPS/ZCTA, or outside our 48-state+DC scope).")
} else {
  message("No mismatches -- every church geoid matched its labeled year's census data, at every level.")
}

write_csv(results, "logs/church_geoid_comparison.csv")
message("Wrote logs/church_geoid_comparison.csv (", nrow(results), " rows).")
