module_name <- "I"

# BEGIN Fonctions ------------------------------------------------------------------------------------------------
# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_)
POL_shiftRateRealCapitalDepreciation <- function() {
    eq({
        start <- gp("startPolicy")
        end <- gp("endPolicy")
        coeff <- gp("coeff_shiftDepreciation")  # S depreciation rates
        base <- gi("R_KrealDepr_i") # S1 depreciation rates i[ind]
        if (t >= start && gp("Act_grossUnempShare") == 1) {
            R_KrealDepr_i <- base * (1 + coeff * min(end - start, t - start) / (end - start))
        } else {
            R_KrealDepr_i <- base
        }
        R_KrealDepr_i
    })
}
# ----------------------------------------------------------------------------------------------------------------
# Here for all other functions

realCapitalDepreciation <- function() {
    eq({# depreciation K i
        F_KrealDepr_i <- ST_Kreal_i_lvl * R_KrealDepr_i
        F_KrealDepr_i
    })
}

realCapitalStock <- function() {
    eq({#K i
        ST_Kreal_i <- ST_Kreal_i_lvl + (F_GFCFreal_i - F_KrealDepr_i)
        ST_Kreal_i
    })
}

realInvestmentDemand <- function() {
    eq({# GFCF real i
        factor_i <- 1 + template_industry_i 
        if (t %in% covidYears) {
            cy <- match(t, covidYears)
            factor_i <- factor_i + gp("R_dGFCFrealCovid")[cy]
            F_GFCFreal_i <- F_GFCFreal_i_lag * factor_i
        }else{
           # min(I desired i[ind],I max i[ind])
            #I desired i[public, education, health]
        }
        F_GFCFreal_i 
    })
}

## period connectors ---------------------------------------------------------------------------------------------

## Regular functions ---------------------------------------------------------------------------------------------

## Vensim initial() ----------------------------------------------------------------------------------------------

realCapitalDepreciation_lag <- function(){
    eq({# depreciation K delay i
        if(t==gp("startYear")){
            F_KrealDepr_i_lag <- F_KrealDepr_i
        }else{
            F_KrealDepr_i_lag <- gd("F_KrealDepr_i", t-1)
        }
      F_KrealDepr_i_lag
    })
}

realCapitalStock_lag2 <- function(){
    eq({#K delay i
        if(t==gp("startYear")){
            ST_Kreal_i_lag2 <- ST_Kreal_i_lvl
        }else if(t==gp("startYear")+1){
            ST_Kreal_i_lag2 <- gd("ST_Kreal_i", 1)
        }else{
            ST_Kreal_i_lag2 <- gd("ST_Kreal_i", 2)
        }
      ST_Kreal_i_lag2
    })
}


#K delay2 i 
# if first period is t = 1 in fact this is lag3, since ST_KReal is actually a level variable. We may be okay with just ST_Kreal_lag for whatever is required (it is different with lambda, since lambda is not a level variable)
# as a matter of fact, it is never used
# initial K delay i


# END Fonctions --------------------------------------------------------------------------------------------------

source(here("notebooks", "r-nb", "B-modules", "_0verbose.r"))
# Store the modules functions in the objects to be retained when cleaning workspace
toKeep <- c(toKeep, functions_in_env)

                                            
                                            