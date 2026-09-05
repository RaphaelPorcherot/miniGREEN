# ==============================================================================
# READING VENSIM TEXT
# ==============================================================================
#
# Pure parsing functions: text in, data frame out. No prompts, no file writing,
# no global state — so each can be run on a string and checked.
#
# The previous version of this lived in two Jupyter notebooks and asked the user
# questions through readline(): which dimension is which, what to rename. That
# made every import a one-off that could not be replayed or reviewed. What was
# being answered interactively is now a row in tool/manifest.csv.
#
# Six shapes turn up in the Vensim text. `vensim_parse()` recognises them.
#
#   1. TABBED ARRAY   name[d1,d2] = TABBED ARRAY( v <tab> v ... )
#   2. constant list  name[d1]    = v, v, v, ...
#   3. cell scalars   name[m1,m2,m3] = v ~~|      repeated, one line per cell
#   3b. slices        name[m1,ind]  = v, v, v ~~|  repeated, a list per slice
#   4. lookup 1D      name( [(x,y)-(x,y)], (x,y), (x,y), ... )
#   5. lookup indexed name[m1]( [range], (x,y), ... ) ~~|   repeated
#   6. WITH LOOKUP    name[m1,m2] = WITH LOOKUP( input, ([range],(x,y),...) ) ~~|
# ------------------------------------------------------------------------------

## Read a Vensim text export.
##
## A line ending in a backslash continues on the next one, so the two are joined
## with nothing between them — not with a newline. Vensim wraps anywhere,
## including inside a number or between the two halves of an (x, y) pair, so a
## newline left in the middle is a newline in the middle of a token.
vensim_read <- function(path) {
  lines <- readLines(path, warn = FALSE)
  out <- character(0); acc <- ""
  for (l in lines) {
    if (grepl("\\\\\\s*$", l)) {
      acc <- paste0(acc, sub("\\\\\\s*$", "", l))     # continues: no separator
    } else {
      out <- c(out, paste0(acc, l)); acc <- ""
    }
  }
  if (nzchar(acc)) out <- c(out, acc)
  paste(out, collapse = "\n")
}

## The description Vensim puts after the equation: ~ units ~ comment |
vensim_description <- function(txt) {
  m <- regmatches(txt, regexpr("~[^|]*\\|\\s*$", txt))
  if (!length(m)) return(NA_character_)
  d <- gsub("[~]", " ~ ", m)
  d <- gsub("[\n\t]+", " ", d)
  d <- gsub("\\s+", " ", d)
  trimws(gsub("^\\s*~\\s*", "", d))
}

## The dimensions as Vensim declares them, in Vensim's own order and names.
## `initial a ii[ind,toind]` gives c("Industry", "Industry"); `coef Ed to C nrg
## i[nrg,ind]` gives c("EnergySource", "Industry") — which is the reverse of the
## R template, and the reason this has to be read rather than assumed.
VENSIM_DIMS <- c(ind = "Industry", toind = "Industry", nrg = "EnergySource",
                 coicop = "COICOP", skill = "PopGroup", gender = "Gender",
                 cohorts = "Cohort", techn = "Technology", "nrg HH" = "EnergyUse")

vensim_declared_dims <- function(txt) {
  m <- regmatches(txt, regexpr("^[^=\\[]*\\[([^]]*)\\]", txt))
  if (!length(m)) return(NULL)
  toks <- trimws(strsplit(gsub("^[^\\[]*\\[|\\]$", "", m), ",")[[1]])
  out <- unname(VENSIM_DIMS[toks])
  if (anyNA(out)) return(NULL)             # a dimension we do not map: say nothing
  out
}

## Which of the six shapes is this?
vensim_shape <- function(txt) {
  if (grepl("TABBED ARRAY", txt))                              return("tabbed")
  if (grepl("WITH LOOKUP", txt))                               return("with_lookup")
  if (grepl("\\[\\(-?[0-9.e+-]+,", txt))                       return("lookup")
  if (grepl("\\]\\s*=\\s*[^=]*~~\\|", txt)) {
    # one value per slice, or a list per slice? Count the numbers in the first.
    first <- sub("~~\\|.*$", "", txt)
    body  <- sub("^[^=]*=", "", first)
    n <- length(Filter(nzchar, trimws(strsplit(body, "[,\n\t]+")[[1]])))
    return(if (n > 1) "slices" else "cells")
  }
  "constants"
}

# --- the parsers --------------------------------------------------------------

## TABBED ARRAY: a flat run of numbers, tab-separated, filled row-major.
parse_tabbed <- function(txt) {
  inner <- regmatches(txt, regexpr("TABBED ARRAY\\(.*", txt))
  inner <- sub("^TABBED ARRAY\\(", "", inner)
  inner <- sub("\\)\\s*~.*$", "", inner)
  as.numeric(Filter(nzchar, trimws(strsplit(inner, "[\t\n,]+")[[1]])))
}

## `name[dim] = v, v, v, ...`
parse_constants <- function(txt) {
  inner <- sub("^[^=]*=", "", txt)
  inner <- sub("~.*$", "", inner)
  as.numeric(Filter(nzchar, trimws(strsplit(inner, "[,\n\t]+")[[1]])))
}

