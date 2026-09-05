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

# ==============================================================================
# WRITING A STATE AND ITS FLOW
# ==============================================================================
#
# Every state advances the same way, and only this way:
#
#     state(t) = state(t - dt) + net_flow * dt
#
# which is what advance_state(prev, flow) does. Do not write the arithmetic out:
# dt must not be written in one place and forgotten in another.
#
# THE QUESTION TO ASK when translating a Vensim INTEG is not "additive or
# multiplicative". It is:
#
#     What is the net flow, and does that flow read the state it feeds?
#
# A flow that reads its own state is fine — it is what makes a smooth a smooth,
# and the population's flow has such a term. What is NOT fine is inventing that
# self-reference when the Vensim flow does not have it. Writing
#
#     state <- state_lvl * factor          # = state_lvl + state_lvl * (factor-1)
#
# scales the flow by the state it feeds. Correct only if the Vensim flow really
# does contain a term proportional to the stock. It did not for SH_skill_is and
# SH_male_is, and it broke the shares summing to one. See inconsistencies_new.md.
#
# SO, FOR A NEW STATE:
#
#   1. read the flow argument of the Vensim INTEG. That is your F_ variable,
#      verbatim — not scaled, not smoothed, not turned into a factor
#   2. give the flow its own equation, returning F_<something>
#   3. advance with advance_state(prev, flow)
#   4. register state, flow and rationale in model_states, in 2-structure.r
#   5. if the state has an invariant, write the check AND make sure it can fire
#
#     flowSkillLabourShare <- function() {
#       eq({
#         F_skillShare_is <- convergence * gp("R_trendSkill_is")
#         F_skillShare_is
#       })
#     }
#
#     shift_SkillLabourShare <- function() {
#       eq({
#         SH_skill_is <- advance_state(SH_skill_is_lvl, F_skillShare_is)
#         SH_skill_is
#       })
#     }
#
# Two functions, not one: a flow that lives only as a local inside its state's
# equation cannot be inspected, plotted, or read by anything else.
#
# ==============================================================================
# WHAT NOT TO WRITE INSIDE AN eq() BLOCK
# ==============================================================================
#
# eq() works out what an equation depends on by *reading* the block — walking
# the expression for names, and excluding the ones that are not dependencies:
# variables the block assigns itself, `for` loop variables, the formal
# arguments of functions defined in the block, and parameters read from `dp`.
#
# It is a syntactic walk. It cannot see anything that only exists at run time.
# Three things therefore break it. All three fail SILENTLY: the block runs when
# it should have waited, and uses whatever stale value was lying around.
#
# 1. A MODEL VARIABLE AS A FORMAL'S DEFAULT VALUE
#
#      f <- function(x = R_labProd_i) x * 2          # WRONG
#      f <- function(x) x * 2 ; f(R_labProd_i)       # right
#
#    all.names() does not descend into default values, so R_labProd_i is not
#    seen at all and never becomes a dependency. Read the variable in the body.
#
# 2. A NAME BUILT AT RUN TIME
#
#      assign(paste0("ST_", thing), value)           # WRONG
#      get(varname)                                  # WRONG
#      eval(parse(text = ...))                       # WRONG
#
#    There is no name in the expression for the walk to find.
#
# 3. gp() / gi() / gl() CALLED WITH ANYTHING BUT A LITERAL STRING
#
#      gp("R_fertility")                             # right, records R_fertility
#      gp(param_name)                                # WRONG, records "param_name"
#
#    The walk takes the symbol's *name*, not its value, which it cannot know.
#    So the parameter actually read is never recorded, and a name that is not a
#    parameter is recorded instead.
#
# If you ever need one of these, say so rather than working around it: the
# fallback is to give eq() an explicit `dep = c(...)` argument again, which is
# about five lines. See README.md section 4.4.
#
# ------------------------------------------------------------------------------
# TEMPLATE (replace <VARIABLE>, <EQUATION> and <FUNCTION> with adequate wording)
# The last line must be the bare name of the target variable: that is how eq()
# knows what the equation computed.
#
# <FUNCTION> <- function() {
#   eq({
#     <INTERMEDIATE VARIABLE> <- <EQUATION>
#     <VARIABLE> <- <EQUATION> <INTERMEDIATE VARIABLE>
#
#     <VARIABLE>
#   })
# }


# BEGIN Fonctions ------------------------------------------------------------------------------------------------
# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_)

# ----------------------------------------------------------------------------------------------------------------
# Here for all other functions



## period connectors ---------------------------------------------------------------------------------------------

## Regular functions ---------------------------------------------------------------------------------------------

## Vensim initial§) ----------------------------------------------------------------------------------------------


# END Fonctions --------------------------------------------------------------------------------------------------
