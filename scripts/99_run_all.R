# 99_run_all.R
# Run the full pipeline: Rscript scripts/99_run_all.R

library(here)

dir.create(here("logs"), showWarnings = FALSE)
log_file <- here("logs", paste0("pipeline_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))

log_msg <- function(msg, level = "INFO") {
    line <- sprintf("[%s] %s: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level, msg)
    message(line)
    cat(line, "\n", file = log_file, append = TRUE)
}

run_script <- function(script_name) {
    message("\n--- Running: ", script_name, " ---")
    log_msg(paste("Starting:", script_name))
    start_time <- Sys.time()
    tryCatch({
        status <- system2(file.path(R.home("bin"), "Rscript"),
                          shQuote(here("scripts", script_name)))
        if (status != 0L) stop("Rscript exited with status ", status)
        log_msg(sprintf("SUCCESS: %s (%.1fs)", script_name,
                        as.numeric(difftime(Sys.time(), start_time, units = "secs"))))
    }, error = function(e) {
        log_msg(paste("ERROR in", script_name, ":", e$message), "ERROR")
        stop(sprintf("Pipeline halted at %s: %s", script_name, e$message))
    })
}

run_script("01a_download_transactions.R")
run_script("01b_snapshot_inputs.R")
run_script("02a_transactions_to_parquet.R")
run_script("02b_card_flags.R")
run_script("03a_gp_outcomes.R")
run_script("03b_treatment_table.R")
run_script("04a_itt.R")
run_script("04b_open_seats.R")
run_script("04c_index_and_placebos.R")
run_script("05a_tables.R")
run_script("98_validate.R")

log_msg("Pipeline finished")
