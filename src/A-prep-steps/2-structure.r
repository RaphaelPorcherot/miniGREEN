## BEGIN Structure

seed <- 18000 
set.seed(seed)
tolerance <- 1e-6
# Define the max number of variables and parameters by modules (and period for nvar) in order to preallocate the data.table
npar <- 250
nvar <- 100
nlookup <- 20

# nb iterations to avoid having to put each equations in the right order
iter <- 3
# number of periods
startYear <- 2010
timePeriods <- 60
endYear <- startYear + timePeriods
## Note that the first period in the d data.table is 1, not 0. There is thus timePeriods-1 periods of time. In Vensim it starts at 0. So each time there is time condition, we need to increase it by 1 in R.
covidYears <- c(2020,2021,2022)

#Saving options ####
#png = 0       #Note: 0 = display; 1 = save plots as png
#if(png==1){png(file="fig3.png",width=1800,height=2800,res=300)}
#if(png==1){dev.off()}

#Choose scenario ####
#scen = 1      #Note: 1 = higher markups; 2 = technical change 


# Define modules by retrieving them from inputs/, except Policy

#modules_in_inputs_folder <- list.dirs(path = input_dir, full.names = FALSE, recursive = FALSE)
#modules <- c("POLICY",modules_in_inputs_folder)

modules <- c("POLICY", # Policy and Shock
             "DEM", # Demography
             "TU", # Time Use
             "IO", # Input Ouput
             "P", # Prices
             "PVA", # Profits and VA
             "C", # Consumption
             "I", # Investment
             "TR", # International Trade
             "FI", # Finance
             "L", # Labour
             "GOV", # Governement 
             "TECH", # Technology
             "EN", # Energy
             "ENV", # Environnment
             "CADA", # Carbon tax et Damage Function
             "WD", # Water demand
             "WS" # Water suply
)

################################################################################################
################################################################################################

# BEGIN Dimensions

# ------------------------------------------------------------------------------------------
# Simple dimensions 
# ------------------------------------------------------------------------------------------

# Industry
industry <- c("agri",
              "mining",
              "manufacturing",
              "petroleum",
              "electricity",           
              "water",
              "construction",
              "trade",
              "transport",
              "hospitality",
              "ict",
              "finance",
              "realestate",
              "profserv",
              "public",
              "education",
              "health",
              "entertainment",
              "otherserv"
)

# Cohort
cohort <- c("0-14", "15-24", "25-44",  "45-64", "65+")
# Gender
gender <- c("male", "female")
# Skill
skill <- c("child", "low", "medium", "high", "cap")
# Status : we have an enlarged definition of olf that includes non retired cap and child
status <-  c("emp", # employed (LabEmp + LabJG)
             "unemp", # unemployed unempLab
             "olf", # ouf of the labour force
             "pension"  # pensioner, retired people
)
# Technology
technology <- paste0("T", 1:4) # Technology
# EnergySource
energy_source <- c("solid", "liquid", "gas", "biomass", "renew")
# EnergyUse
energy_use <- c("HHheat", "HHtransport", "HHother")
# Asset
asset <- c("deposits","bonds","equities")
# COICOP
coicop <- paste0("p_", c("food",
                         "tobacco",
                         "clothing",
                         "rental",
                         "water",
                         "electgas",
                         "furniture",
                         "medical",
                         "vehicles",
                         "transport",
                         "comunic",
                         "culture",
                         "education",
                         "restaurant",
                         "care",
                         "othserv"
                         ))

# TimeUse
timeuse <- c("phys", "study", "paid_w","unpaid_w","leisure")

# income bracket for income tax
n_incomeTaxBracket <- 5
name_bracket <- paste0("incTax_",1:n_incomeTaxBracket)


# ------------------------------------------------------------------------------------------
# Composite dimensions 
# ------------------------------------------------------------------------------------------

# IncomeGroup : composite dimension made of : status, skill, cohort
# gini order
df <- expand.grid(skill=skill,
                  status=status,
                  gender=gender) %>% 
arrange(status, gender, skill)

df <- df %>% filter(!(skill == "child"))  
df_grouped <- df %>% 
  mutate(group = case_when(
                           skill == "cap" ~ "cap",  # Tous les cap ensemble
                           #status == "pension" ~ paste0("pension_", gender),  # Pension par genre
                           TRUE ~ paste(skill, status, gender, sep = "_")  # Autres : combinaison complète
                  )
  )
