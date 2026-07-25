# Shared per-variable / per-year Census code registry.
#
# Every entry here is a fixed, known fact about a table's layout (a single
# code, or a static range like "the 65+ age brackets are codes 20-25 and
# 44-49") -- nothing in this file depends on querying the Census API at
# runtime. It is sourced by both 01_variable_discovery.R (which uses it to
# know what to pull, live-verifies each code still exists, and logs it) and
# 04_build_final_datasets.R (which uses it directly to compute each
# variable, so the exact codes are visible in that script without needing
# to open this one).
#
# `pct_unemployed`'s 2010 entry is deliberately absent: that year's table
# (B23001) has no simple total-unemployed row, so its code list can't be
# written down as a fixed fact the way every other entry here can. It is
# resolved at runtime in 01_variable_discovery.R via live label-matching
# against the Census variable list -- see that script and
# logs/variable_discovery_log.csv for the resolved result.
#
# Fields per (variable, year) entry:
#   type    "direct" (passthrough) or "ratio" (num/den, summed and divided)
#   dataset which Census dataset the code(s) come from (sf1/sf3/dhc/acs5)
#   num/den Census variable code(s)
#   note    human-readable description, used only for the discovery log

variable_codes <- list(
  total_population = list(
    `2000` = list(type = "direct", dataset = "sf1", num = "P001001",
                  note = "Direct count."),
    `2010` = list(type = "direct", dataset = "sf1", num = "P001001",
                  note = "Direct count."),
    `2020` = list(type = "direct", dataset = "dhc", num = "P1_001N",
                  note = "Direct count.")
  ),

  pct_black_nonhisp = list(
    `2000` = list(type = "ratio", dataset = "sf1", num = "P004006", den = "P001001",
                  note = "Black alone, not Hispanic, over total pop."),
    `2010` = list(type = "ratio", dataset = "sf1", num = "P005004", den = "P001001",
                  note = "Black alone, not Hispanic, over total pop."),
    `2020` = list(type = "ratio", dataset = "dhc", num = "P5_004N", den = "P1_001N",
                  note = "Black alone, not Hispanic, over total pop.")
  ),

  pct_hispanic = list(
    `2000` = list(type = "ratio", dataset = "sf1", num = "P004002", den = "P001001",
                  note = "Hispanic or Latino, any race, over total pop."),
    `2010` = list(type = "ratio", dataset = "sf1", num = "P005010", den = "P001001",
                  note = "Hispanic or Latino, any race, over total pop."),
    `2020` = list(type = "ratio", dataset = "dhc", num = "P5_010N", den = "P1_001N",
                  note = "Hispanic or Latino, any race, over total pop.")
  ),

  pct_white_nonhisp = list(
    `2000` = list(type = "ratio", dataset = "sf1", num = "P004005", den = "P001001",
                  note = "White alone, not Hispanic, over total pop."),
    `2010` = list(type = "ratio", dataset = "sf1", num = "P005003", den = "P001001",
                  note = "White alone, not Hispanic, over total pop."),
    `2020` = list(type = "ratio", dataset = "dhc", num = "P5_003N", den = "P1_001N",
                  note = "White alone, not Hispanic, over total pop.")
  ),

  median_age = list(
    `2000` = list(type = "direct", dataset = "sf1", num = "P013001",
                  note = "Direct estimate."),
    `2010` = list(type = "direct", dataset = "sf1", num = "P013001",
                  note = "Direct estimate."),
    `2020` = list(type = "direct", dataset = "dhc", num = "P13_001N",
                  note = "Direct estimate.")
  ),

  # Male + female 65+ age brackets, summed, over total population.
  pct_65plus = list(
    `2000` = list(type = "ratio", dataset = "sf1",
                  num = sprintf("P012%03d", c(20:25, 44:49)), den = "P001001",
                  note = "Sum of male+female 65+ age brackets / total population."),
    `2010` = list(type = "ratio", dataset = "sf1",
                  num = sprintf("P012%03d", c(20:25, 44:49)), den = "P001001",
                  note = "Sum of male+female 65+ age brackets / total population."),
    `2020` = list(type = "ratio", dataset = "dhc",
                  num = sprintf("P12_%03dN", c(20:25, 44:49)), den = "P1_001N",
                  note = "Sum of male+female 65+ age brackets / total population.")
  ),

  median_hh_income = list(
    `2000` = list(type = "direct", dataset = "sf3", num = "P053001",
                  note = "Direct estimate, 1999 dollars (not inflation-adjusted here)."),
    `2010` = list(type = "direct", dataset = "acs5", num = "B19013_001",
                  note = "Direct estimate, 2006-2010 ACS5."),
    `2020` = list(type = "direct", dataset = "acs5", num = "B19013_001",
                  note = "Direct estimate, 2016-2020 ACS5.")
  ),

  pct_poverty_individuals = list(
    `2000` = list(type = "ratio", dataset = "sf3", num = "P087002", den = "P087001",
                  note = "Individuals below poverty / total individuals for whom poverty determined."),
    `2010` = list(type = "ratio", dataset = "acs5", num = "B17001_002", den = "B17001_001",
                  note = "Individuals below poverty / total individuals for whom poverty determined."),
    `2020` = list(type = "ratio", dataset = "acs5", num = "B17001_002", den = "B17001_001",
                  note = "Individuals below poverty / total individuals for whom poverty determined.")
  ),

  # Population 25+, no schooling through HS grad/equivalency, both sexes,
  # over total 25+. 2020's B15003 splits HS diploma and GED into two lines
  # (both included in the <=HS numerator per the locked GED-counts decision).
  pct_le_hs_education = list(
    `2000` = list(
      type = "ratio", dataset = "sf3",
      num = c(sprintf("P037%03d", 3:11), sprintf("P037%03d", 20:28)),
      den = "P037001",
      note = "Population 25+, no schooling through HS grad/equivalency, both sexes, over total 25+."
    ),
    `2010` = list(
      type = "ratio", dataset = "acs5",
      num = c(sprintf("B15002_%03d", 3:11), sprintf("B15002_%03d", 20:28)),
      den = "B15002_001",
      note = "Population 25+, no schooling through HS grad/GED, both sexes, over total 25+."
    ),
    `2020` = list(
      type = "ratio", dataset = "acs5",
      num = sprintf("B15003_%03d", 2:18),
      den = "B15003_001",
      note = "Population 25+, no schooling through HS diploma or GED/alt credential, over total 25+."
    )
  ),

  # 2010 intentionally omitted -- see file header and 01_variable_discovery.R.
  pct_unemployed = list(
    `2000` = list(type = "ratio", dataset = "sf3", num = c("P043007", "P043014"), den = c("P043005", "P043012"),
                  note = "Unemployed (male+female) / civilian labor force (male+female)."),
    `2020` = list(type = "ratio", dataset = "acs5", num = "B23025_005", den = "B23025_003",
                  note = "Unemployed / civilian labor force.")
  ),

  # Renter-occupied / total occupied units. Numerator code shifts across
  # years because 2010/2020 split owner-occupied into mortgage/free-and-clear,
  # pushing renter down one row.
  pct_renters = list(
    `2000` = list(type = "ratio", dataset = "sf1", num = "H004003", den = "H004001",
                  note = "Renter-occupied / total occupied units."),
    `2010` = list(type = "ratio", dataset = "sf1", num = "H004004", den = "H004001",
                  note = "Renter-occupied / total occupied units (code shifts vs 2000 -- tenure table adds owner mortgage/free-and-clear split)."),
    `2020` = list(type = "ratio", dataset = "dhc", num = "H4_004N", den = "H4_001N",
                  note = "Renter-occupied / total occupied units.")
  ),

  # >1.00 occupants/room (owner+renter, all brackets above 1.00) / total
  # occupied units.
  pct_overcrowded = list(
    `2000` = list(type = "ratio", dataset = "sf3",
                  num = sprintf("H020%03d", c(5, 6, 7, 11, 12, 13)), den = "H020001",
                  note = ">1.00 occupants/room (owner+renter, all brackets above 1.00) / total occupied units."),
    `2010` = list(type = "ratio", dataset = "acs5",
                  num = sprintf("B25014_%03d", c(5, 6, 7, 11, 12, 13)), den = "B25014_001",
                  note = ">1.00 occupants/room (owner+renter, all brackets above 1.00) / total occupied units."),
    `2020` = list(type = "ratio", dataset = "acs5",
                  num = sprintf("B25014_%03d", c(5, 6, 7, 11, 12, 13)), den = "B25014_001",
                  note = ">1.00 occupants/room (owner+renter, all brackets above 1.00) / total occupied units.")
  )
)

# Format an entry's codes into the human-readable string used in the
# discovery log (e.g. "P004006 / P001001" or "(H020005+...+H020013) / H020001").
format_codes <- function(entry) {
  fmt_side <- function(codes) {
    if (length(codes) > 1) paste0("(", paste(codes, collapse = "+"), ")") else codes
  }
  if (entry$type == "direct") return(fmt_side(entry$num))
  paste(fmt_side(entry$num), "/", fmt_side(entry$den))
}
