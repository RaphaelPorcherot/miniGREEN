# BEGIN Fonctions ------------------------------------------------------------------------------------------------
# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_)


POL_carbonTaxRate <- function() {
  eq({# carbon tax rate
    start <- gp("startPolicy")
    end <- gp("endPolicy")
    target <- gp("target_carbonTaxRate")
    initial <- gp("initial_carbonTaxRate")
    R_carbonTax <- 0 # there is currently no carbon tax
    if (t >= start && gp("Act_carbonTax") == 1){
      # initial here = 50 euros, clsoe to the current EU ETS price
      R_carbonTax <- initial + ((target - initial)*(t-start)) / (end-start)
    }
    R_carbonTax
  })
}


POL_priceETS <- function(){
  eq({#p ETS=
    start <- gp("startPolicy")
    priceETS_i <- template_industry_i
    if(t>= start && gp("Act_carbonTax")==1){
      priceETS_i <- R_carbonTax
    }else{
      priceETS_i #p ETS = pETS forecast(Time / Year 1) * euro 1
    }
    priceETS_i
  })
}


# ----------------------------------------------------------------------------------------------------------------
# Here for all other functions

# CO2 nrg i  = coeff E C to CO2 nrg i[solid,ind]*E C nrg i[solid,ind] ~~|
#coeff E C to CO2 nrg i =  R_enCarb_t_carbEmis_in

#CO2 i[ind]=
#	sum(CO2 nrg i[nrg!,ind])
#kton 

# ~~~~~~~~~~~~~~
CarbonTaxCoverage <- function(){
  eq({# CO2 for CT i[ind]= CO2 i[ind]* (1 - selection ETS i[ind])
    # CO2 i[in] =	sum(CO2 nrg i[nrg!,ind])
    whichTaxable_i <- 1 - gp("whichIndustryETS_i")
    F_taxableCarbon_i <- whichTaxable_i 
    F_taxableCarbon_i
  })
}

CarbonTaxLevy <- function(){
  eq({#carbon tax i[ind]=
    F_carbonTaxLevy_i <- R_carbonTax * F_taxableCarbon_1 * 1000
    F_carbonTaxLevy_i
  })
}

CarbonCostETS <- function(){
  eq({#CO2 cost ETS i[ind]=
    whichETS_i <- gp("whichIndustryETS_i")

    freeETS_i <- template_industry_i
    for(i in industry){
      sub_lookup <- gl("freeETS_i") %>% filter(industry == !!i)
      # security check
      if (nrow(sub_lookup) < 2) {freeETS_i[i] <- 0 
      next
      }
      # Étape 3.3 : Créer l’interpolateur
      temp_approxfun <- approxfun(sub_lookup$x, sub_lookup$y,rule = 2)
      freeETS_i[i] <- temp_approxfun(t)
    }

    sub_lookup <- gl("priceETSfcst") 
    # security check
    if (nrow(sub_lookup) < 2) {L_priceETSfcst <- 0 
    next
    }
    temp_approxfun <- approxfun(sub_lookup$x, sub_lookup$y,rule = 2)
    priceETSfcst <- temp_approxfun(t)

    F_carbonCostETS_i <- (whichETS_i * 1000 - freeETS_i / 1000) * priceETSfcst
    F_carbonCostETS_i 
  })
}

CarbonCostTotal <- function(){
  eq({# carbon cost tot i[ind]=
    F_carbonCostTotal_i <- F_carbonTaxLevy_i + F_carbonCostETS_i
    F_carbonCostTotal_i
  })
}

#UCC i[ind]= carbon cost tot i[ind]/y nom i[ind]


## period connectors ---------------------------------------------------------------------------------------------

## Regular functions ---------------------------------------------------------------------------------------------

## Vensim initial§) ----------------------------------------------------------------------------------------------


# END Fonctions --------------------------------------------------------------------------------------------------
