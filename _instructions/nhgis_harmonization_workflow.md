# Census Data Harmonization Project — Workflow (Publication Version)

Scope: Total population, population density, % Black/AA, % Hispanic, % White, mean age/% 65+, median household income, % poverty, % ≤HS education, % unemployed, % renters, % overcrowding — at state, county, tract, and block group level — for 2000, 2010, and 2020.

**Data source policy for this version:** All *tabular data that will be published* is pulled from **census.gov / api.census.gov** — the Census Bureau's own distribution, with no redistribution restrictions. **NHGIS geographic crosswalks are used internally only**, purely as a computational tool to reallocate raw Census data across boundary changes. The crosswalk files themselves are never published or redistributed — only the final harmonized Census-sourced values are. Cite NHGIS in the project's methodology documentation as a courtesy/best practice, even though the published dataset itself is Census-sourced. If this project is high-visibility or long-running, consider a one-time email to IPUMS support confirming this internal-use pattern is acceptable under their terms.

---

## LIST 1 — Steps You Must Take Yourself (before handing off to Claude Code)

1. **Register a Census API key** at https://api.census.gov/data/key_signup.html. This is your primary key — all published tabular data will be pulled through this API.
2. **Also register an IPUMS account** at https://uma.pop.umn.edu/nhgis/registration and **generate an IPUMS API key** at https://account.ipums.org/api_keys. This key is used **only** to retrieve geographic crosswalk files for internal harmonization — never to pull tabular data that will be published. Copy it somewhere safe temporarily (you won't be able to view it again after leaving the page — you can always generate a new one if lost).
3. **Store both API keys as environment variables, never hardcoded in a script.**
   - In R: add lines to your `.Renviron` file (open it via `usethis::edit_r_environ()` in R, or edit `~/.Renviron` directly): `CENSUS_API_KEY=your_key_here` and `IPUMS_API_KEY=your_key_here`. Restart R for it to take effect. Your scripts will then read them with `Sys.getenv("CENSUS_API_KEY")` and `Sys.getenv("IPUMS_API_KEY")`.
   - Confirm `.Renviron` is listed in your `.gitignore` if this project is under version control, so neither key is ever committed.
4. **Note the data provenance split for your own records and any legal/compliance review:** all *published* values trace back to census.gov exclusively. The IPUMS key and any downloaded crosswalk files should be stored in a folder clearly marked as internal-only (e.g., `/crosswalks/` — never copied into `/processed/` or any folder destined for the public web app) to keep this separation auditable.
5. **Decide and lock your variable definitions before any code is written.** Specifically:
   - Overcrowding threshold (standard: >1.0 occupants per room)
   - "≤ HS education" — confirm whether GED counts as included, and which age universe (25+ is standard)
   - Poverty universe (individuals vs. families; standard is individuals for whom poverty status is determined)
   - Race categories: "alone" vs. "alone or in combination," and whether Hispanic origin is treated as overlapping with race categories or mutually exclusive
   - Mean age vs. % 65+ — decide which one is primary, since mean age requires computing from age brackets (not a table Census publishes directly)
6. **Decide your base year for boundary harmonization.** Recommended default: 2010 tract/block group boundaries, since NHGIS's crosswalks and most existing academic literature use 2010 as the standard reference year.
7. **Decide your geographic scope.** Nationwide block-group-level data across 3 census years is a very large pull. Decide now whether you need the full U.S. or a specific set of states/counties/metro areas — this materially changes runtime, storage needs, and whether Claude Code should build in state-by-state batching.
8. **Set up your project folder structure** before coding starts, e.g.:
   ```
   /project-root
     /raw          (raw census.gov extracts, untouched)
     /crosswalks   (IPUMS NHGIS crosswalk files — internal use only, never published)
     /processed    (harmonized output)
     /logs         (sanity check reports, metadata logs)
     /docs         (codebook, variable definitions, README)
   ```
9. **Set up version control (git)** for the project if you haven't already, with `.Renviron` and any raw data folders excluded via `.gitignore` (raw census extracts can be large and are also easy to regenerate, so they don't need to be tracked).
10. **Draft a short methodology note acknowledging NHGIS crosswalks as an internal harmonization tool** (not a data source), even though the published dataset is Census-sourced. Review https://www.nhgis.org/citation-and-use for their recommended citation language, and consider including a line like: "Tract and block-group boundary harmonization across census years was performed using geographic crosswalk files provided by IPUMS NHGIS; all underlying demographic data are sourced directly from the U.S. Census Bureau." This documents good-faith acknowledgment without redistributing any NHGIS data.
11. **Install R, RStudio, and required packages** if not already present: `install.packages(c("tidycensus", "ipumsr", "dplyr", "tidyr", "readr", "sf", "purrr", "stringr"))`. `tidycensus` is the recommended R client for the Census API (tabular data + boundary geometry); `ipumsr` is retained solely for crosswalk retrieval.

