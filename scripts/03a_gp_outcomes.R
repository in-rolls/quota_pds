# 03a_gp_outcomes.R
# GP-level leakage outcomes O1-O6, the APL placebo outcome, and the Anderson
# corruption index (signed so higher = more leakage).

library(here)
library(dplyr)
library(DBI)

source(here("scripts", "00_config.R"))
source(here("scripts", "00_utils.R"))

con <- get_duck()
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

gp <- dbGetQuery(con, sprintf("
    SELECT lgd_gp_code,
        count(*) AS n_cards,
        avg(CASE WHEN dup_identity THEN 1.0 ELSE 0 END) AS o1_dup_share,
        avg(CASE WHEN dup_identity AND poor THEN 1.0 ELSE 0 END)
            AS o1b_dup_subsidised,
        avg(CASE WHEN photo_reuse THEN 1.0 ELSE 0 END) AS o2_photo_share,
        sum(n_ghost_absent)::DOUBLE / nullif(sum(n_ghost_pool), 0)
            AS ghost_rate,
        sum(n_bench_absent)::DOUBLE / nullif(sum(n_bench_pool), 0)
            AS bench_rate,
        avg(dead_soul::DOUBLE) AS o4_dead_soul,
        avg(CASE WHEN poor THEN 1.0 ELSE 0 END) AS poor_share,
        avg(CASE WHEN card_type_raw = 'APL' THEN 1.0 ELSE 0 END)
            AS placebo_apl_share,
        avg(CASE WHEN poor THEN
                CASE WHEN n_months_last12 >= %d THEN 1.0 ELSE 0 END
            END) AS o6a_regular_delivery,
        sum(CASE WHEN (dup_identity OR photo_reuse) AND poor
                 THEN coalesce(qty_last12, 0) END) / count(*)
            AS o6b_ghost_offtake_pc,
        avg(CASE WHEN poor AND n_bills IS NULL THEN 1.0 ELSE 0 END)
            AS o6d_subsidised_no_tx
    FROM read_parquet(%s)
    GROUP BY lgd_gp_code
    HAVING count(*) >= %d",
    REGULAR_MONTHS_MIN,
    dbQuoteString(con, here("data", "cards", "card_flags.parquet")),
    MIN_CARDS_PER_GP))

gp <- gp |>
    mutate(
        o3_excess_ghost = ghost_rate - bench_rate,
        o6a_irregular = 1 - o6a_regular_delivery
    )

# Access family: quantities among subsidised cards and coverage of roll
# households. Quantities per member-month (NFSA entitlement is 5 kg/person/
# month); 2019 twins avoid the PMGKAY free-grain era.
access <- dbGetQuery(con, sprintf("
    SELECT lgd_gp_code,
        sum(CASE WHEN poor THEN coalesce(qty_last12, 0) END) /
            nullif(sum(CASE WHEN poor THEN n_members_stated END), 0) / 12.0
            AS a1_qty_pm_pc,
        sum(CASE WHEN poor THEN coalesce(qty_2019, 0) END) /
            nullif(sum(CASE WHEN poor THEN n_members_stated END), 0) / 12.0
            AS a1b_qty_pm_pc_2019,
        sum(coalesce(qty_last12, 0)) / count(*) / 12.0 AS a2_qty_per_card_pm
    FROM read_parquet(%s)
    GROUP BY lgd_gp_code",
    dbQuoteString(con, here("data", "cards", "card_flags.parquet"))))

rolls_hh <- dbGetQuery(con, sprintf("
    SELECT lgd_gp_code, count(DISTINCT hh_id) AS n_roll_hh
    FROM read_parquet(%s, hive_partitioning = true)
    GROUP BY lgd_gp_code",
    dbQuoteString(con, file.path(MILAAN_ROLLS_HH, "*", "*.parquet"))))

linked_hh <- dbGetQuery(con, sprintf("
    SELECT r.lgd_gp_code, count(DISTINCT l.hh_id) AS n_linked_hh
    FROM read_parquet(%s) l
    JOIN (SELECT DISTINCT hh_id, lgd_gp_code
          FROM read_parquet(%s, hive_partitioning = true)) r USING (hh_id)
    GROUP BY r.lgd_gp_code",
    dbQuoteString(con, file.path(MILAAN_PERSON_LINKS, "*.parquet")),
    dbQuoteString(con, file.path(MILAAN_ROLLS_HH, "*", "*.parquet"))))

