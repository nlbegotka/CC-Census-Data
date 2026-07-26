# Census Data Download Overview

The scripts in this folder output state, county, and tract-level Census data of interest
for the years 2000, 2010, and 2020. This data can be found in `data/processed`. 
Census data for all geographic levels are stacked into a single data frame for each year,
with a `geography_level` column and a `GEOID` column. E.g. `data/processed/census_2000.csv` 
ns state, county, and tract-level data for the year 2000. The raw data downloaded 
to produce these data frames could not be included in the repo due to file size limits. 
ZCTA and Block Group data can be downloaded, as well. For efficiency, this step will 
be completed once the current workflow documented below is confirmed to meet research
standards. 

## How the scripts produce the data 

All raw data comes directly from the U.S. Census Bureau's public API (accessed through the R package
`tidycensus`), plus TIGER/Line boundary files for land area. The pipeline runs as a sequence of scripts:

| Script | What it does |
|---|---|
| `00_setup.R` | Loads required R packages, connects to the Census API, and creates the project's folder structure. |
| `variable_codes.R` | Not run directly — the static registry of Census codes for all 13 variables, sourced by both `01_variable_discovery.R` and `04_build_final_datasets.R`. |
| `01_variable_discovery.R` | Confirms the exact Census variable codes for all 13 variables, across all three years/datasets, checking each one live against the Census Bureau's own variable list so a renamed or retired code is caught. |
| `02_pull_data.R` | Pulls the raw tables from the Census API for the 48 contiguous states + DC, at the state, county, and tract level. |
| `03_land_area.R` | Pulls land area from Census TIGER/Line boundary files, for every state, county, and tract, used to compute population density. |
| `04_build_final_datasets.R` | Combines the raw pulls, computes all 13 variables plus population density, and writes the final per-year files to `data/processed/`. |
| `05_compare_sg_geoids.R` | A one-off check confirming county identifiers in the data SG produced for the dashboard line up correctly with the matching census year. |

## Scope

- **Years**: 2000, 2010, 2020 (not harmonized to a common boundary — each year uses its own
  native tract/county boundaries as published by the Census Bureau for that year).
- **Geography**: state, county, tract. 48 contiguous states + DC only. 

## Census data sources

Each year draws on two kinds of Census release: a **full-count** file (every household,
no sampling error) for basic population/housing totals, and a **sample-based** file
(collected from a subset of households, carries margin of error) for socioeconomic detail
like income, poverty, education, and employment. Which specific files fill those two roles
changes across years, since the Census Bureau's data products themselves changed:

- **SF1** (Summary File 1) — the 2000 and 2010 Decennial Census full-count file. Covers
  basic population and housing counts (total population, race/ethnicity, age, tenure) asked
  of every household. Used for **2000 and 2010**.
- **SF3** (Summary File 3) — the 2000 Decennial Census long-form-sample file. Covers the
  socioeconomic detail (income, poverty, education, employment, crowding) that used to be
  collected via the "long form" sent to a sample of households. Used for **2000 only** — the
  long form was discontinued after 2000.
- **ACS5** (American Community Survey, 5-year estimates) — the survey that replaced the
  decennial long form/SF3 starting in the mid-2000s. It runs continuously and is published
  as rolling 5-year-average estimates (rather than tied to a single census year), which is
  what makes tract-level estimates reliable. Used for the same socioeconomic detail SF3 used
  to cover, for **2010 (2006–2010 estimates) and 2020 (2016–2020 estimates)**.
- **DHC** (Demographic and Housing Characteristics File) — the 2020 Decennial Census's
  full-count file, replacing what SF1 provided in 2000/2010. Used for **2020 only**.

Put together, by year:

| Year | Full-count source | Socioeconomic (sample) source |
|---|---|---|
| 2000 | SF1 | SF3 |
| 2010 | SF1 | ACS5 (2006–2010) |
| 2020 | DHC | ACS5 (2016–2020) |

The variable-by-variable breakdown of exactly which table each of these sources supplies
is in the sourcing table below.

## Variable decisions

- **Race** (`pct_black_nonhisp`, `pct_white_nonhisp`): "alone", not
  "alone or in combination". Non-Hispanic.
- **`pct_hispanic`**: Hispanic or Latino of any race.
- **`pct_le_hs_education`**: population 25 years and older; GED/equivalency counted as
  high-school completion.
- **`pct_poverty_individuals`**: individuals, not families.
- **`pct_overcrowded`**: housing units with >1.0 occupants per room (owner + renter combined).
- **`median_hh_income`**: not inflation-adjusted between years.
- **`population_density`**: total population ÷ land area in square miles (land area from
  TIGER/Line `ALAND`, converted from square meters).

## Variable sourcing information

