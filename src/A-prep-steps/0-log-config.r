# ==============================================================================
# LOGGING
# ==============================================================================
#
# One log file per day under log/. Three levels, INFO by default: raise the
# threshold to quieten a run, never by deleting log calls.
#
#   log_info("...")   what happened
#   log_warn("...")   something is odd but the run goes on
#   log_error("...")  something failed
#
#   log_block("Title")            a visual separator in the file
#   log_objects(x, "label")       a sorted list of names, one per line
#
# The file gets plain text: no emoji, no colour. Console feedback is a separate
# concern and goes through message(). Set log_to_console = TRUE in log_init()
# to mirror everything to the console while debugging.
# ------------------------------------------------------------------------------

.log <- new.env(parent = emptyenv())

.LOG_LEVELS <- c(INFO = 1L, WARN = 2L, ERROR = 3L)

log_init <- function(dir = DIR_LOG, prefix = "model_log",
                     level = "INFO", to_console = FALSE) {

  level <- toupper(level)
  if (!level %in% names(.LOG_LEVELS)) {
    stop("Unknown log level '", level, "'. One of: ",
         paste(names(.LOG_LEVELS), collapse = ", "), ".")
  }

  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  .log$file       <- file.path(dir, paste0(prefix, "_", Sys.Date(), ".log"))
  .log$threshold  <- .LOG_LEVELS[[level]]
  .log$to_console <- isTRUE(to_console)

  # `log_file` stays a plain global: run_model.r and the modules point users at
  # it in their console messages.
  assign("log_file", .log$file, envir = .GlobalEnv)

  .log_write("INFO", strrep("=", 70))
  .log_write("INFO", paste("New session:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
  .log_write("INFO", paste("Project:    ", PROJECT_ROOT))
  .log_write("INFO", paste("R:          ", R.version.string))
  .log_write("INFO", strrep("=", 70))

  invisible(.log$file)
}

.log_write <- function(level, ...) {
  if (is.null(.log$file)) log_init()
  if (.LOG_LEVELS[[level]] < .log$threshold) return(invisible(NULL))

  msg  <- paste0(...)
  line <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ",
                 formatC(level, width = -5), " | ", msg)

  cat(line, "\n", sep = "", file = .log$file, append = TRUE)
  if (.log$to_console) cat(line, "\n", sep = "")
  invisible(NULL)
}

log_info  <- function(...) .log_write("INFO",  ...)
log_warn  <- function(...) .log_write("WARN",  ...)
log_error <- function(...) .log_write("ERROR", ...)

## Kept as an alias: it is what the modules and the engine already call.
log_message <- function(msg) .log_write("INFO", msg)

## A visual separator, for finding one's way in a long file.
log_block <- function(title, subtitle = "") {
  sep <- strrep("-", 70)
  .log_write("INFO", sep)
  .log_write("INFO", title, if (nzchar(subtitle)) paste0(" - ", subtitle) else "")
  .log_write("INFO", sep)
}

## Log a sorted list of names under a label. `x` is either a character vector
## or an environment, in which case its objects are listed.
##
## This replaces the BEGIN/END + tempfile pattern, which re-sourced a file into
## a throwaway environment purely to find out what it defined.
log_objects <- function(x, label, width = 76) {
  nms <- if (is.environment(x)) ls(x, all.names = FALSE) else as.character(x)
  nms <- sort(unique(nms[!is.na(nms)]))

  log_info(label, " (", length(nms), ")")
  if (!length(nms)) return(invisible(nms))

  # Wrap into lines so that every line in the file keeps its own prefix and the
  # log stays greppable line by line.
  line <- ""
  for (n in nms) {
    candidate <- if (nzchar(line)) paste(line, n, sep = ", ") else n
    if (nchar(candidate) > width) {
      log_info("  ", line)
      line <- n
    } else {
      line <- candidate
    }
  }
  if (nzchar(line)) log_info("  ", line)

  invisible(nms)
}

log_init()
message("Logging initialised -> ", log_file)
