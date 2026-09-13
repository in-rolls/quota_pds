# 00_utils.R
# Functions marked vendored are copied from quota_marriage/scripts/00_utils.R;
# 01b_snapshot_inputs.R asserts they have not drifted.

library(stringi)
library(stringdist)
library(here)
library(dplyr)

get_duck <- function() {
    con <- DBI::dbConnect(duckdb::duckdb())
    DBI::dbExecute(con, sprintf("SET memory_limit = '%s'", DUCKDB_MEMORY_LIMIT))
    DBI::dbExecute(con, sprintf("SET threads = %d", DUCKDB_THREADS))
    DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", here("data", "tmp")))
    DBI::dbExecute(con, "SET max_temp_directory_size = '60GiB'")
    # Autoloading of icu fails in this environment; date/locale functions
    # (strptime %b, timestamp-date comparisons) need it loaded explicitly
    try(DBI::dbExecute(con, "INSTALL icu"), silent = TRUE)
    try(DBI::dbExecute(con, "LOAD icu"), silent = TRUE)
    con
}

write_audit <- function(df, filename) {
    path <- here("data", "audit", filename)
    readr::write_csv(df, path)
    message("Audit written: ", path, " (", nrow(df), " rows)")
    invisible(path)
}

winsorize <- function(x, p = WINSOR_P) {
    hi <- quantile(x, p, na.rm = TRUE)
    lo <- quantile(x, 1 - p, na.rm = TRUE)
    pmin(pmax(x, lo), hi)
}

# Anderson (2008) inverse-covariance-weighted index over standardized
# components (signed so higher = more leakage)
anderson_index <- function(mat) {
    z <- scale(mat)
    keep <- complete.cases(z)
    S <- solve(cov(z[keep, , drop = FALSE]))
    w <- rowSums(S)
    idx <- as.numeric(z %*% (w / sum(w)))
    as.numeric(scale(idx))
}

# ============================================================================
# VENDORED from quota_marriage
# ============================================================================

normalize_string <- function(input_string) {
     normalized_string <- stri_trans_general(input_string, "Latin-ASCII")
     normalized_string <- stri_trans_tolower(normalized_string)
     normalized_string <- gsub("\\s+", " ", normalized_string)
     normalized_string <- trimws(normalized_string)
     normalized_string <- gsub("[[:punct:]]", "", normalized_string)
     return(normalized_string)
}

run_t_tests <- function(data, vars, labels, treat_var = "treat",
                        na_string = "--", digits = 2) {
    fmt <- paste0("%.", digits, "f")
    purrr::map2_dfr(vars, labels, function(var, label) {
        d <- data %>% dplyr::filter(!is.na(.data[[var]]))

        if (nrow(d) == 0 || length(unique(d[[treat_var]])) < 2) {
            return(tibble::tibble(
                Variable = label,
                Open = na_string,
                Quota = na_string,
                `Diff.` = na_string
            ))
        }

        fml <- stats::reformulate(treat_var, var)
        test <- stats::t.test(fml, data = d)
        stars <- dplyr::case_when(
            test$p.value < 0.01 ~ "$^{***}$",
            test$p.value < 0.05 ~ "$^{**}$",
            test$p.value < 0.1 ~ "$^{*}$",
            TRUE ~ ""
        )
        tibble::tibble(
            Variable = label,
            Open = sprintf(fmt, test$estimate[1]),
            Quota = sprintf(fmt, test$estimate[2]),
            `Diff.` = paste0(sprintf(fmt, test$estimate[1] - test$estimate[2]), stars)
        )
    })
}

compute_district_chisq <- function(data, treat_t1, treat_t2, district_var) {
    results <- data %>%
        group_by(!!sym(district_var)) %>%
        summarise(
            n = n(),
            n_00 = sum(!!sym(treat_t1) == 0 & !!sym(treat_t2) == 0, na.rm = TRUE),
            n_01 = sum(!!sym(treat_t1) == 0 & !!sym(treat_t2) == 1, na.rm = TRUE),
            n_10 = sum(!!sym(treat_t1) == 1 & !!sym(treat_t2) == 0, na.rm = TRUE),
            n_11 = sum(!!sym(treat_t1) == 1 & !!sym(treat_t2) == 1, na.rm = TRUE),
            .groups = "drop"
        ) %>%
        rowwise() %>%
        mutate(
            chisq_p = {
                tbl <- matrix(c(n_00, n_01, n_10, n_11), nrow = 2)
                if (any(rowSums(tbl) == 0) || any(colSums(tbl) == 0)) {
                    NA_real_
                } else {
                    tryCatch(
                        chisq.test(tbl, correct = FALSE)$p.value,
                        error = function(e) NA_real_
                    )
                }
            }
        ) %>%
        ungroup()

    return(results)
}

