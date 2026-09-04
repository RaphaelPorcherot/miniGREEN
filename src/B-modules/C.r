# BEGIN Fonctions ------------------------------------------------------------------------------------------------
# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_)


########################################################################

# ------------------------------------------------------------------------------------------------
# Here for all other functions

## period connectors -----------------------------------------------------------------------------------------

## Regular functions -----------------------------------------------------------------------------------------


accumulatedInflationNACE_i <- function(){
  eq({# infl cumulative i[ind]=p i[ind]-1* Euro good 1 ~	inflation w.r.t. first period, where all prices set to 1
    R_accInfl_i  <- R_p_i - 1 
    R_accInfl_i
  })
}

accumulatedInflationCOICOP_p <- function(){
  eq({# 	infl cumulative p[coicop] = sum(bridge ip[ind!,coicop]*infl cumulative i[ind!]) ~ inflation wrt the first period
    # Hadamard product on column -> we can use simple * | if it had been on row, then sweep(A, 2, B, `*`) would have been necessary
    # Hadamard product on column -> we can use simple * | if it had been on row, then sweep(A, 2, B, `*`) would have been necessary
    #sweep(gp("bridgeNaceCoicop_ip"), "Industry", R_accInfl_i, `*`)

    R_accInfl_p <- colSums(gp("bridgeNaceCoicop_ip") * as.vector(R_accInfl_i))
    R_accInfl_p
  })
}


currentPopIncomeGroups_dsg <- function() {
  eq({#pop d[inc low u f]
    ST_labEmp_sg <- colSums(ST_labEmp_isg, 2) 
    ST_population_dsg <- template_population_dsg

    # Status: employed, unemployed, olf
    sources <- list(
                    emp    = ST_labEmp_sg,
                    unemp  = ST_labUnemp_sg,
                    olf    = ST_inactivePop_sg
    )
    for (status in c("emp", "unemp", "olf")) {
      for (s in pop_group) {
        for (g in gender) {
          ST_population_dsg[status, s, g] <- sources[[status]][s, g]
        }
      }
    }
    # Pension
    ST_population_dsg["pension", , ] <- Pop_lvl["65+", , ]           
    # non retired cap
    for (g in gender) {
      ST_population_dsg["olf", "cap", g] <- sum(Pop_lvl[ , "cap", g]) - Pop_lvl["65+", "cap", g]
    }
    # Child are olf
    ST_population_dsg["olf", "child", ] <- colSums(Pop_lvl[ , "child", ])
    ST_population_dsg
  })
}

# INCOMPLETE 
disposableIncomePerCapita_dsg <- function(){
  eq({#yd d[: individual disposable income by income category PER CAPITA
    F_dispIncPerCap_dsg <- template_population_dsg
    # net labour income pc gis
    #netWagePerCap_sg <- F_GWBperCap_isg - F_incTaxEmpPerCap_isg
    netWage_sg <- colSums(F_taxIncPerCap_e_isg * ST_labEmp_isg) #taxInc -> social security contributions already deducteed
    ST_labEmp_sg <- colSums(ST_labEmp_isg)
    F_incTaxEmpPerCap_sg <- colSums(F_incTaxEmpPerCap_isg)
    netWagePerCap_sg <- netWage_sg/ST_labEmp_sg - F_incTaxEmpPerCap_sg
    netWagePerCap_sg[is.na(netWagePerCap_sg)] <- 0
    # Employed : 
    F_dispIncPerCap_dsg["emp",,] <- netWagePerCap_sg
    # Unemployed
    F_dispIncPerCap_dsg["unemp",,] <- F_GUBperCap_sg - F_incTaxUnempPerCap_sg
    # Pension
    F_dispIncPerCap_dsg["pension",,] <- F_GPBperCap_sg - F_incTaxPensPerCap_sg
    # Cap 
    #dispIncPerCapita_dsg["cap",,] 
    F_dispIncPerCap_dsg 
  })
}

expectationDisposableIncomePerCapita_dsg <- function(){
  eq({# exp yd d[inc cat]= expected disposable income by income category - first period = 1 as per the defintion of lag and lag2 through initial
    lag <- F_dispIncPerCap_dsg_lag
    lag2 <- F_dispIncPerCap_dsg_lag2
    delta <- lag - lag2
    F_expDispIncPerCap_dsg <- lag * (1 + delta/lag2)
    F_expDispIncPerCap_dsg
  })
}



#basic beta dp[inc cat,coicop]=
#	max(lookup extrapolate(beta fct p[coicop],exp yd d[inc cat]* Dmnl Euro 1),0)


sharesNominalConsExpenditurePerCapitaInCOICOP_dp <- function(){# shares of consumption expenditure spend on respective COICOP
  eq({# beta dp[inc cat,coicop]

    #    basic beta dp[inc cat,coicop] * (1 + elast beta p[coicop]*(infl cumulative p[coicop] - av infl cumulative d[inc cat])
    #    + basic beta dp[inc cat,coicop] * sum(-elast beta p[coicop!]*(infl cumulative p[coicop!]-av infl cumulative d[inc cat])*basic beta dp[inc cat,coicop!]
    #    - (share elgas * sens JG * ln(JG L tot)) * basic beta dp[inc cat,p electgas]
    #            + ( 1 - share elgas) * sens JG * ln(JG L tot))*basic beta dp[inc cat,p transport]) * basic beta dp[inc cat,coicop]/sum(basic beta dp[inc cat,coicop!]) 

    SH_nomIndC_dp        
  })
}


