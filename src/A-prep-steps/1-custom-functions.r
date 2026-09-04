# BEGIN StrFunctions

############################################################################################################
############################################################################################################

# ~~~~~~~~~~~ #
# VENSIM to R #
# ~~~~~~~~~~~ #

# The documentation lists the common Vensim constructs and their R equivalents.
# Only the ones with no direct R counterpart are written out here.

# ------------------------------------------------------------------------------
# SMOOTH()
# ------------------------------------------------------------------------------
#
# Vensim's SMOOTH(input, delay) is a first-order exponential smooth, which is a
# hidden stock:
#
#     dSmooth/dt = (input - Smooth) / delay
#     Smooth(t)  = Smooth(t - dt) + (input(t) - Smooth(t - dt)) * dt / delay
#     Smooth(0)  = input(0)                    # it initialises to its input
#
# This function does that arithmetic and nothing else. It takes **values**, not
# expressions: `prev` is last period's smoothed value, read from `d` by the
# equation that calls it, like any other lagged variable.
#
# The smoothed quantity is therefore a variable of the model in its own right,
# with Kind == "state" — visible in `d`, in the outputs and in the dependency
# graph. That is what it always was in Vensim; it was only hidden.
#
# The previous implementation resolved its own variables, walking the
# expression it was handed and searching dp, init, d and the global environment
# in turn. It returned the right answer in the first period and a wrong one
# afterwards — it multiplied a (periods x elements) matrix from gda() by a
# per-element vector from gp(), which recycles down the columns instead of
# across them, then returned a single value where a vector was expected. Nobody
# noticed because the time loop had never run past the first period.

smooth_vensim <- function(input, prev, delay, dt = 1) {
  alpha <- dt / delay
  if (any(alpha <= 0) || any(alpha > 1)) {
    stop("smooth_vensim(): alpha = dt/delay must lie in (0, 1]. ",
         "Got dt = ", dt, ", delay = ", paste(delay, collapse = ", "), ".")
  }
  prev + alpha * (input - prev)
}

############################################################################################################
############################################################################################################

# ~~~~~~~~~~~~~~~~ #
# MODEL MANAGEMENT #
# ~~~~~~~~~~~~~~~~ #

# -----------------------------------------------------------------------------------------------------------
# Loading stuff #
# -----------------------------------------------------------------------------------------------------------

# create init dp lookup and d -------------------------------------------------------------------------------
#
# Pre-allocates `n` empty rows per block, a block being one Module (and, for
# `d`, one Period x Module). Columns:
#
#   Name, Value, Description   what the variable is
#   Kind                       state / flow / aux — how it is computed (README §6.2)
#   Region                     "IT" for now (README §10)
#
# The table is then registered so that writes get an O(1) cursor and reads an
# O(1) row registry. See THE TABLE LAYER below.
create_data_table <- function(name, n, cols = list(), order_by = NULL) {
  combinations <- do.call(expand.grid, c(cols, list(Name = rep(NA_character_, n))))
  nr <- nrow(combinations)

  tbl <- data.table(combinations,
                    Value       = rep(list(NA), nr),
                    Description = rep(list(NA), nr),
                    Kind        = rep(NA_character_, nr),
                    Region      = rep(DEFAULT_REGION, nr))

  # Si order_by est défini, on applique l'ordre
  if (!is.null(order_by)) {
    do.call(setorder, c(list(tbl), order_by))
  }

  assign(name, tbl, envir = .GlobalEnv)  # Assign to global environment
  table_register(name)
  keep_add(name)
}

# loadFillPol to load policy shocks and shifts --------------------------------------------------------------

loadFillPol <- function(name, value, description=NULL) {

  object_name <- name
  filled <- value
  desc <- if(!is.null(description)) description else NA

  dt_set("dp", module = "POLICY", name = object_name, value = filled, description = desc)

  invisible(filled)
}

# Auxiliary function: read CSV, validate columns, extract description ---------------------------------------

read_and_validate_csv <- function(file_path, exclude_cols = NULL, must_have_cols = NULL) {

  data <- read.csv(file_path, header = TRUE)
  csv_basename <- basename(file_path)

  # Validate required columns
  if (!is.null(must_have_cols)) {
    missing_cols <- setdiff(must_have_cols, colnames(data))
    if (length(missing_cols) > 0) {
      message(paste0("Missing columns: ", paste(missing_cols, " in file ", csv_basename, collapse = ", ")))
    }
  }

  # Check for description column
  if ("description" %in% colnames(data) && !is.na(data$description[1])) {
    desc <- data$description[1]
  } else {
    message(paste0("No valid description found in file: ", csv_basename, ". Consider adding a description."))
    desc <- NA
  }
  # Exclude specified columns
  if (!is.null(exclude_cols)) {
    data <- data[, -exclude_cols, drop = FALSE]
  }
  return(list(data = data, description = desc))
}

# Loader for 1D data ------------------------------------------------------------------------------------------

load_1d <- function(file_path, template, description) {

  csv_data <- read_and_validate_csv(file_path, must_have_cols = "value") # 1D must have a value column which we then directly target


  if (length(csv_data$data$value) != length(template)) {
    stop(paste0("Dimension mismatch between data and template in file: ", basename(file_path),
                "\nLength of CSV 'value' column: ", length(csv_data$data$value),
                "\nLength of template: ", length(template),
                "\nTemplate name: ", deparse(substitute(template)),
                "\nCheck the data for missing or excessive modalities."))
  }


  filled <- template
  filled[] <- csv_data$data$value
  desc <- if (!is.null(description)) description else csv_data$description
  list(filled = filled, description = desc)
}

# Loader for 2D data ------------------------------------------------------------------------------------------

