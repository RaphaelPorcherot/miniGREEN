# BEGIN StrFunctions

############################################################################################################
############################################################################################################

                                            # ~~~~~~~~~~~ #
                                            # VENSIM to R #
                                            # ~~~~~~~~~~~ #

# To help smoothing the transition, in the documentation can be found a list of common equivalents or alternative strategies to reproduce vensim-like functions in R. 

# Below can be found only the code for the custom functions that needed to be written to reproduce vensim features with no direct R counterparts.

# What it does

    #smooth_vensim(x, delay)	✅	classique
    #smooth_vensim(x * 2, delay)	✅	constante dans l'expression
    #smooth_vensim(x * cst, delay)	✅	cst dans env global
    #smooth_vensim(x * y, delay)	✅	x, y dans d, récupérés avec gda()
    #smooth_vensim(cst * x * y, delay)	✅	mix de globales et de d

# What it does not

    # TBD

smooth_vensim <- function(x, delay, dt = 1) {
    # Chercher delay dans l'environnement global, dp, ou init
    env <- parent.frame()

    # Récupérer la valeur de delay depuis dp, init ou global
    delay_expr <- deparse(substitute(delay))
    delay_value <- NULL
    if (exists("dp", envir = env) && delay_expr %in% get("dp", envir = env)$Name) {
        # delay dans dp, récupérer la fonction gp(v)
        delay_value <- gp(delay_expr)
    } else if (exists("init", envir = env) && delay %in% get("init", envir = env)$Name) {
        # delay dans init, récupérer la fonction gi(v)
        delay_value <- gi(delay_expr)
    } else if (exists(delay, envir = env)) {
        # delay dans l'environnement global
        delay_value <- get(delay, envir = env)
    } else {
        stop(paste("Delay variable", delay, "not found in dp, init or .GlobalEnv"))
    }

    # Calcul de alpha
    alpha <- dt / delay_value
    if (alpha <= 0 || alpha > 1) stop("alpha = dt/delay must lie in (0,1]")

    # Créer un environnement temporaire pour évaluation des variables
    x_expr <- substitute(x)
    temp_env <- new.env(parent = env)
    on.exit(rm(temp_env), add = TRUE)

    t_val <- tryCatch(
        get("t", envir = env, inherits = TRUE), 
        error = function(e) 1
    )
    
    if (t_val == gp("startYear")) {
        # Si t = gp("startYear"), on évalue directement les variables dans l'environnement temporaire
        varnames <- all.vars(x_expr)
        
        for (v in varnames) {
            if (exists("init", envir = env) && v %in% get("init", envir = env)$Name) {
                # La variable est dans init → gi
                assign(v, gi(v), envir = temp_env)
            } else if (exists("dp", envir = env) && v %in% get("dp", envir = env)$Name) {
                # La variable est dans dp → gp
                assign(v, gp(v), envir = temp_env)
            } else if (exists(v, envir = env)) {
                # Variable dans l'env global
                assign(v, get(v, envir = env), envir = temp_env)
            } else {
                stop(paste("Variable", v, "not found in dp, init or .GlobalEnv"))
            }
        }
        # Évaluer l'expression avec les variables dans temp_env
        x_val <- eval(x_expr, envir = temp_env)
        x <- unname(x_val)  # On enlève le nom de la variable pour simplifier
    } else {
        # Si t > 1, lissage passé
        varnames <- all.vars(x_expr)
        
        for (v in varnames) {
            if (exists("d", envir = env) && v %in% get("d", envir = env)$Name) {
                # La variable est dans d → gda
                assign(v, get("gda", envir = env)(v), envir = temp_env)
            } else if (exists("init", envir = env) && v %in% get("init", envir = env)$Name) {
                # La variable est dans init → gi
                assign(v, gi(v), envir = temp_env)
            } else if (exists("dp", envir = env) && v %in% get("dp", envir = env)$Name) {
                # La variable est dans dp → gp
                assign(v, gp(v), envir = temp_env)
            } else if (exists(v, envir = env)) {
                # Variable dans l'env global
                assign(v, get(v, envir = env), envir = temp_env)
            } else {
                stop(paste("Variable", v, "not found in d, dp, init or .GlobalEnv"))
            }
        }

        x_val <- eval(x_expr, envir = temp_env)
        x <- x_val
    }

    # Gestion vecteur ou matrice
    if (is.matrix(x)) {
        n <- nrow(x)
        p <- ncol(x)
    } else {
        n <- length(x) # To check if x is scalar, 1D, 2D etc
        p <- 1
        x <- matrix(x, ncol = 1)
    }
    
    # First period case : Si t_val = gp("startYear"), on retourne x tel quel, there is nothing to smooth over
    if (n == 1 || t_val == gp("startYear")) { 
        if (p == 1) {
            return(as.vector(x))  # Retourner sous forme de vecteur si p == 1
        } else {
            return(x)  # Retourner sous forme de matrice si p > 1
        }    
    } else {
        # Sinon on applique le lissage
        S <- matrix(0, nrow = n, ncol = p)
        for (j in 1:p) {
            S[1, j] <- x[1, j]
            for (i in 2:n) {
                S[i, j] <- S[i - 1, j] + alpha * (x[i, j] - S[i - 1, j])
            }
        }
        if (p == 1) {
            return(as.vector(S[n, ]))  # Retourner sous forme de vecteur si p == 1
        } else {
            return(S[n, ])  # Retourner sous forme de matrice si p > 1
        }
    }
}

