# 04c_index_and_placebos.R
# Placebo outcome (APL share: state-set, no GP discretion), benchmark-rate
# orthogonality check for O3, and sharpened q-values across components.

library(here)
library(dplyr)
library(fixest)

source(here("scripts", "00_config.R"))
source(here("scripts", "00_utils.R"))

gp <- arrow::read_parquet(here("data", "outcomes", "gp_outcomes.parquet")) |>
    select(-any_of(c("dist_samiti_2020", "district"))) |>
    inner_join(arrow::read_parquet(here("data", "outcomes", "gp_treatment.parquet")),
               by = "lgd_gp_code") |>
    filter(!is.na(treat_2020), !is.na(dist_samiti_2020))

run_itt <- function(y) {
    feols(as.formula(paste0(
        y, " ~ treat_2020 + legacy_dose + sc_2020 + st_2020 + obc_2020",
        " | dist_samiti_2020")),
        data = gp, weights = ~n_cards, cluster = ~dist_samiti_2020)
}

placebos <- purrr::map_dfr(c("placebo_apl_share", "bench_rate"), function(y) {
    m <- run_itt(y)
    tibble(outcome = y,
           term = c("treat_2020", "legacy_dose"),
           estimate = coef(m)[c("treat_2020", "legacy_dose")],
           se = se(m)[c("treat_2020", "legacy_dose")],
           p = pvalue(m)[c("treat_2020", "legacy_dose")],
           n = nobs(m))
})
write_audit(placebos, "04c_placebo_estimates.csv")

flagged <- placebos |> filter(term == "treat_2020", p < 0.05)
if (nrow(flagged) > 0) {
    warning("Placebo/benchmark outcomes respond to treatment — investigate:\n",
            paste(sprintf("  %s: b=%.4f p=%.4f", flagged$outcome,
                          flagged$estimate, flagged$p), collapse = "\n"))
} else {
    message("Placebo outcomes clean")
}

# Benjamini-Hochberg sharpened q-values over the component ITT estimates
itt <- readr::read_csv(here("data", "audit", "04a_itt_estimates.csv"),
                       show_col_types = FALSE) |>
    filter(subset == "full", term == "treat_2020",
           outcome != "corruption_index") |>
    mutate(q_bh = p.adjust(p, method = "BH"))
write_audit(itt |> select(outcome, estimate, se, p, q_bh),
            "04c_component_qvalues.csv")

message("04c complete")