load_2d <- function(file_path, template, description) {
  # Read and validate the CSV data
  csv_data <- read_and_validate_csv(file_path, exclude_cols = c(1, 2))  # Exclude the first 2 columns

  # Check if dimensions match between the CSV data and the template
  if (dim(csv_data$data)[1] != dim(template)[1] || dim(csv_data$data)[2] != dim(template)[2]) {
    stop(paste0("Dimension mismatch between data and template in file: ", basename(file_path),
                "\nDimensions of CSV data: ", paste(dim(csv_data$data), collapse = " x "),
                "\nDimensions of template: ", paste(dim(template), collapse = " x "),
                "\nTemplate name: ", deparse(substitute(template)),
                "\nCheck data for missing or excessive modalities."))
  }

  # Try to assign the data to the template with tryCatch to handle any other runtime errors
  filled <- template
  tryCatch({
    filled[,] <- as.matrix(csv_data$data)
  }, error = function(e) {
    stop(paste0("File: ", basename(file_path), ". Error assigning values to 2D template: ", e$message))
  })

  # Handle the description
  desc <- if (!is.null(description)) description else csv_data$description

  return(list(filled = filled, description = desc))
}

# Loader for 3D data ------------------------------------------------------------------------------------------

load_3d <- function(file_path, template, description) {
  # Retrieving last dimension modalities name
  n_dims <- length(dim(template))
  mod_last_dim <- dimnames(template)[n_dims][[1]]
  n_mod_last_dim <- length(mod_last_dim)

  desc_data <- ""  # Initialize desc_data as an empty string
  object_name <- sub("_[^_]*$", "", basename(file_path[1]))
  filled <- template

  for(mod in 1:n_mod_last_dim) {
    # Create temp_file_path with correct modality suffix 
    temp_file_path <- sub("_[^_]*.csv$", paste0("_", mod_last_dim[mod], ".csv"), file_path)
    # Read and validate the CSV data
    csv_data <- read_and_validate_csv(temp_file_path, exclude_cols = c(1, 2))  # Exclude the first 2 columns

    # Vérification des dimensions avant affectation
    if (dim(csv_data$data)[1] != dim(template)[1] || dim(csv_data$data)[2] != dim(template)[2]) {
      stop(paste0("Dimension mismatch between data and template in file: ", basename(file_path),
                  "\nDimensions of CSV data: ", paste(dim(csv_data$data), collapse = " x "),
                  "\nDimensions of template: ", paste(dim(template), collapse = " x "),
                  "\nTemplate name: ", deparse(substitute(template)),
                  "\nCheck data for missing or excessive modalities."))
    }

    tryCatch({
      filled[, , mod] <- as.matrix(csv_data$data)
    }, error = function(e) {
      stop(paste0("Error assigning ", mod_last_dim[mod], " slice in file: ", object_name, ". Error: ", e$message))
    })

    # Concatenating the description of the current modality
    desc_data <- paste0(desc_data, mod_last_dim[mod], ": ", csv_data$description, " | ")
  }  

  if (is.na(desc)) {
    desc <- if (!is.null(description)) description else desc_data
  }
  name <- object_name 
  list(filled = filled, description = desc, name=name)
}

# Special loader for lookup table (no template) ---------------------------------------------------------------

load_lookup <- function(name, module, file_path, description = NULL) {

  # Read and validate the CSV
  csv_data <- read_and_validate_csv(file_path, exclude_cols = 1)

  value <- csv_data$data
  desc <- if (!is.null(description)) description else csv_data$description

  # Assuming 'lookup' is the object in the parent frame
  #lookup <- get("lookup", envir = parent.frame())
  dt_set("lookup", module = module, name = name, value = value, description = desc)

  invisible(value)
}

# Fonction pour trouver la plus longue superposition (sous-chaîne commune) ------------------------------------

longest_overlap <- function(name, element) {
  max_overlap <- 0  # Initialisation de la longueur maximale
  len_name <- nchar(name)
  len_element <- nchar(element)

  # Chercher la superposition dans toutes les positions possibles
  for (i in 1:(len_name - 1)) {
    # Chercher une sous-chaîne de longueur croissante dans name qui correspond à une partie de element
    for (j in 1:(len_element - 1)) {
      overlap_length <- 0

      # Compare les sous-chaînes correspondantes
      while (i + overlap_length <= len_name && j + overlap_length <= len_element && substr(name, i + overlap_length, i + overlap_length) == substr(element, j + overlap_length, j + overlap_length)) {
        overlap_length <- overlap_length + 1
      }

      # Si la longueur de la superposition est plus longue, mettre à jour
      if (overlap_length > max_overlap) {
        max_overlap <- overlap_length
      }
    }
  }

  return(max_overlap)
}

# -------------------------------------------------- LOADFILL -------------------------------------------------

