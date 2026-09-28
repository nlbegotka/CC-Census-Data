# Census Data Download Overview

The scripts in this folder output state, county, tract, ZCTA, and block-group-level Census data
of interest for the years 2000, 2010, and 2020. This data can be found in `data/processed`.
Census data for all geographic levels are stacked into a single data frame for each year,
with a `geography_level` column and a `GEOID` column. E.g. `data/processed/census_2000.csv`
includes state, county, tract, ZCTA, and block-group-level data for the year 2000. The raw data
downloaded to produce the processed data could not be included in the repo due to file size limits.

## Scope

- **Years**: 2000, 2010, 2020 (not harmonized to a common boundary — each year uses its own
  native tract/county boundaries as published by the Census Bureau for that year).
- **Geography**: state, county, tract, ZCTA, block group. 48 contiguous states + DC only.
  For ACS5-sourced variables, ZCTA and block group can draw on a *different* ACS5 vintage
  than state/county/tract for the same `year` value — the 2006-2010 ACS5 vintage doesn't
  publish ZCTA or block-group geography at all, so those two levels fall back to the earliest
  later vintage that does. See [Geography-level vintage exceptions](#geography-level-vintage-exceptions).

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

## Geography-level vintage exceptions

State/county/tract's ACS5-sourced variables (`median_hh_income`, `pct_poverty_individuals`,
`pct_le_hs_education`, `pct_unemployed`, `pct_overcrowded`) always use the vintage in the table
above (2006–2010 for the 2010 bucket, 2016–2020 for the 2020 bucket). **ZCTA and block group do
not** — confirmed live against the Census API, the 2006–2010 ACS5 vintage does not publish ZCTA
or block-group geography at all (not just one table), and tidycensus additionally refuses
block-group requests for any vintage before 2013 regardless of what the API itself supports. So
for these two geography levels only, each ACS5-sourced variable is independently escalated
forward, one year at a time, to the earliest later vintage that actually returns data for it —
this can differ from variable to variable and from the ZCTA/block-group resolution for the same
variable. This is intentional (state/county/tract data is never re-pulled to "fix" the mismatch)
and resolved live rather than hardcoded, since a table's exact first-available vintage isn't
published anywhere as a stable fact. For `pct_unemployed` specifically, once an escalated vintage
is found where table B23025 (a clean total-unemployed count) exists, it's used directly instead
of replicating the label-matching workaround state/county/tract needed for B23001.

Confirmed examples from initial testing (not a complete list — the authoritative, current
mapping for every variable/year is written by `01b_geography_vintage_discovery.R` to
`logs/geography_vintage_discovery_log.csv` each time the pipeline runs):

| Variable | Geography | State/county/tract vintage | Resolved vintage |
|---|---|---|---|
| `median_hh_income` | ZCTA | ACS5 2006–2010 | ACS5 2007–2011 (earliest vintage ZCTA data exists at all) |
| any ACS5-sourced 2010-bucket variable | block group | ACS5 2006–2010 | no earlier than ACS5 2009–2013 (tidycensus refuses block-group requests before this, regardless of Census API support) |
| `pct_unemployed` | block group | ACS5 2006–2010, B23001 workaround | B23025 (the same clean table 2020 already uses), at whatever vintage it's first available for block group — table B23001 (the workaround the 2010 bucket otherwise needs) is not published at block group in any vintage tested, so B23025 is used unconditionally at this geography rather than only once escalation happens to land on a vintage where B23025 exists |

Decennial-sourced variables (`total_population` and the other SF1/DHC-based variables) have no
vintage concept — they're a fixed, single-year full count — so no escalation applies to them at
any geography level.

**`pct_poverty_individuals` is left `NA` at block group for the 2010 and 2020 buckets** — not a
vintage problem. B17001 (the ACS5 table this variable is sourced from at every other geography
level, and for 2010/2020 at every geography level other than block group) returns an all-`NA`
estimate at block group in every ACS5 vintage tested (2013 through 2022); the Census Bureau
evidently does not tabulate poverty status this granularly, for reliability/disclosure reasons,
and no amount of vintage escalation changes that. 2000 is unaffected — that bucket sources
`pct_poverty_individuals` from SF3 (a decennial long-form table, not ACS5/B17001), and block
group works normally there (~0.6% `NA`, in line with ordinary small-area suppression, not the
~100% seen in 2010/2020). `01b_geography_vintage_discovery.R` hardcodes the 2010/2020 gap as a
known exception (skips the live escalation attempt entirely for those two combinations) rather
than rediscovering the same negative result on every run. A different table,
`C17002` ("Ratio of Income to Poverty Level"), *is* fully tabulated at block group — and at every
other geography level, including ZCTA (confirmed down to the 2011 vintage) — and could stand in
for B17001 (summing the `Under .50` and `.50 to .99` bins over the total, as the "% below poverty"
equivalent) if this gap is worth closing later. That substitution isn't implemented here since it
changes the underlying table/methodology rather than just the vintage, which is a decision
deliberately left open rather than made unilaterally.

