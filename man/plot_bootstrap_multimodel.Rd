% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/nmr_data_analysis.R
\name{plot_bootstrap_multimodel}
\alias{plot_bootstrap_multimodel}
\title{Bootstrap plot predictions}
\usage{
plot_bootstrap_multimodel(bp_results, dataset, y_column, plot = TRUE)
}
\arguments{
\item{bp_results}{bp_kfold_VIP_analysis results}

\item{dataset}{An \link{nmr_dataset_family} object}

\item{y_column}{A string with the name of the y column (present in the
metadata of the dataset)}

\item{plot}{A boolean that indicate if results are plotted or not}
}
\value{
A plot of the results or a ggplot object
}
\description{
Bootstrap plot predictions
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

# plot_bootstrap_multimodel(bp_results, peak_table, "Condition")

}