loadFill <- function(to_load, input_dir = NULL) {

  # --- Vérification de l'input_dir ---
  tryCatch({
    # Vérification de l'argument 'to_load'
    if (missing(to_load)) message("Argument 'to_load' is required (initial, parameter, or lookup).")
    to_load <- match.arg(to_load, c("initial", "parameter", "lookup"))

    # Si input_dir n'existe pas dans l'environnement et que l'argument est NULL
    if (!exists("input_dir", envir = .GlobalEnv) && is.null(input_dir)) {
      stop("No default 'input_dir' found in the environment. You must specify an 'input_dir' path explicitly.")
    }

    # Utiliser input_dir existant dans l'environnement si ce dernier existe
    if (exists("input_dir", envir = .GlobalEnv) && is.null(input_dir)) {
      input_dir <- get("input_dir", envir = .GlobalEnv)
    }

    # Vérification que input_dir n'est pas NULL
    if (is.null(input_dir)) {
      stop("The 'input_dir' argument is missing or NULL. Please specify a valid directory path.")
    }

    # Définition du chemin du sous-dossier en fonction de 'to_load'
    subdir <- switch(to_load,
                     initial = "initial",
                     parameter = "parameter",
                     lookup = "lookup")

    dir <- file.path(input_dir, subdir)

    # Vérification que le répertoire existe
    if (!dir.exists(dir)) stop(paste0("Folder not found: ", dir, ". Check non-standard folder name in inputs/ folder."))

  }, error = function(e) {
    stop(paste0("An error occurred while identifying file directory: ", e$message, ". Nothing has been loaded."))
  }) # Fin du tryCatch()


  # --- Loading scalars ---
  scalars_path <- file.path(input_dir, "scalars.csv")

  if (file.exists(scalars_path) && to_load != "lookup") {
    scalars <- read.csv(scalars_path, header = TRUE)
    if (!all(c("name", "value", "table") %in% names(scalars))) stop("Non-standard column names in scalars.csv. Expected: name, value, module, table, units, description")

    scalars_sub <- scalars[scalars$table == to_load, ]

    for (i in seq_len(nrow(scalars_sub))) {
      row <- scalars_sub[i, ]
      name <- as.character(row$name)
      filled <- as.numeric(row$value)
      module <- row$module
      if (is.na(filled)) warning(paste0("Scalar '", name, "' has no or NA value after conversion to numeric."))
      desc <- if ("description" %in% names(row)) row$description else NA

      toTable <- switch(to_load, parameter = "dp", initial = "init")
      dt_set(toTable, module = module, name = name, value = filled, description = desc)
    }
  }

  # --- Cas LOOKUP ---
  if (to_load == "lookup") {

    lookup_files <- list.files(dir, pattern = "\\.csv$", recursive = TRUE, full.names = TRUE)
    for (file_path in lookup_files) {
      rel_path <- sub(paste0("^", dir, "/?"), "", file_path)
      parts <- strsplit(rel_path, "/")[[1]]

      tryCatch({
        if (length(parts) < 2) message(paste0("A lookup file has been placed outside of a module subfolder: ", rel_path))
      }, error=function(e){
        stop(paste0("An error occured while loading lookup", e$message))
      })# End of tryCatch()

      module <- parts[1]
      name <- tools::file_path_sans_ext(parts[2])
      load_lookup(name = name, module = module, file_path = file_path)
    }
    return(invisible(TRUE))
  }

  # --- Cas initial ou parameter : chargement des fichiers 1D/2D/3D ---
  subdirs <- list.dirs(dir, full.names = TRUE, recursive = FALSE)
  subdirs <- subdirs[!grepl("_non_standard/?$", subdirs)]

  for (sub in subdirs) {
    module <- basename(sub)
    file_paths <- list.files(sub, pattern = "\\.csv$", full.names = TRUE)

    # Extract the part of the filename before the last underscore (excluding the file extension)
    base <- tools::file_path_sans_ext(basename(file_paths))

    # Identify the unique groups (i.e., the common part before the last underscore):  We will keep only one file per group
    unique_groups <- unique(base)
    # Initialize a vector to store the files to keep
    file_paths_to_keep <- c()
    # Loop through each group to keep only the first file in each group
    for (group in unique_groups) {
      # Find all files belonging to the same group : Add only the first file from each group to the list of files to keep
      group_files <- file_paths[base == group]
      file_paths_to_keep <- c(file_paths_to_keep, group_files[1])
    }
    file_paths <- file_paths_to_keep

    for (file_path in file_paths) {

      name <- tools::file_path_sans_ext(basename(file_path))
      # --- Trouver le template correspondant in template_elements---
      template_name <- NULL
      match_id <- sub(".*_([A-Za-z]{1,3})(?=_|$)", "\\1", name, perl = TRUE) #looking for a string from 1 to max 3 characters, between _ and _ or _ and the end of the string

      if(match_id == name){# non standard template : there is no such string, so there is nothing to replace the original string with
        #varname_root <- tolower(sub("^[^_]*_", "", name))
        # which match varname root in template_element
        best_match <- ""
        max_len <- 0
        for (element in template_elements) {
          overlap_len <- longest_overlap(name, element)
          if (overlap_len > max_len) {
            max_len <- overlap_len
            best_match <- element
          }
        }
        template_name <- best_match
      }

      # extracting the short_id to match with template it
      match_short_id <- unique(sub("_[^_]*", "", match_id))
      for (t in template_elements) {
        temp_short_id <- sub("^[^_]*_[^_]*_", "", t)
        if (temp_short_id == match_short_id) {
          template_name <- t
          break
        }
      }

      tryCatch({
        if (is.null(template_name)) {
          message(paste0("No template found for '", name, "'. File not loaded. Check filename's spelling against existing templates: \n", paste(template_elements, collapse = "\n")))
        }
      }, error = function(e) {
        # Message d'erreur et passer au fichier suivant
        message(paste0("An error occurred while loading file '", name, "': ", e$message))
        next  # Passe au fichier suivant dans la boucle
      })

      template <- get(template_name, envir = .GlobalEnv)
      n_dims <- length(dim(template))
      name_last_dim <- names(dimnames(template)[n_dims])

      tryCatch({
        if(n_dims > 3) {
          message(paste0("Template found for '", name, "' has too many dimensions.\n loadFill() only works from scalar to 3D."))
        }
      }, error = function(e) {
        message(paste0("An error occurred while loading file '", name, "': ", e$message))
        next
      })

      loader <- switch(as.character(n_dims),
                       "1"= load_1d,
                       "2"= load_2d,
                       "3"= load_3d
      )

      file <- loader(file_path = file_path, template = template, description = NULL)
      toTable <- switch(to_load, parameter = "dp", initial = "init")
      name <- ifelse(n_dims==3, file$name, name)
      dt_set(toTable, module = module, name = name, value = file$filled, description = file$description)
    }
  }

  invisible(TRUE)


} 

# source module files and assign module name to each function -------------------------------------------------

