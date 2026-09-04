#!/usr/bin/env Rscript
# ===========================================================================
# run_model.r — REWIND orchestrator
#
# Runs the whole model: loads inputs, builds the four tables, sources the
# modules, then runs the simulation loop.
#
#   Rscript src/run_model.r
#
# See README.md for the architecture. Every path resolves through src/paths.r.
# ===========================================================================

# Start from a clean environment BEFORE anything is defined.
rm(list = ls(all = TRUE))

options(warn = -1)      # suppress warnings
options(width = 100)
options(digits = 10)
# options(scipen = 999) # uncomment to get rid of scientific notation

# --- paths -----------------------------------------------------------------
# Must come first: everything below refers to DIR_* and path_*().
# here() anchors on the project root by finding .git, so this works whatever
# the working directory is.
suppressPackageStartupMessages(library(here))
source(here::here("src", "paths.r"))

# --- packages --------------------------------------------------------------
suppressPackageStartupMessages({
  # Base
  library(data.table)
  library(purrr)     # functional programming over lists and vectors (NOT arrays)
  library(tibble)
  library(dplyr)
  # Helpers
  library(abind)     # bind arrays along an arbitrary dimension (3D and above)
  library(lubridate)
  library(truncnorm) # truncated normal draws, for RANDOM NORMAL()
  library(tidyr)
  # Profiling
  library(profvis)
  library(lobstr)    # mem_used(), for memory_checkpoint()
})

# --- engine ----------------------------------------------------------------
input_dir <- DIR_INPUT

source(path_prep("0-log-config.r"))
source(path_prep("1-custom-functions.r"))
source(path_prep("2-structure.r"))

#============================================================================
# STEP 0 — Build the four tables
#============================================================================

create_data_table("dp",     n = npar,    cols = list(Module = modules), order_by = "Module")
create_data_table("init",   n = nvar,    cols = list(Module = modules), order_by = "Module")
create_data_table("lookup", n = nlookup, cols = list(Module = modules), order_by = "Module")
create_data_table("d",
  n        = nvar,
  cols     = list(Period = startYear:endYear, Module = modules),
  order_by = c("Period", "Module")
)

deps_reset()   # the dependency table, filled by eq() as equations run

message("see ", log_file, " for details.")
memory_checkpoint("Preliminary steps")

#============================================================================
# STEP 1 — Load parameters, initial values and lookup tables
#============================================================================

# Import
# --------------------------------------------------------------------------------------------------
loadFill("parameter") # dp
loadFill("initial") # init
loadFill("lookup") # lookup

#============================================================================
# STEP 1b — Non-standard inputs (hand-shaped, no template match)
#============================================================================

# Non standard format
# ------------------------------------------------------------------------------------------
# parameter --------------------------------------------------------------------------------
dir <- path_input("parameter", "_non_standard")

# R_mortality_csg
temp  <- read.csv(file.path(dir, "R_mortality_csg.csv"), header=TRUE)
R_mortality_csg <- template_population_csg
R_mortality_csg[, ,"male"] <-  temp$male
R_mortality_csg[, ,"female"] <- temp$female

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
dt_set("dp", module = "DEM", name = "R_mortality_csg", value = R_mortality_csg)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


# --- Covid stuff : the rate of change during the 3 years of covid 
# R_dLFRPcovid
## DATA FROM ILO, labor force participation rate 2020, 15-64y -0.0248
## DATA FROM ILO, labor force participation rate 2021, 15-64y: 0.0061
## Assuming complete recover of labor force participation rate to pre-pandemic level \2022, 15-64y: 0.0192
temp  <- read.csv(file.path(dir, "R_dLFRPCovid.csv"), header=TRUE)
R_dLFRPCovid <- temp$changeRate

# --- R_dGFCFrealCovid
##2020 GET DIRECT CONSTANTS('economy.xlsx', 'inputoutput' , 'cov_i_1')    
##2021-2022 GET DIRECT CONSTANTS('economy.xlsx', 'inputoutput' , 'cov_i_2')
# note : 2021 value is recycled for 2022 value.
temp  <- read.csv(file.path(dir, "R_dGFCFrealCovid.csv"), header=TRUE)
R_dGFCFrealCovid <- temp$changeRate

