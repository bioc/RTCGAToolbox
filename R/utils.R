#' @importFrom GenomicRanges makeGRangesListFromDataFrame makeGRangesFromDataFrame
#' @importFrom SummarizedExperiment SummarizedExperiment
#' makeSummarizedExperimentFromDataFrame rowData<-
#' @importFrom DelayedArray DelayedArray
#' @importFrom RaggedExperiment RaggedExperiment
#' @importFrom S4Vectors SimpleList metadata metadata<- DataFrame mcols mcols<- splitAsList
#' @importFrom utils type.convert
#' @importFrom methods .hasSlot
#' @importFrom stringr str_extract
## Helper functions for data extraction
.getDataMatrix <- function(object) {
    getElement(object, "DataMatrix")
}

.getFilenames <- function(object) {
    getElement(object, "Filename")
}

## Standardize barcode format
.stdIDs <- function(sampleBarcode) {
    if (all(startsWith(sampleBarcode, "TCGA"))) {
        bcodeTest <- grepl("\\.", sample(sampleBarcode, 10L, replace = TRUE))
        if (all(bcodeTest))
            sampleBarcode <- gsub("\\.", "-", sampleBarcode)
        sampleBarcode <- toupper(sampleBarcode)
    }
    sampleBarcode
}

.standardizeBC <- function(x) {
    colnames(x) <- .stdIDs(colnames(x))
    return(x)
}

.getGISTIC <- function(x, type) {
    x <- getElement(x, type)
    if (!length(x))
        return(list())
    annoteCols <- !grepl("TCGA", names(x), ignore.case = TRUE)
    annoteRowDF <- x[, annoteCols, drop = FALSE]
    rows <- annoteRowDF[,
        grepl("gene|ranges", names(annoteRowDF), ignore.case = TRUE)]
    if (length(rows)) {
        if (as.logical(anyDuplicated(rows))) {
            uniq <- !duplicated(rows)
            rows <- rows[uniq]
            annoteRowDF <- annoteRowDF[uniq, ]
            x <- x[uniq, ]
        }
        rownames(annoteRowDF) <- rows
    }
    x <- x[, !annoteCols]
    x <- vapply(x, type.convert, numeric(nrow(x)))
    x <- .standardizeBC(x)
    if (identical(type, "Peaks") && length(rows)) {
        gist <- SummarizedExperiment(SimpleList(x),
            rowRanges = as(rows, "GRanges"))
        rownames(gist) <- rows
        mcols(gist) <- annoteRowDF
    } else {
        gist <- SummarizedExperiment(SimpleList(x), rowData = annoteRowDF)
    }
    return(gist)
}

.getMethyl <- function(x) {
    headers <- names(x)
    annote <- x[, !grepl("TCGA", headers)]
    isNumRow <- all(grepl("^[0-9]*$",
        sample(rownames(x), size = 100L, replace = TRUE)))
    if (isNumRow) {
        geneSymbols <- annote[, grep("symbol", names(annote),
            ignore.case = TRUE, value = TRUE)]
        rNames <- geneSymbols
    } else { rNames <- rownames(x) }
    dm <- data.matrix(x[, grepl("TCGA", names(x))])
    mode(dm) <- "numeric"
    rownames(dm) <- rNames
    dm <- .standardizeBC(dm)
    dm <- DelayedArray::DelayedArray(dm)
    SummarizedExperiment::SummarizedExperiment(dm, rowData = annote)
}

.removeShell <- function(x, type) {
    if (startsWith(type, "GISTIC"))
        type <- "GISTIC"
    getElement(x, type)
}

.findBuild <- function(fname, type = "UCSC") {
    pattrn <- switch(type, UCSC = "[Hh][Gg][0-9]{2}",
        NCBI = "[Gg][Rr][Cc][Hh][0-9]{2}")
    bno <- stringr::str_extract(fname, pattrn)
    if (!length(bno))
        NA_character_
    else
        bno
}

.nameClean <- function(x) {
    x <- gsub("human|hum|agilent", "", x)
    x <- gsub("transcriptome", "tx", x, ignore.case = TRUE)
    x <- gsub("methylation", "methyl", x, ignore.case = TRUE)
    x
}

