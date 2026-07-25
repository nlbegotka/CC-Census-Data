# Step 1: dataset/table discovery
#
# Confirms exact Census variable codes for all 13 target variables across
# 2000 (dec/sf1 + dec/sf3), 2010 (dec/sf1 + acs/acs5 2006-2010), and
# 2020 (dec/dhc + acs/acs5 2016-2020).
#
# Almost all of these codes are fixed facts about a table's published layout
# (a single code, or a static range) and live in scripts/variable_codes.R,
# shared with 04_build_final_datasets.R so both scripts work from the same
# source instead of two hand-typed copies that could drift apart. This
# script's job is to re-verify every one of those codes against the live
# Census `/variables.json` endpoint before logging it, so a silently
# renamed/retired code fails loudly instead of pulling the wrong table.
#
# ONE variable is not a fixed fact: `pct_unemployed`'s 2010 entry. That
# year's table (B23001) has no simple total-unemployed row -- it breaks
# unemployment out by age and sex across ~16 brackets per sex, with no
# single "total unemployed" cell. There's no static range to write down in
# variable_codes.R for this case; the correct code list can only be
# determined by asking the Census Bureau's own live variable list which
# codes actually mean "unemployed" for this specific table/year. That
# discovery happens here (the only script that talks to the Census API) and
# the resolved result is logged and persisted for 04_build_final_datasets.R
# to consume as-is, without repeating the API call.
#
# NOTE ON OTHER TABLE CHANGES ACROSS YEARS (do not "simplify" these to one
# shared set of codes -- they differ for real reasons; see variable_codes.R
# for details):
#  - Tenure (H004) reorders categories between 2000 and 2010/2020.
#  - Educational attainment: 2020 splits "HS grad/GED" into two line items.

source("scripts/00_setup.R")
source("scripts/variable_codes.R")

# ---- Live variable lists, for verification -------------------------------
v2000_sf1 <- load_variables(2000, "sf1")
v2000_sf3 <- load_variables(2000, "sf3")
v2010_sf1 <- load_variables(2010, "sf1")
v2010_acs5 <- load_variables(2010, "acs5")
v2020_dhc <- load_variables(2020, "dhc")
v2020_acs5 <- load_variables(2020, "acs5")

# ---- The one variable resolved via live API discovery, not a fixed fact ---
# B23001 (2010 unemployment) breaks out by age/sex bracket rather than having
# a simple total/employed/unemployed row, so its component codes are
# identified programmatically by label suffix instead of being hand-typed.
b23001_employed <- v2010_acs5 %>%
  filter(str_detect(concept, "^SEX BY AGE BY EMPLOYMENT STATUS FOR THE POPULATION 16 YEARS AND OVER$")) %>%
  filter(str_ends(label, "Civilian!!Employed")) %>%
  pull(name)
b23001_unemployed <- v2010_acs5 %>%
  filter(str_detect(concept, "^SEX BY AGE BY EMPLOYMENT STATUS FOR THE POPULATION 16 YEARS AND OVER$")) %>%
  filter(str_ends(label, "Civilian!!Unemployed")) %>%
  pull(name)

pct_unemployed_2010 <- list(
  type = "ratio", dataset = "acs5",
  num = b23001_unemployed,
  den = c(b23001_employed, b23001_unemployed),
  note = "B23001 has no simple total; summed across all age/sex brackets by label suffix match (resolved via live Census API lookup, not a fixed code list)."
)
saveRDS(pct_unemployed_2010, "temp/pct_unemployed_2010_codes.rds")
message("Resolved pct_unemployed 2010 codes via live label match: ",
        length(b23001_unemployed), " unemployed + ", length(b23001_employed), " employed brackets.")

# ---- Flatten variable_codes.R + the one resolved entry into one registry --
registry_df <- bind_rows(lapply(names(variable_codes), function(v) {
  entries <- variable_codes[[v]]
  bind_rows(lapply(names(entries), function(yr) {
    e <- entries[[yr]]
    tibble(variable = v, year = as.integer(yr), dataset = e$dataset,
           codes = format_codes(e), note = e$note)
  }))
})) %>%
  bind_rows(tibble(
    variable = "pct_unemployed", year = 2010L, dataset = pct_unemployed_2010$dataset,
    codes = format_codes(pct_unemployed_2010), note = pct_unemployed_2010$note
  )) %>%
  arrange(variable, year)

# ---- Verify every referenced code actually exists in the live variable list ----
var_lookup <- list(
  "2000_sf1" = v2000_sf1$name, "2000_sf3" = v2000_sf3$name,
  "2010_sf1" = v2010_sf1$name, "2010_acs5" = v2010_acs5$name,
  "2020_dhc" = v2020_dhc$name, "2020_acs5" = v2020_acs5$name
)

extract_codes <- function(code_str) {
  unique(unlist(regmatches(code_str, gregexpr("[A-Za-z0-9_]+[0-9]{3}[A-Za-z]?", code_str))))
}

missing_codes <- registry_df %>%
  rowwise() %>%
  mutate(
    key = paste0(year, "_", dataset),
    codes_referenced = list(extract_codes(codes)),
    missing = list(setdiff(codes_referenced, var_lookup[[key]]))
  ) %>%
  ungroup() %>%
  filter(lengths(missing) > 0)

if (nrow(missing_codes) > 0) {
  print(missing_codes %>% select(variable, year, dataset, missing))
  stop(
    "One or more referenced variable codes were not found in the live ",
    "Census variable list for their dataset/year. Do not proceed -- ",
    "investigate and correct variable_codes.R (or the live discovery logic ",
    "above, for pct_unemployed 2010) before pulling data."
  )
}

message("All ", nrow(registry_df), " variable/year entries verified against live Census variable lists.")

# ---- Log ---------------------------------------------------------------
discovery_log <- registry_df %>%
  mutate(geography_levels_confirmed = "state, county, tract (48 contiguous states + DC)")

write_csv(discovery_log, "logs/variable_discovery_log.csv")
message("Wrote logs/variable_discovery_log.csv (", nrow(discovery_log), " rows).")

saveRDS(registry_df, "temp/variable_registry.rds")
message("Wrote temp/variable_registry.rds (consumed by 02_pull_data.R).")
