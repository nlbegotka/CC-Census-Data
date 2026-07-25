# Project Summary: Harmonized Demographic Dataset for Public Web Tool

## 1. Project Overview

**Goal:** Build a public-facing web tool displaying demographic data for **state, county, census tract, and block group** levels, across **2000, 2010, and 2020**.

**Variables (12 total):**
1. Total population
2. Population density (population ÷ land area)
3. % Black or African American
4. % Hispanic or Latino
5. % White
6. Mean age or % 65 and older
7. Median household income
8. % in poverty
9. % with ≤ high school education
10. % unemployed
11. % renters
12. Overcrowding (% of housing units with >1.0 occupants per room)

## 2. Key Decisions Made

- **Data source for anything published: census.gov / api.census.gov only.** NHGIS's terms of use prohibit redistributing their data publicly (only pre-authorized for limited journal-requirement subsets), which rules them out as a source for the public-facing dataset itself.
- **NHGIS geographic crosswalks are retained, but for internal harmonization computation only** — never published or redistributed. Only the final Census-sourced, harmonized values go into the public output. This is treated as a reasonable but not 100%-certain reading of NHGIS's terms; if the project becomes high-visibility, confirming this interpretation directly with IPUMS support is worthwhile.
- **Harmonization base year: 2020**, not 2010. Since the tool is public-facing and current (built in 2026), boundaries should match the tracts/block groups people are actually inside of today. 2010 was the older academic convention only because it predated 2020 data's existence — there's no methodological reason to prefer it now.
- **Verify crosswalk chaining before building the pipeline**: confirm whether NHGIS provides a *direct* 2000-to-2020 tract/block-group crosswalk. If only a chained path exists (2000→2010→2020), each interpolation step compounds estimation error — document this explicitly and consider flagging 2000-vintage harmonized values as higher-uncertainty in the final output.
- **Rate/percentage variables are never interpolated directly.** Numerator and denominator counts are interpolated separately using crosswalk weights, then the rate is recomputed after aggregation — this avoids compounding error from averaging pre-computed ratios.
- **Median household income cannot be summed or simply weight-averaged** (medians don't aggregate arithmetically). Population-weighted averaging is used as the standard approximation, and this must be flagged as an approximation in documentation.
- **State and county boundaries are treated as effectively stable** — no full interpolation needed, just a FIPS-code join plus manual patching for the small number of documented changes (e.g., Bedford City, VA merging into Bedford County in 2013; Broomfield, CO becoming its own county in 2001).
- **Language for the R pipeline: R only** (matches supervisor's preference). `tidycensus` for Census API access, `ipumsr` for crosswalk retrieval only. No Python packages needed — crosswalk *application* is a standard weighted join/aggregate (`dplyr`), not something requiring specialized tooling; `nhgisxwalk` (Python) would only be relevant if constructing brand-new crosswalks from scratch, which isn't needed since NHGIS's pre-built crosswalks cover the standard geography pairs required here.
- **Two CMS data sources were evaluated and rejected** as alternatives: CMS's "Census Data to Target the Uninsured" (PUMA-level only, 2011 only, uninsured-subpopulation-only variables) and the CMS Mapping Medicare Disparities SDOH tool (county/tract only, no state/block group, 2020-only, health-outcome-oriented variable set). Neither covers the required geography levels, years, or general-population variable definitions — confirming that a direct Census Bureau API pull is necessary.

---

## LIST 1 — Steps for the User (not delegated to Claude Code)

1. **Register a Census API key** at https://api.census.gov/data/key_signup.html. This is the primary key — all published tabular data is pulled through this API.
2. **Register an IPUMS account and API key** at https://uma.pop.umn.edu/nhgis/registration and https://account.ipums.org/api_keys. Used **only** for crosswalk retrieval, never for published tabular data.
3. **Store both keys as environment variables** (`.Renviron`: `CENSUS_API_KEY=...` and `IPUMS_API_KEY=...`), never hardcoded in scripts. Confirm `.Renviron` is in `.gitignore`.
4. **Maintain a clear provenance separation**: crosswalk files and the IPUMS key stay in an internal-only folder (`/crosswalks/`), never copied into any output folder feeding the public web app.
5. **Lock variable definitions before coding begins**: overcrowding threshold (>1.0 occupants/room), ≤HS education universe (age 25+, GED inclusion decision), poverty universe (individuals vs. families), race categories (alone vs. alone-or-in-combination, and how Hispanic origin overlaps with race).
6. **Confirm harmonization base year = 2020** (per decision above), and geographic scope (nationwide vs. specific states — affects runtime/storage/batching strategy for block-group-level pulls in particular).
7. **Set up project folder structure**:
   ```
   /project-root
     /raw          (raw census.gov extracts, untouched)
     /crosswalks   (IPUMS NHGIS crosswalk files — internal use only, never published)
     /processed    (harmonized output)
     /logs         (sanity check reports, discovery logs)
     /docs         (codebook, variable definitions, README, methodology note)
   ```
8. **Set up version control (git)**, with `.Renviron` and raw data folders excluded via `.gitignore`.
9. **Draft a methodology note** acknowledging NHGIS crosswalks as an internal harmonization tool (not a data source) in project documentation — e.g., "Tract and block-group boundary harmonization across census years was performed using geographic crosswalk files provided by IPUMS NHGIS; all underlying demographic data are sourced directly from the U.S. Census Bureau." Review https://www.nhgis.org/citation-and-use for suggested citation language.
10. **Install R, RStudio, and required packages**: `install.packages(c("tidycensus", "ipumsr", "dplyr", "tidyr", "readr", "sf", "purrr", "stringr"))`.

---

## LIST 2 — Instructions for Claude Code

> Complete and log each step before moving to the next. If any ambiguity arises (an unclear table code, missing crosswalk, or uncertain geography coverage), **stop and report to the user rather than guessing or substituting a workaround without explicit note.**

### Step 0 — Environment check
- Confirm `CENSUS_API_KEY` and `IPUMS_API_KEY` are available via `Sys.getenv()`. Halt and instruct the user to complete List 1 if either is missing.
- Load `tidycensus`, `ipumsr`, `dplyr`, `tidyr`, `readr`, `sf`, `purrr`, `stringr` (install any missing).
- Create the folder structure from List 1, Step 7 if not already present. Enforce that `/crosswalks/` contents never get copied into `/processed/` or any publication-bound folder.

### Step 1 — Dataset/table discovery (census.gov only)
- Identify exact Census API dataset endpoints and variable codes for each of the 12 variables, per year:
  - **2000**: `dec/sf1` (100%-count: population, race, Hispanic origin, age, tenure); `dec/sf3` (long-form: income, poverty, education, employment, occupants per room)
  - **2010**: `dec/sf1` (100%-count); `acs/acs5?year=2010` (2006–2010 ACS 5-year: income, poverty, education, employment, occupants per room)
  - **2020**: `dec/dhc` (100%-count); `acs/acs5?year=2020` (2016–2020 ACS 5-year: income, poverty, education, employment, occupants per room)
- Verify exact variable codes via each dataset's `/variables.json` endpoint — never assume a code carries the same meaning across years without checking.
- Verify geography support per dataset/year via `/geography.json` — block group support in particular is not guaranteed for every dataset/year combination and often requires state-by-state (or state+county) iteration rather than a single nationwide call.
- Log to `/logs/variable_discovery_log.csv`: variable, year, dataset endpoint, variable code(s), confirmed geography levels supported.
- **Do not proceed until all 12 variables have confirmed codes and geography support for all three years**, or until any gaps are explicitly logged rather than silently skipped.

### Step 2 — Pull tabular data via the Census API
- Construct API calls per year/dataset using `get=`, `for=`, `in=` parameters. Batch block-group pulls by state (and county where needed).
- Respect rate limits; batch methodically rather than firing simultaneous requests.
- Save to `/raw/`, named by year/dataset/geography (e.g., `raw/2010_dec_sf1_tract.csv`).
- Log every call (endpoint, parameters, timestamp, row count) to `/logs/extract_log.csv`.

### Step 3 — Verify and retrieve crosswalks (IPUMS NHGIS, internal use only)
- **First, explicitly check whether NHGIS provides a direct 2000-to-2020 crosswalk** (tract and block group level) before assuming a chained 2010 intermediate step is required. Document whichever path is actually available.
- Download the confirmed crosswalk(s) needed to harmonize 2000 and 2010 data onto **2020 boundaries** (the confirmed base year): tract-to-tract and block-group-to-block-group, for whichever direct or chained path was verified in the prior step.
- Save to `/crosswalks/` only, with a comment at the top of every script referencing this folder: *NHGIS crosswalk data — internal harmonization tool only, not for redistribution or publication.*
- Log source, geography pair(s), chaining path used (direct vs. chained), and download date to `/logs/crosswalk_log.csv`.

### Step 4 — Retrieve boundary/land-area files (census.gov only)
- Download Census Bureau Gazetteer Files or TIGER/Line shapefiles for state, county, tract, and block group, for all three years, for `ALAND` (land area / density calculation).
- Save to `/raw/boundaries/`, named by year and geography level.

### Step 5 — SANITY CHECK (mandatory before harmonization begins)
Produce `/logs/sanity_check_report.md` covering:
1. **Coverage matrix**: 12 variables × (2000, 2010, 2020) × (state, county, tract, block group) — mark available / not available / available via proxy. No silent omissions.
2. **Row count checks**: confirm each year/geography extract falls within the expected count range for that year (tract/block group counts differ by census year).
3. **Missing/suppressed value check**: confirm handling of Census/ACS suppression codes and jam values (note: 2020-vintage ACS table-based summary files use **negative numeric jam values**, not "." — do not treat these as valid data).
4. **GEOID format check**: confirm field lengths (2-digit state, 5-digit county, 11-digit tract, 12-digit block group) before any join.
5. **Crosswalk completeness check**: confirm weights per source unit sum to ~1.0; flag anomalies.
6. **Crosswalk coverage check**: confirm every source-year geographic unit in the tabular data has a corresponding crosswalk entry; report unmatched units by count/state.
7. **Present this report to the user and wait for review before proceeding to Step 6.**

### Step 6 — Apply crosswalks, harmonizing onto 2020 boundaries
- **State/county**: direct FIPS join; apply the small set of documented boundary changes (verify Bedford VA, Broomfield CO, and any Alaska borough reorganizations against this specific dataset).
- **Tract/block group**: join source-year data to the crosswalk on source GEOID.
  - **Count variables**: multiply by interpolation weight, group by target (2020) GEOID, sum.
  - **Rate/percentage variables**: interpolate numerator and denominator separately, then recompute the rate after aggregation — never interpolate a pre-computed rate directly.
  - **Median household income**: population-weighted averaging as the standard approximation; flag this explicitly in output documentation as an approximation, since medians do not aggregate arithmetically.
- **2020 data itself requires no interpolation** — it already uses 2020 GEOIDs natively.
- If the 2000→2020 path required chaining through 2010 (per Step 3), flag all 2000-vintage harmonized values in the output with a higher-uncertainty indicator, since compounding two interpolation steps increases estimation error relative to a direct crosswalk.

### Step 7 — Compute derived variables
- Population density = harmonized total population ÷ land area (matched geography/year from Step 4).
- Mean age: compute from age-bracket counts if no direct mean-age table exists.
- Recompute all percentages from harmonized numerator/denominator per Step 6, not from raw pre-harmonization percentages.

### Step 8 — Final QA pass
- Confirm all percentage variables fall within 0–100%; flag any outside this range as an error to investigate, not a value to keep.
- Spot-check a handful of well-documented tracts/counties for directional reasonableness.
- Confirm one row per geographic unit per year, with all 12 variables populated or explicitly marked unavailable per the Step 5 coverage matrix.

### Step 9 — Documentation output
- Produce a data dictionary in `/docs/`: every variable, source table(s) by year, harmonization method (direct join vs. interpolated, and whether 2000 used a direct or chained crosswalk), and known limitations/approximations (median income averaging, any chained-crosswalk uncertainty flag).
- Include the NHGIS crosswalk citation language (List 1, Step 9) in the project README.

---

**General rule throughout:** any ambiguity in table availability, geography coverage, or crosswalk pairing must be flagged in the relevant log, not silently worked around. Every approximation applied must be documented, not assumed.