sourceSet <- function(module_name) {
  module_path <- path_module(module_name)
  if (!file.exists(module_path)) stop("Module file not found: ", module_path)

  before <- ls(envir = .GlobalEnv)
  source(module_path)
  after  <- ls(envir = .GlobalEnv)

  # what the file just defined
  new_names <- setdiff(after, before)
  is_func   <- vapply(new_names, function(n) is.function(get(n, envir = .GlobalEnv)), logical(1))
  equations <- new_names[is_func]

  # tag each one with its module, so that eq() can label its output
  for (f in equations) {
    fn <- get(f, envir = .GlobalEnv)
    attr(fn, "module") <- module_name
    assign(f, fn, envir = .GlobalEnv)
  }

  # Log what the module brought in. This used to live in _0verbose.r, which
  # each module sourced at its own foot: it re-read the file, re-sourced the
  # section between the BEGIN/END Fonctions markers into a temp environment,
  # and listed that. Every module was therefore evaluated twice. The diff above
  # is the same list, for free.
  log_block("Module", module_name)
  policy <- grep("^(POL|SHOCK)", equations, value = TRUE)
  log_objects(policy, "Policy and shock equations")
  log_objects(setdiff(equations, policy), "Equations")

  keep_add(new_names)
  message(module_name, " loaded (", length(equations), " equations)")

  invisible(equations)
}



# ==============================================================================
# THE TABLE LAYER
# ==============================================================================
#
# The four tables (dp, init, lookup, d) are pre-allocated with empty rows,
# grouped in blocks: one block per Module, and for `d` one per (Period, Module).
#
# Writing means filling the next free row of the right block.
# Reading means finding a row by Name (and Period, for `d`).
#
# Both are O(1) and neither ever scans the table:
#   - a cursor per block holds the next free row,
#   - a registry maps a row key to its row index.
#
# The registry is maintained by dt_set(), which is the only writer. Nothing
# else may call set() on these tables, or the registry goes stale.
#
# See README.md §4.2.
# ------------------------------------------------------------------------------

.store <- new.env(parent = emptyenv())

.key <- function(...) paste(..., sep = "\r")

# --- registration -------------------------------------------------------------

## Index a freshly created table: locate its blocks, open a cursor on each.
table_register <- function(tname) {
  tbl     <- get(tname, envir = .GlobalEnv)
  blocks <- if ("Period" %in% names(tbl)) c("Period", "Module") else "Module"

  keys   <- do.call(.key, lapply(blocks, function(cl) as.character(tbl[[cl]])))
  starts <- which(!duplicated(keys))
  ends   <- c(starts[-1] - 1L, nrow(tbl))

  e         <- new.env(parent = emptyenv())
  e$blocks  <- blocks
  e$cursor  <- new.env(parent = emptyenv())   # block key -> c(next free, last row)
  e$row     <- new.env(parent = emptyenv())   # row key   -> row index

  for (i in seq_along(starts)) {
    assign(keys[starts[i]], c(starts[i], ends[i]), envir = e$cursor)
  }

  assign(tname, e, envir = .store)
  invisible(e)
}

## The next free row of a block. O(1). Errors when the block is full.
table_next_row <- function(tname, module, period = NULL) {
  e   <- get0(tname, envir = .store)
  if (is.null(e)) stop("Table '", tname, "' was never registered. Call create_data_table().")

  k   <- if (is.null(period)) .key(module) else .key(as.character(period), module)
  cur <- get0(k, envir = e$cursor)
  if (is.null(cur)) {
    stop("No block '", gsub("\r", "/", k), "' in '", tname,
         "'. Is the module declared in `modules` in 2-structure.r?")
  }
  if (cur[1] > cur[2]) {
    stop("Block '", gsub("\r", "/", k), "' of '", tname, "' is full (",
         cur[2] - cur[1] + 1L, " rows). Increase ",
         switch(tname, dp = "npar", init = "nvar", lookup = "nlookup", "nvar"),
         " in 2-structure.r.")
  }
  assign(k, c(cur[1] + 1L, cur[2]), envir = e$cursor)
  cur[1]
}

## Row index of a variable, or NULL. O(1).
table_row <- function(tname, name, period = NULL) {
  e <- get0(tname, envir = .store)
  if (is.null(e)) return(NULL)
  get0(if (is.null(period)) name else .key(name, as.character(period)), envir = e$row)
}

## Does this variable exist in the table? O(1).
table_has <- function(tname, name, period = NULL) !is.null(table_row(tname, name, period))

# --- writing ------------------------------------------------------------------

## The single writer. Fills the next free row of the block and registers it.
dt_set <- function(tname, module, name, value, description = NA, period = NULL,
                   kind = NULL, region = DEFAULT_REGION) {

  # Kind comes from the states registry unless the caller states it (README §6.2)
  if (is.null(kind)) kind <- variable_kind(name)

  tbl <- get(tname, envir = .GlobalEnv)
  e  <- get(tname, envir = .store)
  i  <- table_next_row(tname, module, period)

  cols <- c("Name", "Value", "Description", "Kind", "Region")
  vals <- list(name, list(value), description, kind, region)
  keep <- cols %in% names(tbl)
  set(tbl, i = i, j = cols[keep], value = vals[keep])

  # first write wins, as the old is.na(Name) scan did
  rk <- if (is.null(period)) name else .key(name, as.character(period))
  if (is.null(get0(rk, envir = e$row))) assign(rk, i, envir = e$row)

  invisible(i)
}

# --- compatibility shims ------------------------------------------------------
# Kept so that call sites written against the old API keep working. They only
# hand out a row index and do NOT register it — prefer dt_set().

pTo <- function(module) table_next_row("dp", module)
iTo <- function(module) table_next_row("init", module)
lTo <- function(module) table_next_row("lookup", module)
To  <- function(module, period) table_next_row("d", module, period)

# --- reading ------------------------------------------------------------------

