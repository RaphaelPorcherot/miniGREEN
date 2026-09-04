module_name <- "XXX"

# README

# always put gp
# gi are defined in loop
# to do INITIAL(), put a if(t=1){}else{} logic
# always repeat the output variable at the end of the eq() functions
#         R_hourW_sg[is.na(R_hourW_sg)] <- 0
# unpack if given variables is used in more than two functions ST_labour_i 
## THIS VARIABLE CONNECTS PERIOD ## : period connector are variable that have arugment from both periods (not simply shift function)
# levels : il n'y a pas de temps avant le temps : la première valuer est celle de la première période l'actualisation du level arrive à la fin de la période et permet de définir la valeur pour t=2
# It means that there are really LAG: SH_skill_is_lvl eg
# To specify levels, we visualise them first in the before th eloop
# Their functions are called shift_

# LEVEL in Vensim
# initial value is first value, this function allows to compute value for t+1

# Clarify that all stocks are not levels : ST_labour_i for instance. They are stock in the economic sense of the word. 
# But levels are dynamic stocks

# In function writing style : only put the indices when needed for disambiguations for instance for R_u_sg and R_u_s
# NOTES

# To know what is level and what is not, look at lvl variales at the begin of the loop
# unique(dp  ou init ou d$Name) pour avoir les différentes variables

#policy first
#try to put the functions in the order you want to execute them in the main loop
# as dependencies should only be listed variables, not fixed coefficients (that always exists by construction)

# Rule pour les dépendances
# ne mettre que celles qui sont économiquement significative

# les fonctions doivent correspondre à des opérations unitaires. Si parfois on répète le même calcul, ce n'est pas forcément grave
# il faut trouver un équilibre entre lisibilité du code et efficacité

# naming function : les index 
# Différencier les valeurs qui sont de début de période et de fin de période ? 
# opération skillShift
# objet de l'opération _maleLabourShare (si not obvious)

#TEMPLATE (replace <VARIABLE>, <EQUATION>, <DEPENDENCY> and <FUNCTION> with adequate wording)
# Note the { }. Dep are optionnal (standard value is NULL) 
# <FUNCTION>  <- function() {
#   eq({
#  <INTERMEDIATE VARIABLE> <- <EQUATION>
#  <VARIABLE> <- <EQUATION> <INTERMEDIATE VARIABLE>

#    <VARIABLE> (to be sure that it will return the result of the last line)
#)}
#}


# BEGIN Fonctions ------------------------------------------------------------------------------------------------
# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_)

# ----------------------------------------------------------------------------------------------------------------
# Here for all other functions



## period connectors ---------------------------------------------------------------------------------------------

## Regular functions ---------------------------------------------------------------------------------------------

## Vensim initial§) ----------------------------------------------------------------------------------------------


# END Fonctions --------------------------------------------------------------------------------------------------

source(here("notebooks", "r-nb", "B-modules", "_0verbose.r"))
# Store the modules functions in the objects to be retained when cleaning workspace
toKeep <- c(toKeep, functions_in_env)

                                            
                                            