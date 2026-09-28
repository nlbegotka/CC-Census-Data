# Step 2: pull raw tabular data via the Census API
#
# Pulls, for each of the 6 (year, dataset) combinations identified in
# 01_variable_discovery.R, every variable code the registry references, at
# state, county, and tract level, for the 48 contiguous states + DC.
# State and county are single nationwide calls (then filtered down to our
# 49 areas); tract-level pulls are looped one state at a time, since the
# Census API requires a state for tract-level geography.
#
# Also pulls zcta and block group, for the same 49 areas. Decennial rows
# (sf1/sf3/dhc) use the exact same fixed year as state/county/tract -- no
# vintage concept applies to a one-time full count. ACS5 rows (2010/2020
# buckets) do NOT reuse the state/county/tract vintage at these two
# geographies: 01b_geography_vintage_discovery.R already established that
# the 2006-2010 ACS5 vintage doesn't publish zcta/block-group geography at
# all, so each ACS5-sourced variable gets pulled from whatever vintage was
# resolved for it (temp/vintage_overrides_zcta.rds /
# temp/vintage_overrides_blockgroup.rds) -- state/county/tract's own ACS5
# pull below is untouched by this.
#
# Raw pulls are saved untouched to data/raw/, named {year}_{dataset}_{geography}.csv
# (zcta/block group ACS5 pulls go to acs5_{geography}_vintaged.csv instead --
# one file covering both the 2010 and 2020 buckets, since rows can span
# multiple actual API vintages; see the year_bucket/resolved_end_year
# columns added to those files).
# Every call is logged to logs/extract_log.csv.

source("scripts/00_setup.R")
options(tigris_use_cache = TRUE)

registry_df <- readRDS("temp/variable_registry.rds")

extract_codes <- function(code_str) {
  unique(unlist(regmatches(code_str, gregexpr("[A-Za-z0-9_]+[0-9]{3}[A-Za-z]?", code_str))))
}

# codes needed per (year, dataset), deduplicated
pull_plan <- registry_df %>%
  distinct(year, dataset) %>%
  rowwise() %>%
  mutate(
    variables = list(
      registry_df %>%
        filter(year == .env$year, dataset == .env$dataset) %>%
        pull(codes) %>%
        extract_codes() %>%
        unique()
    )
  ) %>%
  ungroup()

# 48 contiguous states + DC (explicit allow-list, not an exclusion list --
# fips_codes includes several territory codes, e.g. "74" for the US Minor
# Outlying Islands, that are easy to miss if filtering by exclusion instead).
contiguous_states_dc <- c(
  "AL","AZ","AR","CA","CO","CT","DE","DC","FL","GA","ID","IL","IN","IA",
  "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH",
  "NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX",
  "UT","VT","VA","WA","WV","WI","WY"
)
# Smoke-testing hook, off by default: set PIPELINE_TEST_STATE=DE (or any
# single state abbreviation) to restrict every loop below to that one state
# AND redirect every write to data/raw/test/ + logs/test_extract_log.csv --
# a real run's output paths are identical regardless of scope, so without
# this redirect a "small" test run would silently overwrite the real,
# already-collected full-scope raw files.
test_state <- Sys.getenv("PIPELINE_TEST_STATE", "")
TEST_MODE <- nzchar(test_state)
if (TEST_MODE) {
  message("PIPELINE_TEST_STATE=", test_state, " set -- restricting to this state only, writing to data/raw/test/ (smoke-test mode).")
  contiguous_states_dc <- test_state
}
raw_dir <- if (TEST_MODE) "data/raw/test" else "data/raw"
if (TEST_MODE) dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
extract_log_path <- if (TEST_MODE) "logs/test_extract_log.csv" else "logs/extract_log.csv"

state_fips <- fips_codes %>%
  distinct(state, state_code) %>%
  filter(state %in% contiguous_states_dc) %>%
  arrange(state_code)

dataset_label <- c(sf1 = "dec_sf1", sf3 = "dec_sf3", dhc = "dec_dhc", acs5 = "acs5")

extract_log <- list()
log_call <- function(endpoint, params, row_count) {
  extract_log[[length(extract_log) + 1]] <<- tibble(
    endpoint = endpoint, params = params,
    timestamp = as.character(Sys.time()), row_count = row_count
  )
}

# ZCTA GEOIDs are plain 5-digit codes with no state prefix, so the
# substr(GEOID,1,2)-based state filter used for county/tract doesn't work.
# ZCTA boundaries are only redrawn in decennial years (2000/2010/2020) --
# any ACS5 vintage in between reuses the nearest decade's ZCTA definitions
# -- so the crosswalk only needs to be built per boundary vintage, not per
# exact ACS5 end year, and is cached to temp/ since it's a modest spatial
# join, not something to redo per (year, dataset) row.
zcta_boundary_vintage <- function(end_year) {
  if (end_year <= 2009) 2000 else if (end_year <= 2019) 2010 else 2020
}

