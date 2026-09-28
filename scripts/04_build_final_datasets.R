# Step 4: build final per-year datasets
#
# Joins each year's raw table pulls (decennial + long-form/ACS5), computes
# the 13 locked derived variables, merges in land area for population
# density, and stacks state+county+tract+zcta+block group into one
# dataframe per year with a geography_level column.
#
# Variable download information can be found in scripts/variable_codes.R (sourced below),
# except pct_unemployed's 2010 entry, which is loaded from temp/pct_unemployed_2010_codes.rds
# because data subsetting was more efficient during the API call for this variable. zcta/block
# group ACS5-sourced variables have their own per-(variable, year) resolved formula, loaded from
# temp/vintage_overrides_zcta.rds / temp/vintage_overrides_blockgroup.rds (written by
# 01b_geography_vintage_discovery.R) -- see resolve_formula() below.
#
# NOT done here (deferred, per the download-only scope of this pass):
# harmonization onto 2020 boundaries, crosswalks, the full sanity-check
# report, suppression/jam-value handling, and final QA. See docs/data_dictionary_download.md.

source("scripts/00_setup.R")
source("scripts/variable_codes.R") # read through to understand download details

pct_unemployed_2010 <- readRDS("temp/pct_unemployed_2010_codes.rds")
overrides_zcta <- readRDS("temp/vintage_overrides_zcta.rds")
overrides_blockgroup <- readRDS("temp/vintage_overrides_blockgroup.rds")
SQM_PER_SQMI <- 2589988.110336

# Smoke-testing hook, off by default -- see the matching block in
# 02_pull_data.R for the rationale. Reads from and writes to the same
# test-scoped paths 02/03 used, so a restricted-scope run never touches the
# real, already-collected full-scope raw files or the real processed output.
TEST_MODE <- nzchar(Sys.getenv("PIPELINE_TEST_STATE", ""))
if (TEST_MODE) message("PIPELINE_TEST_STATE set -- reading data/raw/test/, writing data/processed/test/ (smoke-test mode).")
raw_dir <- if (TEST_MODE) "data/raw/test" else "data/raw"
boundaries_dir <- if (TEST_MODE) "data/raw/test/boundaries" else "data/raw/boundaries"
processed_dir <- if (TEST_MODE) "data/processed/test" else "data/processed"
if (TEST_MODE) dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

year_datasets <- list(
  `2000` = c(sf1 = "dec_sf1", sf3 = "dec_sf3"),
  `2010` = c(sf1 = "dec_sf1", acs5 = "acs5"),
  `2020` = c(dhc = "dec_dhc", acs5 = "acs5")
)

# File paths use "blockgroup" (no space); geography_level values keep the
# "block group" spelling used everywhere else in this pipeline.
geography_file_tag <- c(
  state = "state", county = "county", tract = "tract",
  zcta = "zcta", `block group` = "blockgroup"
)

# state/county/tract's ACS5 rows live in a normal per-(year,dataset) file,
# same as decennial. zcta/block-group ACS5 rows instead live in one combined
# file per geography covering both the 2010 and 2020 buckets (since
# different variables can resolve to different actual API vintages -- see
# 01b_geography_vintage_discovery.R), tagged with a year_bucket column.
read_raw <- function(year, dataset_key, dataset_label, geography) {
  filetag <- geography_file_tag[[geography]]
  if (geography %in% c("zcta", "block group") && dataset_key == "acs5") {
    d <- read_csv(sprintf("%s/acs5_%s_vintaged.csv", raw_dir, filetag), show_col_types = FALSE) %>%
      filter(year_bucket == year)
  } else {
    d <- read_csv(sprintf("%s/%d_%s_%s.csv", raw_dir, year, dataset_label, filetag), show_col_types = FALSE)
  }
  if ("estimate" %in% names(d)) {
    d <- d %>% rename(value = estimate) %>% select(GEOID, NAME, variable, value)
  } else {
    d <- d %>% select(GEOID, NAME, variable, value)
  }
  d
}

# state/county/tract keep exactly their existing formula (including the
# pct_unemployed/2010 RDS lookup). zcta/block-group look up whatever
# 01b_geography_vintage_discovery.R resolved for that (variable, year); a
# variable with no override row (i.e. every decennial-sourced variable,
# which needed no escalation) falls back to the same static formula
# state/county/tract use.
resolve_formula <- function(variable, year, geography) {
  if (geography %in% c("state", "county", "tract")) {
    if (variable == "pct_unemployed" && year == 2010) return(pct_unemployed_2010)
    return(variable_codes[[variable]][[as.character(year)]])
  }
  overrides <- if (geography == "zcta") overrides_zcta else overrides_blockgroup
  row <- overrides %>% filter(variable == .env$variable, year_bucket == .env$year)
  if (nrow(row) == 0) return(variable_codes[[variable]][[as.character(year)]])
  row$formula[[1]]
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
  yr <- as.character(year)

  results <- list()
  for (geography in c("state", "county", "tract", "zcta", "block group")) {
    message("  ", geography, "...")

    raw_long <- bind_rows(lapply(names(datasets), function(dataset_key) {
      read_raw(year, dataset_key, datasets[[dataset_key]], geography)
    }))

    # NAME formatting differs between decennial and ACS5 pulls for the same
    # GEOID -- take it from the first (decennial) dataset only
    primary_dataset_key <- names(datasets)[1]
    name_lookup <- read_raw(year, primary_dataset_key, datasets[[primary_dataset_key]], geography) %>%
      distinct(GEOID, NAME)

    wide <- raw_long %>%
      select(GEOID, variable, value) %>%
      distinct(GEOID, variable, .keep_all = TRUE) %>%
      pivot_wider(names_from = variable, values_from = value)

    out <- wide %>% select(GEOID)
    for (v in names(variable_codes)) {
      out[[v]] <- compute_variable(wide, resolve_formula(v, year, geography))
    }

    land_area <- read_csv(
      sprintf("%s/%d_land_area_%s.csv", boundaries_dir, year, geography_file_tag[[geography]]),
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

  out_path <- sprintf("%s/census_%d.csv", processed_dir, yr)
  write_csv(final_df, out_path)
  message(yr, ": wrote ", nrow(final_df), " rows to ", out_path)
  message(
    "  by geography_level: ",
    paste(capture.output(print(table(final_df$geography_level))), collapse = " ")
  )
}

message("Done.")
