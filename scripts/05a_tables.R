# 05a_tables.R
# Publication tables: ITT headline (index + key components), open-seat arm.

library(here)
library(dplyr)
library(fixest)

source(here("scripts", "00_config.R"))
source(here("scripts", "00_utils.R"))

models <- readRDS(here("data", "outcomes", "itt_models.rds"))

DICT <- c(
    "treat_2020" = "$\\text{Quota}_{2020}$",
    "legacy_dose" = "Prior quotas (2005--2015)",
    "winner_female_2020" = "Woman won (open seat)",
    "corruption_index" = "Corruption index",
    "z_o1_dup_share" = "Duplicate identities (z)",
    "z_o2_photo_share" = "Photo reuse (z)",
    "z_o3_excess_ghost" = "Excess ghosts (z)",
    "z_o6a_irregular" = "Irregular delivery (z)",
    "dist_samiti_2020" = "(District, Samiti)"
)

aer_etable(
    models[c("corruption_index", "z_o1_dup_share", "z_o2_photo_share",
             "z_o3_excess_ghost", "z_o6a_irregular")],
    file = here("tabs", "itt_main.tex"),
    dict = DICT,
    drop = c("%sc_2020", "%st_2020", "%obc_2020"),
    notes = NOTES_ITT
)

gp <- arrow::read_parquet(here("data", "outcomes", "gp_outcomes.parquet")) |>
    select(-any_of(c("dist_samiti_2020", "district"))) |>
    inner_join(arrow::read_parquet(here("data", "outcomes", "gp_treatment.parquet")),
               by = "lgd_gp_code") |>
    filter(treat_2020 == 0, !is.na(winner_female_2020))

CTRL <- paste("lit_rate + f_lit_rate + log_pop + sc_share + st_share +",
              "dist_town + treat_2005 + treat_2010 + treat_2015 +",
              "sc_2020 + st_2020 + obc_2020")
open_models <- lapply(
    c("corruption_index", "z_o1_dup_share", "z_o6a_irregular"),
    function(y) feols(as.formula(paste0(
        y, " ~ winner_female_2020 + ", CTRL, " | dist_samiti_2020")),
        data = gp, weights = ~n_cards, cluster = ~dist_samiti_2020))

aer_etable(
    open_models,
    file = here("tabs", "open_seats.tex"),
    dict = DICT,
    keep = "%winner_female_2020",
    notes = NOTES_OPEN
)

access_dict <- c(DICT,
    "z_a1_qty_pm_pc" = "Grain/member-month, subsidised (z)",
    "z_a1b_qty_pm_pc_2019" = "Grain/member-month, 2019 (z)",
    "z_a4_cards_per_100hh" = "Cards per 100 roll households (z)",
    "z_a5_hh_linked_share" = "Roll households with a card (z)")

aer_etable(
    models[c("z_a1_qty_pm_pc", "z_a1b_qty_pm_pc_2019",
             "z_a4_cards_per_100hh", "z_a5_hh_linked_share")],
    file = here("tabs", "access_main.tex"),
    dict = access_dict,
    drop = c("%sc_2020", "%st_2020", "%obc_2020"),
    notes = paste0(NOTES_ITT,
        " Quantity outcomes cover the 12 months before the 2021 snapshot",
        " (the PMGKAY free-grain period) except the 2019 column.",
        " Coverage denominators are 2018 electoral-roll households.")
)

message("05a complete")