build_zcta_state_crosswalk <- function(boundary_year) {
  cache_path <- sprintf("temp/zcta_state_crosswalk_%d.rds", boundary_year)
  if (file.exists(cache_path)) return(readRDS(cache_path))

  message("  building zcta-state crosswalk for ", boundary_year, " boundaries (one-time spatial join)...")
  zsuf <- substr(as.character(boundary_year), 3, 4) # zcta ALAND/GEOID columns always carry a suffix, even 2020
  ssuf <- if (boundary_year == 2020) "" else substr(as.character(boundary_year), 3, 4)

  zcta_geo <- zctas(year = boundary_year, cb = FALSE)
  zcta_geo$GEOID <- zcta_geo[[paste0("ZCTA5CE", zsuf)]]
  state_geo <- states(year = boundary_year, cb = FALSE)
  state_geo$state_code <- state_geo[[paste0("STATEFP", ssuf)]]

  # st_point_on_surface(), not st_centroid(): a plain geometric centroid is
  # the area-weighted balance point of a shape and is NOT guaranteed to fall
  # inside it -- for multi-part ZCTAs (e.g. a mainland + offshore islands)
  # or concave/irregular ones, the centroid can land in a gap between
  # pieces (often open water), outside every state polygon, silently
  # dropping an otherwise perfectly real ZCTA from the crosswalk.
  # st_point_on_surface() guarantees a point that lies on the geometry
  # itself. Confirmed via a real church-address GEOID comparison: this
  # affected 4 ZCTAs in 2000, 4 in 2010, and 3 in 2020 nationally.
  crosswalk <- st_join(st_point_on_surface(zcta_geo["GEOID"]), state_geo["state_code"]) %>%
    st_drop_geometry() %>%
    filter(!is.na(state_code)) %>%
    # a boundary-straddling zcta's on-surface point falls in exactly one
    # state polygon; distinct() is a defensive guard against join
    # duplicates, not a real disambiguation step
    distinct(GEOID, .keep_all = TRUE)

  saveRDS(crosswalk, cache_path)
  crosswalk
}

# A known tidycensus issue has occasionally returned 7-digit,
# state-prefixed GEOIDs for zcta pulls instead of the plain 5-digit code --
# fix defensively so a silent format bug doesn't propagate downstream.
fix_zcta_geoid <- function(df) {
  bad <- nchar(df$GEOID) != 5
  if (any(bad)) {
    message("    fixing ", sum(bad), " zcta GEOIDs with unexpected length")
    df$GEOID[bad] <- substr(df$GEOID[bad], nchar(df$GEOID[bad]) - 4, nchar(df$GEOID[bad]))
  }
  df
}

filter_zcta_to_scope <- function(df, boundary_year) {
  crosswalk <- build_zcta_state_crosswalk(boundary_year)
  df %>%
    fix_zcta_geoid() %>%
    inner_join(crosswalk, by = "GEOID") %>%
    filter(state_code %in% state_fips$state_code) %>%
    select(-state_code)
}

pull_one <- function(year, dataset, geography, variables, state = NULL) {
  is_decennial <- dataset %in% c("sf1", "sf3", "dhc")
  if (is_decennial) {
    get_decennial(
      geography = geography, variables = variables, year = year,
      sumfile = dataset, state = state
    )
  } else {
    get_acs(
      geography = geography, variables = variables, year = year,
      survey = "acs5", state = state
    )
  }
}

for (i in seq_len(nrow(pull_plan))) {
  yr <- pull_plan$year[i]
  ds <- pull_plan$dataset[i]
  vars <- pull_plan$variables[[i]]
  label <- dataset_label[[ds]]

  message("=== ", yr, " ", ds, " (", length(vars), " variables) ===")

  # --- state ---
  message("  state...")
  d_state <- pull_one(yr, ds, "state", vars) %>%
    filter(GEOID %in% state_fips$state_code)
  write_csv(d_state, sprintf("%s/%d_%s_state.csv", raw_dir, yr, label))
  log_call(sprintf("%d/%s/state", yr, ds), paste(vars, collapse = ";"), nrow(d_state))

  # --- county ---
  message("  county...")
  d_county <- pull_one(yr, ds, "county", vars) %>%
    filter(substr(GEOID, 1, 2) %in% state_fips$state_code)
  write_csv(d_county, sprintf("%s/%d_%s_county.csv", raw_dir, yr, label))
  log_call(sprintf("%d/%s/county", yr, ds), paste(vars, collapse = ";"), nrow(d_county))

  # --- tract, looped by state ---
  message("  tract (looped over ", nrow(state_fips), " states)...")
  d_tract_list <- vector("list", nrow(state_fips))
  for (j in seq_len(nrow(state_fips))) {
    st <- state_fips$state_code[j]
    d_tract_list[[j]] <- pull_one(yr, ds, "tract", vars, state = st)
    log_call(sprintf("%d/%s/tract", yr, ds), paste0("state=", st, "; vars=", paste(vars, collapse = ";")),
              nrow(d_tract_list[[j]]))
    Sys.sleep(0.2)
  }
  d_tract <- bind_rows(d_tract_list)
  write_csv(d_tract, sprintf("%s/%d_%s_tract.csv", raw_dir, yr, label))
  message("  tract total rows: ", nrow(d_tract))

  # --- zcta and block group, decennial rows only. ACS5 rows (ds == "acs5")
  # skip this: 2006-2010 ACS5 doesn't publish these geographies at all, so
  # they're handled separately below via the resolved vintage overrides. ---
  if (ds != "acs5") {
    message("  zcta...")
    d_zcta <- pull_one(yr, ds, "zcta", vars) %>% filter_zcta_to_scope(yr)
    write_csv(d_zcta, sprintf("%s/%d_%s_zcta.csv", raw_dir, yr, label))
    log_call(sprintf("%d/%s/zcta", yr, ds), paste(vars, collapse = ";"), nrow(d_zcta))

    message("  block group (looped over ", nrow(state_fips), " states)...")
    d_bg_list <- vector("list", nrow(state_fips))
    for (j in seq_len(nrow(state_fips))) {
      st <- state_fips$state_code[j]
      d_bg_list[[j]] <- pull_one(yr, ds, "block group", vars, state = st)
      log_call(sprintf("%d/%s/blockgroup", yr, ds), paste0("state=", st, "; vars=", paste(vars, collapse = ";")),
                nrow(d_bg_list[[j]]))
      Sys.sleep(0.2)
    }
    d_bg <- bind_rows(d_bg_list)
    write_csv(d_bg, sprintf("%s/%d_%s_blockgroup.csv", raw_dir, yr, label))
    message("  block group total rows: ", nrow(d_bg))
  }
}

