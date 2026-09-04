module_name <- "GOV"

# NOTES

# BEGIN Fonctions ------------------------------------------------------------------------------------------------
# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_)

POL_unempBenefitsShareInWageBill <- function() {
    eq({
        # ub wage ratio =
        start <- gp("startPolicy")
        end <- gp("endPolicy")
        coeff <- gp("coeff_grossUnempShare")  # S ub ratio
        base <- gi("SH_unempBenef_toWage")    # S1 ub wage ratio (unemployment benefit's fraction of wages)
        
        if (t >= start && gp("Act_grossUnempShare") == 1) {
            SH_unempBenef_toWage <- base * (1 + coeff * min(end - start, t - start) / (end - start))
        } else {
            SH_unempBenef_toWage <- base
        }

        SH_unempBenef_toWage
    })
}


POL_pensionBenefitsShare_in_wageBill <- function() {
    eq({# pension wage ratio= pension's fraction of wages 
        start <- gp("startPolicy")
        end <- gp("endPolicy")
        coeff <- gp("coeff_grossPensionShare") # S pension ratio
        base <- gi("SH_pension_toWage")    # S1 pension wage ratio (unemployment benefit's fraction of wages)
        base <- base * (1 - (t - gp("startYear"))) # MAGIC NUMBER 0.785546*(1-0.0025*Time)
            
        if (t >= start && gp("Act_grossPensionShare") == 1) {
            SH_pension_toWage <- base * (1 + coeff * min(end - start, t - start) / (end - start))
        } else {
            SH_pension_toWage <- base
        }
        SH_pension_toWage
    })
}
	

POL_valueAddedTaxRate <- function() {
    eq({
        # ub wage ratio =
        start <- gp("startPolicy")
        end <- gp("endPolicy")
        coeff <- gp("coeff_VAT")  # S ub ratio
        base <- gi("R_VAT")    # S1 ub wage ratio (unemployment benefit's fraction of wages)

        if (t >= start && gp("Act_VAT") == 1) {
            R_VAT <- base * (1 + coeff * min(end - start, t - start) / (end - start))
        } else {
            R_VAT <- base
        }
        R_VAT
    })
}


POL_govWageCompWTR <- function(){
    eq({
        # quick but less explicit alternative to sweep(R_hrWage_isg_lvl, "Industry", R_gWageCompWTR_i, `*`) 
        F_wageCompWTR_isg <- R_hrWage_isg_lvl *  as.vector(R_gWageCompWTR_i) 
        F_govWageCompWTR_isg <- F_wageCompWTR_isg * gp("SH_govWageCompWTR")
        F_govWageCompWTR_isg
    })
}


POL_otherBenefits <- function() {
    eq({# init other benefits per cap 
        start <- gp("startPolicy")
        end <- gp("endPolicy")
        coeff <- gp("coeff_otherBenefits") # S other benefits
        
        # Switching to focalised benefits ---
        if (t == start && gp("Act_focBenefits") == 1) {
            F_othBenefPerCap <- gp("focBenefits")
        } else {
            F_othBenefPerCap <- F_othBenefPerCap_lag * (1 + R_inflation_lag) # price indexing
        }
        # -----------------------------------
        
        # enchancing other benefits ---
        if (t >= start && gp("Act_otherBenefits") == 1) {
            factor <- 1 + coeff * min(end - start, t - start) / (end - start)
        } else {
            factor <- 1
        }
        F_othBenefPerCap <- F_othBenefPerCap * factor
        # -----------------------------------
        
        # switching off other benefits because of basic income
        if (t >= start && gp("Act_BI") == 1) {
            factor <- 0
        } else {
            factor <- 1
        }
        F_othBenefPerCap <- F_othBenefPerCap * factor
        # -----------------------------------
        
        F_othBenefPerCap
    })
}

POL_incomeTaxRate <- function(){
    eq({
        start <- gp("startPolicy")
        progFactor <- gi("R_incomeTaxProgressivity") #this is a vector
        base_incomeTax <- gi("R_incomeTax") #this is a vector
        R_incomeTax <- base_incomeTax
        
        if(t >= start && gp("Act_progrIncomeTax")){
            R_incomeTax <- gp("R_progIncomeTax")
        }
        
        if(t >= start && gp("Act_BI") && gp("how_financeBI") == 1){# BI financed by income tax hike, wealth tax is not actie
            length_hike <- gp("length_incomeTaxHike")
            end_hike <- start + length_hike
            coeff_hike <- gp("coeff_incomeTaxHike")
            base_hike <- gp("base_incomeTaxHike")
            # ramp()
            hike_ratio <- pmin((t - start) / (end_hike - start), 1)
            taxHike_BI <- base_hike * coeff_hike * hike_ratio
            # compute shift 
            shift <- taxHike_BI * progFactor
            R_incomeTax <- R_incomeTax + shift
        }
        R_incomeTax 
       })
}
       
    
# ------------------------------------------------------------------------------------------------