# Initialisation du résultat
#beta_dp <- matrix(NA, nrow = length(inc_cat_list), ncol = length(coicop_list),
#       dimnames = list(inc_cat_list, coicop_list))

#pop_ratio_ln <- log(People_1_JG_L_tot / People_1)

#for (i_inc in seq_along(inc_cat_list)) {
#  inc_cat <- inc_cat_list[i_inc]
#  av_infl <- av_infl_cum_d[inc_cat]
#  share_el <- share_elgas[inc_cat]
#  
#  for (j_coi in seq_along(coicop_list)) {
#    coicop <- coicop_list[j_coi]
#    
#    basic_val <- basic_beta_dp[i_inc, j_coi]
#    elast_own <- elast_beta_p[coicop]
#    infl_own <- infl_cum_p[coicop]
#    
#    # Effet propre prix
#    own_price_effect <- 1 + elast_own * (infl_own - av_infl)
#    
#    # Effet substitution croisée
#    cross_price_effect <- 0
#    for (k_coi in seq_along(coicop_list)) {
#      if (k_coi != j_coi) {
#        coicop_other <- coicop_list[k_coi]
#        elast_other <- elast_beta_p[coicop_other]
#        infl_other <- infl_cum_p[coicop_other]
#        basic_other <- basic_beta_dp[i_inc, k_coi]
#        
#        cross_price_effect <- cross_price_effect + 
#          (-elast_other) * (infl_other - av_infl) * basic_other
#      }
#    }
#    # Normalisation euro 1/goods 1 ignorée (ou mise à 1) car non précisée
#    
#    beta_dp_raw <- basic_val * (own_price_effect + cross_price_effect)
#    
#    # Correction électricité et transport
#    if (coicop == "p electgas") {
#      beta_dp[i_inc, j_coi] <- beta_dp_raw + share_el * sens_JG * pop_ratio_ln * basic_val
#    } else if (coicop == "p transport") {
#      beta_dp[i_inc, j_coi] <- beta_dp_raw + (1 - share_el) * sens_JG * pop_ratio_ln * basic_val
#    } else {
#      beta_dp[i_inc, j_coi] <- beta_dp_raw
#    }
#  }
#}


nominalIndividualConsExpenditure_dp <- function(){# individual consumption expenditure by income groups and consumption categories
  eq({#c dp[inc cat,coicop]= c tot d[inc cat]*beta dp[inc cat,coicop] 
    F_nomIndC_dp 
  })
}



nominalTotalConsumptionDemandCOICOP_p <- function(){
  eq({# c p[coicop]=sum(c dp[inc cat!,coicop] * pop d[inc cat!])/People 1 	final demand nominal coicop from total population
    F_Cnom_p 
  })
}

realTotalConsumptionDemandCOICOP_p  <- function(){
  eq({# c real p[coicop]=c p[coicop]/(euro goods 1+infl cumulative p[coicop]) # 	real demand of consumption goods within nation in COICOP classification
    F_Creal_p < -F_Cnom_p / (1 + R_accInfl_p)
    F_Creal_p
  })
}

realTotalConsumptionDemandNACE_i <- function(){
  eq({# c real i[ind]= sum(bridge ip[ind,coicop!]*c real p[coicop!]) ~	real demand of consumption goods within nation in NACE classification 
    factor_i <- 1 + template_industry_i 
    if (t %in% covidYears) {
      cy <- match(t, covidYears)
      factor_i <- factor_i + gp("R_dCrealCovid")[cy]
      F_Creal_i <-  F_Creal_i_lag * factor_i 
    }else{
      #            F_Creal_i <- colSums(gp("bridgeNaceCoicop_ip") * -> check la multiplication maticielle

      #sum(bridge ip[ind,coicop!]*c real p[coicop!]) 
    }
    F_Creal_i
  })
}


nominalTotalConsumptionDemandNACE_i <- function(){
  eq({# # c nom i[ind]=	c real i[ind]*p i[ind]	nominal demand of consumption goods within nation in NACE classification
    F_Cnom_i <- F_Creal_i * R_p_i
    F_Cnom_i 
  })
}



# c dom nom i[ind]=
#	(1-share imp hh i[ind])*c nom i[ind]
#	~	Euro
#	~	nominal consumption demand for domestic industries
#	|

#inflation weights i[ind]=
#	c nom i[ind]/sum(c nom i[ind!])
#	~	
#	~		|
#
#price weights i[ind]=
#	c real i[ind]/sum(c real i[ind!])
#	~	Dmnl
#	~		|


## Vensim initial§) -----------------------------------------------------------------------------------------

expectationDisposableIncomePerCapita_dsg_lag <- function(){
  eq({# yd delay d 
    if(t==gp("startYear")){
      F_expDispIncPerCap_dsg_lag <- F_expDispIncPerCap_dsg
    }else{
      F_expDispIncPerCap_dsg_lag <- gd("F_expDispIncPerCap_dsg", t-1)
    }
    F_expDispIncPerCap_dsg
  })
}

expectationDisposableIncomePerCapita_dsg_lag2 <- function(){
  eq({#yd delay2 d
    if(t==gp("startYear")){
      F_expDispIncPerCap_dsg_lag2 <- F_expDispIncPerCap_dsg
    }else if(t==gp("startYear")+1){
      F_expDispIncPerCap_dsg_lag2 <- gd("F_expDispIncPerCap_dsg", 1)
    }else{
      F_expDispIncPerCap_dsg_lag2 <- gd("F_expDispIncPerCap_dsg", 2)
    }
    F_expDispIncPerCap_dsg
  })
}


# END Fonctions ------------------------------------------------------------------------------------------------