# ---- zcta / block group for ACS5, using the per-variable vintage overrides
# resolved by 01b_geography_vintage_discovery.R (2010 and 2020 buckets) ----
overrides_zcta <- readRDS("temp/vintage_overrides_zcta.rds")
overrides_blockgroup <- readRDS("temp/vintage_overrides_blockgroup.rds")

pull_acs5_with_overrides <- function(geography, overrides_df) {
  # overrides_df has a row for every variable, including decennial-sourced
  # ones (dataset sf1/sf3/dhc) -- those were already pulled by the main
  # per-(year,dataset) loop above, at the year state/county/tract already
  # use. Only acs5 rows need the override-vintage treatment here.
  overrides_df <- overrides_df %>% filter(dataset == "acs5")
  results <- list()
  for (bucket in unique(overrides_df$year_bucket)) {
    grp <- overrides_df %>% filter(year_bucket == bucket)
    for (end_yr in unique(grp$resolved_end_year)) {
      vintage_grp <- grp %>% filter(resolved_end_year == end_yr)
      # "NOT_TABULATED" is 01b's placeholder for a variable confirmed to
      # never be tabulated at this geography (e.g. pct_poverty_individuals
      # at block group) -- it's not a real Census code and must never reach
      # the live API. A vintage group can end up with nothing real to pull
      # if it contains only such placeholder variable(s).
      codes <- setdiff(unique(unlist(lapply(vintage_grp$formula, function(f) c(f$num, f$den)))), "NOT_TABULATED")
      if (length(codes) == 0) {
        message(
          "  ", geography, " acs5 ", bucket, " bucket -> vintage ", end_yr,
          " has no real codes to pull (only NA-placeholder variables: ",
          paste(vintage_grp$variable, collapse = ", "), ") -- skipping"
        )
        next
      }
      message(
        "  ", geography, " acs5 ", bucket, " bucket -> vintage ", end_yr,
        " (", paste(vintage_grp$variable, collapse = ", "), ")"
      )

      if (geography == "zcta") {
        d <- pull_one(end_yr, "acs5", "zcta", codes) %>%
          filter_zcta_to_scope(zcta_boundary_vintage(end_yr))
      } else {
        d_list <- vector("list", nrow(state_fips))
        for (j in seq_len(nrow(state_fips))) {
          st <- state_fips$state_code[j]
          d_list[[j]] <- pull_one(end_yr, "acs5", "block group", codes, state = st)
          Sys.sleep(0.2)
        }
        d <- bind_rows(d_list)
      }
      d$resolved_end_year <- end_yr
      d$year_bucket <- bucket
      log_call(
        sprintf("%s/acs5/bucket=%d/vintage=%d", geography, bucket, end_yr),
        paste0("vars=", paste(codes, collapse = ";")), nrow(d)
      )
      results[[paste(bucket, end_yr)]] <- d
    }
  }
  bind_rows(results)
}

d_zcta_acs5 <- pull_acs5_with_overrides("zcta", overrides_zcta)
zcta_acs5_path <- file.path(raw_dir, "acs5_zcta_vintaged.csv")
write_csv(d_zcta_acs5, zcta_acs5_path)
message("Wrote ", zcta_acs5_path, " (", nrow(d_zcta_acs5), " rows).")

d_bg_acs5 <- pull_acs5_with_overrides("block group", overrides_blockgroup)
bg_acs5_path <- file.path(raw_dir, "acs5_blockgroup_vintaged.csv")
write_csv(d_bg_acs5, bg_acs5_path)
message("Wrote ", bg_acs5_path, " (", nrow(d_bg_acs5), " rows).")

write_csv(bind_rows(extract_log), extract_log_path)
message("Wrote ", extract_log_path, " (", nrow(bind_rows(extract_log)), " calls logged).")
