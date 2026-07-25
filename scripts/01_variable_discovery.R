# Step 1: dataset/table discovery
#
# Confirms exact Census variable codes for all 13 target variables across
# 2000 (dec/sf1 + dec/sf3), 2010 (dec/sf1 + acs/acs5 2006-2010), and
# 2020 (dec/dhc + acs/acs5 2016-2020). Codes were identified by inspecting
# load_variables() output for each dataset directly (never assumed to carry
# over between years) and are re-verified here against the live variable
# list before being logged, so a silently renamed/retired code fails loudly
# instead of pulling the wrong table.
#
# NOTE ON TABLE CHANGES ACROSS YEARS (do not "simplify" these to one shared
# set of codes -- they differ for real reasons):
#  - Tenure (H004) reorders categories between 2000 and 2010/2020: in 2000,
#    "Renter occupied" is H004003; in 2010/2020 SF1/DHC, owner-occupied is
#    split into "with mortgage" / "free and clear", pushing renter to
#    H004004 (SF1) / H4_004N (DHC).
#  - Unemployment: 2000 SF3 and 2020 ACS5 both have a simple employment-status
#    table (P043, B23025). 2010 ACS5 (2006-2010 vintage) does NOT have B23025
#    -- it wasn't introduced until a later ACS table redesign -- so 2010 uses
#    the detailed sex-by-age table B23001 instead, summed across all age/sex
#    brackets by matching on label suffix.
#  - Educational attainment: 2000 SF3 (P037) and 2010 ACS5 (B15002) list
#    "High school graduate (includes equivalency)" as a single category.
#    2020 ACS5 (B15003) splits this into "Regular high school diploma" and
#    "GED or alternative credential" as two separate line items -- both are
#    included in the <=HS numerator per the locked GED-counts decision.

source("scripts/00_setup.R")

# ---- 2000 ----------------------------------------------------------------
v2000_sf1 <- load_variables(2000, "sf1")
v2000_sf3 <- load_variables(2000, "sf3")

# ---- 2010 ------------------------------------------------------------------
v2010_sf1 <- load_variables(2010, "sf1")
v2010_acs5 <- load_variables(2010, "acs5")

# ---- 2020 ------------------------------------------------------------------
v2020_dhc <- load_variables(2020, "dhc")
v2020_acs5 <- load_variables(2020, "acs5")

# B23001 (2010 unemployment) and B15002 (2010 education) break out by age/sex
# bracket rather than having simple total/employed/unemployed rows, so their
# component codes are identified programmatically by label suffix instead of
# being hand-typed.
b23001_employed <- v2010_acs5 %>%
  filter(str_detect(concept, "^SEX BY AGE BY EMPLOYMENT STATUS FOR THE POPULATION 16 YEARS AND OVER$")) %>%
  filter(str_ends(label, "Civilian!!Employed")) %>%
  pull(name)
b23001_unemployed <- v2010_acs5 %>%
  filter(str_detect(concept, "^SEX BY AGE BY EMPLOYMENT STATUS FOR THE POPULATION 16 YEARS AND OVER$")) %>%
  filter(str_ends(label, "Civilian!!Unemployed")) %>%
  pull(name)

b15002_le_hs_male <- sprintf("B15002_%03d", 3:11)   # no schooling .. HS grad/GED, male
b15002_le_hs_female <- sprintf("B15002_%03d", 20:28) # no schooling .. HS grad/GED, female

p037_le_hs_male <- sprintf("P037%03d", 3:11)
p037_le_hs_female <- sprintf("P037%03d", 20:28)

b15003_le_hs <- sprintf("B15003_%03d", 2:18) # no schooling .. GED/alt credential

