# NOTES
#working population (F_labour_isg) < active population (activePop) < working age population

# BEGIN Fonctions ------------------------------------------------------------------------------------------------
# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_)
# F_labHr_i : hours i 
# Annual working hours per capita by industry
POL_annualWorkingHours  <- function() {
  eq({
    start <- gp("startPolicy")
    end <- gp("endPolicy")
    coeff <- gp("WTR")

    if (t >= start && gp("Act_WTR") == 1) {
      factor <- 1 + coeff * min(end - start, t - start) / (end - start)
    } else {
      factor <- 1
    }

    F_labHr_i <- gi("F_labHr_i") * factor
    F_labHr_i
  })
}

# LEVEL in Vensim : an outcome of in wage gis[gender,ind,skill],  initial value is first value, this function allows to compute value for t+1
POL_shift_hourlyWage <- function(){# That must be real hourly wages. Yet if this is the case w
  eq({# R_HrWage_isg = wage gis and in wage gis

    # Change during the period resulting from current evolutions – inflation for the current period and not inflation_lag since this is a current period change.

    # growth rate or rate of change of employemnt (stock) : g L i
    diff <- ST_labEmp_isg - ST_labEmp_isg_lag #L gis 
    base <- ST_labEmp_isg_lag #L gis Delay
    R_gEmployedLabour_isg <- diff/base

    eff_gEmpLab_isq <- R_gEmployedLabour_isg * gp("R_sensHrWageEmp")

    # growth rate or rate fo change of labour productivity : g lamba i[ind]  
    diff <- R_labProd_i - R_labProd_i_lag #lamba i[ind] 
    base <- R_labProd_i_lag #lambda delay i
    R_gLabProd_i <- diff/base

    eff_gLabProd_is <- R_gLabProd_i %o% gp("R_sensHrWageLabProd_s") #outer matrix product
    eff_gLabProd_isg <- template_industry_isg
    eff_gLabProd_isg[,,"male"] <- eff_gLabProd_is
    eff_gLabProd_isg[,,"female"] <- eff_gLabProd_is
    # growth rate or rate of change of prices : inflation
    #  inflation= sum(inflation i[ind!]*inflation weights i[ind!])
    eff_inflation <- R_inflation * R_sensHrWagePrice
    factor_isg <- 1 + eff_gEmpLab_isg
    + eff_gLabProd_isg
    + eff_inflation

    start <- gp("startPolicy")
    if (t == start && gp("Act_minHourW") == 1){
      # difference wage min wage gis # difference wage max wage gis
      diff_minToMeanWage_isg <- R_minHrWage - R_hrWage_isg_lvl    

      # (min) average wage changes gis 
      # How many standard deviations separate the minimum wage from the lagged average, so it is a normalized measure of the relative wage gap, not an average wage change.
      gap_minToMeanWage_isg <- diff_minToMeanWage_isg / (gp("coeffWageDispersion_isg") * R_hrWage_isg_lvl)

      # Intensity of the reaction of average wages to the fact that the minimum wage moves away from the average.
      intensityChangeMean <- template_industry_isg
      for (g in gender) {
        for (s in skill) {

          # Zero column for fake skills
          if (s %in% c("child", "cap")) {
            intensityChangeMean[, s, g] <- 0
            next
          }

          for (i in industry) {
            gap_value <- gap_minToMeanWage_isg[i, s, g]
            # Skip si NA, NaN, ou Inf
            if (is.na(gap_value) || is.infinite(gap_value)) {
              intensityChangeMean[industry, skill, gender] <- 0
              next
            }

            sub_lookup <- gl("minWageAverageChange_isg") %>% filter(
                                                                    industry == !!i &
                                                                      skill == !!s &
                                                                      gender == !!g)

            # Skip s’il n’y a pas de points d’interpolation
            if (nrow(sub_lookup) < 2) {
              intensityChangeMean[i,s,g] <- 0
              next
            }
            # Étape 3.3 : Créer l’interpolateur
            temp_approxfun <- approxfun(sub_lookup$x, sub_lookup$y,rule = 2)
            change_value <- temp_approxfun(gap_value)
            intensityChangeMean[i,s,g] <- change_value
          }
        }
      }

      # An average wage change expressed in euros, thus a modification of the distribution curve that varies depending on the gap between the minimum wage and the average wage.
      factor_isg <- factor_isg + intensityChangeMean * gp("coeffWageDispersion_isg")
    }

    if (t == start && gp("Act_maxHourW") == 1){
      diff_maxToMeanWage_isg <- R_maxHrWage - R_hrWage_isg_lvl    
      gap_maxToMeanWage_isg <- diff_maxToMeanWage_isg / (gp("coeffWageDispersion_isg") * R_hrWage_isg_lvl)
      intensityChangeMean <- template_industry_isg
      for (g in gender) {
        for (s in skill) {

          # Zero column for fake skills
          if (s %in% c("child", "cap")) {
            intensityChangeMean[, s, g] <- 0
            next
          }

          for (i in industry) {
            gap_value <- gap_maxToMeanWage_isg[i, s, g]
            # Skip si NA, NaN, ou Inf
            if (is.na(gap_value) || is.infinite(gap_value)) {
              intensityChangeMean[industry, skill, gender] <- 0
              next
            }

            sub_lookup <- gl("maxWageAverageChange_isg") %>% filter(
                                                                    industry == !!i &
                                                                      skill == !!s &
                                                                      gender == !!g)

            # Skip s’il n’y a pas de points d’interpolation
            if (nrow(sub_lookup) < 2) {
              intensityChangeMean[i,s,g] <- 0
              next
            }
            # Étape 3.3 : Créer l’interpolateur
            temp_approxfun <- approxfun(sub_lookup$x, sub_lookup$y,rule = 2)
            change_value <- temp_approxfun(gap_value)
            intensityChangeMean[i,s,g] <- change_value
          }
        }
      }

      factor_isg <- factor_isg + intensityChangeMean * gp("coeffWageDispersion_isg")
    }

    if (t >= start && gp("Act_wageCompWTR") == 1){
      #+  delta wage WTR[gender,ind,skill])}
      factor_isg <- factor_isg + R_gWageCompWTR_i 
      # child and cap column are now not zero, but they will be brought back to this in the next line so no need to get rid of it.
    }

    R_HrWage_isg <- R_hrWage_isg_lvl * factor_isg


    #* actual wage should be the max of min wage and computed wage and the min of max wage and computed wage if policies are active and time is rip
    if (t >= start && gp("Act_minHourW") == 1){
      R_HrWage_isg <- max(R_minHrWage_indexed, R_HrWage_isg)
    }
    if (t >= start && gp("Act_maxHourW") == 1){
      R_HrWage_isg <- min(R_maxHrWage_indexed, R_HrWage_isg)
    }
    R_HrWage_isg
  })
}