# --- R_dXnomCovid
# c19 exp 2020= -0.154 GET DIRECT CONSTANTS('economy.xlsx', 'inputoutput' , 'cov_x_1')
# c19 exp 2021= 0.08 GET DIRECT CONSTANTS('economy.xlsx', 'inputoutput' , 'cov_x_2')
# IF THEN ELSE(Time=10*Year 1,c19 exp 2020,IF THEN ELSE(Time=11*Year 1,c19 exp 2021,0)\
# note : 2021 value recycled for 2022 value.
temp  <- read.csv(file.path(dir, "R_dXnomCovid.csv"), header=TRUE)
R_dXnomCovid <- temp$changeRate

# --- R_dCrealCovid.csv
#C19 cons 2020=-0.088  GET DIRECT CONSTANTS('economy.xlsx', 'inputoutput' , 'cov_c_1')
#c19 cons 2021=0.046 GET DIRECT CONSTANTS('economy.xlsx', 'inputoutput' , 'cov_c_2')	
# IF THEN ELSE(Time=10*Year 1,C19 cons 2020,IF THEN ELSE(Time=11* Year 1,c19 cons 2021,IF THEN ELSE(Time=12*Year 1,c19 cons 2021,0)))
# note : 2021 value recycled for 2022 value, but THAT WAS ALREADY THE CASE IN THE VENSIM MODEL (which treated hence inconsistenly GFGC and Xnom) 
temp  <- read.csv(file.path(dir, "R_dCrealCovid.csv"), header=TRUE)
R_dCrealCovid <- temp$changeRate

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
dt_set("dp", module = "L", name = "R_dLFRPCovid", value = R_dLFRPCovid)
dt_set("dp", module = "L", name = "R_dGFCFrealCovid", value = R_dGFCFrealCovid)
dt_set("dp", module = "L", name = "R_dXnomCovid", value = R_dXnomCovid)
dt_set("dp", module = "L", name = "R_dCrealCovid", value = R_dCrealCovid)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


# initial ----------------------------------------------------------------------------------

dir <- path_input("initial", "_non_standard")

## R_LFRP_csg : LFPR initial gs GET DIRECT CONSTANTS('economy.xlsx', 'labour', 'C58')
temp  <- read.csv(file.path(dir, "R_LFRP_csg.csv"), header=TRUE)
female_participationL_s <- temp$female
male_participationL_s <-  temp$male
R_LFRP_csg <- template_population_csg
#toUpdate <- c("15-24", "25-44", "45-64")
for(i in 2:(length(cohort)-1)){
    R_LFRP_csg[i,,"male"] <- c(0, male_participationL_s, 0)
    R_LFRP_csg[i,,"female"] <- c(0, female_participationL_s, 0)
}

## ST_population_csg
    ### Defining population cohorts by gender : init pop cg 
    ### GET DIRECT CONSTANTS('demography.xlsx', 'demography' , 'C3*' ) 
population_csg <- template_population_csg
temp  <- read.csv(file.path(dir, "ST_population_cg.csv"), header=TRUE)
population_csg[, ,"male"] <-  temp$male
population_csg[, ,"female"] <- temp$female
    ### Values for female and male cohorts : 
    ### init distr skill cgs GET_DIRECT_CONSTANTS('demography.xlsx', 'demography' , 'C8*' )
    ### previous values were adding up to (slightly) more than 1. I changed a bit, substracting (or summing) from (to) the high skill values.b
temp <- read.csv(file.path(dir, "SH_skillByCohort_male.csv"), header=TRUE)
male_cs <- as.matrix(temp)
temp <- read.csv(file.path(dir, "SH_skillByCohort_female.csv"), header=TRUE)
female_cs <- as.matrix(temp)

    ### Normalize male_cs to one
row_sums_male <- apply(male_cs, 1, sum)
male_cs <- sweep(male_cs, 1, row_sums_male, FUN = "/")
male_cs[is.nan(male_cs)] <- 0
    ### Creating the capitalist and the children columns
    #### Capitalist are not a true skill group. They are extracted after each period as 1% of total adult population and get assigned the profit income.
    #### They receive the same mortality rate as their cohort, but the constraint is that they be 1% of the whole adult population for each cohort. 
    #### They thus get adequately replenish at the end of the DEM module so as to satisfy this constraint
cap <- c(0, rep(0.01, length(cohort) - 1)) 
child <- c(1, rep(0, length(cohort) - 1))
    #### The three skills group do need to be only 99% of the whole adult population
    #### because their initial values matters for the computation of their first period value.
male_cs <- male_cs * 0.99
male_cs <- cbind(child, male_cs, cap)
female_cs <- female_cs * 0.99
female_cs <- cbind(child, female_cs, cap)
coeff_population_csg <- abind(male_cs, female_cs, along = 3) # same order as in gender : male, female