# Here for all other functions

## Period connectors -----------------------------------------------------------------------------------------

## Regular functions -----------------------------------------------------------------------------------------

# *** Employment income

grossAnnualIncomePerCapita_employed <- function(){
    eq({# gross annual income e gis[gender,ind,skill]= individual gross annual income employed
        F_GWBperCap_isg <- R_hrWage_isg_lvl * as.vector(F_labHr_i)
        F_GWBperCap_isg[is.na(F_GWBperCap_isg)] <- 0
        F_GWBperCap_isg
    })
}

socialSecurityAnnualContPerCapita_eByEmployer <- function(){
    eq({# soc sec contr employer gis[gender,ind,skill]=social secutity contributions from employers per individual
        F_socSecPerCap_eEmployer_isg <- R_socSecEmployer * F_GWBperCap_isg
        F_socSecPerCap_eEmployer_isg
    })
}

socialSecurityAnnualContPerCapita_employed <- function(){
    eq({# soc sec contr e gis[gender,ind,skill]=individual compulsory scial security contributsions
        F_socSecPerCap_e_isg <- R_socSecEmployee * F_GWBperCap_isg
        F_socSecPerCap_e_isg
    })
}

taxableAnnualIncomePerCapita_employed <- function(){
    eq({# taxable inc e gis[gender,ind,skill] = gross annual income e gis[gender,ind,skill]*(1-ss rate employee) taxable income, after social security contributions
        F_taxIncPerCap_e_isg <- (1 - R_socSecEmployee) * F_GWBperCap_isg
        F_taxIncPerCap_e_isg
    })
}



# *** Unemployment benefits

grossUnempBenefits <- function() {
    eq({#GUB gs total gross unemployment benefits paid by skill and gender
        # ub wage ratio = SH_unempBenefWage
        ST_labEmp_sg <- colSums(ST_labEmp_isg, dims=1) 
        F_GWB_sg <- colSums(F_GWB_isg, dims=1) 
        F_GUB_sg <-  SH_unempBenef_toWage * (F_GWB_sg / ST_labEmp_sg) * gp("SH_unempCov") * ST_labUnemp_sg
        F_GUB_sg[is.na(F_GUB_sg)] <- 0
        F_GUB_sg
 })
}
   
grossAnnualIncomePerCapita_unemployed <- function(){
    eq({# ZIDZ(GUB gs[gender,skill],L u gs[gender,skill]) individual gross annual income unemployed
        F_GUBperCap_sg <- F_GUB_sg / ST_labUnemp_sg
        F_GUBperCap_sg[is.na(F_GUBperCap_sg)] <- 0
        F_GUBperCap_sg
    })
}

socialSecurityAnnualContPerCapita_unemployed <- function(){
    eq({#soc sec contr u gs[gender,skill]=gross annual income u gs[gender,skill]*ss rate employee	
        F_socSecPerCap_u_sg <- R_socSecEmployee * F_GUBperCap_sg
        F_socSecPerCap_u_sg 
    })
}

taxableAnnualIncomePerCapita_unemployed <- function(){
    eq({# taxable inc u gs = gross annual income u gs[gender,skill]*(1-ss rate employee)
        F_taxIncPerCap_u_sg <- (1 - R_socSecEmployee) * F_GUBperCap_sg
        F_taxIncPerCap_u_sg
    })
}

# *** Pension benefits

grossPensionBenefits <- function() {
    eq({# GPB gs[gender,skill]=pension wage ratio*ZIDZ(GWB gs[gender,skill],L gs[gender,skill])*"Skills 65+ gs"[gender,skill] total gross pension benefits paid by guvernment per skill and gender
        ST_labEmp_sg <- colSums(ST_labEmp_isg, dims=1) 
        F_GWB_sg <- colSums(F_GWB_isg, dims=1) 
        F_GPB_sg <-  SH_pension_toWage * (F_GWB_sg / ST_labEmp_sg) * Pop_lvl["65+",,] # NOT ST_population_csg which is not yet the case
        F_GPB_sg[is.na(F_GPB_sg)] <- 0
        F_GPB_sg
    })
}

