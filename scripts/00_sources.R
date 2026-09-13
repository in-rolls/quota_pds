source_path <- function(name) {
    spec <- jsonlite::read_json(here::here("data", "sources.json"))[[name]]
    if (is.null(spec)) stop("Unpinned source: ", name)
    cache <- path.expand(Sys.getenv("INDIA_DATA_HOME", unset = "~/data"))
    path <- file.path(cache, spec$provider, spec$ref, spec$path)
    if (!file.exists(path)) {
        dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
        temporary <- tempfile(tmpdir = dirname(path))
        on.exit(unlink(temporary), add = TRUE)
        sibling <- here::here("..", spec$provider, spec$path)
        if (file.exists(sibling) && identical(
            digest::digest(sibling, algo = "sha256", file = TRUE), spec$sha256
        )) {
            if (!file.copy(sibling, temporary)) stop("Cannot cache ", sibling)
        } else {
            url <- paste("https://raw.githubusercontent.com/in-rolls",
                         spec$provider, spec$ref, spec$path, sep = "/")
            utils::download.file(url, temporary, mode = "wb", quiet = TRUE)
        }
        if (!identical(digest::digest(temporary, algo = "sha256", file = TRUE), spec$sha256)) {
            stop("Source checksum mismatch: ", name)
        }
        if (!file.rename(temporary, path)) stop("Cannot save verified source: ", path)
    }
    if (!identical(digest::digest(path, algo = "sha256", file = TRUE), spec$sha256)) {
        stop("Cached source checksum mismatch: ", name)
    }
    path
}


treatment_panel <- function() {
    panel <- arrow::read_parquet(source_path("raj_panel"))
    geography <- arrow::read_parquet(source_path("raj_lgd_bridge"))
    covariates <- arrow::read_parquet(source_path("raj_census")) |>
        dplyr::filter(!is.na(.data$lgd_gp_code)) |>
        dplyr::select(lgd_gp_code, dplyr::starts_with("pc01_")) |>
        dplyr::distinct()
    stopifnot(!anyDuplicated(covariates$lgd_gp_code))
    panel |>
        dplyr::left_join(geography, by = "match_key", relationship = "many-to-one") |>
        dplyr::left_join(covariates, by = "lgd_gp_code", relationship = "many-to-one")
}