ST_population_csg <- population_csg*coeff_population_csg


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
dt_set("init", module = "L", name = "ST_labJG_csg", value = template_population_csg)
dt_set("init", module = "L", name = "R_LFRP_csg", value = R_LFRP_csg)
dt_set("init", module = "DEM", name = "ST_population_csg", value = ST_population_csg)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
log_message("✅ Parameters, initials, and lookup all loaded.")
#memory_checkpoint("Step 2.2")

#============================================================================
# STEP 1c — Minor computations on inputs
#============================================================================

# Minor computations
# --------------------------------------------------------------------------------------------------

# Rescaling ----------------------------------------------------------------------------------------
    # Make sure that price capital weights are equal to one
    rescale <- gp("SH_pK_i")/sum(gp("SH_pK_i"))
    dp[Name=="SH_pK_i", Value:=rescale]
    # Make sure that coicop weights on nace are equal to one.    
    rescale <- sweep(gp("bridgeNaceCoicop_ip"), 2, colSums(gp("bridgeNaceCoicop_ip")), `/`)
    dp[Name=="bridgeNaceCoicop_ip", Value:=rescale]
    # Make sure that skill shares on nace are equal to one. 
    rescale <- gi("SH_skill_is") / rowSums(gi("SH_skill_is"))
    init[Name=="SH_skill_is", Value := rescale]

# Miscellaneous ----------------------------------------------------------------------------------------

# max and min of growth of labour productivity by indsutryes
R_gLabProdMin_i <- gp("R_gLabProdMean_i") - 3 * gp("R_gLabProdSd_i")
R_gLabProdMax_i <- gp("R_gLabProdMean_i") + 3 * gp("R_gLabProdSd_i")
dt_set("dp", module = "TECH", name = "R_gLabProdMin_i", value = R_gLabProdMin_i)
dt_set("dp", module = "TECH", name = "R_gLabProdMax_i", value = R_gLabProdMax_i)
#============================================================================
# STEP 2 — Policy panel: triggers, shocks, shifts
#============================================================================

# Panel
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
                # Change values to change policies: soon to be CHANGED to SCENARIO panel
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

loadFillPol("I", diag(length(industry)), "ind*ind identity matrix")

# From 2-structure
loadFillPol("startYear", startYear, "simulation's starting year")
loadFillPol("timePeriods", timePeriods, "time span of the simulation")
loadFillPol("endYear", endYear, "simulation's final year")

# POLICY and SHOCK general timing
loadFillPol("startPolicy", 2022, "starting year for policies and shocks")
loadFillPol("lengthPolicy", 30 , "time span of policies")
loadFillPol("endPolicy", gp("startPolicy") + gp("lengthPolicy"), "final year of policies")
loadFillPol("lengthShock", 5, "time span for shocks")

if (gp("endPolicy") > gp("endYear")) {
  stop(sprintf(
    "Policies extend beyond simulation timespan.\nPolicies end in %s\nSimulation ends in %s\nConsider increasing timePeriods or decreasing lengthPolicy.",
    gp("endPolicy"),
    gp("endYear")
  ))
}
# ------------------------------------------------------------------------
# TRIGGERS and SWITCHES 
# ------------------------------------------------------------------------
loadFillPol("financialIncomeSwitch", 0, "0 - no bottom-up integration: Z,i,finance determined from input output ; 1 - bottom-up integration: Z,i,finance from financial module.")
loadFillPol("fullCapacityConstraint", 1, "0 - no constraint ; 1 - output limited by capital stock")
# Activate specific policies/shocks : 0 = inactive ; 1 : active
# ------------------------------------------------------------------------
# SHOCK
# ------------------------------------------------------------------------
# Markup
loadFillPol("Act_markupShock", 0, "shock on markup (all industries)")
loadFillPol("coeff_markupShock", 0.15, "Size of markup shock (factor)")
# domestic price 
loadFillPol("Act_priceShock", 0, "shock on prices ~~CHECK WHICH INDUSTRIES~~")
loadFillPol("slopeRamp_priceShock", 1/3, "size of price shock (slope of ramp)")
# Act_importPriceShock
loadFillPol("Act_importPriceShock", 0, "shock on import price") 
loadFillPol("coeff_importPriceShock", 0.13, "size of import price shock") # import price shock

