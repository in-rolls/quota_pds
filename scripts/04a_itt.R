# 04a_itt.R
# Arm 1: reservation ITT. Outcomes on treat_2020 (+ legacy dose), samiti FE,
# caste-stratum controls, SEs clustered by samiti; randomization inference
# within samiti x caste stratum; rotation-consistency subset (2015 -> 2020).

library(here)
library(dplyr)
library(fixest)

source(here("scripts", "00_config.R"))
source(here("scripts", "00_utils.R"))

set.seed(42)
N_RI <- 1000L

gp <- arrow::read_parquet(here("data", "outcomes", "gp_outcomes.parquet")) |>
    select(-any_of(c("dist_samiti_2020", "district"))) |>
    inner_join(arrow::read_parquet(here("data", "outcomes", "gp_treatment.parquet")),
               by = "lgd_gp_code") |>
    filter(!is.na(treat_2020), !is.na(dist_samiti_2020))

OUTCOMES <- c("corruption_index",
              paste0("z_", c("o1_dup_share", "o2_photo_share", "o3_excess_ghost",
                             "o4_dead_soul", "o5_targeting", "o6a_irregular",
                             "o6b_ghost_offtake_pc", "o6d_subsidised_no_tx",
                             "a1_qty_pm_pc", "a1b_qty_pm_pc_2019",
                             "a2_qty_per_card_pm", "a4_cards_per_100hh",
                             "a5_hh_linked_share")))

run_itt <- function(y, data) {
    feols(as.formula(paste0(
        y, " ~ treat_2020 + legacy_dose + sc_2020 + st_2020 + obc_2020",
        " | dist_samiti_2020")),
        data = data, weights = ~n_cards, cluster = ~dist_samiti_2020)
}

models <- lapply(OUTCOMES, run_itt, data = gp)
names(models) <- OUTCOMES

tidy <- purrr::imap_dfr(models, function(m, y) {
    tibble(outcome = y,
           term = c("treat_2020", "legacy_dose"),
           estimate = coef(m)[c("treat_2020", "legacy_dose")],
           se = se(m)[c("treat_2020", "legacy_dose")],
           p = pvalue(m)[c("treat_2020", "legacy_dose")],
           n = nobs(m))
})

# Randomization inference: permute treat_2020 within samiti x caste stratum
ri_p <- function(y, data, n_perm = N_RI) {
    obs <- coef(run_itt(y, data))[["treat_2020"]]
    strata <- interaction(data$dist_samiti_2020, data$sc_2020, data$st_2020,
                          data$obc_2020, drop = TRUE)
    perms <- replicate(n_perm, {
        d2 <- data
        d2$treat_2020 <- ave(d2$treat_2020, strata,
                             FUN = function(x) sample(x))
        coef(run_itt(y, d2))[["treat_2020"]]
    })
    mean(abs(perms) >= abs(obs))
}

ri_results <- tibble(
    outcome = c("corruption_index", "z_o1_dup_share", "z_o6a_irregular",
                "z_a1_qty_pm_pc", "z_a4_cards_per_100hh"),
    ri_p = vapply(outcome, ri_p, numeric(1), data = gp)
)
tidy <- tidy |> left_join(ri_results, by = "outcome")

# Rotation-consistency subset: districts where 2015->2020 passes independence
raj_panel <- arrow::read_parquet(RAJ_15_20_PANEL)
chisq <- compute_district_chisq(raj_panel, "treat_2015", "treat_2020",
                                "district_std_2020")
rot_districts <- chisq |> filter(chisq_p > 0.05) |> pull(district_std_2020)
write_audit(chisq |> mutate(random_rotation = chisq_p > 0.05),
            "04a_rotation_districts.csv")

gp_rot <- gp |> filter(tolower(district) %in% tolower(rot_districts))
tidy_rot <- purrr::map_dfr(c("corruption_index", "z_o1_dup_share"),
    function(y) {
        m <- run_itt(y, gp_rot)
        tibble(outcome = y, term = "treat_2020",
               estimate = coef(m)[["treat_2020"]], se = se(m)[["treat_2020"]],
               p = pvalue(m)[["treat_2020"]], n = nobs(m),
               subset = "rotation_consistent")
    })

write_audit(bind_rows(tidy |> mutate(subset = "full"), tidy_rot),
            "04a_itt_estimates.csv")
saveRDS(models, here("data", "outcomes", "itt_models.rds"))
message("04a complete")