# ------------------------------------------------------------------------------------------------
# Here for all other functions

## period connectors -----------------------------------------------------------------------------------------

grossWageBill <- function() {
  eq({#GWB gis :  this NOMINAL WAGE
    # Minimum and maximum wage policy : # pmax(R_minHrWage, R_hrWage_isg_lvl) -> no longer necessary now that'is in the R_HrWage_isg
    # lvl = last period wages with current labour hours and current labour pop
    # instead of sweep this also works : (ST_labEmp_isg * R_hrWage_isg_lvl) * as.vector(F_labHr_i)
    F_GWB_isg <-  sweep((ST_labEmp_isg * R_hrWage_isg_lvl), 1, F_labHr_i, `*`)
    F_GWB_isg
    #previous formula (changed 11/11/22)
    #(max(wage min[gender,ind,skill],wage gis[gender,ind,skill])*hours i[ind]*L \
    #gis[gender,ind,skill])/(People 1*Hours 1)
  })
}

#GWB gs[gender,skill]=
#	sum(GWB gis[gender,ind!,skill])
#	~	Euro
#	~		|


# L i - employed workers by industry
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~ THIS VARIABLE CONNECTS PERIOD ~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

desiredLabour_i  <- function() {
  eq({# L i[ind]=
    ST_desLab_i <- F_totalOutputReal_i_lag / (R_labProd_i * F_labHr_i)  # Negative unemployement mistake
    ST_desLab_i[is.nan(ST_desLab_i)] <- 0
    ST_desLab_i
  })
}

