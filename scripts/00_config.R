# 00_config.R
# Central configuration for pds_pradhan

library(here)

JAALI_DIR <- Sys.getenv("JAALI_DIR",
    unset = normalizePath(file.path(here(), "..", "jaali"), mustWork = FALSE))
MILAAN_DIR <- Sys.getenv("MILAAN_DIR",
    unset = normalizePath(file.path(here(), "..", "milaan_raj"), mustWork = FALSE))
QUOTA_SHAADI_DIR <- Sys.getenv("QUOTA_SHAADI_DIR",
    unset = normalizePath(file.path(here(), "..", "quota_shaadi"), mustWork = FALSE))

RATION_CARDS_CSV <- file.path(JAALI_DIR, "data", "rural_rationcard.csv.gz")
PHOTO_MANIFEST <- file.path(JAALI_DIR, "out_full", "manifest.parquet")
FORENSIC_SUMMARY <- file.path(JAALI_DIR, "out_full", "forensic_summary.csv")

MILAAN_BRIDGE <- file.path(MILAAN_DIR, "data", "ration", "panchayat_gp_bridge.parquet")
MILAAN_CARDS <- file.path(MILAAN_DIR, "data", "ration", "cards")
MILAAN_MEMBERS_HH <- file.path(MILAAN_DIR, "data", "households", "ration")
MILAAN_PERSON_LINKS <- file.path(MILAAN_DIR, "data", "links", "persons")
MILAAN_ROLLS_HH <- file.path(MILAAN_DIR, "data", "households", "rolls")

source(here("scripts", "00_sources.R"))

DATAVERSE_SERVER <- "dataverse.harvard.edu"
RATION_DOI <- "doi:10.7910/DVN/FIFZEX"
TRANSACTION_PARTS <- paste0("rural_rationcardtransaction.csv.gz.part",
                            c("aa", "ab", "ac", "ad", "ae"))

# Analysis parameters
POOR_CARD_TYPES <- c("BPL", "SB", "AN")
GHOST_AGE_MIN <- 25L
GHOST_AGE_MAX <- 70L
BENCHMARK_AGE_MIN <- 30L
BENCHMARK_AGE_MAX <- 60L
DEAD_SOUL_AGE <- 85L
REGULAR_MONTHS_MIN <- 10L
PHOTO_REUSE_MIN_NAMES <- 3L
WINSOR_P <- 0.99
MIN_CARDS_PER_GP <- 50L

DUCKDB_MEMORY_LIMIT <- Sys.getenv("DUCKDB_MEMORY_LIMIT", unset = "16GB")
DUCKDB_THREADS <- as.integer(Sys.getenv("DUCKDB_THREADS", unset = "8"))

NOTES_SIGNIF <- "$^{***}$p$<$0.01; $^{**}$p$<$0.05; $^{*}$p$<$0.1."
NOTES_ITT <- paste0(
    NOTES_SIGNIF,
    " Treatment is reservation of the GP pradhan seat for a woman in the 2020",
    " cycle (in office at the 2021 PDS snapshot). All specifications include",
    " (district, samiti) fixed effects and caste-reservation stratum controls;",
    " standard errors clustered by samiti. Outcomes standardized."
)
NOTES_OPEN <- paste0(
    NOTES_SIGNIF,
    " Sample restricted to GPs with open (non-reserved) 2020 seats; the",
    " coefficient on a woman winning is identified conditional on observables",
    " (census covariates, full reservation history, seat caste category) and",
    " is not experimental. Standard errors clustered by samiti."
)