# ------------------------------------------------------------------------
# PARAMETERS GRADUAL SHIFT
# ------------------------------------------------------------------------
# These additions : linear gradual enforcment of some adjustement paramaters (no one : 1).
# Goes into respective module panel not in POLICY panel (no policy as such)
# NEW ADDITION : absolute growth of export 
loadFillPol("Act_absoluteXgrowth", 0, "shifting initial absolute growth sector-specific export growth")
loadFillPol("coeff_absoluteXgrowth", 0, "shift's size")
# NEW ADDITION Act : Entry Skill -> R_trendEntrySkill_csg
loadFillPol("Act_entrySkill", 0, "shifting trend entry skill in DEM")
loadFillPol("coeff_trendEntrySkill", 0, "shift's size") # S skill supply trend
# NEW ADDITION : Act enhancing F_otherBenefitsPerCap
loadFillPol("Act_otherBenefits", 0, "shifting other benefits per capita")
loadFillPol("coeff_otherBenefits", 0, "shift's size")
# NEW ADDITION : Act enhancing POL_unempBenefitsShareInWageBill
loadFillPol("Act_grossUnempShare", 0, "shifting the gross unemployement benefits share in wage (in %)")
loadFillPol("coeff_grossUnempShare", 0, "shift's size")# S ub ratio
# NEW ADDITION : Act enhancing POL_pensionBenefitsShare_in_wageBill()
loadFillPol("Act_grossPensionShare", 0, "shifting the gross pension benefits share in wage (in %)")
loadFillPol("coeff_grossPensionShare", 0, "shift's size")# S pension ratio
# NEW ADDITION Act_shiftDepreciation
loadFillPol("Act_shiftDepreciation", 0, "shifting industry-specific real capital depreciation rates")
loadFillPol("coeff_shiftDepreciation", 0, "shift's size") # S depreciation rates±
# NEW ADDITION : scalling lambda Act_scalingLabProd
loadFillPol("Act_scalingLabProd", 0, "shifting industry-specific (and technology-specific) real labour productivity rate")
loadFillPol("coeff_scalingLabProd", 0.1, "shift's size") # S scalling lambda. Prev :3 
# NEW ADDITION value added tax rates.
loadFillPol("Act_VAT", 0, "shifting economy-wide value added tax rate")
loadFillPol("coeff_VAT", 0, "shift's size") #S vat rate 
# NEW ADDITION value added tax rates.
loadFillPol("Act_impShareInZ", 0, "shifting import share with respect to domestic in intermeiate trade")
loadFillPol("coeff_impShareInZ", 0, "shift's size") # S share imp Z
# ------------------------------------------------------------------------
# ACTUAL POLICIES
# ------------------------------------------------------------------------
# Act public  Renewable Energy Sources
loadFillPol("Act_publicRES",0,"divert public subsidies from fossil to renewable. Also activates renewable energy transition in the variable RES shares grates 2130 i")
loadFillPol("coeff_publicRES",1, "it is a fraction between 0 and 1 of the subsidies to fossils that might be diverted to RES public")
# Progressive income Tax 
loadFillPol("Act_progrIncomeTax",0,"increase the progressivity of the fixed number of income tax brackets")
coeff_progIncomeTax <- template_incometax
coeff_progIncomeTax[] <- c(0.1,0.25,0.55,0.85,0.9) # note that this must match length(gp("n_incomeTaxBracket")), else you will get an erro
loadFillPol("R_progIncomeTax",coeff_progIncomeTax,"new income tax rates, slightly more progressive") 
# we might want to add a logic allowing to parametrize the % change in progressiveity rather than just giving new absolute level of tax rates
# Phasing out non renewable energy
loadFillPol("Act_phaseOut", 0, "phasing out non-renewable energy source")
loadFillPol("how_phaseOut", 1, "1 - replace phase-out energy by renewable ony ; 0 - replace phased-out energy with existing energy product mix")
phaseOut_carbon <- 0 # phase out carbon ?
phaseOut_gas <- 0#phase out gas ?
phaseOut_oil <- 0 #phase out oil ?
phaseOut_bio <- 0 #phase out biomass ?
productPhaseOut_n <- template_energy_n
productPhaseOut_n[] <- c(phaseOut_carbon, phaseOut_gas, phaseOut_oil, phaseOut_bio, 0)
loadFillPol("productPhaseOut_n", productPhaseOut_n, "1 - to be phased out ; 0 - not to be phased out. Energy sources to be phased out (renewables are never phased out = always 0")
loadFillPol("lengthPhaseOut_carbon", 20, "number of years for carbon to be phased out")
loadFillPol("lengthPhaseOut_gas", 50, "number of years for gas to be phased out")
loadFillPol("lengthPhaseOut_oil", 30, "number of years for oil to be phased out")
loadFillPol("lengthPhaseOut_bio", 50, "number of years for biomass to be phased out")
    # the period the respective energy product is phased outer
