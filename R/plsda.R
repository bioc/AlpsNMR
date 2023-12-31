#' Build a PLSDA model, optionally with multilevel
#' @param x the X training set
#' @param y the y training class to predict
#' @param identity the multilevel variable in [mixOmics::plsda]
#' @param ncomp The number of components of the model
#' @noRd
plsda_build <- function(x, y, identity, ncomp) {
    plsda_model <- NULL
    if (ncomp > ncol(x)) {
        cli::cli_abort("The number of components in a plsda model ({ncomp}) can't
                       be larger than the number of features ({ncol(x)})")
    }
    tryCatch(
        {
            suppressMessages(utils::capture.output({
                plsda_model <- mixOmics::plsda(
                    X = x,
                    Y = y,
                    ncomp = ncomp,
                    scale = TRUE,
                    multilevel = identity
                )
            }))
        },
        error = function(e) {
            msg <- conditionMessage(e)
            rlang::abort(
                message = c(
                    "plsda_build failed",
                    "i" = glue::glue("Original message: {msg}")
                ),
                parent = e
            )
        }
    )
    plsda_model
}


#' Compute the area under the ROC curve of a PLS-DA model on a test subset
#' @param plsda_model A mixOmics plsda model
#' @param x_test the x test set
#' @param y_test the y test class to predict
#' @param identity_test the multilevel variable in [mixOmics::plsda]
#' @return A list with two elements:
#'    - `aucs`: A data frame with two columns: `ncomp` (the number of components) and
#'       `auc` the area under roc curve for that number of components. For multiclass problems
#'       the AUC returned is the mean of all the one-vs-other AUCs.
#'    - `aucs_full`: A list of matrices, as returned by [mixOmics::auroc].
#' @noRd
plsda_auroc <-
    function(plsda_model,
    x_test,
    y_test,
    identity_test) {
        aucs <- numeric(0L)
        aucs_full <- list()
        tryCatch(
            {
                suppressMessages(utils::capture.output({
                    roc <- mixOmics::auroc(
                        plsda_model,
                        newdata = x_test,
                        outcome.test = y_test,
                        multilevel = identity_test,
                        plot = FALSE
                    )
                }))
                aucs <- purrr::map_dbl(roc, function(x) {
                    mean(x[, "AUC"])
                })
                aucs_full <- roc
            },
            error = function(e) {
                msg <- conditionMessage(e)
                rlang::abort(
                    message = c(
                        "Area Under Curve estimation failed",
                        "i" = glue::glue("Original message: {msg}")
                    ),
                    parent = e
                )
            }
        )

        ncomps <-
            as.integer(gsub(
                pattern = "Comp(.*)",
                replacement = "\\1",
                x = names(aucs)
            ))

        list(
            aucs = data.frame(
                ncomp = ncomps,
                auc = aucs
            ),
            aucs_full = aucs_full
        )
    }

#' Compute the variable importance in the projection
#' @param plsda_model A mixOmics plsda model
#' @return A matrix with the variable importance in the projection
#' @noRd
plsda_vip <- function(plsda_model) {
    vip <- NULL
    tryCatch(
        {
            suppressMessages(utils::capture.output({
                vip <- mixOmics::vip(object = plsda_model)
            }))
        },
        error = function(e) {
            msg <- conditionMessage(e)
            rlang::inform(
                message = c(
                    "VIP calculation failed",
                    "i" = glue::glue("Original message: {msg}")
                )
            )
        }
    )
    vip
}


#' Callback for building a PLSDA model, computing the AUROC and extract the VIP
#'
#' @param x_train Training data for x
#' @param y_train Training data for y
#' @param identity_train Training data for the identities
#' @param x_test Test data for x
#' @param y_test Test data for y
#' @param identity_test Test data for the identities
#' @param ncomp Number of components to use in the model
#' @param return_model A logical.
#' @param return_auroc A logical.
#' @param return_auroc_full A logical.
#' @param return_vip A logical.
#'
#'
#' For multiclass problems the AUC returned is the mean of all the one-vs-other AUCs.
#'
#' @return A list with the model, the area under the roc curve and the VIP items.
#' @noRd
callback_plsda_auroc_vip <-
    function(x_train,
    y_train,
    identity_train,
    x_test,
    y_test,
    identity_test,
    ncomp,
    return_model = FALSE,
    return_auroc = TRUE,
    return_auroc_full = FALSE,
    return_vip = FALSE) {
        plsda_model <-
            plsda_build(x_train, y_train, identity_train, ncomp = max(ncomp))
        out <-
            list(
                model = NULL,
                auroc = NULL,
                auroc_full = NULL,
                vip = NULL
            )
        if (isTRUE(return_model)) {
            out$model <- plsda_model
            out$model$X_test <- x_test
            out$model$Y_test <- y_test
        }
        if (isTRUE(return_auroc) || isTRUE(return_auroc_full)) {
            aurocs <- plsda_auroc(plsda_model, x_test, y_test, identity_test)
            if (isTRUE(return_auroc)) {
                out$auroc <- aurocs$aucs
            }
            if (isTRUE(return_auroc_full)) {
                out$auroc_full <- aurocs$aucs_full
            }
        }

        if (isTRUE(return_vip)) {
            vip <- plsda_vip(plsda_model)
            out$vip <- vip
        }
        out
    }

#' Choose best number of latent variables
#' @param ncomp_auc a data frame with two columns: ncomp and auc
#' @param auc_threshold The minimum increment to the auc that makes it worth increasing model complexity
#' @noRd
choose_best_nlv_impl <- function(ncomp_auc, auc_threshold) {
    if (nrow(ncomp_auc) == 0L) {
        # This should not happen.
        return(integer(0L))
    }
    
    # If we only have one possible number of latent variables, that's what we choose:
    if (nrow(ncomp_auc) == 1) {
        return(ncomp_auc$ncomp[1])
    }

    # Ensure ncomp_auc is sorted by increasing number of ncomp (increasing model complexity)
    ncomp_auc <- ncomp_auc[order(ncomp_auc$ncomp), , drop = FALSE]

    if (all(is.na(ncomp_auc$auc))) {
        # In absence of AUCs (because all models failed to train) then we
        # can just ask for a simple model and wish for the best.
        return(ncomp_auc$ncomp[1])
    }
    
    # Compute the auc increment. The leading 0 assumes that with 0 latent variables
    # we have an AUC of 0.
    for (i in seq_len(nrow(ncomp_auc) - 1L)) {
        # The next increment in complexity yields an increment of auc of:
        auc_dif <- ncomp_auc$auc[i + 1L] - ncomp_auc$auc[i]
        # If incrementing model complexity does not improve performance,
        # then return current complexity:
        if (auc_dif < auc_threshold) {
            return(ncomp_auc$ncomp[i])
        }
    }
    # Either the threshold is low or the max explored nlv is low, return
    # the highest number of components:
    return(ncomp_auc$ncomp[nrow(ncomp_auc)])
}

#' Choose best number of latent variables based on a threshold on the auc increment.
#' @param inner_cv_results A list of elements returned by [callback_plsda_auroc_vip]
#' @param auc_threshold Threshold on the increment of AUC. Increasing the number of
#' latent variables must increase the AUC at least by this threshold.
#' @return A list with:
#'    - `train_evaluate_model_args`: A list with one element named `ncomp` with the number of latent variables selected
#'             for each outer cross-validation
#'    - `num_latent_var`: A data frame with the number of latent variables chosen for each outer cross-validation
#'    - `diagnostic_plot`: A plot showing the evolution of the AUC vs the number of latent variables for each iteration
#'    - `diagnostic_box_plot`: Same as the `diagnostic_plot` but using box plots
#'    - `model_performances`: A data frame with the AUC model performances
#' @noRd
choose_best_nlv <- function(inner_cv_results, auc_threshold) {
    # Split performances so we get a list of data frames with (ncomp, auc)
    best_nlv <- inner_cv_results %>%
        purrr::map("auroc") %>%
        purrr::map_int(choose_best_nlv_impl, auc_threshold = auc_threshold) %>%
        tibble::enframe(name = "outer_inner", value = "ncomp") %>%
        tidyr::separate(
            "outer_inner",
            into = c("cv_outer_iteration", "cv_inner_iteration"),
            convert = TRUE
        )
    # best_nlv is a data frame with three columns:
    # - cv_outer_iteration: The index of the outer iteration in cv
    # - cv_inner_iteration: The index of the inner iteration in cv
    # - ncomp: The optimal number of latent variables according to the described criteria
    #          for that particular data split
    
    # Choose a single ncomp for each outer iteration, by getting the median of all the best ncomp
    # in its internal validation:
    nlv <-  dplyr::summarise(
        best_nlv,
        ncomp = round(stats::median(.data$ncomp)),
        .by = "cv_outer_iteration"
    )
    
    # nlv is a tibble with two columns: cv_outer_iteration and ncomp
    # It represents for each outer iteration which is the final selection of number of latent variables

    diag_info <- choose_best_nlv_diagnostic_info(inner_cv_results, nlv)

    list(
        train_evaluate_model_args = list(ncomp = nlv$ncomp),
        num_latent_var = nlv,
        diagnostic_plot = diag_info$plot_to_choose_nlv,
        diagnostic_box_plot = diag_info$box_plot,
        model_performances = diag_info$model_performances
    )
}

choose_best_nlv_diagnostic_info <- function(inner_cv_results, nlv) {
    model_performances <- inner_cv_results %>%
        purrr::map("auroc") %>% # inner_cv_results$auroc[1] is a data frame with columns: ncomp auc
        purrr::list_rbind(names_to = "outer_inner") %>%
        tidyr::separate(
            "outer_inner",
            into = c("cv_outer_iteration", "cv_inner_iteration"),
            convert = TRUE
        )
    
    # model_performances is a data frame with the following columns:
    # - cv_outer_iteration: The index of the outer iteration in cv
    # - cv_inner_iteration: The index of the inner iteration in cv
    # - ncomp: The number of latent variables used to train the model
    # - auc: The performance (AUC) obtained for that number of latent variables
    
    plot_to_choose_nlv <- ggplot2::ggplot(model_performances) +
        ggplot2::geom_line(
            ggplot2::aes(
                x = .data$ncomp,
                y = .data$auc,
                color = as.character(.data$cv_inner_iteration)
            )
        ) +
        ggplot2::geom_vline(
            data = nlv,
            mapping = ggplot2::aes(xintercept = .data$ncomp),
            color = "red"
        ) +
        ggplot2::scale_x_continuous(
            name = "Number of latent variables",
            breaks = function(limits) {
                seq(from = 1, to = max(limits))
            }
        ) +
        ggplot2::scale_y_continuous(name = "Area Under ROC") +
        ggplot2::facet_wrap(~cv_outer_iteration) +
        ggplot2::guides(colour = "none")
    
    class_compare <- names(inner_cv_results)
    auroc_tables <- inner_cv_results %>%
        purrr::map("auroc") %>%
        purrr::map2(class_compare, function(auroc, group_name) {
            auroc %>%
                dplyr::select("auc") %>%
                dplyr::mutate(Group = !!group_name)
        })
    
    toplot <- do.call(rbind, auroc_tables)
    box_plot <- ggplot2::ggplot(toplot) +
        ggplot2::geom_boxplot(ggplot2::aes(
            x = .data$Group,
            y = .data$auc,
            fill = .data$Group
        ),
        show.legend = FALSE
        ) +
        ggplot2::scale_x_discrete(name = "Model") +
        ggplot2::scale_y_continuous(name = "Area under ROC")
    
    list(
        diagnostic_plot = plot_to_choose_nlv,
        diagnostic_box_plot = box_plot
    )
}


#' Callback to choose the best number of latent variables based on the AUC threshold
#'
#' @param auc_threshold Threshold on the increment of AUC. Increasing the number of
#' latent variables must increase the AUC at least by this threshold.
#'
#' @return The actual function to compute the best number of latent variables according to a threshold on the increment of AUC
#' @noRd
fun_choose_best_ncomp_auc_threshold <- function(auc_threshold = 0.05) {
    force(auc_threshold)
    function(inner_cv_results) {
        choose_best_nlv(inner_cv_results, auc_threshold)
    }
}

#################### Validation #######

#' Callback to digest the results of the outer cross validation
#' @noRd
callback_outer_cv_auroc_vip <- function(outer_cv_results) {
    auroc <- outer_cv_results %>%
        purrr::map("auroc") %>%
        purrr::map_dfr(~., .id = "cv_outer_iteration") %>%
        dplyr::mutate(cv_outer_iteration = as.integer(.data$cv_outer_iteration)) %>%
        dplyr::group_by(.data$cv_outer_iteration) %>%
        dplyr::filter(.data$ncomp == max(.data$ncomp)) %>%
        dplyr::ungroup() %>%
        dplyr::arrange(.data$cv_outer_iteration)

    vip_vectors <- outer_cv_results %>%
        purrr::map("vip") %>%
        purrr::map2(auroc$ncomp, function(vip_matrix, selected_ncomp) {
            vip_vec <- as.numeric(vip_matrix[, selected_ncomp, drop = TRUE])
            names(vip_vec) <- rownames(vip_matrix)
            vip_vec
        })

    vip_ranks <- do.call(cbind, purrr::map(vip_vectors, ~ rank(-.)))

    vip_rp <-
        apply(vip_ranks, 1, function(x) {
            exp(mean(log(x)))
        }) # geom mean (RankProducts)

    list(
        auroc = auroc,
        vip_vectors = vip_vectors,
        vip_rankproducts = vip_rp
    )
}


#' Method for nmr_data_analysis (PLSDA model with AUROC and VIP outputs)
#' @param ncomp Max. number of latent variables to explore in the PLSDA analysis
#' @param auc_increment_threshold Choose the number of latent variables when the
#' AUC does not increment more than this threshold.
#'
#' @return Returns an object to be used with [nmr_data_analysis] to perform a (optionally
#' multilevel) PLS-DA model, using the area under the ROC curve as figure of
#' merit to determine the optimum number of latent variables.
#'
#'
#' @export
#' @examples
#' method <- plsda_auroc_vip_method(3)
#'
plsda_auroc_vip_method <- function(ncomp, auc_increment_threshold = 0.05) {
    new_nmr_data_analysis_method(
        train_evaluate_model = callback_plsda_auroc_vip,
        train_evaluate_model_params_inner = list(
            ncomp = ncomp,
            return_model = FALSE,
            return_auroc = TRUE,
            return_auroc_full = FALSE,
            return_vip = FALSE
        ),
        choose_best_inner = fun_choose_best_ncomp_auc_threshold(auc_threshold = auc_increment_threshold),
        train_evaluate_model_params_outer = list(
            return_model = TRUE,
            return_auroc = TRUE,
            return_auroc_full = TRUE,
            return_vip = TRUE
        ),
        train_evaluate_model_digest_outer = callback_outer_cv_auroc_vip
    )
}


#' Compare PLSDA auroc VIP results
#'
#' @param ... Results of [nmr_data_analysis] to be combined. Give each result a name.
#'
#' @return A plot of the AUC for each method
#' @export
#' @examples
#' # Data analysis for a table of integrated peaks
#'
#' ## Generate an artificial nmr_dataset_peak_table:
#' ### Generate artificial metadata:
#' num_samples <- 32 # use an even number in this example
#' num_peaks <- 20
#' metadata <- data.frame(
#'     NMRExperiment = as.character(1:num_samples),
#'     Condition = rep(c("A", "B"), times = num_samples / 2)
#' )
#'
#' ### The matrix with peaks
#' peak_means <- runif(n = num_peaks, min = 300, max = 600)
#' peak_sd <- runif(n = num_peaks, min = 30, max = 60)
#' peak_matrix <- mapply(function(mu, sd) rnorm(num_samples, mu, sd),
#'     mu = peak_means, sd = peak_sd
#' )
#' colnames(peak_matrix) <- paste0("Peak", 1:num_peaks)
#'
#' ## Artificial differences depending on the condition:
#' peak_matrix[metadata$Condition == "A", "Peak2"] <-
#'     peak_matrix[metadata$Condition == "A", "Peak2"] + 70
#'
#' peak_matrix[metadata$Condition == "A", "Peak6"] <-
#'     peak_matrix[metadata$Condition == "A", "Peak6"] - 60
#'
#' ### The nmr_dataset_peak_table
#' peak_table <- new_nmr_dataset_peak_table(
#'     peak_table = peak_matrix,
#'     metadata = list(external = metadata)
#' )
#'
#' ## We will use a double cross validation, splitting the samples with random
#' ## subsampling both in the external and internal validation.
#' ## The classification model will be a PLSDA, exploring at maximum 3 latent
#' ## variables.
#' ## The best model will be selected based on the area under the ROC curve
#' methodology <- plsda_auroc_vip_method(ncomp = 1)
#' model1 <- nmr_data_analysis(
#'     peak_table,
#'     y_column = "Condition",
#'     identity_column = NULL,
#'     external_val = list(iterations = 1, test_size = 0.25),
#'     internal_val = list(iterations = 1, test_size = 0.25),
#'     data_analysis_method = methodology
#' )
#'
#' methodology2 <- plsda_auroc_vip_method(ncomp = 2)
#' model2 <- nmr_data_analysis(
#'     peak_table,
#'     y_column = "Condition",
#'     identity_column = NULL,
#'     external_val = list(iterations = 1, test_size = 0.25),
#'     internal_val = list(iterations = 1, test_size = 0.25),
#'     data_analysis_method = methodology2
#' )
#'
#' plsda_auroc_vip_compare(model1 = model1, model2 = model2)
#'
plsda_auroc_vip_compare <- function(...) {
    dots <- list(...)
    class_compare <- names(dots)
    if (is.null(class_compare) || any(nchar(class_compare) == 0)) {
        stop("All arguments should be named")
    }

    auroc_tables <- dots %>%
        purrr::map("outer_cv_results_digested") %>%
        purrr::map("auroc") %>%
        purrr::map2(class_compare, function(auroc, group_name) {
            auroc %>%
                dplyr::select("auc") %>%
                dplyr::mutate(Group = !!group_name)
        })

    toplot <- do.call(rbind, auroc_tables)
    ggplot2::ggplot(toplot) +
        ggplot2::geom_boxplot(ggplot2::aes(
            x = .data$Group,
            y = .data$auc,
            fill = .data$Group
        ),
        show.legend = FALSE
        ) +
        ggplot2::scale_x_discrete(name = "Model") +
        ggplot2::scale_y_continuous(name = "Area under ROC")
}

#' Plot PLSDA predictions
#'
#' @param model A plsda model
#' @param newdata newdata to predict, if not included model$X_test will be used
#' @param plot A boolean that indicate if results are plotted or not
#'
#' @return A plot of the samples or a ggplot object
#' @importFrom stats predict
#' @importFrom mixOmics mixOmics
#' @export
#' @examples
#' #' # Data analysis for a table of integrated peaks
#'
#' ## Generate an artificial nmr_dataset_peak_table:
#' ### Generate artificial metadata:
#' num_samples <- 32 # use an even number in this example
#' num_peaks <- 20
#' metadata <- data.frame(
#'     NMRExperiment = as.character(1:num_samples),
#'     Condition = rep(c("A", "B"), times = num_samples / 2)
#' )
#'
#' ### The matrix with peaks
#' peak_means <- runif(n = num_peaks, min = 300, max = 600)
#' peak_sd <- runif(n = num_peaks, min = 30, max = 60)
#' peak_matrix <- mapply(function(mu, sd) rnorm(num_samples, mu, sd),
#'     mu = peak_means, sd = peak_sd
#' )
#' colnames(peak_matrix) <- paste0("Peak", 1:num_peaks)
#'
#' ## Artificial differences depending on the condition:
#' peak_matrix[metadata$Condition == "A", "Peak2"] <-
#'     peak_matrix[metadata$Condition == "A", "Peak2"] + 70
#'
#' peak_matrix[metadata$Condition == "A", "Peak6"] <-
#'     peak_matrix[metadata$Condition == "A", "Peak6"] - 60
#'
#' ### The nmr_dataset_peak_table
#' peak_table <- new_nmr_dataset_peak_table(
#'     peak_table = peak_matrix,
#'     metadata = list(external = metadata)
#' )
#'
#' ## We will use a double cross validation, splitting the samples with random
#' ## subsampling both in the external and internal validation.
#' ## The classification model will be a PLSDA, exploring at maximum 3 latent
#' ## variables.
#' ## The best model will be selected based on the area under the ROC curve
#' methodology <- plsda_auroc_vip_method(ncomp = 1)
#' model <- nmr_data_analysis(
#'     peak_table,
#'     y_column = "Condition",
#'     identity_column = NULL,
#'     external_val = list(iterations = 1, test_size = 0.25),
#'     internal_val = list(iterations = 1, test_size = 0.25),
#'     data_analysis_method = methodology
#' )
#'
#' # plot_plsda_samples(model$outer_cv_results[[1]]$model)
#'
plot_plsda_samples <- function(model, newdata = NULL, plot = TRUE) {
    # Predictions of test set
    if (is.null(newdata)) {
        predictions <- predict(model, newdata = model$X_test)
    } else {
        predictions <- predict(model, newdata = newdata)
    }

    # Individuals plot
    if (model$ncomp == 1) {
        # This is needed if the model only have one component
        # Hidding the plot
        t <- tempfile()
        pdf(file = t)
        ploty <- mixOmics::plotIndiv(model, comp = c(1, 1))
        dev.off()
        file.remove(t)

        tr_data <- data.frame(
            x = ploty$graph$data$x,
            label = paste("train ", ploty$graph$data$group)
        )
        te_data <- data.frame(
            x = predictions$variates[, 1],
            label = paste("test ", model$Y_test)
        )

        plsda_plot <- ggplot2::ggplot(data = tr_data, ggplot2::aes(.data[["x"]],
            fill = .data[["label"]]
        )) +
            ggplot2::geom_histogram(
                alpha = .5, bins = 10,
                position = "identity"
            ) +
            ggplot2::geom_histogram(
                data = te_data,
                ggplot2::aes(color = .data[["label"]]),
                fill = "white",
                alpha = 0.1,
                position = "identity",
                bins = 10
            ) +
            ggplot2::ggtitle("PLS-DA") +
            ggplot2::labs(x = ploty$graph$labels$x) +
            ggplot2::theme_bw()
    } else {
        # Hidding the plot
        t <- tempfile()
        pdf(file = t)
        ploty <- mixOmics::plotIndiv(model)
        dev.off()
        file.remove(t)

        tr_y <- ploty$graph$data$y
        te_y <- predictions$variates[, 2]


        tr_data <- data.frame(
            x = ploty$graph$data$x,
            y = tr_y,
            label = ploty$graph$data$group,
            group = "train "
        )
        te_data <- data.frame(
            x = predictions$variates[, 1],
            y = te_y,
            label = model$Y_test,
            group = "test "
        )
        data <- rbind(tr_data, te_data)

        plsda_plot <- ggplot2::ggplot(
            data = data,
            ggplot2::aes(
                shape = .data[["group"]],
                col = .data[["label"]]
            )
        ) +
            ggplot2::geom_hline(
                yintercept = 0, linetype = "dashed",
                color = "black", size = 0.5
            ) +
            ggplot2::geom_vline(
                xintercept = 0, linetype = "dashed",
                color = "black", size = 0.5
            ) +
            ggplot2::geom_point(ggplot2::aes(.data[["x"]], .data[["y"]]), size = 1.5) +
            ggplot2::ggtitle("PLS-DA") +
            ggplot2::labs(
                y = ploty$graph$labels$y,
                x = ploty$graph$labels$x
            ) +
            ggplot2::theme_bw()
    }
    if (plot) {
        plsda_plot
    } else {
        return(plsda_plot)
    }
}

#' Multi PLDSA model plot predictions
#'
#' @param model A nmr_data_analysis_model
#' @param plot A boolean that indicate if results are plotted or not
#'
#' @return A plot of the results or a ggplot object
#' @importFrom stats predict
#' @importFrom mixOmics mixOmics
#' @importFrom grDevices dev.off
#' @importFrom grDevices pdf
#' @export
#' @examples
#' #' # Data analysis for a table of integrated peaks
#'
#' ## Generate an artificial nmr_dataset_peak_table:
#' ### Generate artificial metadata:
#' num_samples <- 32 # use an even number in this example
#' num_peaks <- 20
#' metadata <- data.frame(
#'     NMRExperiment = as.character(1:num_samples),
#'     Condition = rep(c("A", "B"), times = num_samples / 2)
#' )
#'
#' ### The matrix with peaks
#' peak_means <- runif(n = num_peaks, min = 300, max = 600)
#' peak_sd <- runif(n = num_peaks, min = 30, max = 60)
#' peak_matrix <- mapply(function(mu, sd) rnorm(num_samples, mu, sd),
#'     mu = peak_means, sd = peak_sd
#' )
#' colnames(peak_matrix) <- paste0("Peak", 1:num_peaks)
#'
#' ## Artificial differences depending on the condition:
#' peak_matrix[metadata$Condition == "A", "Peak2"] <-
#'     peak_matrix[metadata$Condition == "A", "Peak2"] + 70
#'
#' peak_matrix[metadata$Condition == "A", "Peak6"] <-
#'     peak_matrix[metadata$Condition == "A", "Peak6"] - 60
#'
#' ### The nmr_dataset_peak_table
#' peak_table <- new_nmr_dataset_peak_table(
#'     peak_table = peak_matrix,
#'     metadata = list(external = metadata)
#' )
#'
#' ## We will use a double cross validation, splitting the samples with random
#' ## subsampling both in the external and internal validation.
#' ## The classification model will be a PLSDA, exploring at maximum 3 latent
#' ## variables.
#' ## The best model will be selected based on the area under the ROC curve
#' methodology <- plsda_auroc_vip_method(ncomp = 1)
#' model <- nmr_data_analysis(
#'     peak_table,
#'     y_column = "Condition",
#'     identity_column = NULL,
#'     external_val = list(iterations = 2, test_size = 0.25),
#'     internal_val = list(iterations = 2, test_size = 0.25),
#'     data_analysis_method = methodology
#' )
#'
#' # plot_plsda_multimodel(model)
#'
plot_plsda_multimodel <- function(model, plot = TRUE) {
    n_models <- length(model$outer_cv_results)
    min_ncomp <- model$outer_cv_results[[1]]$model$ncomp
    for (n in seq_len(n_models)) {
        if (model$outer_cv_results[[n]]$model$ncomp < min_ncomp) {
            min_ncomp <- model$outer_cv_results[[n]]$model$ncomp
        }
    }

    tr_data <- data.frame()
    te_data <- data.frame()
    # Hidding the plots
    t <- tempfile()
    pdf(file = t)
    for (i in seq_len(n_models)) {
        # Predictions of test set
        predictions <- predict(model$outer_cv_results[[i]]$model,
            newdata = model$outer_cv_results[[i]]$model$X_test
        )
        # Individuals plot
        if (min_ncomp == 1) {
            # This is needed if the model only have one component
            ploty <- mixOmics::plotIndiv(model$outer_cv_results[[i]]$model, comp = c(1, 1))
            tr_data <- rbind(tr_data, data.frame(
                x = ploty$graph$data$x,
                label = paste("train ", ploty$graph$data$group)
            ))
            te_data <- rbind(te_data, data.frame(
                x = predictions$variates[, 1],
                label = paste("test ", model$outer_cv_results[[i]]$model$Y_test)
            ))
        } else {
            ploty <- mixOmics::plotIndiv(model$outer_cv_results[[i]]$model)
            tr_y <- ploty$graph$data$y
            te_y <- predictions$variates[, 2]
            tr_data <- rbind(tr_data, data.frame(
                x = ploty$graph$data$x,
                y = tr_y,
                label = ploty$graph$data$group,
                group = "train "
            ))
            te_data <- rbind(te_data, data.frame(
                x = predictions$variates[, 1],
                y = te_y,
                label = model$outer_cv_results[[i]]$model$Y_test,
                group = "test "
            ))
        }
    }
    dev.off()
    file.remove(t)

    # Individuals plot
    if (min_ncomp == 1) {
        # This is needed if the model only have one component
        plsda_plot <- ggplot2::ggplot(data = tr_data, ggplot2::aes(.data[["x"]], fill = .data[["label"]])) +
            ggplot2::geom_histogram(
                alpha = .5, bins = 10,
                position = "identity"
            ) +
            ggplot2::geom_histogram(
                data = te_data,
                ggplot2::aes(color = .data[["label"]]),
                fill = "white",
                alpha = 0.1,
                position = "identity",
                bins = 10
            ) +
            ggplot2::ggtitle("PLS-DA") +
            ggplot2::labs(x = "Latent variable 1") +
            ggplot2::theme_bw()
    } else {
        data <- rbind(tr_data, te_data)
        plsda_plot <- ggplot2::ggplot(
            data = data,
            ggplot2::aes(
                shape = .data[["group"]],
                col = .data[["label"]]
            )
        ) +
            ggplot2::geom_hline(
                yintercept = 0, linetype = "dashed",
                color = "black", size = 0.5
            ) +
            ggplot2::geom_vline(
                xintercept = 0, linetype = "dashed",
                color = "black", size = 0.5
            ) +
            ggplot2::geom_point(ggplot2::aes(.data[["x"]], .data[["y"]]), size = 1.5) +
            ggplot2::ggtitle("PLS-DA") +
            ggplot2::labs(
                y = "Latent variable 2",
                x = "Latent variable 1"
            ) +
            ggplot2::theme_bw()
    }
    if (plot) {
        plsda_plot
    } else {
        return(plsda_plot)
    }
}
