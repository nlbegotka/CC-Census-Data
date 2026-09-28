# Step 1b: geography-level (ZCTA, block group) vintage discovery
#
# state/county/tract data already exists and is untouched by this script.
# Adding ZCTA and block group means re-checking, for every (variable, year)
# combination, whether that variable's table is actually available at
# these two geographies for the vintage state/county/tract already uses --
# NOT a safe assumption. Confirmed live against the Census API: the
# 2006-2010 ACS5 vintage (the whole "2010" bucket's socioeconomic source)
# does not publish ZCTA or block-group geography AT ALL, so every ACS5-
# sourced 2010-bucket variable needs a later vintage at these two levels.
#
# This escalation is intentionally geography-scoped: state/county/tract
# keep using exactly what they already use (2006-2010, with the existing
# B23001 pct_unemployed workaround) -- only new ZCTA/block-group pulls are
# affected. The resulting vintage mismatch across geography levels is
# documented in the README.
#
# Decennial-sourced variables (SF1/SF3/DHC -- a fixed, single-year full
# count, not a rolling vintage) get a one-shot existence check instead of
# escalation: there's no "later vintage" of a one-time census. An
# unexpected failure there halts the script rather than silently degrading.
#
# Mechanism: for each ACS5-sourced variable, try progressively later ACS5
# vintages (2006-2010 -> 2007-2011 -> ...) with a live test pull at the
# target geography, until one actually returns data. For pct_unemployed
# specifically, once a vintage is found where B23025 (a clean total-
# unemployed table) is confirmed available, prefer it over the messier
# B23001 label-matching workaround state/county/tract had to use.
#
# Outputs consumed downstream:
#   temp/vintage_overrides_zcta.rds, temp/vintage_overrides_blockgroup.rds
#     - used by 02_pull_data.R to know which ACS5 vintage to actually pull
#       each variable from at these geographies, and by
#       04_build_final_datasets.R to know which formula to compute with.
#   logs/geography_vintage_discovery_log.csv - human-readable audit trail.

source("scripts/00_setup.R")
source("scripts/variable_codes.R")

pct_unemployed_2010 <- readRDS("temp/pct_unemployed_2010_codes.rds")

PROBE_STATE <- "18" # Illinois: mid-size, always-populated contiguous state
ESCALATION_WINDOW <- 5 # years to search forward past an ACS5 bucket's normal vintage

result_ok <- function(result) {
  if (inherits(result, "error")) return(FALSE)
  if (nrow(result) == 0) return(FALSE)
  val_col <- if ("estimate" %in% names(result)) "estimate" else "value"
  !all(is.na(result[[val_col]]))
}

pull_test <- function(geography, dataset, codes, end_year, state) {
  is_decennial <- dataset %in% c("sf1", "sf3", "dhc")
  tryCatch({
    if (is_decennial) {
      get_decennial(geography = geography, variables = codes, year = end_year,
                     sumfile = dataset, state = state)
    } else {
      get_acs(geography = geography, variables = codes, year = end_year,
              survey = "acs5", state = state)
    }
  }, error = function(e) e)
}

# Tries start_year (and, for ACS5 formulas, later vintages up to
# max_end_year) until a live test pull at `geography` returns real data.
# Decennial formulas get max_end_year = start_year (no escalation) via the
# caller below.
resolve_geography_vintage <- function(variable, geography, formula, start_year, max_end_year) {
  state_arg <- if (geography == "zcta") NULL else PROBE_STATE
  codes <- unique(c(formula$num, formula$den))
  attempts <- list()

  for (end_year in start_year:max_end_year) {
    result <- pull_test(geography, formula$dataset, codes, end_year, state_arg)
    ok <- result_ok(result)
    resolved_formula <- formula
    note <- if (inherits(result, "error")) conditionMessage(result) else sprintf("%d rows", nrow(result))

    # For pct_unemployed, test B23025 (a small, clean table) independently of
    # whether the starting B23001 workaround succeeded -- a highly
    # disaggregated table like B23001 (~90 age/sex/employment codes) can be
    # withheld at a small geography like block group for reliability even
    # when the much smaller B23025 is published there. Gating this behind
    # `ok` (i.e. only checking B23025 once B23001 already passed) was a bug:
    # it meant block-group pct_unemployed could never resolve via B23025 if
    # B23001 never passes at any vintage, which is exactly the case observed
    # empirically. Always prefer B23025 whenever it's independently available.
    if (variable == "pct_unemployed" && formula$dataset == "acs5") {
      b23025 <- pull_test(geography, "acs5", c("B23025_005", "B23025_003"), end_year, state_arg)
      if (result_ok(b23025)) {
        ok <- TRUE
        resolved_formula <- list(
          type = "ratio", dataset = "acs5", num = "B23025_005", den = "B23025_003",
          note = sprintf(
            "Unemployed / civilian labor force (B23025, confirmed available for %s at %d-%d ACS5 -- preferred over the B23001 label-match workaround, which is not published at %s in any vintage tested).",
            geography, end_year - 4, end_year, geography
          )
        )
        note <- paste0(note, " | B23025 independently available: ", nrow(b23025), " rows")
      }
      Sys.sleep(0.1)
    }

    attempts[[length(attempts) + 1]] <- tibble(end_year = end_year, success = ok, note = note)
    Sys.sleep(0.1)
    if (!ok) next

    return(list(
      variable = variable, geography = geography, year_bucket = start_year,
      resolved_end_year = end_year, escalated_by = end_year - start_year,
      formula = resolved_formula, attempts = bind_rows(attempts)
    ))
  }

  stop(sprintf(
    "No ACS5/decennial vintage in [%d, %d] returned data for variable='%s', geography='%s'.",
    start_year, max_end_year, variable, geography
  ))
}

