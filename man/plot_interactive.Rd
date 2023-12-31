% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/plots.R
\name{plot_interactive}
\alias{plot_interactive}
\title{Plots in WebGL}
\usage{
plot_interactive(plt, html_filename, overwrite = NULL)
}
\arguments{
\item{plt}{A plot created with plotly or ggplot2}

\item{html_filename}{The file name where the plot will be saved}

\item{overwrite}{Overwrite the lib/ directory (use \code{NULL} to prompt the user)}
}
\value{
The html_filename
}
\description{
Plots in WebGL
}
\examples{
dir_to_demo_dataset <- system.file("dataset-demo", package = "AlpsNMR")
dataset <- nmr_read_samples_dir(dir_to_demo_dataset)
dataset_1D <- nmr_interpolate_1D(dataset, axis = c(min = -0.5, max = 10, by = 2.3E-4))
# plot <- plot(dataset_1D)
# html_plot_interactive <- plot_interactive(plot, "html_plot_interactive.html")

}
\seealso{
Other plotting functions: 
\code{\link{plot.nmr_dataset_1D}()}
}
\concept{plotting functions}
