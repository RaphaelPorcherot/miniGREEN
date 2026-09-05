## BEGIN Structure

seed <- 18000 
set.seed(seed)
tolerance <- 1e-6
# Define the max number of variables and parameters by modules (and period for nvar) in order to preallocate the data.table
npar <- 250
nvar <- 100
nlookup <- 20

# Safety cap on the number of passes the equation loop may make. It is not the
# number of passes taken: eq_run_passes() stops as soon as a pass resolves
# nothing new, and errors if that happens while equations are still waiting.
# The model settles in 3 passes today. See README.md 4.5.
max_passes <- 50
# number of periods
startYear <- 2010
timePeriods <- 60
endYear <- startYear + timePeriods
## Note that the first period in the d data.table is 1, not 0. There is thus timePeriods-1 periods of time. In Vensim it starts at 0. So each time there is time condition, we need to increase it by 1 in R.
covidYears <- c(2020,2021,2022)

# Time step. Annual and discrete for now, but written explicitly everywhere a
# state is updated, so that the move to a sub-annual step or to RK4 is a change
# of stepper and not a rewrite of the equations. See README.md §7.
dt <- 1

# Region. One for now; every table and every input CSV carries the column so
# that the multi-regional version is a change of content, not of shape.
# See README.md §10.
regions        <- c("IT")
DEFAULT_REGION <- "IT"

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
# PopGroup — the partition of the population.
#
# It folds three different things into one dimension: a generational status
# (`child`, does not work yet), an actual qualification level (`low`, `medium`,
# `high`) and a class status (`cap`, capitalist). That is deliberate: the
# alternative, a separate `class` dimension, would be a mostly-empty Cartesian
# product, since a capitalist has no qualification level.
#
# The price is that "summing over the dimension" has no single meaning. So the
# genuine qualifications are available as a named subset, and code indexes by
# name — never by position, never by hand-written exclusion. See README.md §5.3.
pop_group <- c("child", "low", "medium", "high", "cap")
skill     <- c("low", "medium", "high")            # the actual qualifications
non_skill <- setdiff(pop_group, skill)             # child and cap
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
df <- expand.grid(pop_group=pop_group,
                  status=status,
                  gender=gender) %>% 
arrange(status, gender, pop_group)

df <- df %>% filter(!(pop_group == "child"))  
df_grouped <- df %>% 
  mutate(group = case_when(
                           pop_group == "cap" ~ "cap",  # Tous les cap ensemble
                           #status == "pension" ~ paste0("pension_", gender),  # Pension par genre
                           TRUE ~ paste(pop_group, status, gender, sep = "_")  # Autres : combinaison complète
                  )
  )
df_grouped <- df_grouped %>% select(pop_group, status, gender, group)
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
# Only actual qualifications here: the Vensim original filtered child and cap
# out of the full partition, which is exactly what `skill` now is.
df <- expand.grid(gender=gender,
                  industry=industry,
                  skill=skill) %>% 
arrange(gender, industry, skill)
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

# ------------------------------------------------------------------------------
# THE STATES
# ------------------------------------------------------------------------------
#
# The 2026 Vensim model has exactly 35 INTEG variables. That list is closed and
# is the authority for what carries Kind == "state": a variable that carries its
# own past, has an initial value, and is advanced by the stepper rather than
# recomputed from scratch. See README.md §6.
#
# `r` is NA where the variable is not translated yet. `integ_rationale` is
# filled only where the economic reading and the numerical one diverge — a share
# that is nonetheless a state — and says in one line why it must integrate.

