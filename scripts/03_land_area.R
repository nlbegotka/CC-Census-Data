# Step 3: land area for population density
#
# Pulls ALAND (land area, square meters) for state/county/tract, for each of
# 2000/2010/2020, via tigris full TIGER/Line files (cb = FALSE). Cartographic
# boundary files (cb = TRUE) were tried first but use inconsistent area
# fields across vintages (AREA in 2000, CENSUSAREA in 2010, ALAND in 2020) --
# full TIGER/Line files give a consistently named ALAND{yy} field in square
# meters across all three years, at the cost of a larger download.
#
# Column names carry a two-digit year suffix for 2000/2010 (ALAND00,
# STATEFP00, ...) and no suffix for 2020 (ALAND, STATEFP, ...) -- normalized
# below into a single land_area_sqm + GEOID per row. GEOID is provided
# directly for 2020 but must be built from the FIPS component fields for
# 2000/2010.

source("scripts/00_setup.R")
options(tigris_use_cache = TRUE)

contiguous_states_dc <- c(
  "AL","AZ","AR","CA","CO","CT","DE","DC","FL","GA","ID","IL","IN","IA",
  "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH",
  "NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX",
  "UT","VT","VA","WA","WV","WI","WY"
)
state_fips <- fips_codes %>%
  distinct(state, state_code) %>%
  filter(state %in% contiguous_states_dc) %>%
  arrange(state_code)

yr_suffix <- function(year) if (year == 2020) "" else substr(as.character(year), 3, 4)

normalize_land_area <- function(df, year, geography) {
  suf <- yr_suffix(year)
  df <- st_drop_geometry(df)
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
  }

  df %>% select(GEOID, land_area_sqm)
}

for (yr in c(2000, 2010, 2020)) {
  message("=== land area ", yr, " ===")

  message("  state...")
  d_state <- states(year = yr, cb = FALSE) %>%
    normalize_land_area(yr, "state") %>%
    filter(GEOID %in% state_fips$state_code)
  write_csv(d_state, sprintf("data/raw/boundaries/%d_land_area_state.csv", yr))

  message("  county...")
  d_county <- counties(year = yr, cb = FALSE) %>%
    normalize_land_area(yr, "county") %>%
    filter(substr(GEOID, 1, 2) %in% state_fips$state_code)
  write_csv(d_county, sprintf("data/raw/boundaries/%d_land_area_county.csv", yr))

  message("  tract (looped over ", nrow(state_fips), " states)...")
  d_tract_list <- vector("list", nrow(state_fips))
  for (j in seq_len(nrow(state_fips))) {
    st <- state_fips$state_code[j]
    d_tract_list[[j]] <- tracts(state = st, year = yr, cb = FALSE) %>%
      normalize_land_area(yr, "tract")
  }
  d_tract <- bind_rows(d_tract_list)
  write_csv(d_tract, sprintf("data/raw/boundaries/%d_land_area_tract.csv", yr))
  message("  tract total rows: ", nrow(d_tract))
}

message("Land area pull complete.")
