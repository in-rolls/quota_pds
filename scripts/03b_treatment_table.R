# 03b_treatment_table.R
# Treatment, history, caste strata, FE ids, and normalized controls from the
# quota_raj 2005-2020 panel (via quota_shaadi's snapshot).

library(here)
library(dplyr)

source(here("scripts", "00_config.R"))
source(here("scripts", "00_utils.R"))

panel <- arrow::read_parquet(TREATMENT_PANEL) |>
    filter(!is.na(lgd_gp_code)) |>
    arrange(lgd_gp_code, match_distance) |>
    distinct(lgd_gp_code, .keep_all = TRUE)

treat <- panel |>
    transmute(
        lgd_gp_code,
        treat_2020, treat_2015, treat_2010, treat_2005,
        winner_female_2020, count_treated,
        legacy_dose = treat_2005 + treat_2010 + treat_2015,
        sc_2020, st_2020, obc_2020,
        dist_samiti_2020,
        district = lgd_district,
        lit_rate = as.numeric(pc01_pca_p_lit) / pmax(as.numeric(pc01_pca_tot_p), 1),
        f_lit_rate = as.numeric(pc01_pca_f_lit) / pmax(as.numeric(pc01_pca_tot_f), 1),
        log_pop = log1p(as.numeric(pc01_pca_tot_p)),
        sc_share = as.numeric(pc01_pca_p_sc) / pmax(as.numeric(pc01_pca_tot_p), 1),
        st_share = as.numeric(pc01_pca_p_st) / pmax(as.numeric(pc01_pca_tot_p), 1),
        dist_town = as.numeric(pc01_vd_dist_town)
    )

arrow::write_parquet(treat, here("data", "outcomes", "gp_treatment.parquet"))

gp <- arrow::read_parquet(here("data", "outcomes", "gp_outcomes.parquet"))
overlap <- treat |> semi_join(gp, by = "lgd_gp_code")

write_audit(
    tibble(
        n_panel_gps = nrow(treat),
        n_outcome_gps = nrow(gp),
        n_analysis_gps = nrow(overlap),
        share_treat_2020 = mean(overlap$treat_2020, na.rm = TRUE),
        share_winner_female_open = overlap |>
            filter(treat_2020 == 0) |>
            summarise(m = mean(winner_female_2020, na.rm = TRUE)) |> pull(m)
    ), "03b_analysis_sample.csv")

covars <- c("lit_rate", "f_lit_rate", "log_pop", "sc_share", "st_share")
bal <- overlap |>
    filter(!is.na(treat_2020)) |>
    run_t_tests(vars = covars, labels = covars, treat_var = "treat_2020")
write_audit(bal, "03b_balance_raw.csv")

message(sprintf("03b complete: %d analysis GPs (%.1f%% reserved 2020)",
                nrow(overlap), 100 * mean(overlap$treat_2020, na.rm = TRUE)))
