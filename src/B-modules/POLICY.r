# BEGIN Fonctions ------------------------------------------------------------------------------------------------

# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_) or SHIFT
# ------------------------------------------------------------------------------------------------

# R_minHourW : Minimum Wage Value generated from  min wage level
POL_minWage <- function() {
  eq({
    start <- gp("startPolicy")

    if (t == start && gp("Act_minHrWage") == 1) {
      R_minHrWage <- gp("R_minHrWage")
    } else {
      R_minHrWage <- R_minHrWage_lag * (1 + R_inflation_lag) * R_sensHrWagePrice
      # 0 if before policy or if policy not active
      # > 0 if not
    }
    R_minHrWage
  })
}

# R_maxHrWage : Maximum Wage Value generated from max wage level
POL_maxWage <- function() {
  eq({
    start <- gp("startPolicy")

    if (t == start && gp("Act_maxHrWage") == 1) {
      R_maxHrWage <- gp("R_maxHrWage")
    } else {
      R_maxHrWage <- R_maxHrWage_lag * (1 + R_inflation_lag) * R_sensHrWagePrice
      # 0 if before policy or if policy not active
      # > 0 if not
    }
    R_maxHrWage
  })
}

# R_sensHourWPrice : sensitivity of hourly wages to inflation
POL_wageIndex <- function() {
  eq({# omega price et Act Wage Indexation Multiplier Wage Indexation
    start <- gp("startPolicy")

    if (t >= start && gp("Act_wageIndex") == 1) {
      R_sensHrWagePrice <- gp("coeff_wageIndex")
    } else {
      R_sensHrWagePrice <- 0.1
    }
    R_sensHrWagePrice
  })
}

POL_wageCompWTR <- function(){
  eq({# delta wage WTR : in fact it only gives the rate of change no the actual delta
    diff <- F_labHr_i - F_labHr_i_lag
    base <- F_labHr_i_lag
    R_gWTR_i <-  diff / base
    R_gWageCompWTR_i <-  - R_gWTR_i  # This a REDUCTION of labour hours that needs to be matched by an INCREASE of hourly wage, hence the negative sign.
    R_gWageCompWTR_i
  })
}


# Here for all other functions


# END Fonctions ------------------------------------------------------------------------------------------------