############################################################################################################
############################################################################################################

                                        # ~~~~~~~~~~~~~~~~ #
                                        # MODEL MANAGEMENT #
                                        # ~~~~~~~~~~~~~~~~ #

# -----------------------------------------------------------------------------------------------------------
                                        # Loading stuff #
# -----------------------------------------------------------------------------------------------------------

# create init dp lookup and dp ------------------------------------------------------------------------------
create_data_table <- function(name, n, cols = list(), order_by = NULL) {
  combinations <- do.call(expand.grid, c(cols, list(Name = rep(NA_character_, n))))
  
  dt <- data.table(combinations,
                   Value = rep(list(NA), nrow(combinations)),
                   Description = rep(list(NA), nrow(combinations)))
  
  # Si order_by est défini, on applique l'ordre
  if (!is.null(order_by)) {
    do.call(setorder, c(list(dt), order_by))
  }
  
  assign(name, dt, envir = .GlobalEnv)  # Assign to global environment
  toKeep <<- c(toKeep, name)
}

# loadFillPol to load policy shocks and shifts --------------------------------------------------------------

loadFillPol <- function(name, value, description=NULL) {
        
        object_name <- name
        filled <- value
        desc <- if(!is.null(description)) description else NA
        idx <- pTo("POLICY")
    
        set(dp, i = idx, j = c("Name", "Value", "Description"), value = list(object_name, filled, desc))        
    
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
  idx <- lTo(module)
  set(lookup, i =idx, j = c("Name", "Value", "Description"), value = list(name, list(value), desc))
  
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
    scalars_path <- file.path(input_dir, "_scalars.csv")
    
    if (file.exists(scalars_path) && to_load != "lookup") {
        scalars <- read.csv(scalars_path, header = TRUE)
        if (!all(c("name", "value", "table") %in% names(scalars))) stop("Non-standard columns name in _scalars.csv/. Expected order : name, value, module, type, units, description ")

        scalars_sub <- scalars[scalars$table == to_load, ]

        for (i in seq_len(nrow(scalars_sub))) {
            row <- scalars_sub[i, ]
            name <- as.character(row$name)
            filled <- as.numeric(row$value)
            module <- row$module
            if (is.na(filled)) warning(paste0("Scalar '", name, "' has no or NA value after conversion to numeric."))
            desc <- if ("description" %in% names(row)) row$description else NA
                
            idx <- switch(to_load, parameter = pTo(module), initial = iTo(module))
            toTable <- switch(to_load, parameter = dp, initial = init)

            set(toTable, i = idx, j = c("Name", "Value", "Description"), value = list(name, filled, desc))
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
            idx <- switch(to_load, parameter = pTo(module), initial = iTo(module))
            toTable <- switch(to_load, parameter = dp, initial = init)
            name <- ifelse(n_dims==3, file$name, name)
            set(toTable, i = idx, j = c("Name", "Value", "Description"), value = list(name, file$filled, file$description))
    }
  }

  invisible(TRUE)


} 