| Variable | 2000 source | 2010 source | 2020 source | data.census.gov table ID (2000 · 2010 · 2020) |
|---|---|---|---|---|
| `total_population` | SF1 P001001 | SF1 P001001 | DHC P1_001N | P001 · P001 · P1 |
| `pct_black_nonhisp` | SF1 P004006 / P001001 | SF1 P005004 / P001001 | DHC P5_004N / P1_001N | P004 · P005 · P5 |
| `pct_hispanic` | SF1 P004002 / P001001 | SF1 P005010 / P001001 | DHC P5_010N / P1_001N | P004 · P005 · P5 |
| `pct_white_nonhisp` | SF1 P004005 / P001001 | SF1 P005003 / P001001 | DHC P5_003N / P1_001N | P004 · P005 · P5 |
| `median_age` | SF1 P013001 | SF1 P013001 | DHC P13_001N | P013 · P013 · P13 |
| `pct_65plus` | SF1 P012 (65+ brackets) / P001001 | SF1 P012 (65+ brackets) / P001001 | DHC P12 (65+ brackets) / P1_001N | P012 · P012 · P12 |
| `median_hh_income` | SF3 P053001 | ACS5 (2006–2010) B19013_001 | ACS5 (2016–2020) B19013_001 | P053 · B19013 · B19013 |
| `pct_poverty_individuals` | SF3 P087002 / P087001 | ACS5 B17001_002 / B17001_001 | ACS5 B17001_002 / B17001_001 | P087 · B17001 · B17001 |
| `pct_le_hs_education` | SF3 P037 (≤HS brackets) / P037001 | ACS5 B15002 (≤HS brackets) / B15002_001 | ACS5 B15003 (≤HS brackets, incl. GED as separate line) / B15003_001 | P037 · B15002 · B15003 |
| `pct_unemployed` | SF3 P043 (unemployed / civilian labor force) | ACS5 B23001 (summed by age/sex bracket — B23025 doesn't exist for this vintage) | ACS5 B23025_005 / B23025_003 | P043 · B23001 · B23025 |
| `pct_renters` | SF1 H004003 / H004001 | SF1 H004004 / H004001 | DHC H4_004N / H4_001N | H004 · H004 · H4 |
| `pct_overcrowded` | SF3 H020 (>1.0 occ/room) / H020001 | ACS5 B25014 (>1.0 occ/room) / B25014_001 | ACS5 B25014 (>1.0 occ/room) / B25014_001 | H020 · B25014 · B25014 |
| `population_density` | `total_population` / land area (TIGER/Line ALAND00, sq mi) | / ALAND10 | / ALAND | N/A — derived from TIGER/Line, not a Census table |

### Notable cross-year table differences (do not assume codes carry over)

- **Tenure (renter %)**: in 2000, "Renter occupied" is H004003. In 2010/2020, the tenure table
  adds an owner-occupied split ("with mortgage" vs. "free and clear"), pushing renter to
  H004004 (SF1) / H4_004N (DHC).
- **Unemployment**: 2000 SF3 and 2020 ACS5 both have a simple employment-status summary table
  (P043, B23025). The 2010 ACS5 (2006–2010) vintage does not include B23025 — it was introduced
  in a later ACS table redesign — so 2010 sums the detailed sex-by-age table B23001 across all
  age/sex brackets instead.
- **Educational attainment**: 2000 SF3 (P037) and 2010 ACS5 (B15002) list "High school graduate
  (includes equivalency)" as one category. 2020 ACS5 (B15003) splits this into "Regular high
  school diploma" and "GED or alternative credential" as two separate line items; both are
  included in the ≤HS numerator.

## Potential limitations of this pass 

- **Not harmonized** — each year's tract/county boundaries are that year's own boundaries, not
  reconciled onto a common geography. A tract's GEOID and shape can differ across years.
- **No suppression/jam-value handling** — small-population tracts with suppressed or
  disclosure-avoided values are not specially flagged; `NA`s from missing table cells are
  treated as 0 when summing sub-categories (e.g., age brackets, education brackets), which can
  slightly understate a rare category in very small geographies.
- **Zero-population tracts produce `NA` percentages** — a small share of tracts (roughly
  0.4-1.7% depending on year; verified these are all `total_population == 0`, e.g. water bodies,
  airports, uninhabited land) have every `pct_*` variable as `NA` (0/0) and
  `population_density` as `NA` when land area is also 0. This is expected, not missing data.
- **No margin-of-error tracking** — ACS-sourced variables (2010, 2020 income/poverty/
  education/employment/crowding) carry sampling error; MOEs were pulled but dropped in the
  final build. 
- **2020 differential privacy** — 2020 Decennial (DHC) counts use the Census Bureau's
  differential-privacy disclosure avoidance system, which injects noise, particularly visible
  in small-population tracts.