## Shared body of gp/gi/gl/gd. `what` names the table for error messages.
.get_from <- function(tname, name, what, info = NULL, period = NULL) {
  valid <- c("all", "desc", "mod", "kind", "region")
  where <- if (is.null(period)) "" else paste0(" at period ", period)

  i <- table_row(tname, name, period)
  if (is.null(i)) stop(what, " '", name, "' not found in `", tname, "`", where, ".")

  tbl <- get(tname, envir = .GlobalEnv)
  if (is.null(info)) return(tbl$Value[[i]])

  if (!(info %in% valid)) {
    stop("Unknown `info`: '", info, "'. One of: ", paste(valid, collapse = ", "), ".")
  }
  switch(info,
    all    = tbl[i],
    desc   = tbl$Description[[i]],
    mod    = as.character(tbl$Module[[i]]),
    kind   = tbl$Kind[[i]],
    region = tbl$Region[[i]]
  )
}

gp <- function(param,    info = NULL) .get_from("dp",     param,    "Parameter",         info)
gi <- function(var,      info = NULL) .get_from("init",   var,      "Initial value",     info)
gl <- function(graphfun, info = NULL) .get_from("lookup", graphfun, "Graphical function", info)

## One variable at one period.
##
## The `time` argument is honoured. It was not before: the filter read
## `Period == Period`, which is always TRUE, so gd() always returned the first
## period. Nothing noticed because the time loop had never run past period one.
gd <- function(var, time, info = NULL) {
  if (missing(time)) stop("gd() needs a period. Use gda() for a whole series.")
  .get_from("d", var, "Variable", info, period = time)
}

## A variable over a window of periods.
##
## `from` and `to` default to the whole horizon, but the model only ever needs
## a few recent periods — pass them. Returns a vector when every period holds a
## scalar, a matrix (periods x elements) when they are same-length vectors, and
## the raw list otherwise.
gda <- function(var, from = NULL, to = NULL) {
  e <- get0("d", envir = .store)
  if (is.null(e)) stop("Table `d` was never registered.")

  periods <- if (is.null(from) && is.null(to)) {
    startYear:endYear
  } else {
    seq.int(if (is.null(from)) startYear else from,
            if (is.null(to))   endYear   else to)
  }

  rows <- vapply(periods, function(p) {
    i <- get0(.key(var, as.character(p)), envir = e$row)
    if (is.null(i)) NA_integer_ else i
  }, integer(1))
  rows <- rows[!is.na(rows)]

  if (!length(rows)) {
    warning("Variable '", var, "' not found in `d` over the requested window.")
    return(NULL)
  }

  out  <- d$Value[rows]
  lens <- lengths(out)
  if (all(lens == 1)) return(as.numeric(unlist(out)))
  if (length(unique(lens)) == 1) return(do.call(rbind, out))
  out
}

# --- the dependency table -----------------------------------------------------
#
# eq() also attaches dependencies as an attribute on the value it stores, which
# the Shiny viewer still reads. The attribute lives on a value that is rewritten
# every period; this table does not, so it is what queries should use.

deps_reset <- function() {
  assign("deps", data.table(
    Variable   = character(),
    Dependency = character(),
    Role       = character(),   # "input" or "parameter"
    Module     = character(),
    Equation   = character()
  ), envir = .GlobalEnv)
  assign("deps_seen", new.env(parent = emptyenv()), envir = .GlobalEnv)
  invisible(NULL)
}

## Record what an equation depends on. Once per variable: dependencies are
## structural and do not change from one period to the next.
deps_record <- function(variable, inputs, parameters, module, equation) {
  if (!exists("deps", envir = .GlobalEnv)) deps_reset()
  if (!is.null(get0(variable, envir = get("deps_seen", envir = .GlobalEnv)))) return(invisible(NULL))
  assign(variable, TRUE, envir = get("deps_seen", envir = .GlobalEnv))

  n <- length(inputs) + length(parameters)
  if (n == 0) return(invisible(NULL))

  assign("deps", rbindlist(list(get("deps", envir = .GlobalEnv), data.table(
    Variable   = variable,
    Dependency = c(inputs, parameters),
    Role       = rep(c("input", "parameter"), c(length(inputs), length(parameters))),
    Module     = module,
    Equation   = equation
  ))), envir = .GlobalEnv)
  invisible(NULL)
}

# -------------------------------------------------------------------------------------------------------------
# Cleaning stuff #
# -------------------------------------------------------------------------------------------------------------


# Fonction de checkpoint mémoire ------------------------------------------------------------------------------

memory_checkpoint <- function(step_name = "") {
  mem <- lobstr::mem_used()
  mem_mb <- round(as.numeric(mem) / (1024^2), 2)
  cat(sprintf("[%s] Mémoire utilisée : %.2f Mo\n", step_name, mem_mb))
}


# ==============================================================================
# THE KEEP REGISTRY
# ==============================================================================
#
# clean_ws() frees memory by emptying the global environment. Everything the
# model needs to keep working must be registered first.
#
# This replaces `toKeep`, a plain character vector that a dozen places appended
# to with `<<-`, in an order that had to be right. The registry is an
# environment: registration is idempotent, order-independent, and nothing can
# quietly drop an entry by reassigning the vector.

.keep <- new.env(parent = emptyenv())
.keep$names <- character()

## Protect names from clean_ws().
keep_add <- function(...) {
  nms <- unlist(list(...), use.names = FALSE)
  .keep$names <- union(.keep$names, as.character(nms))
  invisible(.keep$names)
}

## Protect everything defined so far. Called once, after the prep steps and the
## modules are loaded: at that point the global environment holds the structure,
## the tables and the equations, and nothing else.
keep_snapshot <- function(envir = .GlobalEnv) {
  keep_add(ls(envir, all.names = TRUE))
}

keep_list <- function() sort(.keep$names)