gp <- gp |>
    left_join(access, by = "lgd_gp_code") |>
    left_join(rolls_hh, by = "lgd_gp_code") |>
    left_join(linked_hh, by = "lgd_gp_code") |>
    mutate(
        a4_cards_per_100hh = 100 * n_cards / n_roll_hh,
        a5_hh_linked_share = coalesce(n_linked_hh, 0L) / n_roll_hh
    )

# Targeting discretion: |residual| of poor share on census poverty predictors
panel <- arrow::read_parquet(TREATMENT_PANEL) |>
    filter(!is.na(lgd_gp_code)) |>
    arrange(lgd_gp_code, match_distance) |>
    distinct(lgd_gp_code, .keep_all = TRUE) |>
    transmute(
        lgd_gp_code,
        lit_rate = as.numeric(pc01_pca_p_lit) / pmax(as.numeric(pc01_pca_tot_p), 1),
        f_lit_rate = as.numeric(pc01_pca_f_lit) / pmax(as.numeric(pc01_pca_tot_f), 1),
        log_pop = log1p(as.numeric(pc01_pca_tot_p)),
        sc_share = as.numeric(pc01_pca_p_sc) / pmax(as.numeric(pc01_pca_tot_p), 1),
        st_share = as.numeric(pc01_pca_p_st) / pmax(as.numeric(pc01_pca_tot_p), 1),
        agr_share = as.numeric(pc01_pca_main_al_p) / pmax(as.numeric(pc01_pca_tot_work_p), 1),
        dist_town = as.numeric(pc01_vd_dist_town),
        dist_samiti_2020, district = lgd_district
    )

gp <- gp |> inner_join(panel, by = "lgd_gp_code")
m_target <- lm(poor_share ~ lit_rate + f_lit_rate + log_pop + sc_share +
                   st_share + agr_share + factor(district), data = gp)
gp$o5_targeting <- abs(gp$poor_share - predict(m_target, gp))

OUTCOME_COLS <- c("o1_dup_share", "o2_photo_share", "o3_excess_ghost",
                  "o4_dead_soul", "o5_targeting", "o6a_irregular",
                  "o6b_ghost_offtake_pc", "o6d_subsidised_no_tx")
ACCESS_COLS <- c("a1_qty_pm_pc", "a1b_qty_pm_pc_2019", "a2_qty_per_card_pm",
                 "a4_cards_per_100hh", "a5_hh_linked_share")

gp <- gp |>
    mutate(across(all_of(c(OUTCOME_COLS, ACCESS_COLS)), winsorize)) |>
    mutate(across(all_of(c(OUTCOME_COLS, ACCESS_COLS)), ~ as.numeric(scale(.x)),
                  .names = "z_{.col}"))

z_cols <- paste0("z_", OUTCOME_COLS)
gp$corruption_index <- anderson_index(as.matrix(gp[, z_cols]))

# Census covariates were only needed for the targeting residual; dropping
# them here keeps the treatment table the single source in 04x joins
gp <- gp |> select(-lit_rate, -f_lit_rate, -log_pop, -sc_share, -st_share,
                   -agr_share, -dist_town, -dist_samiti_2020, -district)

arrow::write_parquet(gp, here("data", "outcomes", "gp_outcomes.parquet"))

comp_cor <- round(cor(gp[, z_cols], use = "pairwise.complete.obs"), 3)
write_audit(as.data.frame(comp_cor) |> mutate(component = rownames(comp_cor)),
            "03a_component_correlations.csv")
write_audit(
    gp |> summarise(n_gps = n(),
                    across(all_of(c(OUTCOME_COLS, ACCESS_COLS, "placebo_apl_share",
                                    "poor_share")),
                           list(mean = ~ mean(.x, na.rm = TRUE),
                                sd = ~ sd(.x, na.rm = TRUE)))) |>
        tidyr::pivot_longer(everything()),
    "03a_outcome_summaries.csv")

message(sprintf("03a complete: %d GPs with outcomes", nrow(gp)))
