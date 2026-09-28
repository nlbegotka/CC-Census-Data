# Step 3: land area for population density
#
# Pulls ALAND (land area, square meters) for state/county/tract/zcta/block
# group, for each of 2000/2010/2020, via tigris full TIGER/Line files
# (cb = FALSE). Cartographic boundary files (cb = TRUE) were tried first but
# use inconsistent area fields across vintages (AREA in 2000, CENSUSAREA in
# 2010, ALAND in 2020) -- full TIGER/Line files give a consistently named
# ALAND{yy} field in square meters across all three years, at the cost of a
# larger download.
#
# Column names carry a two-digit year suffix for 2000/2010 (ALAND00,
# STATEFP00, ...) and no suffix for 2020 (ALAND, STATEFP, ...) for
# state/county/tract/block group -- normalized below into a single
# land_area_sqm + GEOID per row. zcta is the one exception: tigris::zctas()
# keeps the two-digit suffix on ALAND/GEOID even in 2020 (confirmed
# empirically -- ALAND20/ZCTA5CE20, not ALAND/GEOID), so it gets its own
# suffix helper instead of reusing yr_suffix().

source("scripts/00_setup.R")
options(tigris_use_cache = TRUE)

contiguous_states_dc <- c(
  "AL","AZ","AR","CA","CO","CT","DE","DC","FL","GA","ID","IL","IN","IA",
  "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH",
  "NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX",
  "UT","VT","VA","WA","WV","WI","WY"
)
# Smoke-testing hook, off by default -- see the matching block in
# 02_pull_data.R for the rationale (a restricted-scope run must not
# overwrite the real, already-collected full-scope boundary files).
test_state <- Sys.getenv("PIPELINE_TEST_STATE", "")
TEST_MODE <- nzchar(test_state)
if (TEST_MODE) {
  message("PIPELINE_TEST_STATE=", test_state, " set -- restricting to this state only, writing to data/raw/test/boundaries/ (smoke-test mode).")
  contiguous_states_dc <- test_state
}
boundaries_dir <- if (TEST_MODE) "data/raw/test/boundaries" else "data/raw/boundaries"
if (TEST_MODE) dir.create(boundaries_dir, recursive = TRUE, showWarnings = FALSE)

state_fips <- fips_codes %>%
  distinct(state, state_code) %>%
  filter(state %in% contiguous_states_dc) %>%
  arrange(state_code)

yr_suffix <- function(year) if (year == 2020) "" else substr(as.character(year), 3, 4)
zcta_suffix <- function(year) substr(as.character(year), 3, 4) # zctas() always suffixes, even 2020

normalize_land_area <- function(df, year, geography) {
  df <- st_drop_geometry(df)

  if (geography == "zcta") {
    zsuf <- zcta_suffix(year)
    df$land_area_sqm <- df[[paste0("ALAND", zsuf)]]
    df$GEOID <- df[[paste0("ZCTA5CE", zsuf)]]
    return(df %>% select(GEOID, land_area_sqm))
  }

  suf <- yr_suffix(year)
  aland_col <- paste0("ALAND", suf)
  df$land_area_sqm <- df[[aland_col]]

  if (geography == "state") {
    statefp_col <- paste0("STATEFP", suf)
    df$GEOID <- df[[statefp_col]]
  } else if (geography == "county") {
    statefp_col <- paste0("STATEFP", suf)
    countyfp_col <- paste0("COUNTYFP", suf)
    df$GEOID <- paste0(df[[statefp_col]], df[[countyfp_col]])
  } else if (geography == "tract") {
    statefp_col <- paste0("STATEFP", suf)
    countyfp_col <- paste0("COUNTYFP", suf)
    tractce_col <- paste0("TRACTCE", suf)
    df$GEOID <- paste0(df[[statefp_col]], df[[countyfp_col]], df[[tractce_col]])
  } else if (geography == "block group") {
    statefp_col <- paste0("STATEFP", suf)
    countyfp_col <- paste0("COUNTYFP", suf)
    tractce_col <- paste0("TRACTCE", suf)
    bgce_col <- paste0("BLKGRPCE", suf)
    df$GEOID <- paste0(df[[statefp_col]], df[[countyfp_col]], df[[tractce_col]], df[[bgce_col]])
  }

  df %>% select(GEOID, land_area_sqm)
}

