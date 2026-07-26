# Ad hoc QA: check SG_data GEOIDs against the census extraction.
#
# data/SG_data/All Metrics By County_06.04.2025.geojson is an external sample
# of ~847 counties, one row per decennial vintage (2000/2010/2020) 
# downloaded by SG, MS. This script checks whether each row's GEOID matches a
# county GEOID in our own data/processed/census_<year>.csv for that same
# year -- i.e., whether the row's year label actually lines up with a FIPS
# code from that vintage.


source("scripts/00_setup.R")

sg_path <- "data/SG_data/All Metrics By County_06.04.2025.geojson"

# ---- Load SG geojson attributes only (sf/GDAL parses this 86MB file in a
# few seconds; we immediately drop the geometry since only the GEOIDs matter) ----
sg_raw <- st_read(sg_path, quiet = TRUE) %>%
  st_drop_geometry() %>%
  select(decennial_census, state_fips, county_fips, geoid) %>%
  mutate(decennial_census = as.integer(decennial_census))

# ---- Normalize geoid: strip TIGER-style "0500000US" prefix where present ----
# (found during inspection: every 2010 row uses "0500000US06001"-style GEOIDs,
# while 2000/2020 rows use plain 5-digit "06001" -- comparing without
# normalizing would make every 2010 row spuriously look "missing")
sg <- sg_raw %>%
  mutate(geoid = str_remove(geoid, "^0500000US"))

bad_length <- sg %>% filter(nchar(geoid) != 5)
if (nrow(bad_length) > 0) {
  print(bad_length)
  stop(
    nrow(bad_length), " SG geoid(s) are not 5 characters after normalization -- ",
    "inspect the rows above before proceeding (unexpected GEOID format)."
  )
}
message("Loaded and normalized ", nrow(sg), " SG geojson rows (", n_distinct(sg$geoid), " distinct geoids).")

# ---- Load county-level GEOIDs from our own processed census files ----
census_ids <- lapply(c(`2000` = 2000, `2010` = 2010, `2020` = 2020), function(yr) {
  read_csv(sprintf("data/processed/census_%d.csv", yr), show_col_types = FALSE) %>%
    filter(geography_level == "county") %>%
    pull(GEOID) %>%
    unique()
})

# ---- Per-year comparison + cross-year diagnostic for mismatches ----
results <- bind_rows(lapply(c(2000, 2010, 2020), function(yr) {
  sg_ids <- sg %>% filter(decennial_census == yr) %>% pull(geoid) %>% unique()
  this_year_ids <- census_ids[[as.character(yr)]]
  other_years <- setdiff(c(2000, 2010, 2020), yr)

  message(sprintf(
    "=== %d: %d / %d SG geoids matched in census_%d.csv ===",
    yr, sum(sg_ids %in% this_year_ids), length(sg_ids), yr
  ))

  tibble(sg_geoid = sg_ids, sg_year = yr) %>%
    mutate(
      matched_same_year = sg_geoid %in% this_year_ids,
      matched_other_years = purrr::map_chr(sg_geoid, function(g) {
        hits <- other_years[vapply(other_years, function(y) g %in% census_ids[[as.character(y)]], logical(1))]
        if (length(hits) == 0) NA_character_ else paste(hits, collapse = ";")
      })
    )
}))

mismatches <- results %>% filter(!matched_same_year)
if (nrow(mismatches) > 0) {
  message(nrow(mismatches), " total mismatched geoid/year rows across all three years:")
  wrong_label <- mismatches %>% filter(!is.na(matched_other_years))
  no_match_any_year <- mismatches %>% filter(is.na(matched_other_years))
  message("  ", nrow(wrong_label), " match a DIFFERENT year's census data (possible mislabeled vintage).")
  message("  ", nrow(no_match_any_year), " match NO year's census data (retired/renamed FIPS, or outside our 48-state+DC scope).")
} else {
  message("No mismatches -- every SG geoid matched its labeled year's census data.")
}

write_csv(results, "logs/sg_geoid_comparison.csv")
message("Wrote logs/sg_geoid_comparison.csv (", nrow(results), " rows).")
