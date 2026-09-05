#!/usr/bin/env Rscript
# ==============================================================================
# check-mapping.r — is MAPPING.md complete, in both directions?
#
#   Rscript tool/check-mapping.r            # report only
#   Rscript tool/check-mapping.r --update   # also refresh the derived sections
#
# MAPPING.md is maintained by hand: the confidence of a row is a human judgement
# and must not be overwritten. Two things in it are *derived* and go stale on
# their own — the counters, and the list of Vensim variables no row claims.
# --update refreshes exactly those two and nothing else.
#
# The checks are:
#
#   R  -> map    every function defined in src/B-modules has a row
#   map -> R     every row names a function that exists
#   V  -> map    every variable of vensim_model_2026.txt is either claimed by a
#                row or listed as not translated
#   map -> V     every Vensim name a row claims exists in the 2026 model
#
# The third is the one that matters for phase 2: a variable that is in neither
# place is a variable nobody has looked at.
# ==============================================================================

suppressPackageStartupMessages(library(here))
source(here::here("src", "paths.r"))

MAP <- file.path(PROJECT_ROOT, "MAPPING.md")
VEN <- file.path(PROJECT_ROOT, "vensim_model_2026.txt")

CONF <- c("checked", "added", "high", "medium", "low", "none")

# --- what the map says --------------------------------------------------------

read_map <- function() {
  lines <- readLines(MAP, warn = FALSE)
  in_details <- cumsum(grepl("^<details>", lines)) > cumsum(grepl("^</details>", lines))
  body <- lines[!in_details]

  rx <- "^\\|\\s*`([^`]+)`\\s*\\|([^|]*)\\|([^|]*)\\|([^|]*)\\|\\s*([a-z?]+)\\s*\\|$"
  hit <- grepl(rx, body) & sub(rx, "\\5", body) %in% CONF
  m <- data.frame(
    fn     = sub(rx, "\\1", body[hit]),
    output = trimws(gsub("`", "", sub(rx, "\\2", body[hit]))),
    vensim = trimws(sub(rx, "\\3", body[hit])),
    line   = trimws(sub(rx, "\\4", body[hit])),
    conf   = sub(rx, "\\5", body[hit]),
    stringsAsFactors = FALSE)

  # the Vensim names a row claims, ignoring struck-through ones and arrows
  m$claims <- lapply(m$vensim, function(v) {
    v <- gsub("~~[^~]*~~", "", v)                 # a struck-through name is not claimed
    v <- sub(".*→", "", v)
    unique(trimws(gsub("`", "", regmatches(v, gregexpr("`[^`]+`", v))[[1]])))
  })
  m
}

read_not_translated <- function() {
  lines <- readLines(MAP, warn = FALSE)
  from <- grep("^<details>", lines); to <- grep("^</details>", lines)
  if (!length(from)) return(character())
  blk <- lines[from[1]:to[1]]
  rx <- "^\\|\\s*`([^`]+)`\\s*\\|.*$"
  sub(rx, "\\1", blk[grepl(rx, blk)])
}

# --- what the code and the model say ------------------------------------------

r_functions <- function() {
  out <- list()
  for (f in list.files(DIR_MODULES, pattern = "[.]r$", full.names = TRUE)) {
    if (startsWith(basename(f), "_")) next
    src <- readLines(f, warn = FALSE)
    src <- src[!grepl("^\\s*#", src)]                     # commented out: not a function
    nm <- sub("^([A-Za-z_][A-Za-z0-9_.]*)\\s*<-\\s*function.*$", "\\1",
              grep("^[A-Za-z_][A-Za-z0-9_.]*\\s*<-\\s*function", src, value = TRUE))
    out[[sub("[.]r$", "", basename(f))]] <- nm
  }
  out
}

vensim_variables <- function() {
  lines <- readLines(VEN, warn = FALSE)
  nm <- sub("^([A-Za-z\"][^=]*?)\\s*(?:\\[[^]]*\\])?\\s*=.*$", "\\1", 
            grep("^[A-Za-z\"][^=]*=", lines, value = TRUE))
  unique(trimws(gsub('"', "", nm)))
}

