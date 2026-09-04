# ---------------------------------------------------------------------------
# paths.r — every path in the project resolves through this file.
#
# Never write a literal path anywhere else. `here::here()` anchors on the
# project root (it finds the .git directory), so the model runs identically
# whether it is launched from the root, from src/, or from an IDE.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages(library(here))

PROJECT_ROOT <- here::here()

DIR_SRC     <- here::here("src")
DIR_PREP    <- here::here("src", "A-prep-steps")
DIR_MODULES <- here::here("src", "B-modules")
DIR_INPUT   <- here::here("input")
DIR_OUTPUT  <- here::here("output")
DIR_LOG     <- here::here("log")
DIR_TOOL    <- here::here("tool")
DIR_APP     <- here::here("app")
DIR_DOCS    <- here::here("docs")

FILE_SCALARS <- file.path(DIR_INPUT, "scalars.csv")

# --- helpers ---------------------------------------------------------------

path_prep   <- function(...) file.path(DIR_PREP, ...)
path_module <- function(module) file.path(DIR_MODULES, paste0(module, ".r"))
path_input  <- function(...) file.path(DIR_INPUT, ...)
path_output <- function(...) file.path(DIR_OUTPUT, ...)
path_log    <- function(...) file.path(DIR_LOG, ...)

# --- directories that must exist -------------------------------------------

for (.d in c(DIR_OUTPUT, DIR_LOG)) {
  if (!dir.exists(.d)) dir.create(.d, recursive = TRUE, showWarnings = FALSE)
}
rm(.d)
