% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/RTCGAToolbox-Class.R
\docType{class}
\name{FirehoseGISTIC-class}
\alias{FirehoseGISTIC-class}
\alias{isEmpty,FirehoseGISTIC-method}
\alias{updateObject,FirehoseGISTIC-method}
\title{An S4 class to store processed copy number data. (Data processed by using GISTIC2 algorithm)}
\usage{
\S4method{isEmpty}{FirehoseGISTIC}(x)

\S4method{updateObject}{FirehoseGISTIC}(object, ..., verbose = FALSE)
}
\arguments{
\item{x}{A FirehoseGISTIC class object}

\item{object}{A \code{FirehoseGISTIC} object}

\item{...}{additional arguments for updateObject}

\item{verbose}{logical (default FALSE) whether to print extra messages}
}
\description{
An S4 class to store processed copy number data. (Data processed by using GISTIC2 algorithm)
}
\section{Methods (by generic)}{
\itemize{
\item \code{isEmpty(FirehoseGISTIC)}: check whether the FirehoseGISTIC object has
data in it or not

\item \code{updateObject(FirehoseGISTIC)}: Update an old FirehoseGISTIC object to the most
recent API

}}
\section{Slots}{

\describe{
\item{\code{Dataset}}{Cohort name}

\item{\code{AllByGene}}{A data frame that stores continuous copy number}

\item{\code{ThresholdedByGene}}{A data frame for discrete copy number data}

\item{\code{Peaks}}{A data frame storing GISTIC peak data.
See \link{getGISTICPeaks}.}
}}