df_grouped <- df_grouped %>% select(skill, status, gender, group)
income_group <- unique(df_grouped$group)
income_group <- c(
                  grep("^low", income_group, value = TRUE),
                  grep("^medium", income_group, value = TRUE),
                  grep("^high", income_group, value = TRUE),
                  grep("^pension", income_group, value = TRUE),
                  grep("^cap", income_group, value = TRUE)
)

# WageCategory : composite dimension made of : status, skill, cohort
# categories of wage earners used to compute gini of labor market. employed workers arranged according to gender, industry and skill.
# gini w order
df <- expand.grid(gender=gender,
                  industry=industry,
                  skill=skill) %>% 
arrange(gender, industry, skill)
df <- df %>% filter(!(skill %in% c("child", "cap")))   
df_grouped <- df %>% mutate(group = paste(gender, industry, skill, sep = "_"))
df_grouped <- df_grouped %>% select(gender, industry, skill, group)
wage_cat <- unique(df_grouped$group)
wage_cat <- c(
              grep("low$", wage_cat, value = TRUE),
              grep("medium$", wage_cat, value = TRUE),
              grep("high$", wage_cat, value = TRUE)
)

# macrosect and res
# macrosect

# END Dimensions

## Compute number of years in each cohort (importation for F_maturation_csg)
bounds <- strsplit(cohort, "[-+]")
lower_bounds <- as.numeric(sapply(
                                  bounds, function(x) 
                                    as.numeric(x[1])
                                  ))                                  
upper_bounds <- as.numeric(sapply(
                                  bounds, function(x) 
                                    ifelse(length(x) > 1, as.numeric(x[2]), NA)
                                  ))
yearsCohort_c <- upper_bounds - lower_bounds
yearsCohort_c <- yearsCohort_c+1
yearsCohort_c[length(yearsCohort_c)] <- NA

# Template arrays
# Notice the big cap for the dimension names (Cohort, Gender etc) 
# and the small caps for the modalities in each dimension (low, male, agri etc.)  

# --------------------------------------------------------------------------------
# Miscellaneous
# --------------------------------------------------------------------------------

# ~~|
# 1D| ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# ~~|

# energy source
template_energy_n <- array(0,
                           dim = c(length(energy_source)),
                           dimnames = list(EnergySource=energy_source)
)

# energy use

# special template
template_incometax <- array(0, 
                            dim = c(length(name_bracket)),
                            dimnames = list(Bracket=name_bracket) 
)


# --------------------------------------------------------------------------------
# Population
# --------------------------------------------------------------------------------

# ~~|
# 3D| ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# ~~|

template_population_csg <- array(0, 
                                 dim = c(length(cohort), length(skill), length(gender)),
                                 dimnames = list(Cohort = cohort, Skill = skill, Gender = gender)
)

template_population_dsg <- array(0, 
                                 dim = c(length(status), length(skill), length(gender)),
                                 dimnames = list(Status = status, Skill = skill, Gender = gender)
)

# ~~|
# 2D| ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ 
# ~~|

template_population_sg <- array(0, 
                                dim = c(length(skill), length(gender)),
                                dimnames = list(Skill = skill, Gender=gender)
)

template_population_dp <- array(0, 
                                dim = c(length(income_group), length(coicop)),
                                dimnames = list(IncomeGroup = income_group,COICOP=coicop)
)

template_population_ds <- array(0,
                                dim = c(length(status), length(skill)),
                                dimnames = list(Status=status, Skill=skill)
)


# ~~|
# 1D| ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# ~~|

template_population_s <- array(0,
                               dim = c(length(skill)),
                               dimnames = list(Skill=skill)
)

template_population_d <- array(0,
                               dim = c(length(status)),
                               dimnames = list(Status=status)
)


# --------------------------------------------------------------------------------
# Industry
# --------------------------------------------------------------------------------

# no child labour, no capitalist labour, but we do need the five "skills" for consistency reasons when crossing over demography arrays with industry arrays (see Labour module)
# Of course, first column (children) and last column (capitalist) will always be zero

# ~~|
# 4D| ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ 
# ~~|

# industry skill technology gender
template_industry_isvg <- array(0, 
                                dim = c(length(industry), length(skill), length(technology), length(gender)),
                                dimnames = list(Industry = industry, Skill = skill, Technology=technology, Gender=gender)
)

# ~~|
# 3D| ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# ~~|

# industry skill technology 
template_industry_isv <- array(0, 
                               dim = c(length(industry), length(skill), length(technology)),
                               dimnames = list(Industry = industry, Skill = skill, Technology=technology)
)