---

## LIST 2 — Instructions for Claude Code

> Copy this section directly as the task brief. Each step should be completed and logged before moving to the next. If any ambiguity arises (e.g., a table code cannot be confidently identified, or expected data is missing), **stop and report to the user rather than guessing or substituting an alternative table.**

### Step 0 — Environment check
- Confirm `CENSUS_API_KEY` is available via `Sys.getenv("CENSUS_API_KEY")`. If empty, halt and instruct the user to complete List 1, Step 1 before proceeding.
- Confirm `IPUMS_API_KEY` is available via `Sys.getenv("IPUMS_API_KEY")` (needed for crosswalks only, Step 3 below). If empty, halt and instruct the user to complete List 1, Step 2.
- Load required packages: `tidycensus` or direct `httr`/`jsonlite` calls to `api.census.gov` for tabular data; `ipumsr` for crosswalk retrieval only; plus `dplyr`, `tidyr`, `readr`, `sf`, `purrr`, `stringr`. Install any that are missing.
- Create the folder structure from List 1, Step 8 if it does not already exist. **Enforce a hard separation**: anything sourced from IPUMS/NHGIS (crosswalk files only) lives exclusively in `/crosswalks/` and must never be copied into `/processed/` or any output folder feeding the public web app.

### Step 1 — Dataset/table discovery (census.gov only, do this before pulling any data)
- Identify the exact Census API dataset endpoints and table/variable IDs needed for each variable, separately for each of the three years:
  - **2000**: `dec/sf1` (100%-count: population, race, Hispanic origin, age, tenure) and `dec/sf3` (sample/long-form: income, poverty, education, employment, occupants per room)
  - **2010**: `dec/sf1` (100%-count variables) and `acs/acs5?year=2010` (2006–2010 5-Year ACS: income, poverty, education, employment, occupants per room)
  - **2020**: `dec/dhc` (100%-count variables) and `acs/acs5?year=2020` (2016–2020 5-Year ACS: income, poverty, education, employment, occupants per room)