## Empty the global environment of everything not registered.
clean_ws <- function() {
  if (!length(.keep$names)) {
    stop("Nothing is registered yet. Call keep_snapshot() before clean_ws().")
  }

  to_remove <- setdiff(ls(envir = .GlobalEnv, all.names = TRUE), .keep$names)

  if (!length(to_remove)) {
    message("Nothing to clean: every object is registered.")
    log_info("clean_ws: nothing to remove")
    return(invisible(character()))
  }

  rm(list = to_remove, envir = .GlobalEnv)
  message("Cleaned ", length(to_remove), " objects from the workspace.")
  log_block("Cleaning workspace")
  log_objects(to_remove, "Removed")
  invisible(to_remove)
}


# ----------------------------------------------------------------------------------------------------------
# Functions for main loop
# ----------------------------------------------------------------------------------------------------------

# ==============================================================================
# THE PASS LOOP
# ==============================================================================
#
# eq() refuses to run an equation whose inputs are not available yet, so the
# equations do not have to be in dependency order: the loop makes several
# passes over them and each pass resolves whatever became computable.
#
# Two things keep that from being wasteful or silent:
#
#   - an equation that succeeded is not run again in the same period. Its value
#     is already in the global environment for the equations downstream, and
#     recomputing it would give the same answer, since nothing it reads has
#     moved.
#
#   - the loop stops when a pass resolves nothing new, not after a fixed number
#     of passes. The old `iter <- 3` was exactly enough for this model, with no
#     margin: one equation added in the wrong order and it would never have been
#     computed, with nothing but a line in a log to say so.
#
# This is not a topological sort. The mechanism and the freedom to order the
# equations however you like are unchanged.

.eq <- new.env(parent = emptyenv())
.eq$done <- new.env(parent = emptyenv())   # equations already computed this period
.eq$mark <- 0L                             # how many were done when the pass began

## Start a period: forget what was computed in the previous one.
eq_new_period <- function() {
  .eq$done <- new.env(parent = emptyenv())
  .eq$mark <- 0L
  invisible(NULL)
}

## Has this equation already been computed in the current period?
eq_is_done <- function(name) !is.null(get0(name, envir = .eq$done))
eq_mark_done <- function(name) assign(name, TRUE, envir = .eq$done)
eq_done_count <- function() length(ls(.eq$done))

## Run the passes until nothing new resolves.
##
## `body` is a function that calls every equation once, in whatever order the
## modules are written in. It is called repeatedly.
eq_run_passes <- function(body, max_passes = getOption("rewind.max_passes", 50L)) {
  for (pass in seq_len(max_passes)) {
    clear_eq_log()
    .eq$mark <- eq_done_count()

    body()

    if (print_eq_log()) return(invisible(pass))          # nothing failed

    if (eq_done_count() == .eq$mark) {                   # a pass changed nothing
      stuck <- .message_log$failure
      log_error("Stalled after ", pass, " passes. Unresolved:")
      for (m in stuck) log_error("  ", m)
      stop("The model stalled after ", pass, " passes: a pass resolved nothing ",
           "new and ", length(stuck), " equation(s) are still waiting on inputs ",
           "that never arrive.\nSee ", log_file, " for the list.\n",
           "Either an input is genuinely missing, or two equations depend on ",
           "each other.")
    }
    log_info("Pass ", pass, ": ", eq_done_count(), " equations resolved, ",
             length(.message_log$failure), " still waiting")
  }
  stop("Still not settled after ", max_passes, " passes.")
}

# to reset eq log ------------------------------------------------------------
clear_eq_log <- function() {
  .message_log <<- list(
                        success = character(), 
                        failure = character()
  )
}

# to print eq log ------------------------------------------------------------
print_eq_log <- function() {
  for (msg in .message_log$failure) message(msg)
  all_ok <- length(.message_log$failure) == 0
  if (all_ok) message("Run with success - all variables have been computed")
  return(all_ok)
}


# ----------------------------------------------------------------------------------------------------------
# The eq() function and its auxiliaries
# ----------------------------------------------------------------------------------------------------------

# Fonction récursive améliorée pour détecter variables assignées -------------------------------------------
find_assigned_vars <- function(expr) {
  assigned_vars <- character()

  find_assigned <- function(e) {
    if (is.call(e)) {
      if (is.symbol(e[[1]]) && as.character(e[[1]]) %in% c("<-", "=")) {
        if (is.symbol(e[[2]])) {
          assigned_vars <<- c(assigned_vars, as.character(e[[2]]))
        } else if (is.call(e[[2]]) && as.character(e[[2]][[1]]) == "[") {
          assigned_vars <<- c(assigned_vars, as.character(e[[2]][[2]]))
        }
      }
      lapply(e[-1], find_assigned)
    }
  }

  find_assigned(expr)
  assigned_vars <- unique(assigned_vars)
  assigned_vars[grepl("^[A-Za-z]", assigned_vars)]  # exclure `[`, `0-14`, etc.
}

# helpfer function that centralise all the cleaning and return auxiliaries and dependencies ----------------
# Helper function that centralizes all the cleaning and returns auxiliaries and dependencies
# Formal arguments of functions defined inside the block ----------------------
#
# A name bound as a formal argument is not a dependency: it exists only while
# the local function runs, and comes from its caller. Without this, writing a
# helper inside an eq() block makes eq() block on the helper's own arguments.
#
# Only the argument *name* is excluded here. Note a pre-existing blind spot,
# independent of this function: `all.names()` does not descend into the default
# value of a formal, so `function(x = R_labProd_i)` never reports R_labProd_i as
# a dependency at all — with or without this exclusion. Writing a model variable
# as a formal default inside an eq() block would therefore let the block run
# before that variable is ready. Do not do it; read the variable in the body.
# Fixing it properly would mean walking the pairlist values, roughly six lines,
# if the case ever turns up.
find_local_formals <- function(expr) {
  found <- character()
  walk <- function(e) {
    if (is.call(e)) {
      if (identical(e[[1]], as.name("function")) && length(e) >= 2) {
        nms <- names(e[[2]])
        if (!is.null(nms)) found <<- c(found, nms)
      }
      lapply(as.list(e)[-1], walk)
    }
    invisible(NULL)
  }
  walk(expr)
  unique(found[nzchar(found)])
}

