module_name <- "EN"

# BEGIN Fonctions ------------------------------------------------------------------------------------------------
# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_


POL_PhaseOutReductionEnShare <- function() {
  eq({
    start <- gp("startPolicy")
    length_i <- gp("lengthPhaseOut_i")
    product_i <- gp("productPhaseOut_i")
    # end and start year as vector
    endYear_i <- (length_i + start) 
    startYear_i <- (template_energy_n + start) 

    # Store the energy share matrix at the time of policy start
    if(t == start && gp("Act_phaseOut") == 1){
      dt_set("dp", module = "POLICY", name = "SH_enSrc_atPolStart_in", value = SH_enSrc_enDemZ_in_lvl)
    }
    # Create output object as matrix of 0
    R_gEnShare_fromPolicy_in <- template_industry_in
    # Get policy start energy shares, used to compute progressive phasing out
    SH_enSrc_atPolStart_in <- if (t < start) NA else gp("SH_enSrc_atPolStart_in")

    if (!is.null(SH_enSrc_atPolStart_in) && !all(is.na(SH_enSrc_atPolStart_in))) {
      # annual reduction given starting share and length of phasing
      annualReduc_in <- sweep(SH_enSrc_atPolStart_in, 2, length_i, "/")
      annualReduc_in[!is.finite(annualReduc_in)] <- 0        
      # Check which energy is being phased out :  with selection of product to phase out (renew is never phased out = always 0 in produtPhaseOut_i)
      phaseOut_InProgress_i <- (t >= startYear_i & t < endYear_i) & gp("Act_phaseOut") == 1 & product_i == 1
      # Compute reduction in energy share from policy
      R_gEnShare_fromPolicy_in[] <- - sweep(annualReduc_in, 2, phaseOut_InProgress_i, "*") # the minus sign becasue its a reduction !
    }
    R_gEnShare_fromPolicy_in
  })
}

#RES shares g rates 2130 i[ind]=
#	S1 RES shares g rates 2130 i[ind]*0.8+IF THEN ELSE(Time <S Time Policy start,0,Act RES public\
#		*S1 RES shares g rates 2130 i[ind]*0.2)
#	~	Dmnl
#	~		|

POL_fossilSubsidiesReduction <- function(){
  eq({##Subs RES fossil SRF i
    start <- gp("startPolicy")
    end <- gp("endPolicy")

    fossilSubRed_i <- template_industry_i # initialise at 0
    if(t>= start && gp("Act_publicRES")){
      fossilSubRed_i["mining"]
      fossilSubRed_i["petroleum"]
      fossilSubRed_i["electricity"]
      fossilSubRed_i["transport"]

    }
    fossilSubRed_i

  })
}
# This lvl
POL_Shift_EnSourceShare_in_InterProdEnDemand <- function(){
  eq({# Share source Ed Z nrg i[nrg,ind]= INTEG (in share sources)
    start <- gp("startPolicy")
    end <- gp("endPolicy")
    product_i <- gp("productPhaseOut_i")

    # RESCALE : Ensure the shares sum up exactly to 1 by industry = no free (energy) lunch
    SH_enSources_in_lvl <- SH_enSrc_enDemZ_in_lvl/rowSums(SH_enSrc_enDemZ_in_lvl)
    #SH_enSourcesNotPhasedOut_in_lvl 
    # Change from endogenous renewable growth
    factor_in <- 1 + R_gEnShare_fromRenew_in

    # Change from policy
    if(t >= start && gp("Act_phaseOut")==1){

      if(gp("how_phaseOut")==1){# Full phasing out through renewable

        # the reduction
        factor_in <- factor_in + R_gEnShare_fromPolicy_in 

        # the increase
        # Sum up all reduction from other energies and make it an increase (with the minus)
        idx_renew <- which("renew" == colnames(R_gEnShare_fromPolicy_in))
        sumFromPolicy <- - rowSums(R_gEnShare_fromPolicy_in[, - idx_renew]) # minus by minus = plus
        factor_in[, "renew"] <- factor_in[, "renew"] + sumFromPolicy

      }else{# phasing out through reallocation to current energy mix 

        # the reduction
        factor_in <- factor_in + R_gEnShare_fromPolicy_in 

        # the increase
        idx_phasedOut <- which(product_i == 1)
        # Compute the shares of current energy mix leaving out phasing out energies 
        # These will be the weight of redistribution
        SH_currEnSources_in <- SH_enSources_in_lvl * (1 + R_gEnShare_fromRenew_in)
        relSH_currEnergyMix <- SH_currEnSources_in / (1 - rowSums(SH_currEnSources_in[, idx_phasedOut]))
        relSH_currEnergyMix[,idx_phasedOut] <- 0 #
        # Compute total change in energy share to redistribute
        energyToRedistr_i <- - rowSums(R_gEnShare_fromPolicy_in) # a minus because this is the positive counterpart of a sum of negative change
        # Compute rate of change in the shares of the non-phased out energy
        R_gEnShare_fromRedistr_in <- relSH_currEnergyMix * energyToRedistr_i # this should be 0 or > 0
        factor_in <- factor_in + R_gEnShare_fromRedistr_in 
      }
    }
    # We use as level the rescaled SH_enSources_in_lvl to be coherent with POL_Shift_EnSourceShare_FromRenewGrowth_i
    SH_enSrc_enDemZ_in <- SH_enSources_in_lvl * factor_in
    SH_enSrc_enDemZ_in
  })
}


