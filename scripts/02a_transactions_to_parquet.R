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

    # Bill_Date format: '12 Mar 2018 08:25:50:843' — parse the date prefix.
    # Quantities mix units (grain in kg, kerosene in liters); qty is kept
    # only for grain rows (गेहूँ wheat, चावल rice), months count all activity.
    # Streamed to parquet first: materializing 200M+ rows as a temp table
    # exhausts memory.
    bills_pq <- here("data", "transactions", "bills.parquet")
    if (file.exists(bills_pq) && file.size(bills_pq) > 1e9) {
        message("bills.parquet already present, skipping csv scan")
    } else dbExecute(con, sprintf("
        COPY (
            SELECT
                lpad(CAST(Ration_Card_Number AS VARCHAR), 12, '0') AS card_no,
                CAST(try_strptime(substr(Bill_Date, 1, 11), '%%d %%b %%Y') AS DATE)
                    AS bill_date,
                CASE WHEN Type_of_Food IN ('गेहूँ', 'गेहूं', 'चावल')
                     THEN try_cast(regexp_extract(Quantity_of_Food,
                                                  '[0-9]+\\.?[0-9]*') AS DOUBLE)
                END AS qty,
                Type_of_Food AS food_type
            FROM read_csv(%s, header = true, all_varchar = true,
                          ignore_errors = true)
        ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
        dbQuoteString(con, src), dbQuoteString(con, bills_pq)))

    food_types <- dbGetQuery(con, sprintf(
        "SELECT food_type, count(*) AS n FROM read_parquet(%s)
         GROUP BY 1 ORDER BY n DESC LIMIT 20", dbQuoteString(con, bills_pq)))
    write_audit(food_types, "02a_food_types.csv")

    month_series <- dbGetQuery(con, sprintf("
        SELECT date_trunc('month', bill_date) AS month,
               count(*) AS n_bills, sum(qty) AS total_qty,
               count(DISTINCT card_no) AS n_cards
        FROM read_parquet(%s) WHERE bill_date IS NOT NULL
        GROUP BY 1 ORDER BY 1", dbQuoteString(con, bills_pq)))
    write_audit(month_series, "02a_month_series.csv")

    max_month <- as.Date(dbGetQuery(con, sprintf("
        SELECT max(date_trunc('month', bill_date)) AS m
        FROM read_parquet(%s)
        WHERE bill_date IS NOT NULL AND bill_date <= current_date",
        dbQuoteString(con, bills_pq)))$m)

    last12_start <- seq(max_month, length.out = 2, by = "-11 months")[2]

    # Two-stage aggregation: card x month first, then card. Avoids
    # count(DISTINCT) over 200M rows x 16M groups, which exhausts the spill
    # budget.
    card_month_pq <- here("data", "transactions", "card_month.parquet")
    dbExecute(con, sprintf("
        COPY (
            SELECT card_no, date_trunc('month', bill_date) AS month,
                   count(*) AS n_bills, sum(qty) AS qty
            FROM read_parquet(%s)
            WHERE bill_date IS NOT NULL
            GROUP BY 1, 2
        ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
        dbQuoteString(con, bills_pq), dbQuoteString(con, card_month_pq)))

    dbExecute(con, sprintf("
        COPY (
            SELECT card_no,
                   sum(n_bills) AS n_bills,
                   count(*) AS n_months_ever,
                   count(*) FILTER (month >= DATE '%s') AS n_months_last12,
                   count(*) FILTER (month >= DATE '2019-01-01'
                                    AND month < DATE '2020-01-01')
                       AS n_months_2019,
                   sum(qty) AS total_qty,
                   sum(qty) FILTER (month >= DATE '%s') AS qty_last12,
                   min(month) AS first_bill,
                   max(month) AS last_bill
            FROM read_parquet(%s)
            GROUP BY card_no
        ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
        last12_start, last12_start, dbQuoteString(con, card_month_pq),
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

# Ensure the card-level file carries qty_2019 (added after the first release);
# rebuild from card_month.parquet, never from the raw csv
offtake_pq <- here("data", "transactions", "card_offtake.parquet")
card_month_pq <- here("data", "transactions", "card_month.parquet")
have_cols <- names(arrow::open_dataset(offtake_pq)$schema)
if (!"qty_2019" %in% have_cols) {
    message("Adding qty_2019 to card_offtake")
    max_month <- as.Date(dbGetQuery(con, sprintf(
        "SELECT max(month) AS m FROM read_parquet(%s) WHERE month <= current_date",
        dbQuoteString(con, card_month_pq)))$m)
    last12_start <- seq(max_month, length.out = 2, by = "-11 months")[2]
    dbExecute(con, sprintf("
        COPY (
            SELECT card_no,
                   sum(n_bills) AS n_bills,
                   count(*) AS n_months_ever,
                   count(*) FILTER (month >= DATE '%s') AS n_months_last12,
                   count(*) FILTER (month >= DATE '2019-01-01'
                                    AND month < DATE '2020-01-01')
                       AS n_months_2019,
                   sum(qty) AS total_qty,
                   sum(qty) FILTER (month >= DATE '%s') AS qty_last12,
                   sum(qty) FILTER (month >= DATE '2019-01-01'
                                    AND month < DATE '2020-01-01') AS qty_2019,
                   min(month) AS first_bill,
                   max(month) AS last_bill
            FROM read_parquet(%s)
            GROUP BY card_no
        ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
        last12_start, last12_start, dbQuoteString(con, card_month_pq),
        dbQuoteString(con, offtake_pq)))
}

message("02a complete")