clean_and_collect_dependencies <- function(expr) {

  # Liste des opérateurs à exclure des dépendances
  excluded_operators <- c("*", "/", "+", "-")

  # Variables à exclure explicitement
  excluded_vars <- c("x", "y", "tolerance")

  # Fonction pour collecter toutes les variables utilisées dans l'expression, excluant les fonctions
  all_vars <- all.names(expr, functions = FALSE, unique = TRUE)

  # Identifier les variables assignées dans l'expression
  assigned_vars <- find_assigned_vars(expr)

  # Identifier les variables utilisées dans les boucles `for(...)` (à exclure)
  find_for_vars <- function(e) {
    vars <- character()
    if (is.call(e) && e[[1]] == as.name("for")) {
      if (is.symbol(e[[2]])) vars <- as.character(e[[2]])
    }
    if (is.recursive(e)) {
      vars <- c(vars, unlist(lapply(e[-1], find_for_vars)))
    }
    unique(vars)
  }
  for_vars <- find_for_vars(expr)

  # Formal arguments of functions defined in the block, which are local names
  local_formals <- find_local_formals(expr)

  # Variables considérées comme des templates (à exclure)
  templates <- grep("^template_", all_vars, value = TRUE)

  # Collecter les variables auxiliaires (paramètres, valeurs initiales, etc.)
  auxiliaries <- character()
  if (exists("dp", envir = .GlobalEnv)) {
    dp_names <- get("dp", envir = .GlobalEnv)$Name
    auxiliaries <- intersect(all_vars, dp_names)
  }

  # Trouver les variables passées dans les appels à `gp(...)`, `gi(...)`, ou `gl(...)`
  find_gp_like_args <- function(e) {
    res <- character()
    if (is.call(e)) {
      fname <- as.character(e[[1]])
      if (fname %in% c("gp", "gi", "gl")) {
        if (length(e) >= 2) {
          arg <- e[[2]]
          if (is.character(arg)) {
            res <- c(res, arg)
          } else if (is.symbol(arg)) {
            res <- c(res, as.character(arg))
          }
        }
      }
      for (i in seq_along(e)) {
        res <- c(res, find_gp_like_args(e[[i]]))
      }
    }
    unique(res)
  }
  gp_aux <- find_gp_like_args(expr)
  auxiliaries <- union(auxiliaries, gp_aux)

  # Déterminer les dépendances en excluant certaines variables
  deps_all <- setdiff(all_vars, c(assigned_vars, for_vars, local_formals,
                                  templates, auxiliaries, excluded_vars))

  # Retirer les opérateurs classiques *, /, +, -
  deps_all <- setdiff(deps_all, excluded_operators)

  # Retourner les dépendances et les auxiliaires
  return(list(deps = deps_all, auxiliaries = auxiliaries))
}


