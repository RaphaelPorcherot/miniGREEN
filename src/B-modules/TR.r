# BEGIN Fonctions ------------------------------------------------------------------------------------------------
# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_)

SHIFT_nominalExport <- function() {
  eq({
    # g exp i[ind]= exogenous exp growth. Prev : 0.6
    start <- gp("startPolicy")
    end <- gp("endPolicy")
    coeff <- gp("coeff_absoluteXgrowth")
    base <- gi("F_gXnom_i")

    if (t >= start && gp("Act_absoluteXgrowth") == 1) {
      factor <- 1 + coeff * min(end - start, t - start) / (end - start)
    } else {
      factor <- 1
    }
    F_gXnom_i <- base * (1 + factor)

    # total exp nom i[ind]=
    factor_i <- 1 + template_industry_i
    if (t %in% covidYears) {
      cy <- match(t, covidYears)
      factor_i <- factor_i + gp("R_dXnomCovid")[cy]
    } else {
      # Previous magic number : exp_initial_i[ind]* (1 - elast_p_exp * inflation_i[ind]) +(g_exp_i[ind]*Time*convergence)
      # 1.2 * exp initial i[ind] * (1 - elast p exp * inflation i[ind])+(g exp i[ind])
      F_Xnom_i <- gi("F_Xnom_i") * (1 - gp("elastXp") * R_inflation) + F_gXnom_i
    }
    F_Xnom_i <- pmax(F_Xnom_i, 0)
    F_Xnom_i
  })
}


POL_importShareInIntermediateTrade <- function() {
  eq({
    #share imp Z ii[ind,toind] share of imports with respect to domestic in intermediate trade
    start <- gp("startPolicy")
    end <- gp("endPolicy")
    coeff <- gp("coeff_impShareInZ") # S share imp Z
    base_ii <- gi("SH_impZ_ii") # add indices to make type explicit : here 2D arrays.s
    SH_impZ_ii <- template_industry_ii
    factor <- 1
    if (t >= start && gp("Act_impShareInZ")) {
      factor <- factor + coeff * min(end - start, t - start) / (end - start)
    } #shorter version of structure used elsewhere.
    SH_impZ_ii <- base_ii * factor
    SH_impZ_ii <- pmax(SH_impZ_ii, 0) # import share can not be negative
    SH_impZ_ii <- pmin(SH_impZ_ii, 1) # import share can not exeed 100% - note the use of pmin(), the object is 2D array
    SH_impZ_ii
  })
}

SHIFT_nominalImportIntermediateDemand <- function() {
  eq({
    #Z imp nom i[toind]=sum(p i[ind!]*Z imp real ii[ind!,toind])*IF THEN ELSE(Time=Time 1st import price shock,1+import price shock*Act Price Shock,1)*IF THEN ELSE(Time=Time shock,1+import price shock*Act Price Shock,1)
    start <- gp("startPolicy")
    end <- gp("endPolicy")
    coeff <- gp("coeff_importPriceShock") # import price shock

    factor <- 1
    if (t >= start && gp("Act_importPriceShock") == 1) {
      factor <- factor + coeff
    }
    impZnom_i <- colSums(impZreal_ii * as.vector(R_p_i)) * factor
    impZnom_i
  })
}

# ----------------------------------------------------------------------------------------------------------------
# Here for all other functions

realExport <- function() {
  eq({
    #total exp real i[ind]= total exp nom i[ind]/p i[ind]
    F_Xreal_i <- F_Xnom_i / R_p_i
    F_Xreal_i
  })
}


realImportInterMediateDemand <- function() {
  eq({
    #Z imp real ii[ind,toind]= share imp Z ii[ind,toind] * Z real ii[ind,toind]
    impZreal_ii <- SH_impZ_ii * Zreal_ii
    impZreal_ii
  })
}

totalRealImportIntermediateDemand <- function() {
  eq({
    #Z imp real tot=sum(Z imp real ii[ind!,ind!])
    totalImpZ <- sum(impZreal_ii)
    totalImpZ
  })
}


## period connectors ---------------------------------------------------------------------------------------------

## Regular functions ---------------------------------------------------------------------------------------------

## Vensim initial§) ----------------------------------------------------------------------------------------------

# END Fonctions --------------------------------------------------------------------------------------------------