- For each dataset, query its `/variables.json` endpoint (e.g., `https://api.census.gov/data/2020/dec/dhc/variables.json`) to confirm the exact variable codes — do not guess or reuse a variable code from one year in another year without verifying it still means the same thing.
- For each of the 12 project variables, record: variable name, year, dataset endpoint, variable code(s), and geographic levels supported by that dataset (check the dataset's `/geography.json` endpoint, since not every dataset supports `block group` as a `for=` parameter in every year). Save this as `/logs/variable_discovery_log.csv`.
- **Do not proceed to Step 2 until every one of the 12 variables has a confirmed variable code and confirmed geography support for all three years.** If block group is not queryable directly for a given dataset/year, note it explicitly (see Step 2 note on block group workarounds).

### Step 2 — Pull tabular data via the Census API
- For each year/dataset combination identified in Step 1, construct API calls using `get=` (variable codes), `for=` (target geography, e.g. `tract:*`, `block group:*`), and `in=` (parent geography, e.g. `state:XX+county:YYY`) parameters.
- **Block group note**: the decennial and ACS APIs generally require iterating state-by-state (and sometimes county-by-county) for block-group-level pulls rather than a single nationwide call — build in this looping/batching rather than assuming one call returns all block groups nationally.
- Respect API rate limits; with a registered key, batch requests methodically (e.g., loop by state) rather than firing all requests simultaneously.
- Save each year/dataset/geography-level pull to `/raw/`, named clearly (e.g., `raw/2010_dec_sf1_tract.csv`, `raw/2010_acs5_blockgroup.csv`).
- Log every API call made (endpoint, parameters, timestamp, row count returned) to `/logs/extract_log.csv` for reproducibility.

### Step 3 — Retrieve crosswalks (IPUMS NHGIS — internal harmonization use only)
- Using `ipumsr`, identify and download the NHGIS geographic crosswalk files needed for:
  - Tract-to-tract: 2000 tracts → 2010 tracts, and 2010 tracts → 2020 tracts (or 2020 → 2010, depending on which direction NHGIS provides for your chosen base year)
  - Block-group-to-block-group: same year pairs
- Confirm whether NHGIS provides a direct 2000-to-2010 crosswalk at block group level, or whether this requires going through an intermediate geography (e.g., block-level crosswalks aggregated up). If only an indirect path exists, document the exact chain used.
- Save crosswalk files to `/crosswalks/` **only** — this folder is internal-use and must never be merged into any output destined for publication. Log source, geography pair, and download date to `/logs/crosswalk_log.csv`.
- Add a comment at the top of every script that touches `/crosswalks/` reiterating: *NHGIS crosswalk data — internal harmonization tool only, not for redistribution or publication.*

### Step 4 — Retrieve boundary/land-area files (census.gov only)
- Download Census Bureau **Gazetteer Files** (simplest, plain text with `ALAND`) or **TIGER/Line shapefiles** for state, county, tract, and block group, for each of the three census years, to obtain land area for population density calculations.
- Source: https://www.census.gov/geographies/reference-files/time-series/geo/gazetteer-files.html (select the correct vintage year for each geography).
- Save to `/raw/boundaries/`, named by year and geography level.

### Step 5 — SANITY CHECK (mandatory before any harmonization or analysis begins)
Produce a written report at `/logs/sanity_check_report.md` covering:

1. **Coverage matrix**: a table with rows = each of the 12 variables, columns = (2000, 2010, 2020) × (state, county, tract, block group), and cell values = "available" / "not available" / "available via proxy table [name]". Flag every "not available" cell explicitly rather than silently dropping the variable.
2. **Row count checks**: for each year/geography level, confirm the number of rows returned is in the expected range (e.g., ~3,143 counties, ~73,000 tracts nationally as of 2010 — adjust expected counts per year since tract/block group counts change over time). Flag any extract with a suspiciously low or high row count.
3. **Missing/suppressed value check**: scan for Census/ACS suppression codes and "jam values" (note: ACS summary files from 2020 onward use the newer table-based format with **negative numeric jam values** instead of the older "." character — confirm which format each downloaded file uses, and do not treat negative jam values as valid numeric data).
4. **GEOID format check**: confirm GEOID field lengths are consistent with expectations (2-digit state, 5-digit county, 11-digit tract, 12-digit block group) before any join is attempted. Flag any inconsistency.
5. **Crosswalk completeness check**: for each crosswalk file, confirm weights for each source unit sum to approximately 1.0 (within reasonable rounding tolerance). Flag any source units with missing or clearly incorrect weight totals.
6. **Crosswalk coverage check**: confirm every source-year geographic unit present in your Step 2 tabular data has a corresponding entry in the Step 3 crosswalk file. Report any unmatched units by count and (if feasible) by state, so the user can assess whether the gap is material.
7. Present this full report to the user before proceeding to Step 6. **Do not begin harmonization until the user has reviewed the sanity check report**, since gaps identified here may change the analysis plan (e.g., a variable unavailable at block group level might need to be dropped or handled differently for that geography level only).

### Step 6 — Apply crosswalks to harmonize tract and block group data
- For **state and county**: join years directly on FIPS code. Apply the small set of known documented boundary changes (e.g., Bedford City, VA absorbed into Bedford County in 2013; Broomfield, CO became its own county in 2001) — cross-reference the Census Bureau's county change reference documentation and confirm whether any affected counties appear in this dataset before finalizing.
- For **tract and block group**: 
  - Join each year's raw data to the corresponding crosswalk file on the source geography ID.
  - **For count variables** (total population, race counts, etc.): multiply by the interpolation weight, then group by target geography ID and sum.
  - **For rate/percentage variables** (poverty rate, unemployment rate, median household income, % renters, overcrowding): do **not** interpolate the rate directly. Interpolate the numerator and denominator counts separately using the weighting method above, then recompute the rate from the harmonized totals. This avoids compounding error from averaging pre-computed ratios.
  - Median household income specifically cannot be summed or simply weight-averaged across areas in a statistically rigorous way (medians don't aggregate arithmetically) — use population-weighted averaging as the standard approximation, and flag this as an approximation in the documentation.

### Step 7 — Compute derived variables
- Population density = total population ÷ land area (from Step 4 boundary files, matched to the same harmonized geography and year).
- Mean age: compute from age-bracket counts if a direct mean age table is unavailable (standard census tables report age in brackets, not a direct mean).
- All percentage variables: recompute from harmonized numerator/denominator per Step 6, not from raw pre-harmonization percentages.

### Step 8 — Final QA pass
- Check that all percentage variables fall within a valid range (0–100%) after harmonization; flag any that fall outside this range as an error requiring investigation, not a data point to keep.
- Spot-check a handful of tracts/block groups/counties against known values (e.g., a well-documented urban county) to confirm harmonized results are directionally reasonable.
- Confirm the final panel has one row per geographic unit per year, with all 12 variables populated (or explicitly marked as unavailable per the Step 5 coverage matrix) — no silent gaps.

### Step 9 — Documentation output
- Produce a final data dictionary in `/docs/` listing every variable, its source table(s) by year, its harmonization method (direct join vs. interpolated), and any known limitations or approximations (e.g., the median income caveat from Step 6).
- Include the NHGIS citation language from List 1, Step 10 in the project README.

---

**General rule for Claude Code throughout:** if at any point a table, geography level, or crosswalk pairing is not clearly available or the correct approach is ambiguous, stop and flag it in the relevant log rather than substituting a workaround or approximation without explicit note. Every approximation made (e.g., income averaging in Step 6) must be documented, not silently applied.
