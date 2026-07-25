# 02b_card_flags.R
# Per-card leakage flags, GP-attached:
#   dup_identity  — (applicant, father, village) appears on >1 card
#   photo_reuse   — card photo md5 shared across cards with >= 3 distinct names
#   ghost_share   — share of the card's adults (25-70 in 2021) with no milaan
#                   elector counterpart; benchmark_absent likewise for male
#                   heads 30-60 (nets out linkage recall at the GP level)
#   dead_soul     — any member aged >= 85
#   poor          — card type in {BPL, SB, AN}

library(here)
library(dplyr)
library(DBI)

source(here("scripts", "00_config.R"))
source(here("scripts", "00_utils.R"))

con <- get_duck()
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

cards_glob <- file.path(MILAAN_CARDS, "*", "*.parquet")
members_glob <- file.path(MILAAN_MEMBERS_HH, "*", "*.parquet")
links_glob <- file.path(MILAAN_PERSON_LINKS, "*.parquet")

dbExecute(con, sprintf("CREATE OR REPLACE TEMP TABLE bridge AS
    SELECT panchayat_code, block_code, district_code, lgd_gp_code
    FROM read_parquet(%s)", dbQuoteString(con, MILAAN_BRIDGE)))

# Duplicate identities over the FULL card set (fire2 logic in duckdb)
dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE dup AS
    SELECT applicant_dev, father_dev, village_code
    FROM read_parquet(%s, hive_partitioning = true)
    WHERE applicant_dev != '' AND father_dev != ''
    GROUP BY 1, 2, 3
    HAVING count(*) > 1", dbQuoteString(con, cards_glob)))

# Photo reuse: md5 shared by cards carrying >= PHOTO_REUSE_MIN_NAMES names.
# Zero-byte images all share the empty-file md5 (jaali's 42k-card exact_1
# cluster) and are excluded — they are scraping failures, not shared photos.
dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE photo AS
    WITH m AS (
        SELECT lpad(card_id, 12, '0') AS card_no, md5
        FROM read_parquet(%s)
        WHERE size > 0
    ), j AS (
        SELECT m.md5, m.card_no, c.applicant_dev
        FROM m JOIN read_parquet(%s, hive_partitioning = true) c USING (card_no)
    ), bad AS (
        SELECT md5 FROM j GROUP BY md5
        HAVING count(DISTINCT applicant_dev) >= %d
    )
    SELECT DISTINCT j.card_no FROM j JOIN bad USING (md5)",
    dbQuoteString(con, PHOTO_MANIFEST), dbQuoteString(con, cards_glob),
    PHOTO_REUSE_MIN_NAMES))

# Ghost and benchmark absence from milaan members + person links
dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE linked AS
    SELECT DISTINCT card_no, member_no FROM read_parquet(%s)",
    dbQuoteString(con, links_glob)))

dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE ghost AS
    SELECT m.card_no,
           count(*) FILTER (m.age_2021 BETWEEN %d AND %d) AS n_ghost_pool,
           count(*) FILTER (m.age_2021 BETWEEN %d AND %d AND l.card_no IS NULL)
               AS n_ghost_absent,
           count(*) FILTER (m.relationship_dev = 'स्वयं'
                            AND m.age_2021 BETWEEN %d AND %d) AS n_bench_pool,
           count(*) FILTER (m.relationship_dev = 'स्वयं'
                            AND m.age_2021 BETWEEN %d AND %d
                            AND l.card_no IS NULL) AS n_bench_absent,
           max(CASE WHEN m.age_2021 >= %d THEN 1 ELSE 0 END) AS dead_soul
    FROM read_parquet(%s, hive_partitioning = true) m
    LEFT JOIN linked l ON m.card_no = l.card_no AND m.member_no = l.member_no
    GROUP BY m.card_no",
    GHOST_AGE_MIN, GHOST_AGE_MAX, GHOST_AGE_MIN, GHOST_AGE_MAX,
    BENCHMARK_AGE_MIN, BENCHMARK_AGE_MAX,
    BENCHMARK_AGE_MIN, BENCHMARK_AGE_MAX,
    DEAD_SOUL_AGE,
    dbQuoteString(con, members_glob)))

dbExecute(con, sprintf("
    COPY (
        SELECT c.card_no, c.card_type_raw,
               c.card_type_raw IN ('BPL', 'SB', 'AN') AS poor,
               b.lgd_gp_code,
               (d.applicant_dev IS NOT NULL) AS dup_identity,
               (p.card_no IS NOT NULL) AS photo_reuse,
               g.n_ghost_pool, g.n_ghost_absent,
               g.n_bench_pool, g.n_bench_absent,
               g.dead_soul,
               t.n_months_last12, t.n_months_2019, t.qty_last12, t.n_bills
        FROM read_parquet(%s, hive_partitioning = true) c
        JOIN bridge b ON c.panchayat_code = b.panchayat_code
                     AND c.block_code = b.block_code
                     AND c.district_code = b.district_code
        LEFT JOIN dup d ON c.applicant_dev = d.applicant_dev
                       AND c.father_dev = d.father_dev
                       AND c.village_code = d.village_code
        LEFT JOIN photo p ON c.card_no = p.card_no
        LEFT JOIN ghost g ON c.card_no = g.card_no
        LEFT JOIN read_parquet(%s) t ON c.card_no = t.card_no
    ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
    dbQuoteString(con, cards_glob),
    dbQuoteString(con, here("data", "transactions", "card_offtake.parquet")),
    dbQuoteString(con, here("data", "cards", "card_flags.parquet"))))

flags <- dbGetQuery(con, sprintf("
    SELECT count(*) AS n_cards,
           avg(CASE WHEN dup_identity THEN 1.0 ELSE 0 END) AS share_dup,
           avg(CASE WHEN photo_reuse THEN 1.0 ELSE 0 END) AS share_photo_reuse,
           avg(CASE WHEN dead_soul = 1 THEN 1.0 ELSE 0 END) AS share_dead_soul,
           avg(CASE WHEN poor THEN 1.0 ELSE 0 END) AS share_poor,
           avg(CASE WHEN n_bills IS NOT NULL THEN 1.0 ELSE 0 END) AS share_with_tx
    FROM read_parquet(%s)",
    dbQuoteString(con, here("data", "cards", "card_flags.parquet"))))
write_audit(flags, "02b_card_flag_stats.csv")

message(sprintf(
    "02b complete: %s cards flagged (dup %.2f%%, photo %.2f%%, dead-soul %.2f%%)",
    format(flags$n_cards, big.mark = ","), 100 * flags$share_dup,
    100 * flags$share_photo_reuse, 100 * flags$share_dead_soul))