## How the scripts produce the data 

All raw data comes directly from the U.S. Census Bureau's public API (accessed through R's
`tidycensus`), plus TIGER/Line boundary files for land area. The pipeline runs as a sequence of scripts:

| Script | What it does |
|---|---|
| `00_setup.R` | Loads required R packages, connects to the Census API, and creates the project's folder structure. |
| `variable_codes.R` | Not run directly — the static registry of Census codes for all 13 variables, sourced by both `01_variable_discovery.R` and `04_build_final_datasets.R`. |
| `01_variable_discovery.R` | Confirms the exact Census variable codes for all 13 variables, across all three years/datasets, checking each one live against the Census Bureau's own variable list so a renamed or retired code is caught. |
| `01b_geography_vintage_discovery.R` | For ZCTA and block group only: live-tests each variable against progressively later ACS5 vintages until one actually returns data at that geography (see [Geography-level vintage exceptions](#geography-level-vintage-exceptions)), and persists the resolved vintage/formula for `02_pull_data.R` and `04_build_final_datasets.R` to use. |
| `02_pull_data.R` | Pulls the raw tables from the Census API for the 48 contiguous states + DC, at the state, county, tract, ZCTA, and block-group level. ZCTA/block-group ACS5 pulls use the vintage overrides from `01b` instead of the state/county/tract vintage. |
| `03_land_area.R` | Pulls land area from Census TIGER/Line boundary files, for every state, county, tract, ZCTA, and block group, used to compute population density. |
| `04_build_final_datasets.R` | Combines the raw pulls, computes all 13 variables plus population density, and writes the final per-year files to `data/processed/`, stacking all five geography levels. |
| `05_compare_sg_geoids.R` | A one-off check confirming county identifiers in the data SG produced for the dashboard line up correctly with the matching census year. |
| `06_compare_church_geoids.R` | A one-off check comparing GEOIDs in SG's church/religious-organization panel dataset (state/county/tract derived from its block-group GEOID, plus its native block-group and ZCTA columns) against this pipeline's own extraction, across all 5 geography levels and all three years, with the same cross-year mislabel diagnostic `05` uses. |

## Potential limitations 

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
- **ZCTA/block-group vintage mismatch** — for ACS5-sourced variables, ZCTA and block group can
  come from a different (later) ACS5 vintage than state/county/tract for the same `year` value.
  See [Geography-level vintage exceptions](#geography-level-vintage-exceptions).
- **ZCTA state assignment is approximate** — ZCTA GEOIDs carry no state FIPS code, so scoping
  ZCTAs to the 48 contiguous states + DC uses a point-on-surface-in-polygon spatial join against
  state boundaries (`sf::st_point_on_surface()`, guaranteed to land on the ZCTA's own shape). An
  earlier version of this join used a plain geometric centroid (`st_centroid()`) instead, which
  is *not* guaranteed to fall inside a multi-part or concave polygon — for ZCTAs with offshore
  islands or irregular, concave shapes, the centroid could land in a gap between pieces (often
  open water), outside every state polygon, silently dropping an otherwise valid ZCTA from scope
  entirely. That was found and fixed (confirmed to have affected exactly 4 ZCTAs in 2000, 4 in
  2010, and 3 in 2020, nationally) via a real GEOID comparison against an external dataset. The
  remaining, inherent limitation: a handful of ZCTAs genuinely straddle a state line, and each
  still gets assigned to a single state based on where its on-surface point falls, which can
  occasionally be the "wrong" side for an oddly-shaped, boundary-straddling ZCTA.
- **Block group has a hard floor on how far back it goes** — tidycensus refuses ACS5 block-group
  requests before the 2009-2013 vintage regardless of Census API support, so no amount of vintage
  escalation can produce block-group ACS5 data earlier than that.
- **`pct_poverty_individuals` is `NA` at block group for the 2010 and 2020 buckets** — B17001
  (the ACS5 table those two years source it from) is never tabulated at block group by the
  Census Bureau, in any ACS5 vintage. 2000 is unaffected, since it sources this variable from
  SF3 instead. See [Geography-level vintage exceptions](#geography-level-vintage-exceptions)
  for the alternative table (`C17002`) that could close this gap if desired.
