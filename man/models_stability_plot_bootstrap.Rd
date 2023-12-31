% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/nmr_data_analysis.R
\name{models_stability_plot_bootstrap}
\alias{models_stability_plot_bootstrap}
\title{Models stability plot}
\usage{
models_stability_plot_bootstrap(bp_results)
}
\arguments{
\item{bp_results}{bp_kfold_VIP_analysis results}
}
\value{
A plot of models stability
}
\description{
Plot stability among models of the external cross validation
}
\examples{
# Data analysis for a table of integrated peaks

## Generate an artificial nmr_dataset_peak_table:
### Generate artificial metadata:
num_samples <- 64 # use an even number in this example
num_peaks <- 20
metadata <- data.frame(
    NMRExperiment = as.character(1:num_samples),
    Condition = rep(c("A", "B"), times = num_samples / 2)
)

### The matrix with peaks
peak_means <- runif(n = num_peaks, min = 300, max = 600)
peak_sd <- runif(n = num_peaks, min = 30, max = 60)
peak_matrix <- mapply(function(mu, sd) rnorm(num_samples, mu, sd),
    mu = peak_means, sd = peak_sd
)
colnames(peak_matrix) <- paste0("Peak", 1:num_peaks)

## Artificial differences depending on the condition:
peak_matrix[metadata$Condition == "A", "Peak2"] <-
    peak_matrix[metadata$Condition == "A", "Peak2"] + 70

peak_matrix[metadata$Condition == "A", "Peak6"] <-
    peak_matrix[metadata$Condition == "A", "Peak6"] - 60

### The nmr_dataset_peak_table
peak_table <- new_nmr_dataset_peak_table(
    peak_table = peak_matrix,
    metadata = list(external = metadata)
)

## We will use bootstrap and permutation method for VIPs selection
## in a a k-fold cross validation
# bp_results <- bp_kfold_VIP_analysis(peak_table, # Data to be analized
#                           y_column = "Condition", # Label
#                           k = 3,
#                           nbootstrap = 10)

# message("Selected VIPs are: ", bp_results$importarn_vips)

# models_stability_plot_bootstrap(bp_results)

}
