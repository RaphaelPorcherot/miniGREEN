#!/usr/bin/env Rscript
# ==============================================================================
# extract.r — turn Vensim text exports into the CSV files under input/
#
#   Rscript tool/extract.r            # every row of the manifest
#   Rscript tool/extract.r R_a_ii     # one variable
#   Rscript tool/extract.r --check    # parse and compare, write nothing
#
# What to extract, and how, is declared in tool/manifest.csv: one row per
# variable, giving its Vensim name, its R name, which table it belongs to, its
# dimensions and any modality renaming. Nothing is asked interactively — an
# import that cannot be replayed is an import nobody can check.
#
# --check re-parses everything and compares against what is already in input/,
# without writing. That is the regression test for this tool.
# ==============================================================================

suppressPackageStartupMessages({
  library(here)
})
source(here::here("src", "paths.r"))
source(file.path(DIR_TOOL, "extract-vensim.r"))

# the dimensions, straight from the model so that the two cannot drift apart
local({
  lines <- readLines(path_prep("2-structure.r"))
  from <- grep("^# BEGIN Dimensions", lines)
  to <- grep("^# END Dimensions", lines)
  suppressPackageStartupMessages({
    library(dplyr)
  })
  eval(parse(text = lines[(from + 1):(to - 1)]), envir = globalenv())
})

DEFAULT_REGION <- "IT"

# ------------------------------------------------------------------------------

## Modalities of a dimension, R-side. Accepts the capitalised template names and
## the lower-case names used in lookup files.
modalities <- function(dim) {
  key <- c(
    Industry = "industry",
    Cohort = "cohort",
    Gender = "gender",
    PopGroup = "pop_group",
    Skill = "skill",
    Status = "status",
    EnergySource = "energy_source",
    COICOP = "coicop",
    Technology = "technology",
    industry = "industry",
    gender = "gender",
    skill = "skill",
    coicop = "coicop",
    cohort = "cohort"
  )[[dim]]
  get(key, envir = globalenv())
}

## Where the CSV goes.
csv_path <- function(row) {
  file.path(DIR_INPUT, row$table, row$module, paste0(row$r_name, ".csv"))
}

## Keep a description that a human has edited, rather than overwriting it with
## the Vensim comment. R_a_ii is the example: its CSV explains that the value is
## the first period, not the period before, which Vensim does not say.
keep_description <- function(path, parsed) {
  if (file.exists(path)) {
    old <- read.csv(path, nrows = 1)$description
    if (length(old) && !is.na(old) && nzchar(old)) return(as.character(old))
  }
  if (is.na(parsed)) "" else parsed
}

# --- writers ------------------------------------------------------------------

build_1d <- function(v, dims, desc) {
  mods <- modalities(dims[1])
  if (length(v) != length(mods)) {
    stop(
      "expected ",
      length(mods),
      " values for ",
      dims[1],
      ", parsed ",
      length(v)
    )
  }
  d <- data.frame(
    description = "",
    region = DEFAULT_REGION,
    setNames(list(mods), dims[1]),
    value = v,
    stringsAsFactors = FALSE
  )
  d$description[1] <- desc
  d
}