# Confirmed by live testing (not a vintage question): B17001, the poverty
# table pct_poverty_individuals uses, returns an all-NA estimate at block
# group in every ACS5 vintage tested (2013 through 2022) -- Census does not
# tabulate poverty status this granularly, evidently for reliability/
# disclosure reasons, and no amount of vintage escalation will change that.
# Hardcoded here (rather than discovered live) to avoid burning a 5-year
# window of live test pulls on something already known not to resolve, and
# to avoid halting the whole script on a gap that's expected, not a bug.
# Left NA at build time -- see README's Potential limitations.
# Gated on dataset == "acs5": the empirical finding was specific to B17001
# (the ACS5 table 2010/2020 use), not to pct_poverty_individuals as a
# concept -- 2000's poverty source is SF3 (a different, decennial table)
# and was never tested, so it must go through the normal live-check path
# rather than being short-circuited too.
known_unavailable <- function(variable, geography, dataset) {
  variable == "pct_poverty_individuals" && geography == "block group" && dataset == "acs5"
}
na_formula <- function(variable, geography) {
  list(
    # "NOT_TABULATED" is a placeholder, not a real Census code -- it will
    # never match a column in the pulled data, so compute_variable()'s
    # get_col_sum() correctly falls through to its "no codes found" branch
    # and returns NA for every row. (An actual empty vector here would break
    # format_codes()/the discovery log instead, since a 0-length value can't
    # sit in a one-row tibble alongside the other scalar columns.)
    type = "direct", dataset = "acs5", num = "NOT_TABULATED",
    note = sprintf(
      "%s is not tabulated at %s by the Census Bureau in any ACS5 vintage (B17001 returns an all-NA estimate at every vintage tested, 2013-2022) -- left NA rather than substituting a different table/methodology.",
      variable, geography
    )
  )
}

geographies <- c("zcta", "block group")
year_buckets <- c(2000, 2010, 2020)

resolved <- list()
blocked <- list()

for (geography in geographies) {
  for (year_bucket in year_buckets) {
    yr <- as.character(year_bucket)
    message("=== ", geography, " / ", year_bucket, " ===")

    for (v in names(variable_codes)) {
      formula <- if (v == "pct_unemployed" && year_bucket == 2010) {
        pct_unemployed_2010
      } else {
        variable_codes[[v]][[yr]]
      }
      if (is.null(formula)) next

      if (known_unavailable(v, geography, formula$dataset)) {
        resolved[[paste(geography, year_bucket, v)]] <- list(
          variable = v, geography = geography, year_bucket = year_bucket,
          resolved_end_year = year_bucket, escalated_by = 0L,
          formula = na_formula(v, geography), attempts = tibble()
        )
        message("  ", v, ": known unavailable at ", geography, " -- left NA (no live pull attempted)")
        next
      }

      max_end <- if (formula$dataset == "acs5") year_bucket + ESCALATION_WINDOW else year_bucket

      res <- tryCatch(
        resolve_geography_vintage(v, geography, formula, start_year = year_bucket, max_end_year = max_end),
        error = function(e) {
          blocked[[length(blocked) + 1]] <<- tibble(
            variable = v, geography = geography, year_bucket = year_bucket,
            reason = conditionMessage(e)
          )
          NULL
        }
      )
      if (!is.null(res)) {
        resolved[[paste(geography, year_bucket, v)]] <- res
        message(
          "  ", v, ": resolved at ", res$resolved_end_year,
          if (res$escalated_by > 0) paste0(" (escalated +", res$escalated_by, "y)") else ""
        )
      }
    }
  }
}

if (length(blocked) > 0) {
  print(bind_rows(blocked))
  stop(
    "One or more (variable, geography, year) combinations have no available ",
    "Census data within the search window -- investigate before running ",
    "02_pull_data.R. See above."
  )
}

# ---- Persist overrides for 02_pull_data.R / 04_build_final_datasets.R ----
build_overrides <- function(geography) {
  rows <- resolved[sapply(resolved, function(r) r$geography == geography)]
  bind_rows(lapply(rows, function(r) {
    tibble(
      variable = r$variable, year_bucket = r$year_bucket, dataset = r$formula$dataset,
      resolved_end_year = r$resolved_end_year, escalated_by = r$escalated_by,
      formula = list(r$formula)
    )
  }))
}

overrides_zcta <- build_overrides("zcta")
overrides_blockgroup <- build_overrides("block group")
saveRDS(overrides_zcta, "temp/vintage_overrides_zcta.rds")
saveRDS(overrides_blockgroup, "temp/vintage_overrides_blockgroup.rds")

# ---- Human-readable log ----
discovery_log <- bind_rows(lapply(resolved, function(r) {
  tibble(
    geography = r$geography, year_bucket = r$year_bucket, variable = r$variable,
    dataset = r$formula$dataset, resolved_end_year = r$resolved_end_year,
    escalated_by_years = r$escalated_by, codes_used = format_codes(r$formula),
    note = r$formula$note
  )
})) %>% arrange(geography, year_bucket, variable)

write_csv(discovery_log, "logs/geography_vintage_discovery_log.csv")
message("Wrote logs/geography_vintage_discovery_log.csv (", nrow(discovery_log), " rows).")
message(
  "Wrote temp/vintage_overrides_zcta.rds (", nrow(overrides_zcta), " rows) and ",
  "temp/vintage_overrides_blockgroup.rds (", nrow(overrides_blockgroup), " rows)."
)