# --- the report ---------------------------------------------------------------

m        <- read_map()
untrans  <- read_not_translated()
rfn      <- r_functions()
allr     <- unlist(rfn, use.names = FALSE)
ven      <- vensim_variables()
claimed  <- unique(unlist(m$claims))

miss_row  <- setdiff(allr, m$fn)                       # a function with no row
ghost_row <- setdiff(m$fn, allr)                       # a row with no function
unseen    <- setdiff(ven, union(claimed, untrans))     # a Vensim variable nobody looked at
phantom   <- setdiff(claimed, ven)                     # a row claiming something absent from 2026
stale     <- intersect(claimed, untrans)               # claimed and still listed as not translated

cat("MAPPING.md\n")
cat("  rows                     ", nrow(m), "\n")
cat("  R functions in modules   ", length(allr), "\n")
cat("  Vensim 2026 variables    ", length(ven), "\n\n")

report <- function(label, x, hint = "") {
  cat(sprintf("  %-38s %4d %s\n", label, length(x), if (length(x)) "" else "ok"))
  if (length(x)) {
    cat("     ", paste(head(x, 12), collapse = ", "),
        if (length(x) > 12) paste0(" ... and ", length(x) - 12, " more") else "", "\n")
    if (nzchar(hint)) cat("      -> ", hint, "\n")
  }
}

cat("R -> map\n")
report("functions with no row", miss_row, "add a row, or the function is new")
report("rows naming no function", ghost_row, "the function was renamed or removed")
cat("\nVensim -> map\n")
report("variables nobody has looked at", unseen, "neither claimed nor listed as untranslated")
report("rows claiming a name absent from 2026", phantom, "renamed in 2026, or a typo")
report("claimed but still listed untranslated", stale, "--update removes them from the list")

cat("\nConfidence\n")
tb <- table(factor(m$conf, levels = CONF))
for (k in CONF) cat(sprintf("  %-10s %4d\n", k, tb[[k]]))

problems <- length(miss_row) + length(ghost_row) + length(unseen) + length(phantom)

# --- refresh the derived sections ---------------------------------------------

if ("--update" %in% commandArgs(trailingOnly = TRUE)) {
  lines <- readLines(MAP, warn = FALSE)

  new_untrans <- sort(setdiff(ven, claimed))
  vlines <- readLines(VEN, warn = FALSE)
  where <- vapply(new_untrans, function(v) {
    i <- grep(paste0("^\"?", gsub("([.|()\\^{}+$*?\\[\\]])", "\\\\\\1", v), "\"?\\s*(\\[|=)"), vlines)
    if (length(i)) i[1] else NA_integer_
  }, integer(1))

  from <- grep("^<details>", lines)[1]; to <- grep("^</details>", lines)[1]
  block <- c("<details><summary>Show the list</summary>", "", "| Vensim | Line |", "|---|---|",
             sprintf("| `%s` | %s |", new_untrans, ifelse(is.na(where), "", where)),
             "", "</details>")
  lines <- c(lines[1:(from - 1)], block, lines[(to + 1):length(lines)])

  # the sentence above the list carries the count
  lines <- sub("^[0-9]+ of the [0-9]+ variables in",
               paste0(length(new_untrans), " of the ", length(ven), " variables in"), lines)

  cfrom <- grep("^## Counters", lines)[1]
  cbody <- c("## Counters", "",
             "Refreshed by `Rscript tool/check-mapping.r --update`. The confidence of a row is",
             "a human judgement and is never touched.", "",
             "| | |", "|---|---|",
             sprintf("| R functions | %d |", nrow(m)),
             sprintf("| `%s` | %d |", CONF, as.integer(tb[CONF])),
             sprintf("| Vensim variables not claimed | %d / %d |", length(new_untrans), length(ven)))
  lines <- c(lines[1:(cfrom - 1)], cbody)

  writeLines(lines, MAP)
  cat("\nrefreshed: counters, and the list of variables no row claims\n")
}

cat("\n", if (problems == 0) "nothing missing in either direction" else
         paste(problems, "gap(s) to close"), "\n")
