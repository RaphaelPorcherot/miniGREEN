

# Auxiliary function: read CSV, validate columns, extract description
read_and_validate_csv <- function(path, exclude_cols = NULL, must_have_cols = NULL) {
  if (!file.exists(path)) stop(paste0("File not found: ", path))
  df <- read.csv(path, header = TRUE)
  
  if (!is.null(must_have_cols)) {
    missing_cols <- setdiff(must_have_cols, colnames(df))
    if (length(missing_cols) > 0) stop(paste0("Missing columns: ", paste(missing_cols, collapse = ", ")))
  }
  
  desc <- if ("description" %in% colnames(df)) df$description[1] else NA
  
  if (!is.null(exclude_cols)) {
    data <- df[, -exclude_cols, drop = FALSE]
  } else {
    data <- df
  }
  
  list(data = data, description = desc)
}

# Loader for 1D data
load_1d <- function(name, dir_path, template, description) {
  path <- here::here(dir_path, paste0(name, ".csv"))
  csv_data <- read_and_validate_csv(path, must_have_cols = "value")
  filled <- template
  filled[] <- csv_data$data$value
  desc <- if (!is.null(description)) description else csv_data$description
  list(filled = filled, description = desc)
}

# Loader for 2D data
load_2d <- function(name, dir_path, template, description) {
  path <- here::here(dir_path, paste0(name, ".csv"))
  csv_data <- read_and_validate_csv(path, exclude_cols = c(1, 2))
  
  if (nrow(csv_data$data) < ncol(csv_data$data)) {
    stop("Dimension mismatch: rows less than columns (excluding first two columns).")
  }
  
  filled <- template
  tryCatch({
    filled[,] <- as.matrix(csv_data$data)
  }, error = function(e) {
    stop("Error assigning matrix values: ", e$message)
  })
  
  desc <- if (!is.null(description)) description else csv_data$description
  list(filled = filled, description = desc)
}

# Loader for 3D data (assuming gender as third dimension)
load_3d <- function(name, dir_path, template, description) {
  genders <- c("male", "female")
  filled <- template
  desc <- NA
  
  for (gender in genders) {
    path <- here::here(dir_path, paste0(name, "_", gender, ".csv"))
    csv_data <- read_and_validate_csv(path, exclude_cols = c(1, 2))
    
    if (nrow(csv_data$data) < ncol(csv_data$data)) {
      stop(paste0("Dimension mismatch in gender CSV: ", gender))
    }
    
    tryCatch({
      filled[, , gender] <- as.matrix(csv_data$data)
    }, error = function(e) {
      stop(paste0("Error assigning ", gender, " slice: ", e$message))
    })
    
    if (is.na(desc)) {
      desc <- if (!is.null(description)) description else csv_data$description
    }
  }
  
  list(filled = filled, description = desc)
}

# Special loader for lookup table (no template)
load_lookup <- function(name, input_dir, module, description = NULL) {
  dir_path <- here::here(input_dir)  # Don't add "lookup/" again here
  if (!dir.exists(dir_path)) stop(paste0("Lookup directory does not exist: ", dir_path))
  
  file_path <- file.path(dir_path, paste0(name, ".csv"))  # Now use the directory directly without extra "lookup/"
  
  # Read and validate the CSV
  csv_data <- read_and_validate_csv(file_path, exclude_cols = 1)
  
  value <- csv_data$data
  desc <- if (!is.null(description)) description else csv_data$description
  
  # Assuming 'lookup' is the object in the parent frame
  lookup <- get("lookup", envir = parent.frame())
  idx <- lTo(module)
  set(lookup, i =idx, j = c("Name", "Value", "Description"), value = list(name, list(value), desc))
  
  invisible(value)
}


# Main function loadFill refactored
loadFill <- function(name, module, table, template = NULL, value = NULL, description = NULL) {
  dir_path <- get("dir", envir = parent.frame())
  if (!dir.exists(dir_path)) stop(paste0("Directory does not exist: ", dir_path))
  
  table_name <- deparse(substitute(table))

# Vérification du module dans tous les autres cas (sauf le cas "loadFillPol")
  if (is.null(module)) {
    stop("Error: Module must be specified for this loadFill operation. Please provide a module name.")
  }
    
    # Handle lookup case (no template)
  if (table_name == "lookup" && is.null(template)) {
    return(load_lookup(name, dir_path, module, description))  # Pass the module to load_lookup()
  }
    
  # Scalars case (no template)
  if (is.null(template)) {
    scalars_path <- here::here(dir_path, "_scalars.csv")
    scalars <- read.csv(scalars_path, header = TRUE)
    if (!"name" %in% names(scalars) || !"value" %in% names(scalars)) stop("Scalars file missing columns.")
    row <- scalars[scalars$name == name, ]
    if (nrow(row) == 0) stop(paste0("No scalar named '", name, "' found."))
    
    filled <- as.numeric(row$value[1])
    if (is.na(filled)) warning("Scalar could not be coerced to numeric.")
    desc <- if (!is.null(description)) description else {
      if ("description" %in% colnames(row)) row$description[1] else NA
    }
    
    idx <- switch(table_name, dp = pTo(module), init = iTo(module), stop("Unknown table name"))
    set(table, i = idx, j = c("Name", "Value", "Description"), value = list(name, filled, desc))
    
    return(invisible(filled))
  }
  
  # Template case with dimension dispatch
  n_dims <- if (is.null(dim(template))) 1 else length(dim(template))
  object_name <- tools::file_path_sans_ext(basename(name))
  
  loader <- switch(as.character(n_dims),
                   "1" = load_1d,
                   "2" = load_2d,
                   "3" = load_3d,
                   stop("Only up to 3-dimensional templates are supported.")
  )
  
  result <- loader(name, dir_path, template, description)
  
  idx <- switch(table_name, dp = pTo(module), init = iTo(module), stop("Unknown table name"))
  set(table, i = idx, j = c("Name", "Value", "Description"), value = list(object_name, result$filled, result$description))
  
  invisible(result$filled)
}