# source module files and assign module name to each function -------------------------------------------------

sourceSet <- function(module_name) {
    prev <- ls(envir=.GlobalEnv)
    module_path <- here(module_dir, paste0(module_name, ".r")) 
    if (!file.exists(module_path)) stop("Module file not found: ", module_path)
    source(module_path)
        
    # identify new function
    now <- ls(envir=.GlobalEnv)
    delta <- setdiff(now, prev)
    is_func <- sapply(delta, function(nom) is.function(get(nom, envir = .GlobalEnv)))
    delta <- delta[which(is_func)]
        
    # attribute them module_name for eq() to retrieve and associate to output
    for(f in delta){
        func <- get(f, envir=.GlobalEnv)  
        attr(func, "module") <- module_name
        assign(f, func, envir=.GlobalEnv)
    }

    invisible(delta) # we could store the list of functions in it
}


# -------------------------------------------------------------------------------------------------------------
                                            # Set and get stuff #
# -------------------------------------------------------------------------------------------------------------

# dp datatable ------------------------------------------------------------------------------------------------

### to use with the set() functions in the data.table dp

pTo <- function(module) {
  index <- which(dp$Module == module & is.na(dp$Name))[1]
  
  if (is.na(index)) {
    stop("No unmodified line found in the module - consider increasing npar", module)
  }
  
  return(index)
}

    ### To access values in the parameter datatabl


gp <- function(param, info = NULL) {
  valid_choices <- c("all", "desc", "mod")

  if (is.null(info)) {
    result <- dp[Name == param, Value]
    if (length(result) == 0) {
      stop(paste0("Parameter '", param, "' not found in dp. No value found."))
    }
    return(result[[1]])
  }

  if (!(info %in% valid_choices)) {
    stop(paste0("Unknown input in info field: '", info, "'. Allowed values are: ", paste(valid_choices, collapse = ", "), "."))
  }

  result <- dp[Name == param]
  if (nrow(result) == 0) {
    stop(paste0("Parameter '", param, "' not found in dp."))
  }

  switch(info,
    all = result[1],
    desc = {
      if ("Description" %in% names(result)) {
        result$Description[[1]]
      } else {
        stop("Column 'Description' not found in dp.")
      }
    },
    mod = {
      if ("Module" %in% names(result)) {
        result$Module[[1]]
      } else {
        stop("Column 'Module' not found in dp.")
      }
    }
  )
}

# init datatable ----------------------------------------------------------------------------------------------   

### to use with the set() functions in the data.table init

iTo <- function(module) {
  index <- which(init$Module == module & is.na(init$Name))[1]
  
  if (is.na(index)) {
    stop("No unmodified line found in the module - consider increasing nvar", module)
  }
  
  return(index)
}

    ### To access values in the initial value datatable