## `name[m1,m2,m3] = v ~~|` repeated. Returns one row per cell.
parse_cells <- function(txt, dim_names) {
  m <- gregexpr("\\[([^]]*)\\]\\s*=\\s*\n?\\s*(-?[0-9.eE+-]+)", txt)
  hits <- regmatches(txt, m)[[1]]
  if (!length(hits)) return(NULL)
  mods <- sub("^\\[([^]]*)\\].*", "\\1", hits)
  vals <- as.numeric(sub(".*=\\s*\n?\\s*", "", hits))
  out <- do.call(rbind, lapply(strsplit(mods, ","), trimws))
  out <- as.data.frame(out, stringsAsFactors = FALSE)
  names(out) <- dim_names
  out$value <- vals
  out
}

## `name[m1,dim2] = v, v, v ~~|` repeated: one constant list per slice of the
## first dimension. Returns a long frame, so that the writer can place values by
## name rather than trusting the order the dimensions happen to be written in —
## Vensim writes [EnergySource, Industry] where the R template is
## Industry x EnergySource.
parse_slices <- function(txt, dim_names) {
  chunks <- Filter(nzchar, trimws(strsplit(txt, "~~\\|")[[1]]))
  out <- lapply(chunks, function(ch) {
    mods <- regmatches(ch, regexpr("\\[[^]]*\\]", ch))
    if (!length(mods)) return(NULL)
    mods <- trimws(strsplit(gsub("[][]", "", mods), ",")[[1]])
    slice <- mods[1]                       # the named modality
    body <- sub("^[^=]*=", "", ch); body <- sub("~.*$", "", body)
    v <- as.numeric(Filter(nzchar, trimws(strsplit(body, "[,\n\t]+")[[1]])))
    if (!length(v)) return(NULL)
    data.frame(slice = slice, along = seq_along(v), value = v, stringsAsFactors = FALSE)
  })
  do.call(rbind, Filter(Negate(is.null), out))
}

## The (x, y) pairs of one lookup table, dropping the leading [(..)-(..)] range.
parse_pairs <- function(chunk) {
  chunk <- gsub("[[:space:]]", "", chunk)          # Vensim wraps inside pairs
  chunk <- sub("\\[\\([^]]*\\)\\]", "", chunk)     # the display range, not data
  pairs <- regmatches(chunk, gregexpr("\\(\\s*-?[0-9.eE+-]+\\s*,\\s*-?[0-9.eE+-]+\\s*\\)", chunk))[[1]]
  if (!length(pairs)) return(NULL)
  nums <- lapply(pairs, function(p) as.numeric(strsplit(gsub("[()]", "", p), ",")[[1]]))
  data.frame(x = vapply(nums, `[`, numeric(1), 1),
             y = vapply(nums, `[`, numeric(1), 2))
}

## A lookup, indexed or not. Returns one row per (modalities, x, y).
parse_lookup <- function(txt, dim_names = NULL) {
  if (is.null(dim_names)) return(parse_pairs(txt))

  # split into one chunk per indexed table
  chunks <- strsplit(txt, "~~\\||\\|\\s*\n")[[1]]
  chunks <- Filter(function(c) grepl("\\[", c) && grepl("\\(", c), chunks)

  out <- lapply(chunks, function(ch) {
    mods <- regmatches(ch, regexpr("\\[[^]()]*\\]", ch))
    if (!length(mods)) return(NULL)
    mods <- trimws(strsplit(gsub("[][]", "", mods), ",")[[1]])
    if (length(mods) != length(dim_names)) return(NULL)
    p <- parse_pairs(sub("^[^(]*\\[[^]]*\\]", "", ch))
    if (is.null(p)) return(NULL)
    cbind(setNames(as.data.frame(as.list(mods), stringsAsFactors = FALSE), dim_names), p)
  })
  out <- do.call(rbind, Filter(Negate(is.null), out))
  out
}

## Dispatch on the shape.
vensim_parse <- function(txt, dim_names = NULL) {
  shape <- vensim_shape(txt)
  value <- switch(shape,
    tabbed      = parse_tabbed(txt),
    constants   = parse_constants(txt),
    cells       = parse_cells(txt, dim_names),
    slices      = parse_slices(txt, dim_names),
    lookup      = parse_lookup(txt, dim_names),
    with_lookup = parse_lookup(txt, dim_names),
    stop("Unrecognised Vensim shape."))
  list(shape = shape, value = value, description = vensim_description(txt))
}

## Rename modalities, from a manifest entry like "mid=medium;hig=high".
##
## `spaces` renames "p food" to "p_food": Vensim allows spaces in a modality
## name, R dimnames in this project do not. The previous extractor had that as a
## special case for coicop; here it is a rule any row can ask for.
apply_recode <- function(df, recode) {
  if (is.na(recode) || !nzchar(recode)) return(df)
  if (identical(trimws(recode), "spaces")) {
    for (j in seq_along(df)) if (is.character(df[[j]])) df[[j]] <- gsub(" ", "_", df[[j]])
    return(df)
  }
  for (r in strsplit(recode, ";")[[1]]) {
    kv <- trimws(strsplit(r, "=")[[1]])
    for (j in seq_along(df)) if (is.character(df[[j]])) df[[j]][df[[j]] == kv[1]] <- kv[2]
  }
  df
}