lengthPhaseOut_n <- template_energy_n
lengthPhaseOut_n[] <- c(gp("lengthPhaseOut_carbon"), gp("lengthPhaseOut_gas"), gp("lengthPhaseOut_oil"), gp("lengthPhaseOut_bio"), 0)
# was: loadFillPol("lengthPhaseOut_i", 50, ...) — the scalar, not the vector built above
loadFillPol("lengthPhaseOut_n", lengthPhaseOut_n, "energy sources and their number of phasing out years")    
# Act carbon tax 
loadFillPol("Act_carbonTax", 0, "introducing a carbon tax")
loadFillPol("initial_carbonTaxRate", 50, "intial level of the carbon tax ~ADJUST by the current EU ETS price~~ - 50 is close to the current EU ETS price")
loadFillPol("target_carbonTaxRate", 200, "target carbon tax - in euros (maxreached in 2050, that is the policy target) yearly increase of the carbon taxparameter to be changed to make it more/less strong: with 5euros carbon tax reaches around 188euro in 2050, from 50euros in 2022 (p ETS)")
# Act labour tax redistribution :  we got rid of it it seemed incohrerent as percentage paid by employer was suggesting a redistribution FROM labour to CAPITAL#
# Act Wage Indexation
loadFillPol("Act_wageIndex", 0, "wage indexation on inflation")
loadFillPol("coeff_wageIndex", 0.5, "% of the indexation - may be said to reflect balance of power between workers, capitalists (and the State) ; 1 means full indexation. Note that max and min hour wage should may be affected by the same factor")
# Act maximum wage
loadFillPol("Act_maxHrWage", 0, "maximum wage policy")
loadFillPol("R_maxHrWage", 40, "maximum nominal hourly wage by the time policy kicks in ; then indexed on inflation")
# Act minimum wage
loadFillPol("Act_minHrWage", 0, "minimum wage policy")
loadFillPol("R_minHrWage", 10, "minimum nominal hourly wage by the time policy kicks in ; then indexed on inflation")
# Act WTR : Work-time reduction
loadFillPol("Act_WTR", 0, "working time reduction policy - Assumed to be without wage compensation = pure wage loss for employed. see Act_wageComp for wage compensation")
loadFillPol("WTR", - 0.15 , "% of reduction in annual labour hours. Before : -0.2 -0.125 0 (30 35 & 40 hours week)?")
# Act_WTR_wageComp : this triggers wage compensation in case of working time reduction
# This policy corrects the hourly earning in order to keep sustain the total wage
loadFillPol("Act_wageCompWTR", 0, "wage compensation for working time reduction. By default construed as being a full compensation")
loadFillPol("SH_govWageCompWTR", 0.5, "part of wage increase because of WTR wage compensation financed by the State.")  # gov share wage WTR
# Act wealth Tax 
loadFillPol("Act_wealthTax", 0, "Wealth tax policy. May be used to finance BI.")
# Act BI :  Basic Income 
loadFillPol("Act_BI", 0, "basic income policy. financed by Income Tax, Act wealth tax to have it financed by the wealth tax and cancel the increase in income tax")
loadFillPol("how_financeBI", 1 - gp("Act_wealthTax"),"1 : financed by income tax hike ; 0 : financed by wealth tax")
loadFillPol("length_incomeTaxHike",4,"number of years over which extends the income tax rate hike necessary to finance Basic Income")
loadFillPol("base_incomeTaxHike",0.12,"base value of income tax hike to finance BI")
loadFillPol("coeff_incomeTaxHike",0.25,"income tax hike factor to finance BI")
# Act focalized benefit # Act focalized benefit=
loadFillPol("Act_focBenefits", 0, "switch to focalised benefits replacing previous level of other benefits per capita")
loadFillPol("focBenefits", 3500, "size of focalised benefits per capita. Compare with `gp(F_othBenefPerCap`)") # Focalized benefit per capita

log_message("✅ Parameters datatable is loaded in dp.")

# set() erase the key (but not the order...)
#setkey(dp, Name)

#memory_checkpoint("Step 1.4")

#============================================================================
# STEP 3 — Load the module files
#============================================================================

# Open modules files                
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

loading_modules <- c("POLICY", # Policy 
                     "DEM", # Demography
                     #"TU", # Time-Use
                     "IO", # Input Ouput
                     "P", # Prices
                     #"PVA", 
                     "C", # Consumption
                     "I", # Investment
                     "TR", # international trade
                     #"FI", 
                     "L", # Labour
                     "GOV", # Governement 
                     "TECH", # Technology
                     "EN", 
                     #"ENV", # Environnment
                     "CADA"#, 
                     #"WD", # Water demand
                     #"WS" # Water suply
            )