## A TABBED ARRAY is a flat run of numbers filled row-major in the order Vensim
## declares its dimensions — which is not always the order of the R template.
## `declared` is read from the text; when it is the reverse of the manifest, the
## matrix is filled Vensim's way and then transposed.
build_2d <- function(v, dims, desc, declared = NULL) {
  rows <- modalities(dims[1])
  cols <- modalities(dims[2])
  if (length(v) != length(rows) * length(cols)) {
    stop(
      "expected ",
      length(rows) * length(cols),
      " values, parsed ",
      length(v)
    )
  }
  flip <- !is.null(declared) &&
    length(declared) == 2 &&
    !identical(declared, dims)
  m <- if (flip) {
    t(matrix(
      v,
      nrow = length(cols),
      ncol = length(rows),
      byrow = TRUE,
      dimnames = list(cols, rows)
    ))
  } else {
    matrix(
      v,
      nrow = length(rows),
      ncol = length(cols),
      byrow = TRUE,
      dimnames = list(rows, cols)
    )
  }
  d <- data.frame(
    description = "",
    region = DEFAULT_REGION,
    setNames(list(rows), dims[1]),
    m,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  d$description[1] <- desc
  d
}

## One constant list per slice. Which of the two dimensions the slice names
## belong to is worked out from the names themselves, not from the order they
## appear in — Vensim writes [EnergySource, Industry] where the R template is
## Industry x EnergySource.
##
## A slice holding a single value is Vensim shorthand for that value everywhere
## on the slice, and is broadcast.
build_slices <- function(df, dims, desc) {
  slices <- unique(df$slice)
  which_dim <- which(vapply(
    dims,
    function(d) all(slices %in% modalities(d)),
    logical(1)
  ))
  if (length(which_dim) != 1) {
    stop(
      "cannot tell which dimension the slices belong to: ",
      paste(slices, collapse = ", ")
    )
  }
  along_dim <- dims[-which_dim]
  rows <- modalities(along_dim)
  cols <- modalities(dims[which_dim])

  m <- matrix(
    0,
    nrow = length(rows),
    ncol = length(cols),
    dimnames = list(rows, cols)
  )
  for (s in slices) {
    v <- df$value[df$slice == s]
    if (length(v) == 1) {
      v <- rep(v, length(rows))
    } # Vensim shorthand
    if (length(v) != length(rows)) {
      stop(
        "slice ",
        s,
        ": ",
        length(v),
        " values for ",
        length(rows),
        " ",
        along_dim
      )
    }
    m[, s] <- v
  }
  # emit in the order the manifest declares
  if (which_dim == 1) {
    m <- t(m)
  }
  d <- data.frame(
    description = "",
    region = DEFAULT_REGION,
    setNames(list(rownames(m)), if (which_dim == 1) dims[2] else along_dim),
    m,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  d$description[1] <- desc
  d
}

## Cell-by-cell values, one file per modality of the last dimension. Where the
## R dimension is wider than the Vensim one — PopGroup has child and cap, skill
## does not — the missing modalities are written as zeros.
build_3d <- function(df, dims, desc) {
  rows <- modalities(dims[2])
  cols <- modalities(dims[3])
  slices <- modalities(dims[1])
  out <- list()
  for (s in slices) {
    sub <- df[df[[1]] == s, ]
    m <- matrix(
      0,
      nrow = length(rows),
      ncol = length(cols),
      dimnames = list(rows, cols)
    )
    for (k in seq_len(nrow(sub))) {
      m[sub[[2]][k], sub[[3]][k]] <- sub$value[k]
    }
    d <- data.frame(
      description = "",
      region = DEFAULT_REGION,
      setNames(list(rows), dims[2]),
      m,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    d$description[1] <- desc
    out[[s]] <- d
  }
  out
}

build_lookup <- function(df, desc) {
  d <- cbind(
    description = "",
    region = DEFAULT_REGION,
    df,
    stringsAsFactors = FALSE
  )
  d$description[1] <- desc
  d
}

# --- the runner ---------------------------------------------------------------

extract_one <- function(row, write = TRUE) {
  txt <- vensim_read(file.path(DIR_TOOL, row$source))
  dims <- if (nzchar(row$dimensions)) {
    trimws(strsplit(row$dimensions, ",")[[1]])
  } else {
    NULL
  }

  p <- vensim_parse(txt, dim_names = dims)
  if (is.data.frame(p$value)) {
    p$value <- apply_recode(p$value, row$recode)
  }

  path <- csv_path(row)
  desc <- keep_description(path, p$description)

  built <- if (row$table == "lookup") {
    build_lookup(p$value, desc)
  } else if (p$shape == "cells") {
    build_3d(p$value, dims, desc)
  } else if (p$shape == "slices") {
    build_slices(p$value, dims, desc)
  } else if (length(dims) == 2) {
    build_2d(p$value, dims, desc, declared = vensim_declared_dims(txt))
  } else {
    build_1d(p$value, dims, desc)
  }

  if (write) {
    if (is.data.frame(built)) {
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      write.csv(built, path, row.names = FALSE)
      message("  wrote ", sub(paste0(PROJECT_ROOT, "/"), "", path))
    } else {
      for (s in names(built)) {
        p2 <- sub("\\.csv$", paste0("_", s, ".csv"), path)
        dir.create(dirname(p2), recursive = TRUE, showWarnings = FALSE)
        write.csv(built[[s]], p2, row.names = FALSE)
        message("  wrote ", sub(paste0(PROJECT_ROOT, "/"), "", p2))
      }
    }
  }
  invisible(built)
}

args <- commandArgs(trailingOnly = TRUE)
check <- "--check" %in% args
selected <- setdiff(args, "--check")

manifest <- read.csv(
  file.path(DIR_TOOL, "manifest.csv"),
  stringsAsFactors = FALSE,
  colClasses = "character"
)
if (length(selected)) {
  manifest <- manifest[manifest$r_name %in% selected, ]
}
if (!nrow(manifest)) {
  stop(
    "Nothing selected. Known: ",
    paste(read.csv(file.path(DIR_TOOL, "manifest.csv"))$r_name, collapse = ", ")
  )
}

ok <- 0
for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, ]
  res <- tryCatch(
    {
      extract_one(row, write = !check)
      TRUE
    },
    error = function(e) {
      message("  FAILED ", row$r_name, ": ", conditionMessage(e))
      FALSE
    }
  )
  ok <- ok + res
}
message(if (check) "checked " else "extracted ", ok, " / ", nrow(manifest))
