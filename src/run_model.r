# Structural elements
options(warn = -1) # Suppresses warnings in this cell
options(jupyter.rich_display = FALSE) # Jupyter renders R output as HTML, not plain text — which is heavier. THis line allows to disable this feature.
options(width = 100) # Change la largeur d'affichage, augmente cette valeur selon tes besoins
#options(scipen = 999)  # Get rid of scientific notation
options(digits = 10)

suppressPackageStartupMessages({
  # Debug packages
  library(profvis)
  library(pryr)
  # Base packages
  library(data.table)
  library(here) # Useful to specify paths of file to oepn
  library(purrr) # Facilitates functional programming, enabling vectorization and efficient iteration over data structures like lists or vectors (but NOT ARRAYS !)
  library(tibble) # tibble functions
  library(dplyr) # A core package for data manipulation, allowing efficient filtering, transforming, and summarizing of datasets using intuitive functions.
  # Helper packages
  library(abind) # Provides the ability to concatenate multidimensional arrays along a specified dimension, allowing for flexible assembly of complex data structures, especially useful for 3D or higher-dimensional data manipulation.
  library(lubridate) # Streamlines date and time manipulation in R, making it easier to parse, extract, and work with date-time objects.
  library(truncnorm) # Generates random numbers from a truncated normal distribution, allowing you to define upper and lower bounds for your sample data.
  library(tidyr) # Simplifies data tidying by reshaping datasets (e.g., pivoting, unnesting) to prepare them for analysis or visualization.
})
# Prepare environment
rm(list = ls(all = TRUE))

# Open A-prepSteps files
toKeep <- c("toKeep")
input_dir <- here("notebooks", "r-nb", "inputs")

# LOGGING
source(here("notebooks", "r-nb", "A-prepSteps", "0-logConfig.r"))
source(here("notebooks", "r-nb", "A-prepSteps", "1-customFunctions.r"))
source(here("notebooks", "r-nb", "A-prepSteps", "2-structure.r"))

# ~~~ Create tables ~~~

# Create 'dp'
create_data_table(
  "dp",
  n = npar,
  cols = list(Module = modules),
  order_by = "Module"
)

# Create 'init'
create_data_table(
  "init",
  n = nvar,
  cols = list(Module = modules),
  order_by = "Module"
)

# Create 'lookup'
create_data_table(
  "lookup",
  n = nlookup,
  cols = list(Module = modules),
  order_by = "Module"
)

# Create 'd'
create_data_table(
  "d",
  n = length(timePeriods) * nvar,
  cols = list(Period = startYear:endYear, Module = modules),
  order_by = c("Period", "Module")
)


message("see ", log_file, " for details.")
memory_checkpoint("Preliminary steps")

# Size of datatables
#message(paste0("Size of the dp datatable: ", format(object.size(dp), units="auto")))
#message(paste0("Size of the init datatable: ", format(object.size(init), units="auto")))
#message(paste0("Size of the lookup datatable: ", format(object.size(lookup), units="auto")))
#message(paste0("Size of the d datatable: ", format(object.size(d), units="auto")))