func_in_mod <- list()
for (m in loading_modules) {
    func_in_mod[[m]] <- sourceSet(m)
}

# Everything the model needs now exists: structure, tables, equations. Register
# it, so that clean_ws() can free anything created later without taking the
# model with it. See README.md §4.1.
keep_snapshot()
log_objects(keep_list(), "Registered (protected from clean_ws)")

t <- (gp("startYear"):gp("endYear"))[1]
idx_t <- t - gp("startYear") +1
convergence <- 1-(idx_t/(gp("timePeriods")))^0.5 # BEFORE : 1-(Time/30)^0.5

message("see ", log_file, " for details.")
# -------------------------------------------------------------------------------------------
# Clear memory space 
#clean_ws()
#memory_checkpoint("Step 3.3 right after clean_ws()")

#============================================================================
# STEP 3b — Lagged and level variables (period connectors)
#============================================================================

# Lagged variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# WHEN SWITCHING TO next periods NEED TO BE CHANGED TO gd:
# Not integrating these elements in the definition of the function allows to avoid having to write two functions for init and for the restartDescription

## INITIAL 
# -> they are defined in the main loop

## DELAY
R_minHrWage_lag <- 0
R_maxHrWage_lag <- 0

F_totalOutputReal_i_lag <- gi("F_totalOutputReal_i")   
F_totalOutputNom_i_lag <- gi("F_totalOutputReal_i")  
R_inflation_lag <- gi("R_inflation")
F_othBenefPerCap_lag <- gi("F_othBenefPerCap")
F_labHr_i_lag <- gi("F_labHr_i")
R_labProd_i_lag <- gi("R_labProd_i")
F_GFCFreal_i_lag <- gi("F_GFCFreal_i") #GFCF real i delay
R_unitFactorCost_i_lag <- gi("R_unitFactorCost_i")

### magic number
if(t==gp("startYear")){
    R_markup_i_lag <- gi("R_markup_i") * 0.45  
}else{
    R_markup_i_lag <- gd("R_markup_i", t-1)
}

### Normalize prices (only first period)
dt_set("d", module = "P", name = "R_p_i", value = 1 + template_industry_i, period = gp("startYear"))
### lag's first value is one
if(t==gp("startYear")){
    R_p_i_lag <- 1 + template_industry_i 
}else{
    R_p_i_lag <- gd("R_p_i", t-1)
}
if(t==gp("startYear")){# not by industry however: to fix with actual weights of every industry in composition of GFCF
    R_pK_lag <- 1
}else{
    R_pK_lag <- gd("R_pK", t-1)
}

## LEVELS
SH_skill_is_lvl <- gi("SH_skill_is")
SH_male_is_lvl <- gi("SH_male_is")
Pop_lvl <- gi("ST_population_csg")
R_LFRP_csg_lvl <- gi("R_LFRP_csg")
ST_labJG_csg_lvl <- gi("ST_labJG_csg")
R_hrWage_isg_lvl <- gi("R_hrWage_isg") 
ST_Kreal_i_lvl <- gi("ST_Kreal_i") # K i : there is a lagged of this lvl : a lag2
R_hrWage_isg_lvl <- gi("R_hrWage_isg") 
SH_enSrc_enDemZ_in_lvl <- gi("SH_enSrc_enDemZ_in")
SH_enSrc_enDemZ_in_lvl <- SH_enSrc_enDemZ_in_lvl / rowSums(SH_enSrc_enDemZ_in_lvl) # rescale because it does not sum up to one
# -------------------------------------------------------------------------------------------

# Formally this is not the case, we only use this to isolate modules

# Uncomment to isolate GOV
    # R_inflation_lag P <- gi("R_inflation")
    # L : ST_unempLabour_sg  ???

# Uncomment to isolate DEM
    # R_u_s <- template_population_
    # R_u_s[] <- c(0, round(runif(3, min = 0.01, max = 0.1), 4), 0)
R_labProd_i <- gi("R_labProd_i") # initial lambda i[ind])
# Uncomment to isolate L
    # D : ST_population_csg <- gi("ST_population_csg")  
    # TECH : R_labProd_i <- gi("R_labProd_i")
    # GOV : F_GUB_sg, F_otherIncomePerCapita ???
    # P : O_CPI ???

memory_checkpoint("Step 3.3 after full init")

#============================================================================
# STEP 3c — Development or run mode
#============================================================================