.mergeNames <- function(platform, version) {
    plat <- Filter(function(x) { !is.na(x) && length(x) }, tolower(platform))
    plat <- plat[which.min(nchar(plat))]
    if (!length(version))
        return(plat)
    ver <- tolower(version)
    logRM <- ver %in% plat
    version <- version[!logRM]
    relNames <- c(plat, version)
    if (length(plat) > 1L) {
        warning("Multiple platform names found, taking first one")
        plat <- plat[[1L]]
    }
    if (length(plat) && any(grepl(plat, tolower(version)))) {
        keep <- grepl("[0-9]{2}$", relNames, ignore.case = TRUE)
        result <- relNames[keep]
    } else if (length(version) > 1L) {
        result <- paste(toupper(plat), paste0(version, collapse = "_"),
                        sep = "_")
    } else if (length(version)) {
        result <- paste(toupper(plat), version, sep = "_")
    } else {
        result <- ""
    }
    return(result)
}

.searchPlatform <- function(x) {
    brokenUP <- unlist(strsplit(x, "_"))
    brokenUP <- Filter(function(y) nchar(y) != 0L, brokenUP)
    platNumExp <- "[0-9]k$|[0-9]a$|450$|27$|ht|hg"
    namePlat <- unique(grep("cgh|mirna|meth|huex|^trans|illu", brokenUP,
        ignore.case = TRUE, value = TRUE))
    namePlat <- .nameClean(namePlat)
    vers <- grep(platNumExp, brokenUP, ignore.case = TRUE, value = TRUE)
    vers <- .nameClean(vers)
    result <- .mergeNames(namePlat, vers)
    return(result)
}

#' @importFrom methods is
.unNestList <- function(x) {
    suppclasses <- all(vapply(x, function(y) {
        any(is(y, "FirehosemRNAArray"), is(y, "FirehoseCGHArray"),
            is(y, "FirehoseMethylationArray")) },
        logical(1L)))
    if (suppclasses) {
        x <- lapply(x, function(y) {
            fname <- .getFilenames(y)
            platform <- .searchPlatform(fname)
            build <- .findBuild(fname)
            y <- .getDataMatrix(y)
            ## Use DataFrame for metadata
            y <- DataFrame(y)
            metadata(y) <- list(filename = fname, build = build,
                platform = platform)
            return(y)
        })
        if (length(x) > 1L) {
            platNames <- vapply(x, function(y) {
                metadata(y)[["platform"]] }, character(1L))
            platNames <- gsub("human|hum|agilent", "", platNames)
            names(x) <- platNames
            if (anyDuplicated(platNames))
                x <- .mergePlatforms(x)
            names(x) <- make.unique(names(x), sep = "_")
        } else if (length(x) == 1L) { x <- x[[1L]] }
    }
    return(x)
}

.fileSelect <- function() {
    g <- readline(
        paste0("The selected data type has more than one",
               "file available.\nPlease select the desired file.",
               "\n(Enter 0 for the first file with the most number of samples)\n_"))
    g <- suppressWarnings(as.integer(g))
    if(is.na(g)){
        stop("Your selection must be an integer!")
    } else {
        return(g)
    }
}

.findCol <- function(x, colname) {
    if (!is.character(colname))
        stop("<internal> colname is not character")
    dataNames <- tolower(gsub("[^A-Za-z0-9]", "", names(x)))
    colname <- tolower(gsub("[^A-Za-z0-9]", "", colname))
    foundInData <- dataNames %in% colname
    if (sum(foundInData) > 1L)
        foundInData <- which.max(foundInData)
    if (!sum(foundInData))
        return(character(0L))
    names(x)[foundInData]
}

.hasInfo <- function(x, info = "NCBI_Build") {
    ## check "Hugo_Symbol" also possible
    buildInfo <- .findCol(x, info)
    as.logical(length(buildInfo))
}

.TCGAcols <- function(df) {
    apply(df, 2L, function(col) {
        all(startsWith(col, "TCGA"))
    })
}

.findUniqueAnnoCol <-
    function(df, annoCol = c("Hugo_Symbol", "Entrez_Gene_Id"))
{
    resname <- unlist(lapply(annoCol, function(anno) {
        annoName <- .findCol(df, anno)
        if (!length(annoName)) {
            character(0L)
        } else {
            annos <- df[[annoName]]
            if (identical(length(annos), length(unique(annos))))
                annoName
            else
                character(0L)
        }
    }))
    resname <- Filter(nchar, resname)
    if (length(resname) > 1L)
        resname[[1L]]
    else
        resname
}

