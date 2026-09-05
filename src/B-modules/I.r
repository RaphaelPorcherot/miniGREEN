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

# K delay2 i is not translated. In Vensim 2025 it appears in its own definition
# and in the sketch metadata, in no equation; in Vensim 2026 it does not exist.
# `K i` is a state, so `K delay i` is already its own previous value —
# ST_Kreal_i_lvl here — and a second lag of it has no reader. Lambda is the
# opposite case: an auxiliary, with no past of its own, so lambda delay2 i is
# genuine and is used. See inconsistencies_new.md.

# END Fonctions --------------------------------------------------------------------------------------------------