desiredLabour_isg  <- function() {
  eq({# L is - employed workers by industry and skill (in fact its **desired** employment)
    ST_desLab_is <- sweep(SH_skill_is_lvl, 1, ST_desLab_i, `*`)

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ LOGIC CHECK ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    if (!all(abs(rowSums(sweep(SH_skill_is_lvl, 1, ST_desLab_i, `*`)) - ST_desLab_i) < tolerance)) {
      stop("Error: Row sums do not match ST_desLab_i within the allowed tolerance.")
    }
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~    
    # L gis - employment by industry, skill and gender (in fact its **desired** employment)
    ST_desLab_isg <- template_industry_isg
    ST_desLab_isg[,,"male"] <- ST_desLab_is * SH_male_is_lvl
    SH_female_is_lag <- 1 - SH_male_is_lvl
    ST_desLab_isg[,,"female"] <- ST_desLab_is * SH_female_is_lag
    ST_desLab_isg
  })
}

## Regular functions -----------------------------------------------------------------------------------------

workingAgePop <- function(){
  eq({# Working age population cgs
    # Working age pop is defined out of levels variables in vensim : hence its a lagged variable
    ST_workAgePop_csg <- Pop_lvl
    ST_workAgePop_csg[,c("child", "cap"),] <- 0
    ST_workAgePop_csg["65+",,] <- 0
    ST_workAgePop_csg
  })
}

# Does not include hence Jobg Guarantee workers
availableLabour <- function() {
  eq({# defined out of levels variables in vensim : hence its a lagged variable
    # ST_labS_csg : labour supply gs
    ST_labS_csg <- R_LFRP_csg_lvl * Pop_lvl - ST_labJG_csg_lvl
    ST_labS_csg 
  })
}

activePop <- function(){
  eq({
    ST_activePop_csg <- ST_labS_csg + ST_labJG_csg_lvl
    ST_activePop_csg
  })
}

inactivePop <- function(){
  eq({# N olf gs[gender,skill]= number of people being out of labour force by gender and skill
    ST_workAgePop_sg <- colSums(ST_workAgePop_csg, dims = 1)
    ST_activePop_sg  <- colSums(ST_activePop_csg , dims = 1)
    ST_inactivePop_sg <- ST_workAgePop_sg - ST_activePop_sg
    ST_inactivePop_sg
  })
}

employedLabour  <- function() {
  eq({# NOVEL ADDITION TO PREVENT NEGATIVE UNEMPLOYEMNT
    rescaleFactor_sg <- colSums(ST_labS_csg, dims=1)/colSums(ST_desLab_isg, dims=1)
    rescaling_index <- which(rescaleFactor_sg < 1)
    rescaleFactor_sg[-rescaling_index] <- 1
    rescaleFactor_sg[c("child", "cap"),] <- 0 # Storing it <<- would give an idea of labour bottlenecks - to check whether they are realistic
    rescaleFactor_isg <- template_industry_isg
    for(i in 1:length(industry)){
      rescaleFactor_isg[i,,"male"] <- rescaleFactor_sg[,"male"]
      rescaleFactor_isg[i,,"female"] <- rescaleFactor_sg[,"female"]
    }

    ST_labEmp_isg <- rescaleFactor_isg * ST_desLab_isg
    ST_labEmp_isg
  })
}


