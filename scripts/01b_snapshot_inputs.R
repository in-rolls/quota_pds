# 01b_snapshot_inputs.R
# Provenance manifest for inputs consumed in place, and vendored-function
# drift check against quota_shaadi.

library(here)
library(dplyr)
library(purrr)
library(digest)

source(here("scripts", "00_config.R"))
source(here("scripts", "00_utils.R"))

repo_head <- function(d) {
    out <- suppressWarnings(system2("git", c("-C", d, "rev-parse", "HEAD"),
                                    stdout = TRUE, stderr = FALSE))
    if (length(out) == 0) NA_character_ else out[1]
}

files <- tibble(
    role = c("ration_cards", "photo_manifest", "forensic_summary",
             "milaan_bridge"),
    path = c(RATION_CARDS_CSV, PHOTO_MANIFEST, FORENSIC_SUMMARY,
             MILAAN_BRIDGE)
)
pins <- jsonlite::read_json(here("data", "sources.json"))
files <- bind_rows(files, tibble(
    role = names(pins),
    path = map_chr(names(pins), source_path),
    provider = map_chr(pins, "provider"),
    ref = map_chr(pins, "ref"),
    sha256 = map_chr(pins, "sha256")
))
stopifnot(all(file.exists(files$path)))

manifest <- files |>
    mutate(
        bytes = file.size(path),
        mtime = as.character(file.mtime(path)),
        md5 = map_chr(path, ~ if (file.size(.x) < 5e8) digest(file = .x)
                              else NA_character_)
    ) |>
    bind_rows(tibble(
        role = c("repo_jaali", "repo_milaan", "repo_quota_shaadi"),
        path = c(JAALI_DIR, MILAAN_DIR, QUOTA_SHAADI_DIR),
        bytes = NA_real_, mtime = NA_character_,
        md5 = c(repo_head(JAALI_DIR), repo_head(MILAAN_DIR),
                repo_head(QUOTA_SHAADI_DIR))
    ))
write_audit(manifest, "01b_input_manifest.csv")

VENDORED <- c("normalize_string", "run_t_tests", "compute_district_chisq",
              "convert_sci_to_decimal", "aggressive_round", "format_coef_stars",
              "format_se_parens", "format_n_comma", "aer_etable")

extract_function_body <- function(lines, fn_name) {
    start <- grep(paste0("^", fn_name, " <- function"), lines)
    if (length(start) == 0) return(NA_character_)
    depth <- 0
    for (i in start[1]:length(lines)) {
        depth <- depth + lengths(regmatches(lines[i], gregexpr("\\{", lines[i]))) -
                 lengths(regmatches(lines[i], gregexpr("\\}", lines[i])))
        if (depth == 0 && i > start[1]) {
            return(paste(gsub("\\s+", " ", trimws(lines[start[1]:i])), collapse = " "))
        }
    }
    NA_character_
}

local_lines <- readLines(here("scripts", "00_utils.R"))
src_lines <- readLines(file.path(QUOTA_SHAADI_DIR, "scripts", "00_utils.R"))
drift <- map_dfr(VENDORED, function(fn) {
    tibble(fn = fn,
           identical = identical(extract_function_body(src_lines, fn),
                                 extract_function_body(local_lines, fn)))
})
write_audit(drift, "01b_vendored_function_drift.csv")
if (!all(drift$identical)) {
    warning("Vendored functions drifted: ",
            paste(drift$fn[!drift$identical], collapse = ", "))
}

message("01b complete")
