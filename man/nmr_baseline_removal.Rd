% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/nmr_baseline_removal.R
\name{nmr_baseline_removal}
\alias{nmr_baseline_removal}
\title{Baseline Removal NMR}
\usage{
nmr_baseline_removal(nmr_dataset, lambda = 6, p = 0.05, maxit = 20)
}
\arguments{
\item{nmr_dataset}{An \link{nmr_dataset_1D}.}

\item{lambda}{ 2nd derivative constraint }

\item{p}{ Weighting of positive residuals }

\item{maxit}{ Maximum number of iterations }
}
\value{
The same \link{nmr_dataset_1D} object after baseline removal.
}
\description{
Removes the baseline on an \link{nmr_dataset_1D} object, using \link[baseline:baseline.als]{baseline::baseline.als}.
}
\examples{
dataset_1D <- nmr_dataset_load(system.file("extdata", "nmr_dataset.rds", package = "AlpsNMR"))
dataset_no_base_line <- nmr_baseline_removal(dataset_1D, lambda = 6, p = 0.01)

}
\seealso{
\link[baseline:baseline.als]{baseline::baseline.als}

Other baseline removal functions: 
\code{\link{nmr_baseline_estimation}()}
}
\concept{baseline removal functions}