# Fonction principale pour gérer l'environnement des fonctions de calcul du modèle ---------------------------
## check si .message_log existe et le crée en cas de besoin : usage typique, test des fonctions dans la console
## écris sur message_log
## reconnais les dépendances et les paramètres
## bloque l'exécution si des dépendances sont manquantes     
## associe à l'output ses attributs : fonction de calcul, dépendance et paramètres.
## return the output to globalEnv
## récupère le nom du module qui est attribut de la fonction appellante et set() if run mode is on
## return an output but invisibly
# `eq()` takes only the block. It used to accept a `dep = c(...)` argument for
# declaring dependencies by hand; automatic collection replaced it and the
# parameter was left in the signature, silently ignored — a caller writing it
# got no error and no effect. Removed.
#
# If automatic collection is ever wrong in a way find_local_formals() and the
# rest cannot cover, reinstating an explicit argument is the fallback: give
# eq() a `dep` parameter again and use it in place of `result$deps` below.
# It is five lines. Nothing else in the design depends on inference.
eq <- function(expr_block) {

  # Initialize message log if not already present
  if (!exists(".message_log", envir = .GlobalEnv)) {
    assign(".message_log", list(success = character(), failure = character()), envir = .GlobalEnv)
    message("ℹ️ .message_log was automatically initialized.")
  }

  # Get the name of the calling function
  calling_func <- sys.call(-1)
  func_name <- as.character(calling_func)[1]

  # Already computed in this period? Then there is nothing to do: the value is
  # in the global environment for the equations downstream, and nothing this
  # equation reads has moved since. Only in run mode — in dev mode you are
  # calling functions from the console and expect them to run.
  if (exists("dev_or_run", envir = .GlobalEnv) && dev_or_run == "run" &&
      eq_is_done(func_name)) {
    return(invisible(NULL))
  }

  # Try to retrieve the module name from the calling function's "module" attribute
  module_name <- NULL
  if (exists(func_name, envir = .GlobalEnv)) {
    func_obj <- get(func_name, envir = .GlobalEnv)
    module_name <- attr(func_obj, "module")
  }

  # Capture the expression block to be evaluated
  expr <- substitute(expr_block)

  # Nettoyer et collecter les dépendances et les auxiliaires
  result <- clean_and_collect_dependencies(expr)

  # Extraire les dépendances et auxiliaires
  deps <- result$deps
  auxiliaries <- result$auxiliaries

  # Check if any dependencies are missing in the global environment
  if (length(deps) == 0) {
    missing_deps <- character(0)
  } else {
    missing_deps <- deps[sapply(deps, function(d) {
                                  !exists(d, envir = .GlobalEnv) || is.null(get(d, envir = .GlobalEnv))
  })]
  }

  # Infer target variable: last expression in block if it is a symbol (variable name)
  target_var <- NULL
  if (is.call(expr) && expr[[1]] == as.name("{")) {
    last_expr <- expr[[length(expr)]]
    if (is.name(last_expr)) {
      target_var <- as.character(last_expr)
    }
  }

  # Throw explicit errors if module name or target variable cannot be determined
  if (is.null(module_name)) {
    stop(paste0("❌ eq() could not determine the module name for function '", func_name,
                "'. Ensure the function has a 'module' attribute."))
  }

  if (is.null(target_var)) {
    stop(paste0("❌ eq() could not determine the target variable for function '", func_name,
                "'. Ensure the last line is a variable name."))
  }

  # If all dependencies are available, evaluate the expression block
  if (length(missing_deps) == 0) {
    result <- eval(expr, envir = parent.frame())

    eq_mark_done(func_name)

    # Log success message
    .message_log$success <<- c(.message_log$success,
                               paste0("✅ ", func_name, " run with success.",
                                      if (!is.null(target_var)) paste0(" Calculated: ", target_var, ".")))

    # The value is stored as it is computed. Metadata about the equation —
    # what it depends on, which module and function it came from — goes to the
    # `deps` table below, never onto the value itself: an attribute would ride
    # on something that is rewritten every period, and would silently change
    # what identical() and all.equal() say about two runs.
    res <- result

    # assign to globlEnv to avoid having to <<- in each eq() bloc
    if (is.null(target_var)) {
      stop(paste0("❌ Internal error in eq(): 'target_var' is NULL at assignment stage. ",
                  "Check the expression block in function '", func_name, "'."))
    } else {
      assign(target_var, res, envir = .GlobalEnv)
    }

    # Record what this equation depends on. Once per variable: dependencies are
    # structural, they do not change from one period to the next.
    deps_record(target_var, deps, auxiliaries, module_name, func_name)

    # If in simulation mode, update the data table accordingly
    if (exists("dev_or_run", envir = .GlobalEnv) && dev_or_run == "run") {

      # O(1) registry lookup, not a scan of the whole table
      if (!table_has("d", target_var, t)) {
        dt_set("d",
               module = module_name,
               name   = target_var,
               value  = res,
               period = t,
               kind   = variable_kind(target_var))
      } #else {
      #message(paste0("⚠️ Variable '", target_var, "' already defined for module '", module_name,
      #              "' and period ", t, ". Skipping set()."))
      #} --> THIS PART SHOUDL BE USED AT A LATER STAGE FOR LOGGING PURPOSES
    }
    if (exists("dev_or_run", envir = .GlobalEnv) && dev_or_run == "dev") {
      return(invisible(res))
    }

  } else {
    # Log failure message with missing dependencies
    .message_log$failure <<- c(.message_log$failure,
                               paste0("❌ ", func_name, " not run. Missing: ",
                                      paste(missing_deps, collapse = ", "),
                                      if (!is.null(target_var)) paste0(". Not calculated: ", target_var)))
    return(NULL)
  }
}


# ----------------------------------------------------------------------------------------------------------
# Preventing hallucinations and other controls
# ----------------------------------------------------------------------------------------------------------

# To make sure nothing weird is happening with population --------------------------------------------------
check_population_consistency <- function() {
  total_active <- sum(ST_activePop_csg)
  total_employed <- sum(ST_labEmp_isg)
  total_unemployed <- sum(ST_labUnemp_sg)

  if (total_active != (total_employed + total_unemployed)) {
    stop("❌ Inconsistency: Active population ≠ Employed + Unemployed.")
  }

  total_workage <- sum(ST_workAgePop_csg)
  total_inactive <- sum(ST_inactivePop_sg)

  if (total_workage != (total_active + total_inactive)) {
    stop("❌ Inconsistency: Working-age population ≠ Active + Inactive.")
  }

  total_pop <- sum(Pop_lvl)
  pop_children <- sum(Pop_lvl[, "child", ])
  pop_capitalists <- sum(Pop_lvl[, "cap", ])
  pop_retired <- sum(Pop_lvl["65+", , ])
  pop_overlap_retired_cap <- sum(Pop_lvl["65+", "cap", ])

  decomposed_pop <- total_workage + pop_children + pop_capitalists + pop_retired - pop_overlap_retired_cap

  if (total_pop != decomposed_pop) {
    stop("❌ Inconsistency: Total population ≠ Sum of demographic components.")
  }

  message("✅ Population is consistent: no one is missing or in excess.")
}

# ~~~~~~~ #
# THE END #
# ~~~~~~~ #
############################################################################################################
############################################################################################################

# END StrFonctions

# ------------------------------------------------------------------------------
# What this file defines, for the log.
#
# The engine functions are what a module author calls; the rest is machinery.
# This used to be worked out by re-sourcing this very file into a throwaway
# environment through a temp file, which meant evaluating everything twice.
# ls() on the environment that has just been populated says the same thing.
# ------------------------------------------------------------------------------

local({
  engine <- list(
    "Read"          = c("gp", "gi", "gl", "gd", "gda"),
    "Write"         = c("dt_set"),
    "Equations"     = c("eq"),
    "Tables"        = c("create_data_table", "table_register", "table_row", "table_has"),
    "Dependencies"  = c("deps_reset", "deps_record"),
    "Workspace"     = c("keep_add", "keep_snapshot", "keep_list", "clean_ws"),
    "Loading"       = c("loadFill", "loadFillPol", "sourceSet")
  )

  defined <- ls(envir = .GlobalEnv)
  defined <- defined[vapply(defined, function(n) is.function(get(n, envir = .GlobalEnv)), logical(1))]

  log_block("Functions loaded")
  for (group in names(engine)) log_objects(intersect(engine[[group]], defined), group)
  log_objects(setdiff(defined, unlist(engine, use.names = FALSE)), "Helpers")

  keep_add(defined)
})

message("Functions loaded")