.setAnnoRows <- function(df, rowAnnotation = c("Hugo_Symbol", "Entrez_Gene_Id"))
{
    annoName <- .findUniqueAnnoCol(df, rowAnnotation)
    if (length(annoName)) {
        annos <- df[[annoName]]
        rownames(df) <- annos
    }
    df
}

.validateNCBI <- function(bvec) {
    bnum <- unique(bvec)
    if (length(bnum) > 1L)
        stop("Inconsistent build numbers found")
    bnum
}

.standardstrand <- function(strandv) {
    strandv <- gsub("null", "*", strandv, ignore.case = TRUE)
    isnullna <- is.null(strandv) | is.na(strandv)
    strandv[isnullna] <- "*"
    strandv[strandv == 1] <- "+"
    strandv[strandv == -1] <- "-"
    strandv
}

.standardizeStrand <- function(x, strandcol) {
    x[[strandcol]] <- .standardstrand(x[[strandcol]])
    x
}

.getBuild <- function(x, type = "NCBI_Build") {
    binf <- .hasInfo(x, type)
    if (binf) {
        BCOL <- .findCol(x, type)
        build <- TCGAutils::uniformBuilds(x[[BCOL]])
        if (length(build) > 1L)
           build <- .validateNCBI(build)
        return(as.character(build))
    } else {
        NA_character_
    }
}

.ansRangeNames <- function(x) {
    if (is(x, "list")) { return(list()) }
    granges_cols <- TCGAutils::findGRangesCols(names(x))
    fielders <- list(seqnames.field = "seqnames", start.field = "start",
        end.field = "end", strand.field = "strand")
    Fargs <- lapply(fielders, function(name) { names(x)[granges_cols[[name]]] })
    strd <- Fargs[["strand.field"]]
    allStrandNA <- if (!is.na(strd)) all(is.na(x[[strd]])) else TRUE
    Fargs[["ignore.strand"]] <- allStrandNA
    Filter(function(g) {!is.na(g)}, Fargs)
}

#' @importFrom stats na.omit
.findSampleCol <-
    function(x, sampcols = c("tumor_sample_barcode", "sample", "id"))
{
    sampcols <- tolower(sampcols)
    tsb <- na.omit(match(sampcols, tolower(names(x))))
    if (length(tsb)) {
        names(x)[tsb[[1L]]]
    } else {
        NA_character_
    }
}

.hasConsistentRanges <- function(object) {
    primary <- .findSampleCol(object)
    if (is.na(primary)) {
        return(FALSE)
    }
    ansRanges <- .ansRangeNames(object)
    # check if all ranges are of the same length
    grl <- do.call(.makeGRangesListFromDataFrame,
        c(list(df = object, split.field = primary), ansRanges))
    uniranges <- S4Vectors::isSingleInteger(unique(lengths(grl)))
    # then check if all ranges have same values
    if (!uniranges)
        return(FALSE)
    else
        all(vapply(grl[-1L], function(gr)
            S4Vectors::setequal(gr, grl[[1L]]), logical(1L))
        )
}

.hasRangeNames <- function(x) {
    if (is(x, "list")) { return(FALSE) }
    if (all(grepl("^TCGA", names(x)))) { return(FALSE) }
    if (!any(is.data.frame(x), is(x, "DataFrame"), is.matrix(x)))
        stop("(internal) 'x' must be rectangular")
    res <- is.na(TCGAutils::findGRangesCols(names(x)))
    if (any(res[c("seqnames", "start", "end")]))
        FALSE
    else
        !all(res)
}

.samplesAsCols <- function(x, sampleNames = character(0L)) {
    tcganames <- grepl("^TCGA", names(x), ignore.case = TRUE)
    sampleNames <- as.character(sampleNames)
    if (length(sampleNames))
        vapply(names(x), function(y) any(startsWith(y, sampleNames)),
            logical(1L))
    else
        tcganames
}

.hasExperimentData <- function(x, colnames = c("Hugo", "Entrez")) {
    anySamplesAsCols <- any(.samplesAsCols(x, colnames))
    sampcols <- na.omit(.findSampleCol(x))
    .hasRangeNames(x) || length(sampcols) || anySamplesAsCols
}