# ---- Variable code registry -------------------------------------------------
# One row per (variable, year) with the code(s) needed to compute it and a
# short note on how they combine. This is what 02_pull_data.R and
# 04_build_final_datasets.R consume.
variable_registry <- list(
  list(variable = "total_population", year = 2000, dataset = "sf1",
       codes = "P001001", note = "Direct count."),
  list(variable = "total_population", year = 2010, dataset = "sf1",
       codes = "P001001", note = "Direct count."),
  list(variable = "total_population", year = 2020, dataset = "dhc",
       codes = "P1_001N", note = "Direct count."),

  list(variable = "pct_black_nonhisp", year = 2000, dataset = "sf1",
       codes = "P004006 / P001001", note = "Black alone, not Hispanic, over total pop."),
  list(variable = "pct_black_nonhisp", year = 2010, dataset = "sf1",
       codes = "P005004 / P001001", note = "Black alone, not Hispanic, over total pop."),
  list(variable = "pct_black_nonhisp", year = 2020, dataset = "dhc",
       codes = "P5_004N / P1_001N", note = "Black alone, not Hispanic, over total pop."),

  list(variable = "pct_hispanic", year = 2000, dataset = "sf1",
       codes = "P004002 / P001001", note = "Hispanic or Latino, any race, over total pop."),
  list(variable = "pct_hispanic", year = 2010, dataset = "sf1",
       codes = "P005010 / P001001", note = "Hispanic or Latino, any race, over total pop."),
  list(variable = "pct_hispanic", year = 2020, dataset = "dhc",
       codes = "P5_010N / P1_001N", note = "Hispanic or Latino, any race, over total pop."),

  list(variable = "pct_white_nonhisp", year = 2000, dataset = "sf1",
       codes = "P004005 / P001001", note = "White alone, not Hispanic, over total pop."),
  list(variable = "pct_white_nonhisp", year = 2010, dataset = "sf1",
       codes = "P005003 / P001001", note = "White alone, not Hispanic, over total pop."),
  list(variable = "pct_white_nonhisp", year = 2020, dataset = "dhc",
       codes = "P5_003N / P1_001N", note = "White alone, not Hispanic, over total pop."),

  list(variable = "median_age", year = 2000, dataset = "sf1",
       codes = "P013001", note = "Direct estimate."),
  list(variable = "median_age", year = 2010, dataset = "sf1",
       codes = "P013001", note = "Direct estimate."),
  list(variable = "median_age", year = 2020, dataset = "dhc",
       codes = "P13_001N", note = "Direct estimate."),

  list(variable = "pct_65plus", year = 2000, dataset = "sf1",
       codes = paste0("(", paste(sprintf("P012%03d", c(20:25, 44:49)), collapse = "+"), ") / P001001"),
       note = "Sum of male+female 65+ age brackets / total population."),
  list(variable = "pct_65plus", year = 2010, dataset = "sf1",
       codes = paste0("(", paste(sprintf("P012%03d", c(20:25, 44:49)), collapse = "+"), ") / P001001"),
       note = "Sum of male+female 65+ age brackets / total population."),
  list(variable = "pct_65plus", year = 2020, dataset = "dhc",
       codes = paste0("(", paste(sprintf("P12_%03dN", c(20:25, 44:49)), collapse = "+"), ") / P1_001N"),
       note = "Sum of male+female 65+ age brackets / total population."),

  list(variable = "median_hh_income", year = 2000, dataset = "sf3",
       codes = "P053001", note = "Direct estimate, 1999 dollars (not inflation-adjusted here)."),
  list(variable = "median_hh_income", year = 2010, dataset = "acs5",
       codes = "B19013_001", note = "Direct estimate, 2006-2010 ACS5."),
  list(variable = "median_hh_income", year = 2020, dataset = "acs5",
       codes = "B19013_001", note = "Direct estimate, 2016-2020 ACS5."),

  list(variable = "pct_poverty_individuals", year = 2000, dataset = "sf3",
       codes = "P087002 / P087001", note = "Individuals below poverty / total individuals for whom poverty determined."),
  list(variable = "pct_poverty_individuals", year = 2010, dataset = "acs5",
       codes = "B17001_002 / B17001_001", note = "Individuals below poverty / total individuals for whom poverty determined."),
  list(variable = "pct_poverty_individuals", year = 2020, dataset = "acs5",
       codes = "B17001_002 / B17001_001", note = "Individuals below poverty / total individuals for whom poverty determined."),

  list(variable = "pct_le_hs_education", year = 2000, dataset = "sf3",
       codes = paste0("sum(", paste(c(p037_le_hs_male, p037_le_hs_female), collapse = "+"), ") / P037001"),
       note = "Population 25+, no schooling through HS grad/equivalency, both sexes, over total 25+."),
  list(variable = "pct_le_hs_education", year = 2010, dataset = "acs5",
       codes = paste0("sum(", paste(c(b15002_le_hs_male, b15002_le_hs_female), collapse = "+"), ") / B15002_001"),
       note = "Population 25+, no schooling through HS grad/GED, both sexes, over total 25+."),
  list(variable = "pct_le_hs_education", year = 2020, dataset = "acs5",
       codes = paste0("sum(", paste(b15003_le_hs, collapse = "+"), ") / B15003_001"),
       note = "Population 25+, no schooling through HS diploma or GED/alt credential, over total 25+."),

  list(variable = "pct_unemployed", year = 2000, dataset = "sf3",
       codes = "(P043007+P043014) / (P043005+P043012)",
       note = "Unemployed (male+female) / civilian labor force (male+female)."),
  list(variable = "pct_unemployed", year = 2010, dataset = "acs5",
       codes = paste0("sum(", paste(b23001_unemployed, collapse = "+"), ") / sum(",
                       paste(c(b23001_employed, b23001_unemployed), collapse = "+"), ")"),
       note = "B23001 has no simple total; summed across all age/sex brackets by label suffix match."),
  list(variable = "pct_unemployed", year = 2020, dataset = "acs5",
       codes = "B23025_005 / B23025_003", note = "Unemployed / civilian labor force."),

  list(variable = "pct_renters", year = 2000, dataset = "sf1",
       codes = "H004003 / H004001", note = "Renter-occupied / total occupied units."),
  list(variable = "pct_renters", year = 2010, dataset = "sf1",
       codes = "H004004 / H004001", note = "Renter-occupied / total occupied units (code shifts vs 2000 -- tenure table adds owner mortgage/free-and-clear split)."),
  list(variable = "pct_renters", year = 2020, dataset = "dhc",
       codes = "H4_004N / H4_001N", note = "Renter-occupied / total occupied units."),

  list(variable = "pct_overcrowded", year = 2000, dataset = "sf3",
       codes = "(H020005+H020006+H020007+H020011+H020012+H020013) / H020001",
       note = ">1.00 occupants/room (owner+renter, all brackets above 1.00) / total occupied units."),
  list(variable = "pct_overcrowded", year = 2010, dataset = "acs5",
       codes = "(B25014_005+B25014_006+B25014_007+B25014_011+B25014_012+B25014_013) / B25014_001",
       note = ">1.00 occupants/room (owner+renter, all brackets above 1.00) / total occupied units."),
  list(variable = "pct_overcrowded", year = 2020, dataset = "acs5",
       codes = "(B25014_005+B25014_006+B25014_007+B25014_011+B25014_012+B25014_013) / B25014_001",
       note = ">1.00 occupants/room (owner+renter, all brackets above 1.00) / total occupied units.")
)

