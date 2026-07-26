# Step 0: environment check, package load, folder setup

required_packages <- c(
  "tidycensus", "dplyr", "tidyr", "readr", "purrr",
  "stringr", "tigris", "httr", "jsonlite", "sf"
)

missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages) > 0) {
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}

invisible(lapply(required_packages, library, character.only = TRUE))

census_key <- Sys.getenv("CENSUS_API_KEY")
if (identical(census_key, "")) {
  stop(
    "CENSUS_API_KEY not found in environment. ",
    "Add CENSUS_API_KEY=<your key> to .Renviron, restart R, and rerun this script."
  )
}
census_api_key(census_key, overwrite = TRUE, install = FALSE)

# Assumes the working directory is the project root (true when run via the
# .Rproj file, or from the project root with `Rscript scripts/00_setup.R`).
dirs_needed <- c(
  "data/raw",
  "data/raw/boundaries",
  "data/crosswalks",
  "data/processed",
  "logs"
)
for (d in dirs_needed) {
  if (!dir.exists(d)) {
    dir.create(d, recursive = TRUE)
    message("Created: ", d)
  }
}

message("Setup complete. CENSUS_API_KEY loaded, packages ready, folders in place.")