template_industry_isg <- array(0, 
                               dim = c(length(industry), length(skill), length(gender)),
                               dimnames = list(Industry = industry, Skill = skill, Gender=gender)
)

# ~~|
# 2D| ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# ~~|

# industry and skill
template_industry_is <- array(0, 
                              dim = c(length(industry), length(skill)),
                              dimnames = list(Industry = industry , Skill = skill)
)

# industry and technology
template_industry_iv <- array(0, 
                              dim = c(length(industry), length(technology)),
                              dimnames = list(Industry = industry , Technology = technology)
)

# industry and energy source
template_industry_in <- array(0, 
                              dim = c(length(industry), length(energy_source)),
                              dimnames = list(Industry = industry , EnergySource = energy_source)
)

# industry from AND industry to (IO)
template_industry_ii <- array(0, 
                              dim = c(length(industry), length(industry)),
                              dimnames = list(Industry = industry , Industry = industry)
)

# industry (nace) and coicop
template_industry_ip <- array(0, 
                              dim = c(length(industry), length(coicop)),
                              dimnames = list(Industry = industry , COICOP = coicop)
)

# ~~|
# 1D| ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# ~~|

template_industry_i <- array(0,
                             dim = c(length(industry)),
                             dimnames = list(Industry=industry)
)

################################################################################################
################################################################################################

## END Structure


# Créer un environnement local
env <- new.env()

#message("✅ Structure defined, see ", log_file, " for details.")
message("✅ Structure defined")
# Lire le contenu du fichier et extraire les lignes entre les balises BEGIN et END
script_lines <- readLines(path_prep("2-structure.r"))
start_line <- grep("# BEGIN Structure", script_lines)
end_line <- grep("# END Structure", script_lines)

# Extraire le code entre ces lignes
code_lines <- script_lines[(start_line + 1):(end_line - 1)]

# Écrire ce code dans un fichier temporaire
temp_file <- tempfile()
writeLines(code_lines, temp_file)

# Sourcer le fichier temporaire dans l'environnement local
source(temp_file, local = env)

# Liste des objets dans l'environnement local
functions_in_env <- ls(envir = env)

# Extraire et trier les éléments "template"
template_elements <- functions_in_env[grep("template", functions_in_env)]
template_elements <- sort(template_elements)

log_message("###############################")
log_message("🌍 Structural Elements Loaded")
log_message("###############################")
log_message("\n")
log_message(paste("Maximum number of parameters per module: ", env$npar))
log_message(paste("Maximum number of variables per module: ", env$nvar))
log_message(paste("Number of periods: ", env$timePeriods))
log_message(paste("Number of iterations: ", env$iter))
log_message(paste("Modules: ", paste(env$modules, collapse = ", ")))
log_message("Templates:")
log_message(paste(template_elements, collapse = "\n"))
log_message("\n")  # Ajouter une ligne vide pour séparer les sections dans le fichier de log


# Définir les éléments à conserver
toKeep1 <<- c("npar", "nvar", "timePeriods", "iter", "modules", template_elements)

# Nettoyer le fichier temporaire et l'environnement
unlink(temp_file)
rm(env)

# ────────────────────────────────────────────────────────────
# 🌍 STEP 3 : DIMENSIONS + LOGGING
# ────────────────────────────────────────────────────────────

# Créer un nouvel environnement local pour les dimensions
env <- new.env()

# Lire le contenu du fichier et extraire les lignes entre les balises BEGIN et END
script_lines <- readLines(path_prep("2-structure.r"))
start_line <- grep("# BEGIN Dimensions", script_lines)
end_line <- grep("# END Dimensions", script_lines)

# Extraire le code entre ces lignes
code_lines <- script_lines[(start_line + 1):(end_line - 1)]

# Écrire ce code dans un fichier temporaire
writeLines(code_lines, temp_file)

# Sourcer le fichier temporaire dans l'environnement local
source(temp_file, local = env)

# Liste des objets dans l'environnement local
objects_in_env <- ls(envir = env)
objects_in_env <- sort(objects_in_env)

log_message("###############################")
log_message("🌍 Defined Dimensions")
log_message("###############################")
log_message("\n")
log_message(paste(objects_in_env, collapse = "\n"))
log_message("\n")  # Ajouter une ligne vide pour séparer les sections dans le fichier de log


# Définir les éléments à conserver
toKeep2 <<- objects_in_env

# Nettoyer le fichier temporaire et l'environnement
unlink(temp_file)
rm(env)

# Fusionner les éléments à conserver
toKeep <- c(toKeep, toKeep1, toKeep2, "covidYears", "yearsCohort_c")