model_states <- data.frame(
  stringsAsFactors = FALSE,
  vensim = c(
    "Pop 014 g / Pop 1524 g / Pop 2544 g / Pop 4564 g / Pop 65+ g / Skills {1524,2544,4564,65+} gs",
    "LFPR gs",
    "wage gis",
    "male share is",
    "skill trend is",
    "smooth(sens skill cs * (u s[mid] - u s), duration skill transition)",
    "K i",
    "Share source Ed Z nrg i",
    "I desired i",
    "gov c nom i",
    "prob T2 i",
    "prob T3 i",
    "adaptation",
    "stock of bonds",
    "interest",
    "debt i",
    "b cap", "b gs", "d cap", "d gs", "eq cap", "eq gs"
  ),
  r = c(
    "ST_population_csg",
    "R_LFRP_csg",
    "R_hrWage_isg",
    "SH_male_is",
    "SH_skill_is",
    "R_smoothSkillShift_s",
    "ST_Kreal_i",
    "SH_enSrc_enDemZ_in",
    NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA
  ),
  # The R flow that feeds each state, where the state is translated and active.
  # NA means the state's equation is still commented out of the main loop.
  flow = c(
    "F_population_csg", NA, NA, "F_maleShare_is", "F_skillShare_is",
    "F_smoothSkillShift_s", NA, NA,
    NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA
  ),
  module = c(
    "DEM", "L", "L", "L", "L", "DEM", "I", "EN",
    "I", "GOV", "TECH", "TECH", "CADA",
    "FI", "FI", "FI", "FI", "FI", "FI", "FI", "FI", "FI"
  ),
  integ_rationale = c(
    NA,
    NA,
    NA,
    "A share economically. The inflow contains a saturation guard that reads the stock itself (IF THEN ELSE(... + male share is > 1, 0, ...)), so it is self-referential and genuinely path-dependent. Cannot be an auxiliary.",
    "A share economically. Its inflow is purely exogenous (convergence * trend), so a closed-form cumulative sum would work. Kept as a state for uniform treatment only.",
    NA,
    "A Vensim SMOOTH, which is a hidden stock: dSmooth/dt = (input - Smooth) / delay. It is not one of the 35 INTEG because Vensim writes SMOOTH() inline rather than declaring it, but it carries its own past exactly as they do, and is declared here so that it appears in d like any other state.",
    "A share economically. The inflow reads the stock: -g(t) * ZIDZ(Share[nrg], 1 - Share[renew]). Making it an auxiliary would create an algebraic loop, and the model is sequentially solvable precisely because this one is not.",
    NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA
  )
)

## Kind of a variable, from the states registry (README section 6.2).
##
##   state  it carries its own past and is advanced by advance_state()
##   flow   it is the net flow feeding one of those states
##   aux    everything else, recomputed from scratch each period
##
## A variable is a flow because it feeds a state, not because its name starts
## with F_. Plenty of F_ variables are flows in the economic sense — births,
## deaths, investment — without being the net flow of a state in this registry;
## they are terms that a net flow is built from.
variable_kind <- function(name) {
  if (name %in% stats::na.omit(model_states$r))    return("state")
  if (name %in% stats::na.omit(model_states$flow)) return("flow")
  "aux"
}

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

# ------------------------------------------------------------------------------
# TEMPLATES
# ------------------------------------------------------------------------------
#
# Every array in the model is built from a named template, so that dimension
# names travel with the data and a mismatch fails loudly instead of recycling
# silently.
#
# make_template() takes dimension NAMES (capitalised) and looks their modalities
# up in `dimension_modalities`. Writing them out by hand, as this file used to,
# meant that adding a dimension — a Region index, say — was twenty edits plus
# every loader. Now it is one.
#
#   make_template(c("Cohort", "PopGroup", "Gender"))
#
# The name of a template encodes its indices with the suffix letters of
# README.md §5.2, in the same order as its dimensions.

dimension_modalities <- list(
  Industry     = industry,
  Cohort       = cohort,
  Gender       = gender,
  PopGroup     = pop_group,
  Skill        = skill,
  Status       = status,
  Technology   = technology,
  EnergySource = energy_source,
  EnergyUse    = energy_use,
  Asset        = asset,
  COICOP       = coicop,
  TimeUse      = timeuse,
  Bracket      = name_bracket,
  IncomeGroup  = income_group,
  WageCat      = wage_cat,
  Region       = regions
)