grossAnnualIncomePerCapita_pension <- function(){
    eq({# gross annual income p gs[gender,skill]= ZIDZ(GPB gs[gender, skill],"Skills 65+ gs"[gender,skill]) individual gross annual income pensioners
        F_GPBperCap_sg <- F_GPB_sg / Pop_lvl["65+",,] # SAME REMARK than grossPensionBenefits
        F_GPBperCap_sg[is.na(F_GPBperCap_sg)] <- 0
        F_GPBperCap_sg
    })
}

socialSecurityAnnualContPerCapita_pension <- function(){
    eq({#soc sec contr u gs[gender,skill]=gross annual income u gs[gender,skill]*ss rate employee	
        F_socSecPerCap_p_sg <- R_socSecEmployee * F_GPBperCap_sg
        F_socSecPerCap_p_sg
    })
}

taxableAnnualIncomePerCapita_pension <- function(){
    eq({# taxable inc p gs[gender,skill]= gross annual income p gs[gender,skill]*(1-ss rate employee)
        F_taxIncPerCap_p_sg <- F_GPBperCap_sg * (1 - R_socSecEmployee)
        F_taxIncPerCap_p_sg
    })
}

# *** Let's tax !

incomeTaxLevyPerCapita_employed <- function(){
    eq({# inc tax e gs
        ntax <- length(R_incomeTax)
        treshold <- gi("F_incomeTaxTreshold")
        F_incTaxEmpPerCap_isg <- template_industry_isg
        for(n in 2:ntax){
            bracket <- treshold[n] - treshold[n-1]
            incomeInBracket <- F_taxIncPerCap_e_isg - treshold[n-1]
            F_incTaxEmpPerCap_isg[] <- F_incTaxEmpPerCap_isg + R_incomeTax[n-1] * pmin(bracket, pmax(incomeInBracket, 0))
        }
        F_incTaxEmpPerCap_isg
    })
}

incomeTaxLevyPerCapita_unemployed <- function(){
    eq({# inc tax u gs
        ntax <- length(R_incomeTax)
        treshold <- gi("F_incomeTaxTreshold")        
        F_incTaxUnempPerCap_sg <- template_population_sg
        for(n in 2:ntax){
            bracket <- treshold[n] - treshold[n-1]
            incomeInBracket <- F_taxIncPerCap_u_sg - treshold[n-1]
            F_incTaxUnempPerCap_sg[] <- F_incTaxUnempPerCap_sg + R_incomeTax[n-1] * pmin(bracket, pmax(incomeInBracket, 0))
        }
        F_incTaxUnempPerCap_sg
    })
}

incomeTaxLevyPerCapita_pension <- function(){
    eq({# inc tax p gs
        ntax <- length(R_incomeTax)
        treshold <- gi("F_incomeTaxTreshold")        
        F_incTaxPensPerCap_sg <- template_population_sg
        for(n in 2:ntax){
            bracket <- treshold[n] - treshold[n-1]
            incomeInBracket <- F_taxIncPerCap_p_sg - treshold[n-1]
            F_incTaxPensPerCap_sg[] <- F_incTaxPensPerCap_sg + R_incomeTax[n-1] * pmin(bracket, pmax(incomeInBracket, 0))
        }
        F_incTaxPensPerCap_sg
    })
}

totalIncomeTaxLevy <- function(){
    eq({# inc tax rev=government revenue from income tax
        fromEmp <- sum(F_incTaxEmpPerCap_isg * ST_labEmp_isg)
        fromUnemp <- sum(F_incTaxUnempPerCap_sg * ST_labUnemp_sg)
        fromPension <- sum(F_incTaxPensPerCap_sg * Pop_lvl["65+",,])
        F_incTaxLevy <- fromEmp + fromUnemp + fromPension
        F_incTaxLevy
    })
}


socialSecurityContRateTotal <- function() {
    eq({
        R_socSec <- gi("R_socSec")
        R_socSec
    })
}


socialSecurityContRateByEmployer <- function() {
    eq({
        R_socSecEmployer <- R_socSec - gi("R_socSecEmployer")  
        R_socSecEmployer
    })
}

socialSecurityContRateByEmployee <- function() {
    eq({
        R_socSecEmployee <- R_socSec - R_socSecEmployer 
        R_socSecEmployee
    })
}



# Vensim INITIAL --------------------------------------------------------------------------------------------


# END Fonctions ------------------------------------------------------------------------------------------------

source(here("notebooks", "r-nb", "B-modules", "_0verbose.r"))
# Store the modules functions in the objects to be retained when cleaning workspace
toKeep <- c(toKeep, functions_in_env)

                                            
                                            