employmentRate_sg <- function() {
  eq({# Actifs occupés / Pop. It counts workers in JG as active workers.
    ST_labEmp_sg <- colSums(ST_labEmp_isg, dims = 1) 
    ST_labJG_sg_lag <- colSums(ST_labJG_csg_lvl, dims=1)
    workAgePop_sg_lag <-  colSums(ST_workAgePop_csg, dims = 1)
    # e gs - emplopyment rate by skill by gender (e delay gs, e initial gs)
    empPop_sg <- ST_labEmp_sg + ST_labJG_sg_lag
    R_e_sg <- empPop_sg / workAgePop_sg_lag
    R_e_sg[is.nan(R_e_sg)] <- 0
    R_e_sg
  })
}

employmentRate_s <- function() {
  eq({
    ST_labEmp_s <- rowSums(colSums(ST_labEmp_isg, dims = 1))
    ST_labJG_s_lag <- rowSums(colSums(ST_labJG_csg_lvl, dims=1))
    workAgePop_s_lag <- rowSums(colSums(ST_workAgePop_csg, dims = 1))
    # e s - emplopyment rate by skill by gender (e delay gs, e initial gs)
    empPop_s <- (ST_labEmp_s + ST_labJG_s_lag)
    R_e_s <- empPop_s / workAgePop_s_lag
    R_e_s[is.nan(R_e_s)] <- 0
    R_e_s
  })
}

employmentRate_g <- function() {
  eq({
    ST_labEmp_g <- colSums(ST_labEmp_isg, dims=2)
    ST_labJG_g_lag <- colSums(ST_labJG_csg_lvl, dims=2)    
    workAgePop_g_lag <- colSums(ST_workAgePop_csg, dims=2)
    # e s - emplopyment rate by skill by gender (e delay gs, e initial gs)
    empPop_g <- ST_labEmp_g + ST_labJG_g_lag
    R_e_g <- empPop_g / workAgePop_g_lag
    R_e_g[is.nan(R_e_g)] <- 0
    R_e_g
  })
}

unemploymentRate_sg <- function() {
  eq({# Actifs occupés / Actifs
    # JG is actually also in the numerator, but by way of the definition of the labour supply it cancels out
    # See "inconsistencies" file for further details
    # Note that these unemployment rate are general, and not restricted to the economy that is not JG only.
    # Note that as computed, given the initial values, unemployemnt rate are negative for male of all skills while being positive for women. The rescaleFactor applies to avoid this.
    ST_labS_sg <- colSums(ST_labS_csg, dims=1)
    ST_labEmp_sg <- colSums(ST_labEmp_isg, dims = 1)
    ST_activePop_sg <- colSums(ST_activePop_csg, dims=1)
    # u gs - unemployment rate by industry by skill by gender
    R_u_sg <- template_population_sg
    unempLab_sg <- ST_labS_sg - ST_labEmp_sg
    # this is consistent with ST_labS_csg <- R_LFRP_csg_lvl * Pop_lvl - ST_labJG_csg_lvl
    R_u_sg[] <- unempLab_sg / ST_activePop_sg
    R_u_sg[is.nan(R_u_sg)] <- 0
    R_u_sg
  })
}

unemploymentRate_s <- function() {
  eq({# Since we resolved negative unemployment we get rid of magic numbers of 1% minimal unemployment.
    ST_labS_s <- rowSums(colSums(ST_labS_csg, dims=1))
    ST_labEmp_s <- rowSums(colSums(ST_labEmp_isg, dims=1))
    ST_activePop_s <- rowSums(colSums(ST_activePop_csg, dims=1))
    # R_u_s : u s
    R_u_s <- template_population_s
    unempLab_s <- ST_labS_s - ST_labEmp_s
    R_u_s[] <- unempLab_s / ST_activePop_s
    R_u_s[is.nan(R_u_s)] <- 0
    R_u_s
  })
}