gi <- function(var, info = NULL) {
  valid_choices <- c("all", "desc", "mod")

  if (is.null(info)) {
    result <- init[Name == var, Value]
    if (length(result) == 0) {
      stop(paste0("Initial variable '", var, "' not found in init. No value found."))
    }
    return(result[[1]])
  }

  if (!(info %in% valid_choices)) {
    stop(paste0("Unknown input in info field: '", info, "'. Allowed values are: ", paste(valid_choices, collapse = ", "), "."))
  }

  result <- init[Name == var]
  if (nrow(result) == 0) {
    stop(paste0("Initial variable '", var, "' not found in init."))
  }

  switch(info,
    all = result[1],
    desc = {
      if ("Description" %in% names(result)) {
        result$Description[[1]]
      } else {
        stop("Column 'Description' not found in init.")
      }
    },
    mod = {
      if ("Module" %in% names(result)) {
        result$Module[[1]]
      } else {
        stop("Column 'Module' not found in init.")
      }
    }
  )
}

# lookup datatable --------------------------------------------------------------------------------------------

### to use with the set() functions in the data.table lookup

lTo <- function(module) {
  index <- which(lookup$Module == module & is.na(lookup$Name))[1]
  
  if (is.na(index)) {
    stop("No unmodified line found in the module - consider increasing nlookup", module)
  }
  
  return(index)
}

    ### To access values in the initial value datatable

gl <- function(graphfun, info = NULL) {
  valid_choices <- c("all", "desc", "mod")

  if (is.null(info)) {
    result <- lookup[Name == graphfun, Value]
    if (length(result) == 0) {
      stop(paste0("Graphical function '", graphfun, "' not found in lookup. No value found."))
    }
    return(result[[1]])
  }

  if (!(info %in% valid_choices)) {
    stop(paste0("Unknown input in info field: '", info, "'. Allowed values are: ", paste(valid_choices, collapse = ", "), "."))
  }

  result <- lookup[Name == graphfun]
  if (nrow(result) == 0) {
    stop(paste0("Graphical function '", graphfun, "' not found in lookup."))
  }

  switch(info,
    all = result[1],
    desc = {
      if ("Description" %in% names(result)) {
        result$Description[[1]]
      } else {
        stop("Column 'Description' not found in lookup.")
      }
    },
    mod = {
      if ("Module" %in% names(result)) {
        result$Module[[1]]
      } else {
        stop("Column 'Module' not found in lookup.")
      }
    }
  )
}

# d main datatable --------------------------------------------------------------------------------------------

    ### to use with the set() functions in the main data.table d

To <- function(module, period) {
  index <- which(d$Module == module & d$Period == period & is.na(d$Name))[1]
  if (is.na(index)) {
    stop("No unmodified line found for Module: ", module, " and Period: ", period, " - consider increasing nvar")
  }
  
  return(index)
}

    ### To access values in the main d datatable
gd <- function(var, time, info = NULL) {
  valid_choices <- c("all", "desc", "mod")

  if (is.null(info)) {
    result <- d[Name == var & Period==Period, Value]
    if (length(result) == 0) {
      stop(paste0("Variable '", var, "' not found in d. No value found."))
    }
    return(result[[1]])
  }

  if (!(info %in% valid_choices)) {
    stop(paste0("Unknown input in info field: '", info, "'. Allowed values are: ", paste(valid_choices, collapse = ", "), "."))
  }

  result <- lookup[Name == var]
  if (nrow(result) == 0) {
    stop(paste0("Variable '", var, "' not found in d."))
  }

  switch(info,
    all = result[1],
    desc = {
      if ("Description" %in% names(result)) {
        result$Description[[1]]
      } else {
        stop("Column 'Description' not found in d")
      }
    },
    mod = {
      if ("Module" %in% names(result)) {
        result$Module[[1]]
      } else {
        stop("Column 'Module' not found in d")
      }
    }
  )
}

    ### To get all the values of a variable in main d datatable

gda <- function(var) {
  result <- d[Name == var, Value]
  
  # Cas où aucune correspondance
  if (length(result) == 0) {
    warning(paste0("Variable '", var, "' not found in main datatable. Returning NA.")) # does not work
    return(NA)
  }

  # Si tous les éléments sont de longueur 1 → retourne un vecteur numérique
  if (all(sapply(result, length) == 1)) {
    return(as.numeric(unlist(result)))
  }

  # Si tous les éléments ont la même longueur > 1 → retourne une matrice
  len_vecs <- sapply(result, length)
  if (length(unique(len_vecs)) == 1 && unique(len_vecs) > 1) {
    return(do.call(rbind, result))  # matrice n x p
  }

  # Sinon : retourne tel quel (liste hétérogène, non simplifiable)
  return(result)
}

