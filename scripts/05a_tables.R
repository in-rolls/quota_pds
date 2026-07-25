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

message("05a complete")