## Build a named, zero-filled array from a vector of dimension names.
## A name may repeat: make_template(c("Industry", "Industry")) is the IO matrix.
make_template <- function(dims, fill = 0) {
  unknown <- setdiff(dims, names(dimension_modalities))
  if (length(unknown)) {
    stop("Unknown dimension(s): ", paste(unknown, collapse = ", "),
         ".\nKnown: ", paste(names(dimension_modalities), collapse = ", "), ".")
  }
  modalities        <- dimension_modalities[dims]
  names(modalities) <- dims          # keep duplicates, e.g. Industry x Industry
  # unname(): lengths() returns a *named* vector, which would put names on the
  # dim attribute itself and make otherwise identical arrays compare unequal.
  array(fill, dim = unname(lengths(modalities)), dimnames = modalities)
}

# --------------------------------------------------------------------------------
# Miscellaneous
# --------------------------------------------------------------------------------

template_energy_n  <- make_template("EnergySource")
template_incometax <- make_template("Bracket")

# --------------------------------------------------------------------------------
# Population
# --------------------------------------------------------------------------------

template_population_csg <- make_template(c("Cohort", "PopGroup", "Gender"))
template_population_dsg <- make_template(c("Status", "PopGroup", "Gender"))
template_population_sg  <- make_template(c("PopGroup", "Gender"))
template_population_ds  <- make_template(c("Status", "PopGroup"))
template_population_s   <- make_template("PopGroup")
template_population_d   <- make_template("Status")
template_population_dp  <- make_template(c("IncomeGroup", "COICOP"))

# --------------------------------------------------------------------------------
# Industry
# --------------------------------------------------------------------------------
#
# There is no child labour and no capitalist labour, but the full PopGroup
# partition is carried all the same, so that industry arrays cross cleanly with
# demography arrays (see the Labour module). The `child` and `cap` slices are
# structurally zero.

template_industry_isvg <- make_template(c("Industry", "PopGroup", "Technology", "Gender"))
template_industry_isv  <- make_template(c("Industry", "PopGroup", "Technology"))
template_industry_isg  <- make_template(c("Industry", "PopGroup", "Gender"))
template_industry_is   <- make_template(c("Industry", "PopGroup"))
template_industry_iv   <- make_template(c("Industry", "Technology"))
template_industry_in   <- make_template(c("Industry", "EnergySource"))
template_industry_ii   <- make_template(c("Industry", "Industry"))
template_industry_ip   <- make_template(c("Industry", "COICOP"))
template_industry_i    <- make_template("Industry")

################################################################################################
################################################################################################

## END Structure

# ------------------------------------------------------------------------------
# What this file defines, for the log.
#
# `template_elements` is not just for the log: loadFill() matches an input file
# against it to find the array it should be poured into. It used to be produced
# by re-sourcing the BEGIN/END Dimensions section into a temp environment and
# grepping it; the templates are in the global environment already, so ls() is
# both simpler and impossible to get out of step with the file.
# ------------------------------------------------------------------------------

template_elements <- sort(grep("^template_", ls(envir = .GlobalEnv), value = TRUE))

local({
  dims <- c("industry", "cohort", "gender", "skill", "pop_group", "status",
            "technology", "energy_source", "energy_use", "asset", "coicop",
            "timeuse", "income_group", "wage_cat", "regions")

  log_block("Structure loaded")
  log_info("Periods:    ", startYear, "-", endYear, " (", timePeriods, " steps of dt = ", dt, ")")
  log_info("Max passes: ", max_passes)
  log_info("Capacity:   npar = ", npar, ", nvar = ", nvar, ", nlookup = ", nlookup)
  log_info("Seed:       ", seed)
  log_info("Region(s):  ", paste(regions, collapse = ", "))
  log_objects(modules, "Modules")
  log_objects(intersect(dims, ls(envir = .GlobalEnv)), "Dimensions")
  log_objects(template_elements, "Templates")

  states <- model_states[!is.na(model_states$r), ]
  log_objects(states$r, "States translated")
  log_objects(model_states$vensim[is.na(model_states$r)], "States not translated yet")
})

keep_add(ls(envir = .GlobalEnv))

message("Structure defined")
