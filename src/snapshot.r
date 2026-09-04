#!/usr/bin/env Rscript
# ===========================================================================
# snapshot.r — take or check a reference snapshot of the model output.
#
#   Rscript src/snapshot.r take  <name>   # run the model, save d as reference
#   Rscript src/snapshot.r check <name>   # run the model, compare against it
#
# Used to prove that a refactoring step changes no results. It does not
# validate the model against Vensim — see README.md §9.
# ===========================================================================

args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args) >= 1) args[1] else "check"
name <- if (length(args) >= 2) args[2] else "phase0"

suppressPackageStartupMessages({
  library(here)
  library(data.table)
})
source(here::here("src", "paths.r"))
ref_file <- path_output(paste0("_ref_", name, ".rds"))

# run the model in a child process so its rm(list=ls()) cannot bite us
tmp <- tempfile(fileext = ".rds")
code <- sprintf(
  'source("%s"); saveRDS(d[!is.na(Name)], "%s")',
  here::here("src", "run_model.r"), tmp
)
out <- system2("Rscript", c("-e", shQuote(code)), stdout = TRUE, stderr = TRUE)
if (!file.exists(tmp)) {
  cat(paste(out, collapse = "\n"), "\n")
  stop("the model did not produce a table")
}
current <- readRDS(tmp)

if (mode == "take") {
  saveRDS(current, ref_file)
  cat(sprintf("reference saved: %s (%d rows, %d variables)\n",
              basename(ref_file), nrow(current), length(unique(current$Name))))
  quit(status = 0)
}

if (!file.exists(ref_file)) stop("no reference named '", name, "'. Run `take` first.")
ref <- readRDS(ref_file)

setkeyv(ref, c("Period", "Module", "Name"))
setkeyv(current, c("Period", "Module", "Name"))

if (isTRUE(all.equal(ref, current))) {
  cat(sprintf("identical to reference '%s' — %d rows, %d variables\n",
              name, nrow(current), length(unique(current$Name))))
  quit(status = 0)
}

cat("DIFFERS from reference '", name, "'\n\n", sep = "")
gone  <- setdiff(ref$Name, current$Name)
added <- setdiff(current$Name, ref$Name)
if (length(gone))  cat("  no longer computed:", paste(gone, collapse = ", "), "\n")
if (length(added)) cat("  newly computed:   ", paste(added, collapse = ", "), "\n")

common <- intersect(ref$Name, current$Name)
changed <- Filter(function(v) {
  a <- ref[Name == v, Value][[1]]; b <- current[Name == v, Value][[1]]
  !isTRUE(all.equal(a, b))
}, common)
if (length(changed)) cat("  values changed:   ", paste(changed, collapse = ", "), "\n")
quit(status = 1)
