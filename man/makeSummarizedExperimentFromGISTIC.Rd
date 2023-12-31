% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/makeSummarizedExperimentFromGISTIC.R
\name{makeSummarizedExperimentFromGISTIC}
\alias{makeSummarizedExperimentFromGISTIC}
\title{Create a SummarizedExperiment from FireHose GISTIC}
\usage{
makeSummarizedExperimentFromGISTIC(
  gistic,
  dataType = c("AllByGene", "ThresholdedByGene", "Peaks"),
  rownameCol = "Gene.Symbol",
  ...
)
}
\arguments{
\item{gistic}{A \link[RTCGAToolbox]{FirehoseGISTIC-class} object}

\item{dataType}{character(1) One of "ThresholdedByGene" (default),
"AllByGene", or "Peaks"}

\item{rownameCol}{character(1) The name of the column in the data to use as
rownames in the data matrix (default: 'Gene.Symbol'). The row names are
only set when the column name is found in the data and all values are
unique.}

\item{...}{Additional arguments passed to 'getGISTICPeaks'.}
}
\value{
A \code{SummarizedExperiment} object
}
\description{
Use the output of \code{getFirehoseData} to create a
\linkS4class{SummarizedExperiment}. This can be done for three types of
data, G-scores thresholded by gene, copy number by gene, and copy number by
peak regions.
}
\examples{

co <- getFirehoseData("COAD", clinical = FALSE, GISTIC = TRUE,
    destdir = tempdir())
makeSummarizedExperimentFromGISTIC(co, "AllByGene")

}
\author{
L. Geistlinger, M. Ramos
}