convert_sci_to_decimal <- function(text, digits = 2) {
    pattern <- "\\$(-?[0-9]+\\.?[0-9]*)\\\\times 10\\^\\{(-?[0-9]+)\\}\\$"
    matches <- gregexpr(pattern, text, perl = TRUE)
    if (matches[[1]][1] == -1) return(text)

    result <- text
    for (match_info in regmatches(text, matches)[[1]]) {
        parts <- regmatches(match_info, regexec(pattern, match_info, perl = TRUE))[[1]]
        mantissa <- as.numeric(parts[2])
        exponent <- as.numeric(parts[3])
        value <- mantissa * (10 ^ exponent)
        formatted <- sprintf(paste0("%.", digits, "f"), value)
        result <- sub(match_info, formatted, result, fixed = TRUE)
    }
    return(result)
}

aggressive_round <- function(x, digits = 2) {
    x <- sapply(x, convert_sci_to_decimal, digits = digits)
    x <- gsub("([0-9])\\.([0-9]{2})[0-9]+", "\\1.\\2", x)
    x <- gsub(" \\.([0-9]{2})[0-9]+", " .\\2", x)
    return(x)
}

format_coef_stars <- function(coef, pval, digits = 2) {
    if (is.null(coef) || is.na(coef)) return("---")
    stars <- ""
    if (!is.na(pval)) {
        if (pval < 0.01) stars <- "$^{***}$"
        else if (pval < 0.05) stars <- "$^{**}$"
        else if (pval < 0.1) stars <- "$^{*}$"
    }
    paste0(sprintf(paste0("%.", digits, "f"), coef), stars)
}

format_se_parens <- function(se, digits = 2) {
    if (is.null(se) || is.na(se)) return("")
    paste0("(", sprintf(paste0("%.", digits, "f"), se), ")")
}

format_n_comma <- function(n) {
    if (is.null(n) || is.na(n)) return("---")
    format(n, big.mark = ",")
}

