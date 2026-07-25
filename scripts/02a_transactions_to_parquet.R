# 02a_transactions_to_parquet.R
# Collapse the bill-level table straight to card-level offtake features (the
# analysis never needs individual bills): months active, bills, quantities,
# plus a state-level month series for the COVID/PMGKAY audit.

library(here)
library(dplyr)
library(DBI)

source(here("scripts", "00_config.R"))
source(here("scripts", "00_utils.R"))

con <- get_duck()
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

src <- here("data", "raw", "rural_rationcardtransaction.csv.gz")
done_flag <- here("data", "transactions", ".ingest_complete")

if (!file.exists(done_flag)) {
    stopifnot(file.exists(src))

    dbExecute(con, sprintf("
        CREATE OR REPLACE TEMP TABLE tx AS
        SELECT
            lpad(CAST(Ration_Card_Number AS VARCHAR), 12, '0') AS card_no,
            coalesce(try_strptime(Bill_Date, '%%d/%%m/%%Y'),
                     try_strptime(Bill_Date, '%%d-%%m-%%Y'),
                     try_strptime(Bill_Date, '%%Y-%%m-%%d')) AS bill_date,
            try_cast(regexp_extract(Quantity_of_Food, '[0-9]+\\.?[0-9]*') AS DOUBLE)
                AS qty,
            Type_of_Food AS food_type
        FROM read_csv(%s, header = true, all_varchar = true,
                      ignore_errors = true)",
        dbQuoteString(con, src)))

    month_series <- dbGetQuery(con, "
        SELECT date_trunc('month', bill_date) AS month,
               count(*) AS n_bills, sum(qty) AS total_qty,
               count(DISTINCT card_no) AS n_cards
        FROM tx WHERE bill_date IS NOT NULL
        GROUP BY 1 ORDER BY 1")
    write_audit(month_series, "02a_month_series.csv")

    max_month <- dbGetQuery(con, "
        SELECT max(date_trunc('month', bill_date)) AS m
        FROM tx WHERE bill_date IS NOT NULL AND bill_date <= current_date")$m

    dbExecute(con, sprintf("
        COPY (
            SELECT card_no,
                   count(*) AS n_bills,
                   count(DISTINCT date_trunc('month', bill_date)) AS n_months_ever,
                   count(DISTINCT date_trunc('month', bill_date))
                       FILTER (bill_date >= DATE '%s' - INTERVAL 11 MONTH)
                       AS n_months_last12,
                   count(DISTINCT date_trunc('month', bill_date))
                       FILTER (bill_date >= DATE '2019-01-01'
                               AND bill_date < DATE '2020-01-01')
                       AS n_months_2019,
                   sum(qty) AS total_qty,
                   sum(qty) FILTER (bill_date >= DATE '%s' - INTERVAL 11 MONTH)
                       AS qty_last12,
                   min(bill_date) AS first_bill,
                   max(bill_date) AS last_bill
            FROM tx
            WHERE bill_date IS NOT NULL
            GROUP BY card_no
        ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
        max_month, max_month,
        dbQuoteString(con, here("data", "transactions", "card_offtake.parquet"))))

    stats <- dbGetQuery(con, sprintf("
        SELECT count(*) AS n_cards_with_tx,
               avg(n_months_last12) AS mean_months_last12,
               avg(n_bills) AS mean_bills,
               avg(CASE WHEN n_months_last12 >= %d THEN 1.0 ELSE 0 END)
                   AS share_regular
        FROM read_parquet(%s)",
        REGULAR_MONTHS_MIN,
        dbQuoteString(con, here("data", "transactions", "card_offtake.parquet"))))
    write_audit(stats |> mutate(max_month = as.character(max_month)),
                "02a_offtake_stats.csv")

    file.create(done_flag)
    file.remove(src)
    message("Raw transaction archive deleted after ingest")
} else {
    message("Already ingested, skipping")
}

message("02a complete")