unemployedLabour <- function() {
  eq({#L u gs[gender,skill]= max(50000* People 1,labour supply gs[gender,skill]-L gs[gender,skill])
    ST_labUnemp_sg <- colSums(ST_labS_csg, dims=1) - colSums(ST_labEmp_isg, dims=1)
    ST_labUnemp_sg
    # No need to substract also JG workers since they have been substracted already from the labour supply
  })
}

diffRateUnemploymentBySkill <- function() {
  eq({# The 0 in the "medium" column is there because we compute the skill shift in that column as the remainder between total amount of ppl in cohort minus skill shift in low and high columns
    # The 1 in the "cap" column is there in order to keep the amount of capitalists unchanged - they are by construction not affected by skill shift
    R_diffSkill_u_s <-  c(0, R_u_s["medium"] - R_u_s["low"], 0, R_u_s["medium"] - R_u_s["high"], 1)
    R_diffSkill_u_s
  })
}

diffRateUnemploymentByGender <- function() {
  eq({
    R_diffGender_u_s <- R_u_sg[,"male"] - R_u_sg[,"female"]
    R_diffGender_u_s
  })
}

# LEVEL in Vensim
# initial value is first value, this function allows to compute value for t+1
shift_SkillLabourShare <- function() {
  eq({# SH_skill_is : skill distribution initial is / skill trend delay is / in skill trend is

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ LOGIC CHECK ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    if(!all(rowSums(SH_skill_is_lvl) - 1) < tolerance) {
      stop("Error: Row sums on SH_skill_is_lvl are not equal to 1 within the allowed tolerance.")
    }
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    shift_is <- convergence * gp("R_trendSkill_is")
    factor_is <- 1 + shift_is
    SH_skill_is <- SH_skill_is_lvl * factor_is
    SH_skill_is
  })
}

# LEVEL in Vensim
# initial value is first value, this function allows to compute value for t+1
shift_MaleLabourShare <- function() {
  eq({# SH_male_is : male share is
    # When male unemployment is higher than female unemployment, the male share in that category decreases accordingly.
    eff_unempMale_s <- - gp("R_sensMaleU_s") * R_diffGender_u_s
    eff_unempMale_is <- template_industry_is
    eff_unempMale_is[,] <- rep(eff_unempMale_s, each = nrow(eff_unempMale_is))
    eff_trendMale_is <- convergence * gp("R_trendMale_is")
    # Addition directe (évite sweep)
    shift_is <- template_industry_is
    shift_is[] <- eff_trendMale_is + eff_unempMale_is 
    # Where is trigger (SH_male_is_lvl * (1 + shift_is) < 1)
    # whereUpdate is a true/false matrix : we update only if the new computed share does not exceed 1
    whereUpdate <- (SH_male_is_lvl * (1 + shift_is) < 1)
    factor_is <- 1 + whereUpdate * shift_is
    SH_male_is <- SH_male_is_lvl * factor_is
    SH_male_is
  })
}

# LEVEL in Vensim
# initial value is first value, this function allows to compute value for t+1
shift_LabourForceParticipationRate <- function(){
  eq({
    R_LFRP_sg_lvl <- template_population_sg
    R_LFRP_sg_lvl[,"male"] <- R_LFRP_csg_lvl["15-24",,"male"]
    R_LFRP_sg_lvl[,"female"] <- R_LFRP_csg_lvl["15-24",,"female"]

    R_gExpIncome_sg <- (F_expIncome_sg - F_expIncome_sg_lag) / F_expIncome_sg_lag
    factor_csg <- 1 + template_population_csg
    # Change in LFRP  in LFPR gs
    if (t %in% covidYears) {
      cy <- match(t, covidYears)
      factor_csg <- factor_csg + gp("R_dLFRPCovid")[cy]
    } else if (R_LFRP_sg_lvl + R_e_sg * R_gExpIncome_sg > 1){
      factor_sg <- 1 + gp("R_sensLFPRIncome") * R_e_sg
      factor_csg[,,"male"] <- factor_sg[, "male"]
      factor_csg[,,"female"] <- factor_sg[, "female"]
    }
    # LFPR gs
    R_LFRP_csg <- R_LFRP_csg_lvl * (factor_csg + F_labourJG_csg / ST_workAgePop_csg) # end of period working pop

    R_LFRP_csg["0-14",,] <- 0
    R_LFRP_csg["65+",,] <- 0
    R_LFRP_csg
  })
}


