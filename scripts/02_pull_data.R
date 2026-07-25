# Step 2: pull raw tabular data via the Census API
#
# Pulls, for each of the 6 (year, dataset) combinations identified in
# 01_variable_discovery.R, every variable code the registry references, at
# state, county, and tract level, for the 48 contiguous states + DC.
# State and county are single nationwide calls (then filtered down to our
# 49 areas); tract-level pulls are looped one state at a time, since the
# Census API requires a state for tract-level geography.
#
# Raw pulls are saved untouched to data/raw/, named {year}_{dataset}_{geography}.csv.
# Every call is logged to logs/extract_log.csv.

source("scripts/00_setup.R")

variable_registry <- readRDS("temp/variable_registry.rds")
registry_df <- bind_rows(lapply(variable_registry, as_tibble))

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
  write_csv(d_state, sprintf("data/raw/%d_%s_state.csv", yr, label))
  log_call(sprintf("%d/%s/state", yr, ds), paste(vars, collapse = ";"), nrow(d_state))

  # --- county ---
  message("  county...")
  d_county <- pull_one(yr, ds, "county", vars) %>%
    filter(substr(GEOID, 1, 2) %in% state_fips$state_code)
  write_csv(d_county, sprintf("data/raw/%d_%s_county.csv", yr, label))
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
  write_csv(d_tract, sprintf("data/raw/%d_%s_tract.csv", yr, label))
  message("  tract total rows: ", nrow(d_tract))
}

write_csv(bind_rows(extract_log), "logs/extract_log.csv")
message("Wrote logs/extract_log.csv (", nrow(bind_rows(extract_log)), " calls logged).")