registry_df <- bind_rows(lapply(variable_registry, as_tibble))

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
    "investigate and correct the registry above before pulling data."
  )
}

message("All ", nrow(registry_df), " variable/year entries verified against live Census variable lists.")

# ---- Log ---------------------------------------------------------------
discovery_log <- registry_df %>%
  mutate(geography_levels_confirmed = "state, county, tract (48 contiguous states + DC)") %>%
  select(variable, year, dataset, codes, note, geography_levels_confirmed)

write_csv(discovery_log, "logs/variable_discovery_log.csv")
message("Wrote logs/variable_discovery_log.csv (", nrow(discovery_log), " rows).")

saveRDS(variable_registry, "temp/variable_registry.rds")

# ---- Machine-usable formulas for 04_build_final_datasets.R -----------------
# The `codes` field above is a human-readable string for the log; this list
# gives 04_build_final_datasets.R the actual numerator/denominator code
# vectors to sum, keyed by "<variable>_<year>", so the build script never has
# to re-parse formula text.
formulas <- list(
  total_population_2000 = list(type = "direct", num = "P001001"),
  total_population_2010 = list(type = "direct", num = "P001001"),
  total_population_2020 = list(type = "direct", num = "P1_001N"),

  pct_black_nonhisp_2000 = list(type = "ratio", num = "P004006", den = "P001001"),
  pct_black_nonhisp_2010 = list(type = "ratio", num = "P005004", den = "P001001"),
  pct_black_nonhisp_2020 = list(type = "ratio", num = "P5_004N", den = "P1_001N"),

  pct_hispanic_2000 = list(type = "ratio", num = "P004002", den = "P001001"),
  pct_hispanic_2010 = list(type = "ratio", num = "P005010", den = "P001001"),
  pct_hispanic_2020 = list(type = "ratio", num = "P5_010N", den = "P1_001N"),

  pct_white_nonhisp_2000 = list(type = "ratio", num = "P004005", den = "P001001"),
  pct_white_nonhisp_2010 = list(type = "ratio", num = "P005003", den = "P001001"),
  pct_white_nonhisp_2020 = list(type = "ratio", num = "P5_003N", den = "P1_001N"),

  median_age_2000 = list(type = "direct", num = "P013001"),
  median_age_2010 = list(type = "direct", num = "P013001"),
  median_age_2020 = list(type = "direct", num = "P13_001N"),

  pct_65plus_2000 = list(type = "ratio", num = sprintf("P012%03d", c(20:25, 44:49)), den = "P001001"),
  pct_65plus_2010 = list(type = "ratio", num = sprintf("P012%03d", c(20:25, 44:49)), den = "P001001"),
  pct_65plus_2020 = list(type = "ratio", num = sprintf("P12_%03dN", c(20:25, 44:49)), den = "P1_001N"),

  median_hh_income_2000 = list(type = "direct", num = "P053001"),
  median_hh_income_2010 = list(type = "direct", num = "B19013_001"),
  median_hh_income_2020 = list(type = "direct", num = "B19013_001"),

  pct_poverty_individuals_2000 = list(type = "ratio", num = "P087002", den = "P087001"),
  pct_poverty_individuals_2010 = list(type = "ratio", num = "B17001_002", den = "B17001_001"),
  pct_poverty_individuals_2020 = list(type = "ratio", num = "B17001_002", den = "B17001_001"),

  pct_le_hs_education_2000 = list(type = "ratio", num = c(p037_le_hs_male, p037_le_hs_female), den = "P037001"),
  pct_le_hs_education_2010 = list(type = "ratio", num = c(b15002_le_hs_male, b15002_le_hs_female), den = "B15002_001"),
  pct_le_hs_education_2020 = list(type = "ratio", num = b15003_le_hs, den = "B15003_001"),

  pct_unemployed_2000 = list(type = "ratio", num = c("P043007", "P043014"), den = c("P043005", "P043012")),
  pct_unemployed_2010 = list(type = "ratio", num = b23001_unemployed, den = c(b23001_employed, b23001_unemployed)),
  pct_unemployed_2020 = list(type = "ratio", num = "B23025_005", den = "B23025_003"),

  pct_renters_2000 = list(type = "ratio", num = "H004003", den = "H004001"),
  pct_renters_2010 = list(type = "ratio", num = "H004004", den = "H004001"),
  pct_renters_2020 = list(type = "ratio", num = "H4_004N", den = "H4_001N"),

  pct_overcrowded_2000 = list(type = "ratio", num = sprintf("H020%03d", c(5, 6, 7, 11, 12, 13)), den = "H020001"),
  pct_overcrowded_2010 = list(type = "ratio", num = sprintf("B25014_%03d", c(5, 6, 7, 11, 12, 13)), den = "B25014_001"),
  pct_overcrowded_2020 = list(type = "ratio", num = sprintf("B25014_%03d", c(5, 6, 7, 11, 12, 13)), den = "B25014_001")
)

# Sanity-check every formula's codes exist in variable_registry's codes for
# that variable/year (catches a copy-paste mismatch between the two lists).
for (key in names(formulas)) {
  parts <- str_split(key, "_(?=\\d{4}$)", n = 2)[[1]]
  var_name <- parts[1]
  yr <- as.integer(parts[2])
  reg_entry <- registry_df %>% filter(variable == var_name, year == yr)
  if (nrow(reg_entry) != 1) {
    stop("formulas entry '", key, "' has no matching row in variable_registry.")
  }
  reg_codes <- extract_codes(reg_entry$codes)
  formula_codes <- unique(c(formulas[[key]]$num, formulas[[key]]$den))
  if (!setequal(reg_codes, formula_codes)) {
    stop(
      "Mismatch between variable_registry and formulas for '", key, "':\n",
      "  registry codes: ", paste(sort(reg_codes), collapse = ", "), "\n",
      "  formula codes:  ", paste(sort(formula_codes), collapse = ", ")
    )
  }
}
message("All ", length(formulas), " formula entries cross-checked against variable_registry.")

saveRDS(formulas, "temp/formulas.rds")
message("Wrote temp/formulas.rds.")