#flux_JobGuarantee <- function(){
#    eq({# JG L gs
#        F_labourJG_csg <- inJG - outJG
#        F_labourJG_csg
#        },
#       dep=c(""))
#}
#


# LEVEL in Vensim
# initial value is first value, this function allows to compute value for t+1
#shift_stockJobGuarantee <- function(){
#    eq({
#        # Transf JG
#        # Out JG
#        ST_labJG_csg <- ST_labJG_csg_lvl + F_labourJG_csg
#        ST_labJG_csg
#        },
#       dep=c("ST_labJG_csg_lvl", "F_labourJG_csg"))
#}

# exp inc e gs exp inc e gs delay exp inc e gs initial
# Meant to be for employed, and used to compute LFRP, but in fact it includes incomes from other sources than just labor income
# cb gs[gender,skill] also to integates ? Might smooth reaction to labor market conditions
incomeExpectation <- function(){
  eq({# exp inc e gs
    # labourIncome : based on last period hourly wage
    # unempIncome : based on current period GUB which is based on current period Emp et UnempLabour MAIS sur last period hourly wage
    R_HrWage_sg <- colSums(R_hrWage_isg_lvl * ST_labEmp_isg, dims=1) / colSums(ST_labEmp_isg, dims=1)
    R_HrWage_sg[is.na(R_HrWage_sg)] <- 0
    meanHours <- sum(F_labHr_i * rowSums(ST_labEmp_isg)) / sum(ST_labEmp_isg)
    # Real values
    labourIncome <- ((1 - R_u_sg ) * R_HrWage_sg * meanHours) / CPI 
    unempIncome <-  (R_u_sg * (F_GUB_sg / ST_labUnemp_sg))/ CPI 
    unempIncome[is.na(unempIncome)] <- 0
    otherBenefits <- F_othBenefPerCap / CPI

    # sum(ST_labEmp_isg) should be nearly equal to sum(ST_labEmp_i)
    # all.equal(sum(ST_labEmp_isg), sum(ST_labEmp_i)) 
    # THis is the case
    # Make sure capitalist do not earn labour income
    F_expIncome_sg <- labourIncome + unempIncome
    F_expIncome_sg["low",] <- F_expIncome_sg["low",] + otherBenefits
    F_expIncome_sg
  })
}

# Vensim INITIAL --------------------------------------------------------------------------------------------

incomeExpectation_lag <- function(){
  eq({
    if(t==gp("startYear")){
      F_expIncome_sg_lag <- F_expIncome_sg    
    }else{
      F_expIncome_sg_lag <- gd("F_expIncome_sg", t-1)
    }
    F_expIncome_sg_lag   
  })
}

employedLabour_lag <- function(){
  eq({# L gis initial L gis Delay
    if(t==gp("startYear")){
      ST_labEmp_isg_lag <- ST_labEmp_isg    
    }else{
      ST_labEmp_isg_lag <- gd("ST_labEmp_isg", t-1)
    }
    ST_labEmp_isg_lag
  })
}



# END Fonctions ------------------------------------------------------------------------------------------------

source(here("notebooks", "r-nb", "B-modules", "_0verbose.r"))

# Store the modules functions in the objects to be retained when cleaning workspace
toKeep <- c(toKeep, functions_in_env)