# Duplicated from 02_pull_data.R (same rationale as this file's existing
# contiguous_states_dc duplication): zcta GEOIDs carry no state FIPS, so
# scoping to the 48 contiguous states + DC needs a centroid-in-polygon
# spatial join rather than a substring filter. Cached to temp/ so it's only
# computed once even if both scripts run in the same session.
build_zcta_state_crosswalk <- function(boundary_year) {
  cache_path <- sprintf("temp/zcta_state_crosswalk_%d.rds", boundary_year)
  if (file.exists(cache_path)) return(readRDS(cache_path))

  message("  building zcta-state crosswalk for ", boundary_year, " boundaries (one-time spatial join)...")
  zsuf <- zcta_suffix(boundary_year)
  ssuf <- yr_suffix(boundary_year)

  zcta_geo <- zctas(year = boundary_year, cb = FALSE)
  zcta_geo$GEOID <- zcta_geo[[paste0("ZCTA5CE", zsuf)]]
  state_geo <- states(year = boundary_year, cb = FALSE)
  state_geo$state_code <- state_geo[[paste0("STATEFP", ssuf)]]

  # st_point_on_surface(), not st_centroid() -- see the matching comment in
  # 02_pull_data.R's copy of this function. A plain centroid can fall
  # outside a multi-part or concave ZCTA polygon (often in open water),
  # silently dropping it from every state's scope. Confirmed to affect 4
  # ZCTAs in 2000, 4 in 2010, and 3 in 2020 nationally.
  crosswalk <- st_join(st_point_on_surface(zcta_geo["GEOID"]), state_geo["state_code"]) %>%
    st_drop_geometry() %>%
    filter(!is.na(state_code)) %>%
    distinct(GEOID, .keep_all = TRUE)

  saveRDS(crosswalk, cache_path)
  crosswalk
}

for (yr in c(2000, 2010, 2020)) {
  message("=== land area ", yr, " ===")

  message("  state...")
  d_state <- states(year = yr, cb = FALSE) %>%
    normalize_land_area(yr, "state") %>%
    filter(GEOID %in% state_fips$state_code)
  write_csv(d_state, sprintf("%s/%d_land_area_state.csv", boundaries_dir, yr))

  message("  county...")
  d_county <- counties(year = yr, cb = FALSE) %>%
    normalize_land_area(yr, "county") %>%
    filter(substr(GEOID, 1, 2) %in% state_fips$state_code)
  write_csv(d_county, sprintf("%s/%d_land_area_county.csv", boundaries_dir, yr))

  message("  tract (looped over ", nrow(state_fips), " states)...")
  d_tract_list <- vector("list", nrow(state_fips))
  for (j in seq_len(nrow(state_fips))) {
    st <- state_fips$state_code[j]
    d_tract_list[[j]] <- tracts(state = st, year = yr, cb = FALSE) %>%
      normalize_land_area(yr, "tract")
  }
  d_tract <- bind_rows(d_tract_list)
  write_csv(d_tract, sprintf("%s/%d_land_area_tract.csv", boundaries_dir, yr))
  message("  tract total rows: ", nrow(d_tract))

  message("  zcta...")
  zcta_crosswalk <- build_zcta_state_crosswalk(yr)
  d_zcta <- zctas(year = yr, cb = FALSE) %>%
    normalize_land_area(yr, "zcta") %>%
    inner_join(zcta_crosswalk, by = "GEOID") %>%
    filter(state_code %in% state_fips$state_code) %>%
    select(-state_code)
  write_csv(d_zcta, sprintf("%s/%d_land_area_zcta.csv", boundaries_dir, yr))
  message("  zcta total rows: ", nrow(d_zcta))

  message("  block group (looped over ", nrow(state_fips), " states)...")
  d_bg_list <- vector("list", nrow(state_fips))
  for (j in seq_len(nrow(state_fips))) {
    st <- state_fips$state_code[j]
    d_bg_list[[j]] <- block_groups(state = st, year = yr, cb = FALSE) %>%
      normalize_land_area(yr, "block group")
  }
  d_bg <- bind_rows(d_bg_list)
  write_csv(d_bg, sprintf("%s/%d_land_area_blockgroup.csv", boundaries_dir, yr))
  message("  block group total rows: ", nrow(d_bg))
}

message("Land area pull complete.")