# ----------------------------------------------------------------------------------------------------------------
# Here for all other functions

## period connectors ---------------------------------------------------------------------------------------------

## Regular functions ---------------------------------------------------------------------------------------------


shift_EnSourceShare_FromRenewGrowth_i <- function(){
  eq({# in share RES i (qui n'a pas de lvl correspondant mais est utilisé plutôt dans la fonction ci-desssous ainsi que dans celle de la demande finale donc on l'isole
    # Compute the growth rate of renew energy by industry
    if(t < 2022){
      R_gRenewShare_i <- gp("R_gRenewShare_2010_2021_i")
    }else{
      R_gRenewShare_i <- gp("R_gRenewShare_2021_2030_i")
    }
    # Ensure the shares sum up exactly to 1 by industry = no free (energy) lunch
    SH_enSources_in_lvl <- SH_enSrc_enDemZ_in_lvl/rowSums(SH_enSrc_enDemZ_in_lvl)

    # Compute elements
    SH_renew_i <- SH_enSources_in_lvl[,"renew"]
    SH_fossil_i <- 1 - SH_renew_i

    relShareEn_in_fossil_in <- SH_enSources_in_lvl / SH_fossil_i
    # if no fossil at all, then simply 0
    relShareEn_in_fossil_in[is.na(relShareEn_in_fossil_in)] <- 0

    # General case : shift out of fossil towards renew
    R_gEnShare_fromRenew_in <- template_industry_in
    R_gEnShare_fromRenew_in[] <- - R_gRenewShare_i * relShareEn_in_fossil_in # reduction
    R_gEnShare_fromRenew_in[, "renew"] <- + R_gRenewShare_i # increase

    # Special case : renew totally takes over fossil. 
    # TEST : Check whether the new level would be above unity given selected growth rate and previous year lvl
    renewExceedCap <- ( SH_renew_i * (1 + R_gRenewShare_i) ) > 1
    idx <- which(renewExceedCap)
    R_gEnShare_fromRenew_in[idx,] <- - SH_fossil_i[idx] # reduction
    R_gEnShare_fromRenew_in[idx, "renew"] <- + SH_fossil_i[idx] # increase 
    # in fact this is a cap here : since renew g rate exceeds 1, this applies to assign to make renewable the sole energy source of sector that was verifying the condition
    R_gEnShare_fromRenew_in
  })
}

## Vensim initial§) ----------------------------------------------------------------------------------------------


# END Fonctions --------------------------------------------------------------------------------------------------

source(path_module("_0verbose"))
# Store the modules functions in the objects to be retained when cleaning workspace
toKeep <- c(toKeep, functions_in_env)



