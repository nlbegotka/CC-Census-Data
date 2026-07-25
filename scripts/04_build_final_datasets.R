# Step 5 (per instructions doc numbering): build final per-year datasets
#
# Joins each year's raw table pulls (decennial + long-form/ACS5), computes
# the 13 locked derived variables from the formulas in temp/formulas.rds,
# merges in land area for population density, and stacks state+county+tract
# into one dataframe per year with a geography_level column.
#
# NOT done here (deferred, per the download-only scope of this pass):
# harmonization onto 2020 boundaries, crosswalks, the full sanity-check
# report, suppression/jam-value handling, and final QA. See docs/data_dictionary_download.md.

source("scripts/00_setup.R")

formulas <- readRDS("temp/formulas.rds")
SQM_PER_SQMI <- 2589988.110336

year_datasets <- list(
  `2000` = c(sf1 = "dec_sf1", sf3 = "dec_sf3"),
  `2010` = c(sf1 = "dec_sf1", acs5 = "acs5"),
  `2020` = c(dhc = "dec_dhc", acs5 = "acs5")
)

variables_13 <- c(
  "total_population", "pct_black_nonhisp", "pct_hispanic", "pct_white_nonhisp",
  "median_age", "pct_65plus", "median_hh_income", "pct_poverty_individuals",
  "pct_le_hs_education", "pct_unemployed", "pct_renters", "pct_overcrowded"
  # population_density is computed separately (needs land area), appended after
)

read_raw <- function(year, dataset_key, dataset_label, geography) {
  path <- sprintf("data/raw/%d_%s_%s.csv", year, dataset_label, geography)
  d <- read_csv(path, show_col_types = FALSE)
  if ("estimate" %in% names(d)) {
    d <- d %>% rename(value = estimate) %>% select(GEOID, NAME, variable, value)
  } else {
    d <- d %>% select(GEOID, NAME, variable, value)
  }
  d
}

compute_variable <- function(wide, formula) {
  get_col_sum <- function(codes) {
    codes <- codes[codes %in% names(wide)]
    if (length(codes) == 0) return(rep(NA_real_, nrow(wide)))
    if (length(codes) == 1) return(wide[[codes]])
    rowSums(wide[, codes, drop = FALSE], na.rm = TRUE)
  }

  if (formula$type == "direct") {
    get_col_sum(formula$num)
  } else {
    num <- get_col_sum(formula$num)
    den <- get_col_sum(formula$den)
    round(100 * num / den, 2)
  }
}

build_year <- function(year) {
  message("=== building ", year, " ===")
  datasets <- year_datasets[[as.character(year)]]

  results <- list()
  for (geography in c("state", "county", "tract")) {
    message("  ", geography, "...")

    raw_long <- bind_rows(lapply(names(datasets), function(dataset_key) {
      read_raw(year, dataset_key, datasets[[dataset_key]], geography)
    }))

    # NAME formatting differs between decennial and ACS5 pulls for the same
    # GEOID (e.g. "Census Tract 307; Russell County; Alabama" vs
    # "Census Tract 307, Russell County, Alabama") -- take it from the first
    # (decennial) dataset only, or distinct(GEOID, NAME) below would produce
    # two rows per GEOID and silently double every downstream join.
    primary_dataset_key <- names(datasets)[1]
    name_lookup <- read_raw(year, primary_dataset_key, datasets[[primary_dataset_key]], geography) %>%
      distinct(GEOID, NAME)

    wide <- raw_long %>%
      select(GEOID, variable, value) %>%
      distinct(GEOID, variable, .keep_all = TRUE) %>%
      pivot_wider(names_from = variable, values_from = value)

    out <- wide %>% select(GEOID)
    for (v in variables_13) {
      f <- formulas[[paste0(v, "_", year)]]
      out[[v]] <- compute_variable(wide, f)
    }

    land_area <- read_csv(
      sprintf("data/raw/boundaries/%d_land_area_%s.csv", year, geography),
      show_col_types = FALSE
    )
    out <- out %>%
      left_join(land_area, by = "GEOID") %>%
      mutate(
        land_area_sqmi = land_area_sqm / SQM_PER_SQMI,
        population_density = round(total_population / land_area_sqmi, 2)
      ) %>%
      select(-land_area_sqm)

    out <- out %>%
      left_join(name_lookup, by = "GEOID") %>%
      mutate(geography_level = geography, year = year) %>%
      select(GEOID, NAME, geography_level, year, everything())

    results[[geography]] <- out
  }

  bind_rows(results)
}

for (yr in c(2000, 2010, 2020)) {
  final_df <- build_year(yr)

  # QA: percentages must fall within 0-100
  pct_cols <- names(final_df)[startsWith(names(final_df), "pct_")]
  out_of_range <- final_df %>%
    filter(if_any(all_of(pct_cols), ~ !is.na(.x) & (.x < 0 | .x > 100)))
  if (nrow(out_of_range) > 0) {
    warning(nrow(out_of_range), " rows in ", yr, " have a percentage outside 0-100 -- inspect before use.")
  }

  write_csv(final_df, sprintf("data/processed/census_%d.csv", yr))
  message(yr, ": wrote ", nrow(final_df), " rows to data/processed/census_", yr, ".csv")
  message(
    "  by geography_level: ",
    paste(capture.output(print(table(final_df$geography_level))), collapse = " ")
  )
}

message("Done.")
