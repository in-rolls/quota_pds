library(testthat)
source(here::here("scripts", "00_sources.R"))

test_that("source acquisition checks downloaded bytes and ignores wrong sibling revisions", {
    root <- tempfile("pds-source-")
    dir.create(file.path(root, "project", "data"), recursive = TRUE)
    withr::defer(unlink(root, recursive = TRUE))
    withr::local_envvar(INDIA_DATA_HOME = file.path(root, "cache"))
    local_mocked_bindings(here = function(...) file.path(root, "project", ...), .package = "here")
    pinned <- charToRaw("pinned source\n")
    spec <- list(provider = "example", ref = paste(rep("a", 40), collapse = ""),
                 path = "input.csv", sha256 = digest::digest(pinned, "sha256", serialize = FALSE))
    jsonlite::write_json(list(example = spec), file.path(root, "project", "data", "sources.json"), auto_unbox = TRUE)
    requested <- character()
    local_mocked_bindings(download.file = function(url, destfile, ...) {
        requested <<- c(requested, url)
        writeBin(pinned, destfile)
        0L
    }, .package = "utils")
    cold <- source_path("example")
    expect_identical(readBin(cold, "raw", n = 100), pinned)
    expect_identical(requested, paste("https://raw.githubusercontent.com/in-rolls/example",
                                      spec$ref, "input.csv", sep = "/"))
    unlink(cold)
    dir.create(file.path(root, "example"))
    sibling <- file.path(root, "example", "input.csv")
    writeLines("different revision", sibling)
    expect_identical(readBin(source_path("example"), "raw", n = 100), pinned)
    expect_identical(readLines(sibling), "different revision")
    unlink(cold)
    pinned <- charToRaw("corrupt source")
    expect_error(source_path("example"), "Source checksum mismatch")
    expect_false(file.exists(cold))
})

test_that("canonical histories and geographic joins preserve source rows", {
    panel <- arrow::read_parquet(source_path("raj_panel"))
    linked <- treatment_panel()
    expect_identical(linked[names(panel)], panel)
    expect_equal(nrow(linked), 5334L)
    expect_equal(sum(!is.na(linked$lgd_gp_code)), 4728L)
    expect_false(anyDuplicated(arrow::read_parquet(source_path("raj_lgd_bridge"))$match_key) > 0)
    census <- arrow::read_parquet(source_path("raj_census")) |>
        dplyr::filter(!is.na(lgd_gp_code)) |>
        dplyr::select(lgd_gp_code, dplyr::starts_with("pc01_")) |>
        dplyr::distinct()
    expected <- census[match(linked$lgd_gp_code, census$lgd_gp_code), setdiff(names(census), "lgd_gp_code")]
    expect_identical(linked[names(expected)], expected)
})

test_that("study treatment rows match the canonical elected and reserved outcomes", {
    panel <- treatment_panel() |>
        dplyr::filter(!is.na(lgd_gp_code)) |>
        dplyr::arrange(lgd_gp_code, match_distance) |>
        dplyr::distinct(lgd_gp_code, .keep_all = TRUE)
    treatment <- arrow::read_parquet(here::here("data", "outcomes", "gp_treatment.parquet"))
    common <- setdiff(intersect(names(treatment), names(panel)), "winner_female_2020")
    expect_identical(treatment[common], panel[common])
    expect_identical(treatment$winner_female_2020, panel$female_winner_2020)
    expect_false(anyDuplicated(treatment$lgd_gp_code) > 0)
})