## Safe to assume equal number of ranges == equal ranges (?)
.makeSummarizedExperimentFromDataFrame <-
    function(df, ..., colnames = c("Hugo", "Entrez"))
{
    samplesAsCols <- .samplesAsCols(df, colnames)
    if (is(df, "DataFrame"))
        metadat <- metadata(df)
    if (any(samplesAsCols)) {
        rowData <- df[, !samplesAsCols, drop = FALSE]
    }
    df <- data.matrix(df[, samplesAsCols])

    df <- .standardizeBC(df)
    args <- list(...)
    names.field <- args[["names.field"]]
    if (is.null(names.field) || !length(names.field)) {
        df <- .setAnnoRows(df)
    } else {
        rownames(df) <- rowData[[names.field]]
    }
    ## Use "" instead of missing due to changes in SummarizedExperiment
    ## constructor
    if (any(is.na(rownames(df))))
        rownames(df)[is.na(rownames(df))] <- ""
    if (length(rowData))
    object <- SummarizedExperiment(assays = SimpleList(df),
        rowData = rowData)
    else
    object <- makeSummarizedExperimentFromDataFrame(df)
    if (length(metadat))
        metadata(object) <- metadat
    return(object)
}

.makeRangedSummarizedExperimentFromDataFrame <-
    function(df, ..., seqinfo = NULL, starts.in.df.are.0based = FALSE) {
    args <- list(...)
    build <- args[["build"]]
    names.field <- args[["names.field"]]
    if (is.null(names.field) || !length(names.field)) {
        df <- .setAnnoRows(df)
    } else {
        rownames(df) <- df[[names.field]]
    }
    metadat <- if (is(df, "DataFrame")) metadata(df) else list()
    split.field <- .findSampleCol(df)
    ansRanges <- .ansRangeNames(df)
    strictRanges <- Filter(function(x) !is.logical(x), ansRanges)
    RangeInfo <- c(strictRanges, list(split.field = split.field))
    numInfo <- df[, !(names(df) %in% RangeInfo)]
    numAssays <- ncol(numInfo)
    nameAssays <- names(numInfo)
    if (is(df, "DataFrame"))
        numInfo <- S4Vectors::splitAsList(numInfo, df[[split.field]])
    else
        numInfo <- base::split(numInfo, df[[split.field]])
    countList <- vector(mode = "list", length = numAssays)
    for (i in seq_len(numAssays)) {
        countList[[i]] <- do.call(cbind, lapply(numInfo, `[[`, i))
    }
    names(countList) <- nameAssays
    rowRanges <- do.call(.makeGRangesListFromDataFrame,
        c(list(df = df[, unlist(RangeInfo)], split.field = split.field,
            names.field = names.field), ansRanges)
    )
    if (!is.null(build))
        GenomeInfoDb::genome(rowRanges) <- build
    ## All row ranges the same, take first one
    newSE <- SummarizedExperiment(assays = SimpleList(countList),
        rowRanges = rowRanges[[1L]])
    metadata(newSE) <- metadat
    return(newSE)
}

.removeNASeq <- function(x, colname) {
    nas <- is.na(x[[colname]])
    if (any(nas))
        message("Removing ", sum(nas), " rows where 'is.na(seqnames.field)'")
    x[!is.na(x[[colname]]), ]
}

.makeRaggedExperimentFromDataFrame <- function(df, ...) {
    args <- list(...)
    build <- args[["build"]]
    names.field <- args[["names.field"]]
    if (is.null(names.field) || !length(names.field))
        df <- .setAnnoRows(df)
    metadat <- if (is(df, "DataFrame")) { metadata(df) } else { list() }
    split.field <- args[["split.field"]]
    if (is.null(split.field))
        split.field <- .findSampleCol(df)

    ansRanges <- .ansRangeNames(df)
    rangeInfo <- c(ansRanges, list(split.field = split.field,
        names.field = names.field))

    df <- .removeNASeq(df, ansRanges[["seqnames.field"]])
    if (!is.null(ansRanges[["strand.field"]]) || length(ansRanges[["strand.field"]]))
        df <- .standardizeStrand(df, ansRanges[["strand.field"]])
    dropIdx <- .omitAdditionalIdx(df, ansRanges)
    if (length(dropIdx))
        df <- df[, -dropIdx]

    newGRL <- do.call(.makeGRangesListFromDataFrame,
        args = c(list(df = df, keep.extra.columns = TRUE), rangeInfo))
    if (!is.null(build))
        GenomeInfoDb::genome(newGRL) <- build
    newRE <- RaggedExperiment::RaggedExperiment(newGRL)
    metadata(newRE) <- metadat
    return(newRE)
}

.rmNAse <- function(x, ansranges) {
    naRanges <- .missingRanges(x, ansranges)
    x[!naRanges, ]
}

