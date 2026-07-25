# 04b_open_seats.R
# Arm 2: women ELECTED in open 2020 seats, conditional on observables.
# Coefficient-stability check: no controls -> +covariates -> +history.

library(here)
library(dplyr)
library(fixest)

source(here("scripts", "00_config.R"))
source(here("scripts", "00_utils.R"))

gp <- arrow::read_parquet(here("data", "outcomes", "gp_outcomes.parquet")) |>
    select(-any_of(c("dist_samiti_2020", "district"))) |>
    inner_join(arrow::read_parquet(here("data", "outcomes", "gp_treatment.parquet")),
               by = "lgd_gp_code") |>
    filter(treat_2020 == 0, !is.na(winner_female_2020))

OUTCOMES <- c("corruption_index",
              paste0("z_", c("o1_dup_share", "o2_photo_share", "o3_excess_ghost",
                             "o4_dead_soul", "o5_targeting", "o6a_irregular",
                             "o6b_ghost_offtake_pc", "o6d_subsidised_no_tx",
                             "a1_qty_pm_pc", "a1b_qty_pm_pc_2019",
                             "a2_qty_per_card_pm", "a4_cards_per_100hh",
                             "a5_hh_linked_share")))

CTRL_COVARS <- "lit_rate + f_lit_rate + log_pop + sc_share + st_share + dist_town"
CTRL_HIST <- "treat_2005 + treat_2010 + treat_2015 + sc_2020 + st_2020 + obc_2020"

spec_battery <- function(y) {
    list(
        bare = feols(as.formula(paste0(y, " ~ winner_female_2020 | dist_samiti_2020")),
                     data = gp, weights = ~n_cards, cluster = ~dist_samiti_2020),
        covars = feols(as.formula(paste0(
            y, " ~ winner_female_2020 + ", CTRL_COVARS, " | dist_samiti_2020")),
            data = gp, weights = ~n_cards, cluster = ~dist_samiti_2020),
        full = feols(as.formula(paste0(
            y, " ~ winner_female_2020 + ", CTRL_COVARS, " + ", CTRL_HIST,
            " | dist_samiti_2020")),
            data = gp, weights = ~n_cards, cluster = ~dist_samiti_2020)
    )
}

all_tidy <- purrr::map_dfr(OUTCOMES, function(y) {
    ms <- spec_battery(y)
    purrr::imap_dfr(ms, function(m, spec) {
        tibble(outcome = y, spec = spec,
               estimate = coef(m)[["winner_female_2020"]],
               se = se(m)[["winner_female_2020"]],
               p = pvalue(m)[["winner_female_2020"]],
               r2 = fitstat(m, "r2")[[1]], n = nobs(m))
    })
})

stability <- all_tidy |>
    select(outcome, spec, estimate, r2) |>
    tidyr::pivot_wider(names_from = spec, values_from = c(estimate, r2)) |>
    mutate(coef_movement = estimate_full - estimate_bare,
           movement_share = coef_movement / estimate_bare)

write_audit(all_tidy, "04b_open_seat_estimates.csv")
write_audit(stability, "04b_coefficient_stability.csv")

message(sprintf("04b complete: %d open-seat GPs, %.1f%% woman-won",
                nrow(gp), 100 * mean(gp$winner_female_2020, na.rm = TRUE)))