# -------------------------------------------------------------------------------------------------------------
                                            # Cleaning stuff #
# -------------------------------------------------------------------------------------------------------------


# Fonction de checkpoint mémoire ------------------------------------------------------------------------------

memory_checkpoint <- function(step_name = "") {
  mem <- mem_used()
  mem_mb <- round(as.numeric(mem) / (1024^2), 2)
  cat(sprintf("[%s] Mémoire utilisée : %.2f Mo\n", step_name, mem_mb))
}


# Fonction pour supprimer tous les objets sauf ceux dans 'toKeep' ---------------------------------------------
clean_ws <- function() {
  # Vérifiez si 'toKeep' existe dans l'environnement global
  if (!exists("toKeep", envir = .GlobalEnv)) {
    stop("The list of objects to be kept has not been defined.")
  }
  
  # Obtenez la liste de tous les objets dans l'environnement global
  all_objects <- ls(envir = .GlobalEnv)
  
  # Supprimez tous les objets qui ne sont pas dans 'toKeep'
  objects_to_remove <- setdiff(all_objects, toKeep)
    
    if (length(objects_to_remove) == 0) {
    message("No objects to delete. All objects are retained.")
    log_message("No objects to delete. All objects are retained.")  # Utilisation de log_file directement
    return()
  }
  # Supprimez les objets à partir de l'environnement global
  rm(list = objects_to_remove, envir = .GlobalEnv)
    deleted_objects_msg <- paste(objects_to_remove, collapse = ", ")
    message("The following objects have been deleted: ", deleted_objects_msg)
    sep <- paste(rep("─", 60), collapse = "")
    log_message(paste0(
        "\n", sep,
        "\n", "🗑️ Cleaning workspace",
        "\n⏰ ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        "\n", sep)
               )
                
    log_message(paste("The following objects have been deleted: ", deleted_objects_msg))  # Utilisation de log_file directement
  
}

# ----------------------------------------------------------------------------------------------------------
                            # Functions for main loop
# ----------------------------------------------------------------------------------------------------------

# to reset eq log ------------------------------------------------------------------------------------------
clear_eq_log <- function() {
    .message_log <<- list(
        success = character(), 
        failure = character()
    )
}

# to print eq log ------------------------------------------------------------------------------------------
print_eq_log <- function() {
  for (msg in .message_log$failure) message(msg)

  all_ok <- length(.message_log$failure) == 0

  if (all_ok) {
    message("✅ Run with success – all variables have been computed ✅")
  }

  .message_log <<- list(success = character(), failure = character())

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
  deps_all <- setdiff(all_vars, c(assigned_vars, for_vars, templates, auxiliaries, excluded_vars))

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
eq <- function(expr_block, dep = NULL) {
  
  # Initialize message log if not already present
  if (!exists(".message_log", envir = .GlobalEnv)) {
    assign(".message_log", list(success = character(), failure = character()), envir = .GlobalEnv)
    message("ℹ️ .message_log was automatically initialized.")
  }

  # Get the name of the calling function
  calling_func <- sys.call(-1)
  func_name <- as.character(calling_func)[1]

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

    # Log success message
    .message_log$success <<- c(.message_log$success,
                               paste0("✅ ", func_name, " run with success.",
                                      if (!is.null(target_var)) paste0(" Calculated: ", target_var, ".")))

    # Attach metadata: dependencies, auxiliaries, and function name
    res <- structure(result, deps = deps, auxiliaries = auxiliaries, equation = func_name)

                                      # assign to globlEnv to avoid having to <<- in each eq() bloc
      if (is.null(target_var)) {
          stop(paste0("❌ Internal error in eq(): 'target_var' is NULL at assignment stage. ",
                      "Check the expression block in function '", func_name, "'."))
      } else {
          assign(target_var, res, envir = .GlobalEnv)
      }
      
    # If in simulation mode, update the data table accordingly
   if (exists("dev_or_run", envir = .GlobalEnv) && dev_or_run == "run") {
      
      already_defined <- d[Period == t & Module == module_name & Name == target_var, .N] > 0
    
      if (!already_defined) {
        set(d, i = To(module_name, t), j = c("Name", "Value"), value = list(target_var, list(res)))
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

# Créer un environnement local
env <- new.env()

#message("✅ Functions loaded, see ", log_file, " for details.")
message("✅ Functions loaded")

# Lire le contenu du fichier et extraire les lignes entre les balises BEGIN et END
script_lines <- readLines(here("notebooks", "r-nb", "A-prepSteps","1-customFunctions.R"))
start_line <- grep("# BEGIN StrFonctions", script_lines)
end_line <- grep("# END StrFonctions", script_lines)

# Extraire le code entre ces lignes
code_lines <- script_lines[(start_line + 1):(end_line - 1)]

# Écrire ce code dans un fichier temporaire
temp_file <- tempfile()
writeLines(code_lines, temp_file)

# Sourcer le fichier temporaire dans l'environnement local
source(temp_file, local = env)

# Liste des objets dans l'environnement local
functions_in_env <- ls(envir = env)

# Filtrer pour obtenir uniquement les fonctions
functions_in_env <- functions_in_env[
    sapply(
        functions_in_env, function(x) is.function(
            get(x, envir = env)
        )
        )
]

toKeep0 <<- functions_in_env

# Define groups of functions to be excluded
excluded_functions <- list(
  "Get variables" = c("gd", "gi", "gp"),  # Group for model management functions related to "gd", "gi", "gp"
  "Assign variables" = c("iTo", "pTo", "To"),  # Group for other related functions: "iTo", "pTo", "To"
  "Write equations" = c("dep_check", "eq"),  # Group for "dep_check" and "eq"
  "Free memory" = c("clean_ws")  # Group for clean workspace function
)

# Initialize a vector to store custom functions (functions to be included)
custom_functions <- functions_in_env

# Exclude the functions defined in the excluded groups
for (group in excluded_functions) {
  custom_functions <- setdiff(custom_functions, group)
}

# Sort the remaining custom functions alphabetically
custom_functions_sorted <- sort(custom_functions)

# Message pour informer que les fonctions ont été chargées
log_message("###############################")
log_message("🌍 Functions Loaded")
log_message("###############################")
log_message("\n")


# Préparer l'affichage des résultats dans le log
log_message("###############################")
log_message("👌 Custom Functions:")
log_message("###############################")
log_message(paste(custom_functions_sorted, collapse = "\n"))
log_message("\n")

# Afficher les fonctions des groupes exclues
log_message("\n###############################")
log_message("👌 Model Mangement Functions:")
log_message("###############################")
for (group_name in names(excluded_functions)) {
  log_message(paste(group_name, ":"))
  log_message(paste(excluded_functions[[group_name]], collapse = "\n"))
    log_message("\n")
}

# Prepare the display of results
#message("Custom Functions:")
# Print out the list of custom functions
#message(paste(custom_functions_sorted, collapse = "\n"))

# Print out the functions in each group (model management)
#message("\nModel Management Functions:")
# Loop through each group in excluded_functions and print their functions
#for (group_name in names(excluded_functions)) {
 # message(paste(group_name, ":"))
  #message(paste(excluded_functions[[group_name]], collapse = "\n"))
#}
   
# Nettoyer le fichier temporaire
unlink(temp_file)

rm(env)


toKeep <- c(toKeep, toKeep0)