aer_etable <- function(models, file, dict = NULL, digits = 2, notes = NULL,
                       title = NULL, label = NULL, placement = "htbp",
                       cmidrules = NULL, colsep = NULL, headers = NULL, ...) {
    args <- list(models = models,
           tex = TRUE,
           style.tex = fixest::style.tex("aer", model.format = "[i]", depvar.style = "*"),
           digits = digits,
           digits.stats = digits,
           fitstat = ~ r2 + n,
           se.row = FALSE,
           dict = dict,
           interaction.combine = " $\\times $ ",
           ...)

    if (!is.null(headers)) {
        args$headers <- headers
    }

    res <- do.call(fixest::etable, args)
    res <- aggressive_round(res)

    res <- gsub(" fixed effects", " FE", res)

    fe_pattern <- "^\\s*\\(.*\\) FE\\s*&"
    fe_indices <- grep(fe_pattern, res)
    if (length(fe_indices) > 1) {
        fe_labels <- sub("^\\s*(\\([^)]+\\) FE).*", "\\1", res[fe_indices])
        rows_to_remove <- c()
        for (fe_label in unique(fe_labels)) {
            label_indices <- fe_indices[fe_labels == fe_label]
            if (length(label_indices) > 1) {
                first_row <- res[label_indices[1]]
                for (idx in label_indices[-1]) {
                    first_row <- gsub("&\\s*&", "& PLACEHOLDER &", first_row)
                    other_row <- res[idx]
                    rows_to_remove <- c(rows_to_remove, idx)
                    if (grepl("\\$\\\\checkmark\\$", other_row)) {
                        parts_other <- strsplit(other_row, "&")[[1]]
                        parts_first <- strsplit(first_row, "&")[[1]]
                        for (i in seq_along(parts_other)) {
                            if (grepl("\\$\\\\checkmark\\$", parts_other[i]) &&
                                !grepl("\\$\\\\checkmark\\$", parts_first[i])) {
                                parts_first[i] <- parts_other[i]
                            }
                        }
                        first_row <- paste(parts_first, collapse = "&")
                    }
                }
                first_row <- gsub("PLACEHOLDER", "", first_row)
                res[label_indices[1]] <- first_row
            }
        }
        if (length(rows_to_remove) > 0) {
            res <- res[-rows_to_remove]
        }
    }

    res <- res[!grepl("\\\\begin\\{table\\}|\\\\end\\{table\\}|\\\\centering|\\\\caption|\\\\label", res)]
    res <- res[!grepl("\\\\scriptsize", res)]
    res <- res[!grepl("^\\s*\\\\\\\\\\s*$", res)]

    if (!is.null(headers)) {
        toprule_idx <- grep("\\\\toprule", res)
        midrule_idx <- grep("\\\\midrule", res)
        if (length(toprule_idx) > 0 && length(midrule_idx) > 0) {
            header_region <- (toprule_idx[1] + 1):(midrule_idx[1] - 1)
            multicolumn_rows <- which(grepl("\\\\multicolumn", res))
            multicolumn_in_header <- multicolumn_rows[multicolumn_rows %in% header_region]
            if (length(multicolumn_in_header) > 1) {
                rows_to_remove <- multicolumn_in_header[1]
                res <- res[-rows_to_remove]
            }
        }
    }

    res <- gsub("\\\\begin\\{tabular\\}\\{l(c+)\\}",
                "\\\\begin{tabular}{@{}l\\1@{}}", res)

    if (!is.null(colsep)) {
        tabular_line <- grep("\\\\begin\\{tabular\\}", res)
        if (length(tabular_line) > 0) {
            spec <- res[tabular_line[1]]
            n_cols <- colsep$after
            space <- if (!is.null(colsep$space)) colsep$space else "1em"
            pattern <- paste0("(\\\\begin\\{tabular\\}\\{@\\{\\}l", paste(rep("c", n_cols), collapse = ""), ")(c+)(@\\{\\}\\})")
            replacement <- paste0("\\1@{\\\\hspace{", space, "}}\\2\\3")
            res[tabular_line[1]] <- gsub(pattern, replacement, spec)
        }
    }

    if (!any(grepl("\\\\end\\{tabular\\}", res))) {
        bottomrule_idx <- grep("\\\\bottomrule", res)
        if (length(bottomrule_idx) > 0) {
            res <- c(res[1:bottomrule_idx[length(bottomrule_idx)]],
                     "\\end{tabular}",
                     if (bottomrule_idx[length(bottomrule_idx)] < length(res)) res[(bottomrule_idx[length(bottomrule_idx)]+1):length(res)] else NULL)
        }
    }

    if (!is.null(cmidrules)) {
        toprule_idx <- grep("\\\\toprule", res)
        if (length(toprule_idx) > 0) {
            midrule_idx <- grep("\\\\midrule", res)
            if (length(midrule_idx) > 0) {
                header_rows <- which(grepl("\\\\multicolumn", res) & seq_along(res) > toprule_idx[1] & seq_along(res) < midrule_idx[1])
                if (length(header_rows) >= cmidrules$after) {
                    insert_after <- header_rows[cmidrules$after]
                    cmidrule_line <- paste0("   ", paste(sapply(cmidrules$rules, function(r) paste0("\\cmidrule(lr){", r, "}")), collapse = " "))
                    res <- c(res[1:insert_after], cmidrule_line, res[(insert_after+1):length(res)])
                }
            }
        }
    }

    if (!is.null(title) || !is.null(label)) {
        wrapped_output <- c(
            paste0("\\begin{table}[", placement, "]"),
            "\\centering"
        )
        if (!is.null(title)) {
            if (!is.null(label)) {
                wrapped_output <- c(wrapped_output,
                    paste0("\\caption{\\label{", label, "}", title, "}"))
            } else {
                wrapped_output <- c(wrapped_output,
                    paste0("\\caption{", title, "}"))
            }
        } else if (!is.null(label)) {
            wrapped_output <- c(wrapped_output,
                paste0("\\label{", label, "}"))
        }
        wrapped_output <- c(wrapped_output,
            "{\\centering\\scriptsize",
            res,
            "\\par}"
        )
        if (!is.null(notes)) {
            wrapped_output <- c(wrapped_output,
                "",
                "\\vspace{0.5ex}",
                paste0("\\parbox{\\linewidth}{\\scriptsize \\emph{Notes: } ", notes, "}")
            )
        }
        wrapped_output <- c(wrapped_output, "\\end{table}")
    } else {
        wrapped_output <- c(
            "{\\centering\\scriptsize",
            res,
            "\\par}"
        )
        if (!is.null(notes)) {
            wrapped_output <- c(wrapped_output,
                "",
                "\\vspace{0.5ex}",
                paste0("\\parbox{\\linewidth}{\\scriptsize \\emph{Notes: } ", notes, "}")
            )
        }
    }

    if (!is.null(file)) {
        writeLines(wrapped_output, con = file)
    }
    invisible(wrapped_output)
}