# developing or running ? # -----------------------------------------------------------------
dev_or_run <- "run"#"dev" #run # ion
keep_add(c("dev_or_run", ".message_log"))  # engine state, must survive clean_ws()

#============================================================================
# STEP 4 — The model
#============================================================================

for (iterations in 1:iter){

# ----------------------------------------
    clear_eq_log()
# ----------------------------------------

# VENSIM INITIAL()

   # # 2 year lag
    labourProductivity_lag2()
    #ST_KReal_i_lag2 <- realCapitalStock_lag2()
    #F_expDispIncPerCap_dsg_lag2 <- expectationDisposableIncomePerCapita_dsg_lag2()
    realCapitalDepreciation_lag() # because K is level ? 
    
   # # 1 year lag
    #F_expDispIncPerCap_dsg_lag <- expectationDisposableIncomePerCapita_dsg_lag()
    #F_expIncome_sg_lag <- incomeExpectation_lag()
    employedLabour_lag()

# BEGIN module
    
    # POLICY ------------------------------------------------------------------ CHECKED

    POL_wageCompWTR()
    POL_wageIndex()
    POL_minWage() # 10 euros for now: it is not yet updated, hence the real value of these 10 euros may vary across simulations
    POL_maxWage() # 40 euros for now: it is not yet updated, hence the real value of these 10 euros may vary across simulations
    

    # GOV --------------------------------------------------------------------- CHECKED
    
    POL_unempBenefitsShareInWageBill()
    POL_pensionBenefitsShare_in_wageBill()
    POL_otherBenefits()
    POL_govWageCompWTR()
    POL_valueAddedTaxRate()
    POL_incomeTaxRate()
    
    grossUnempBenefits()
    grossPensionBenefits()
    
    socialSecurityContRateTotal()
    socialSecurityContRateByEmployer()
    socialSecurityContRateByEmployee()

    grossAnnualIncomePerCapita_employed()
    socialSecurityAnnualContPerCapita_eByEmployer()
    socialSecurityAnnualContPerCapita_employed()
    taxableAnnualIncomePerCapita_employed()

    grossAnnualIncomePerCapita_unemployed()
    socialSecurityAnnualContPerCapita_unemployed()
    taxableAnnualIncomePerCapita_unemployed()
    
    grossAnnualIncomePerCapita_pension()
    taxableAnnualIncomePerCapita_pension()
    socialSecurityAnnualContPerCapita_pension() # This Contribution Social Généralisée, but this only in France?

    incomeTaxLevyPerCapita_employed()
    incomeTaxLevyPerCapita_unemployed()
    incomeTaxLevyPerCapita_pension()
    totalIncomeTaxLevy()
    
   
    # L ----------------------------------------------------------------------- CHECKED
    
  #  #R_hourW_isg <- POL_shift_hourlyWage()
    POL_annualWorkingHours()
    
    grossWageBill()  # Period connector : prev hourW, current labourH and ST_labour
    desiredLabour_i()   # Period connector : prev totalOuput, current lambda and labourH
    desiredLabour_isg()  
    
    workingAgePop()
    availableLabour() # Not activePop in its general sense, but in its strict sense : without JG workers (to allows use to compute effectve LabEmp)
    activePop() # This includes JG in addition of labour supply
    inactivePop()
    employedLabour()    
    unemployedLabour()
    
    employmentRate_s() # in btw periods
    employmentRate_g() # in btw periods
    employmentRate_sg() # in btw periods
    unemploymentRate_s() # less clearly so but also in btw periods
    unemploymentRate_sg() # less clearly so but also in btw periods
    
    diffRateUnemploymentBySkill()
    diffRateUnemploymentByGender()
    shift_SkillLabourShare()
    shift_MaleLabourShare()
  #  #F_expIncome_sg <- incomeExpectation()
  #  #F_labJG_csg <- flux_JobGuarantee()
  #  #R_LFRP_csg <- shift_LabourForceParticipationRate()
  #  #ST_labJG_csg <- shift_stockJobGuarantee()  
    

    # C -----------------------------------------------------------------------
    
    currentPopIncomeGroups_dsg()
    #expectationDisposableIncomePerCapita_dsg()
    #accumulatedInflationNACE_i()
    #accumulatedInflationCOICOP_p()
    disposableIncomePerCapita_dsg()
    
 #   F_Creal_p <- realTotalConsumptionDemandCOICOP_p()
 #   F_Cnom_i <- nominalTotalConsumptionDemandNACE_i()

    # I -----------------------------------------------------------------------

    #setPricesCapital()
    POL_shiftRateRealCapitalDepreciation() 
    realCapitalDepreciation()
    #F_GFCFreal_i <- realInvestmentDemand()
    
   # ST_KReal_i <- realCapitalStock()
    
    # P -----------------------------------------------------------------------
   
    SHOCK_setMarkup()
    #unitLabCost()
    #unitInputCost()
    #unitFactorCost()
    #setPrices() #***
    #currentInflationByIndustry_i()
    #SH_nomConsNACE_i <- currentInflationWeights_i()
    #R_inflation <- currentInflation()

    # TR ----------------------------------------------------------------------
    
    POL_importShareInIntermediateTrade()
    #SHIFT_nominalImportIntermediateDemand()
    #SHIFT_nominalExport()
    
    #realExport()
    #realImportInterMediateDemand()
    #totalRealImportIntermediateDemand() # not used elsewhere it seems
    
    # IO ----------------------------------------------------------------------
  
    
    interIndustryCoeff()  #***
    leontieffMatrix_ii()
    #realInterIndustryTradeMatrix_ii()
   # nominalInterIndustryTradeMatrix_ii()
    #nominalIntermediateDemand_interindustryAndImport()
  #  F_finalDemReal_i <- realFinalDemandForDomesticGoods_i()
  #  F_finalDemNom_i <- nominalFinalDemandForDomesticGoods_i()
  #  #F_totalOutputReal_i <- realTotalOuput_i()
  #  #F_totalOutputNom_i <- nominalTotalOuput_i()    
    
    # TECH ---------------------------------------------------------------------

    POL_scalingLabourProductivity()
    
    techFrontierLabourProd()
    computeAlternativeChangeLabourProductivity()
    #R_labProdDiffusion_i <- currTechDiffusionLabourProd() #~~~~
    #R_labProdAlt_iv <- computeAlternativeLabourProductivity()
    #ST_desLabAlt_isvg <- computeAlternativeDesiredLabour()
    #F_GWBAlt_iv <- computeAlternativeGrossWageBill()
    
    #R_unitLabCostAlt_iv <- unitLabCostAlt(
    #R_unitInputCostAlt_iv <- unitLabCostAlt()
    #R_unitFactorCostAlt_iv <- unitFactorCostAlt()
    #R_labProd_i <- shiftLabourProductivity_i()

    # EN -----------------------------------------------------------------------
#
 #   R_gEnShare_fromPolicy_in <- POL_PhaseOutReductionEnShare()
 #   SH_enSrc_enDemZ_in <- POL_Shift_EnSourceShare_in_InterProdEnDemand()
#
 #   R_gEnShare_fromRenew_in <- shift_EnSourceShare_FromRenewGrowth_i()

     # CADA --------------------------------------------------------------------- 1

    POL_carbonTaxRate()
    # priceETS_i <- POL_priceETS()
    # F_taxableCarbon_i <- CarbonTaxCoverage()
    #F_carbonTaxLevy_i <-CarbonTaxLevy()
    #F_carbonCostETS_i <- CarbonCostETS()
    #F_carbonCostTotal_i <-CarbonCostTotal()
    
    # DEM --------------------------------------------------------------------- 8

    POL_trendEntrySkill()
    
    birth()
    death()
    maturationOut()
    maturationIn()
    skillShiftIncomingPop()
    skillShiftAllPop()
    endCurrentPeriodPop()

# END module 
    # -----------------------------------------------------------------------
    # -----------------------------------------------------------------------
    # -----------------------------------------------------------------------
    
    success <- print_eq_log()
    
    if (success) break  # 🚪 Sortir de la boucle si tout est bon    
    
    message(paste0("----------------------\n","After : ", iterations, " in ", iter, " iterations\n","----------------------"))

}

    # ~~~~~~~~ This should come after L else it will throw an error ~~~~~~~~
    check_population_consistency() # with beginning-of-period Pop_lvl
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#============================================================================
# STEP 5 — Save
#============================================================================

# Save environment to write documentation 
# Save GlobalEnv
output_path <- DIR_OUTPUT

save.image(file = file.path(output_path, "model_only.RData"))
message("model data saved to:\n", paste0(output_path,"/model_only.RData"))
# Save only main datatables 
modelDT <- list()
modelDT[["dp"]] <- dp 
modelDT[["init"]] <- init
modelDT[["lookup"]] <- lookup
modelDT[["d"]] <- d

save(modelDT, file = file.path(output_path, "modelDT.RData"))
message("model datatable saved to:\n", paste0(output_path,"/modelDT.RData"))