.missingRanges <- function(x, ansranges) {
    startf <- ansranges[["start.field"]]
    endf <- ansranges[["end.field"]]
    is.na(x[[startf]]) | is.na(x[[endf]])
}

.makeGRangesFromDataFrame <- function(df, ...) {
    args <- list(...)
    build <- args[["build"]]
    metadat <- if (is(df, "DataFrame")) { metadata(df) } else { list() }
    ansRanges <- .ansRangeNames(df)
    df <- .rmNAse(df, ansRanges)
    dropIdx <- .omitAdditionalIdx(df, ansRanges)
    if (length(dropIdx))
        df <- df[, -dropIdx]
    df <- .setAnnoRows(df)
    newgr <- do.call(GenomicRanges::makeGRangesFromDataFrame,
        args = c(list(df = df, keep.extra.columns = TRUE), ansRanges))
    if (!is.null(build))
        GenomeInfoDb::genome(newgr) <- build
    metadata(newgr) <- metadat
    return(newgr)
}

## replacing .makeGRangesFromDataFrame in GenomicRanges
.makeGRangesListFromDataFrame <-
    function(df, split.field = NULL, names.field = NULL, ...)
{
    splitIdx <- namesIdx <- integer()
    if (!is.null(split.field)) {
        if (!isSingleString(split.field))
            stop("'split.field' must be a single string")
        splitIdx <- which(names(df) %in% split.field)
        if (!length(splitIdx))
            stop("'split.field' is not in 'names(df)'")
        if (length(splitIdx) > 1L)
            stop("'split.field' matched more than one 'names(df)'")
        splitField <- df[[split.field]]
    }
    else splitField <- seq_len(nrow(df))
    if (!is.null(names.field)) {
        if (!isSingleString(names.field))
            stop("'names.field' must be a single string")
        namesIdx <- which(names(df) %in% names.field)
        if (!length(namesIdx))
            stop("'names.field' is not found in 'names(df)'")
        if (length(namesIdx) > 1L)
            stop("'names.field' matched more than one 'names(df)'")
        namesField <- df[[names.field]]
    }
    else namesField <- NULL
    if (length(c(splitIdx, namesIdx)))
        df <- df[, -c(splitIdx, namesIdx)]

    ansRanges <- .ansRangeNames(df)
    NAranges <- .missingRanges(df, ansRanges)
    df <- df[!NAranges, ]
    splitField <- splitField[!NAranges]

    gr <- .makeGRangesFromDataFrame(df, ...)
    names(gr) <- namesField
    S4Vectors::split(gr, splitField)
}


.omitAdditionalIdx <- function(object, rangeNames) {
    rangeNames <- Filter(function(x) !is.logical(x), rangeNames)
    rangeIdx <- match(rangeNames, names(object))
    omitAdditional <- c("seqnames", "seqname", "chromosome", "chrom",
        "chromosome_name", "ranges", "seqlevels", "seqlengths", "seq_id",
        "iscircular", "start", "end", "strand", "width", "element", "chr")
    rmIdx <- which(tolower(names(object)) %in% omitAdditional)
    setdiff(rmIdx, rangeIdx)
}

.runOnDupElements <- function(vect, FUN, ...) {
    vnames <- names(vect)
    uvect <- unique(vnames)
    dups <- stats::setNames(nm = vnames[duplicated(vnames)])
    nonDups <- !vnames %in% dups
    cdups <- vector("list", length(dups))
    for (d in dups) {
        cdups[[d]] <- FUN(vect[vnames %in% d], ...)
    }
    res <- c(cdups[dups], vect[nonDups])
    res[order(match(names(res), uvect))]
}

.mergePlatforms <- function(x) {
    .runOnDupElements(x, function(dup, ...) {
        nrows <- vapply(dup, nrow, integer(1L))
        if (length(unique(nrows)) == 1L) {
            mets <- lapply(dup, metadata)
            meta <- split(
                unlist(mets, use.names = FALSE), names(unlist(unname(mets)))
            )
            dup <- do.call(cbind, unname(dup))
            metadata(dup) <- meta
        }
        dup
    })
}

## Genome build from FILENAME
## RSE helper function from genome symbols to build (RNASeq, ExpSets)

.extractList <- function(object, type) {
    for (i in seq_along(object))
        object[[i]] <- biocExtract(object[[i]], type)
    return(object)
}
