# 01a_download_transactions.R
# Download and assemble the bill-level transaction table (5 parts, 9.5 GB).
# Raw parts are deleted after assembly; the assembled gz is deleted by 02a
# after parquet ingest, so skip-if-ingested comes first.

library(here)
library(httr2)
library(dplyr)
library(purrr)

source(here("scripts", "00_config.R"))
source(here("scripts", "00_utils.R"))

raw_dir <- here("data", "raw")
target <- file.path(raw_dir, "rural_rationcardtransaction.csv.gz")
token <- Sys.getenv("DATAVERSE_KEY", unset = Sys.getenv("DATAVERSE_API_TOKEN"))

if (file.exists(here("data", "transactions", ".ingest_complete"))) {
    message("Transactions already ingested, skipping download")
} else {
    req <- request(sprintf("https://%s/api/datasets/:persistentId/versions/:latest/files",
                           DATAVERSE_SERVER)) |>
        req_url_query(persistentId = RATION_DOI)
    if (nzchar(token)) req <- req |> req_headers(`X-Dataverse-key` = token)
    resp <- req |> req_retry(max_tries = 5) |> req_perform() |> resp_body_json()
    stopifnot(resp$status == "OK")

    file_index <- map_dfr(resp$data, function(f) {
        tibble(label = f$label, id = f$dataFile$id,
               bytes_expected = f$dataFile$filesize)
    })
    targets <- file_index |> filter(label %in% TRANSACTION_PARTS)
    stopifnot(nrow(targets) == length(TRANSACTION_PARTS))
    total_expected <- sum(targets$bytes_expected)

    if (file.exists(target) && file.size(target) == total_expected) {
        message("Assembled archive already present")
    } else {
        for (i in seq_len(nrow(targets))) {
            dest <- file.path(raw_dir, targets$label[i])
            if (file.exists(dest) && file.size(dest) == targets$bytes_expected[i]) next
            message("Downloading ", targets$label[i])
            h <- curl::new_handle(low_speed_limit = 1000, low_speed_time = 120)
            if (nzchar(token)) curl::handle_setheaders(h, "X-Dataverse-key" = token)
            tmp <- paste0(dest, ".part")
            curl::curl_download(
                sprintf("https://%s/api/access/datafile/%s?format=original",
                        DATAVERSE_SERVER, targets$id[i]),
                tmp, handle = h, quiet = TRUE, mode = "wb")
            stopifnot(file.size(tmp) == targets$bytes_expected[i])
            file.rename(tmp, dest)
        }
        if (file.exists(target)) file.remove(target)
        ok <- file.append(target, file.path(raw_dir, TRANSACTION_PARTS))
        stopifnot(all(ok), file.size(target) == total_expected)
        file.remove(file.path(raw_dir, TRANSACTION_PARTS))
    }

    con_gz <- gzfile(target, "r")
    header <- readLines(con_gz, n = 1)
    close(con_gz)
    write_audit(tibble(bytes = file.size(target), header = header),
                "01a_transactions_manifest.csv")
}

message("01a complete")
