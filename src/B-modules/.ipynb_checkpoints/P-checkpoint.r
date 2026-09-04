# NOTES

# BEGIN Fonctions ------------------------------------------------------------------------------------------------

# Here put the functions that are affected by policy or shocks

SHOCK_setMarkup <- function(){
    eq({#markup i[ind]=
        start <- gp("startPolicy")
        length <- gp("lengthShock")
        end <- start + length
        coeff <- gp("coeff_markupShock")
        decay <- (1 / (1 + coeff))^(1 / length) # gradual adjustement factor
        
        if(t >= start && gp("Act_markupShock")==1){
            if(t==start){
                shock <- 1 + coeff
            }else if(t <= end){ 
                idx <- t - start # Number of years since initial shock
                shock <- (1 + coeff) * decay^idx
            }else{
                shock <- 1
            }
                factor <- 1 + gp("R_markupCalib_i") * (R_markup_i_lag - gp("R_markupNormal") ) * shock
            }else{
            factor <- 1 + gp("R_markupCalib_i") * (R_markup_i_lag - gp("R_markupNormal") )
        }
        R_markup_i <-  R_markup_i_lag * factor 
        R_markup_i
    })
}


# ------------------------------------------------------------------------------------------------

# Here for all other functions

## period connectors -----------------------------------------------------------------------------------------

setPricesCapital <- function(){#to fix with actual weights of every industry in composition of GFCF
    eq({#price capital=sum(p i[ind!]*price capital weights i[ind!])
        weightsOnCapitalPrices_i <- gp("SH_pK_i")
        R_pK <- sum(R_p_i * weightsOnCapitalPrices_i)
        R_pK # not by industry
    })
}


# F_GWB_isg = f(R_hrWage_isg_lvl, ST_labEmp_isg) = f(R_hrWage_isg_lvl, g(F_totalOutputReal_i_lag)) 
unitLabCost <- function() {
    eq({#ULC i[ind]=(ZIDZ((GWB i[ind]-level WTR gov paid i[ind])*(1+ss rate employer),y real delay i[ind]))* Euro good 1
        totalLabCost_isg <- (F_GWB_isg - F_govWageCompWTR_isg) * (1 + R_socSecEmployer) 
        # Weird point : costs of current period (assuming current employment) are compared to previous period output (though the latter is used in the computed of current desired labour hence of current employed labour)
        totalLabCost_i <- rowSums(totalLabCost_isg) # nominal 
        totalProd_i <-  F_totalOutputReal_i # real : "physical" quantities of ouptut
        R_unitLabCost_i <- totalLabCost_i / totalProd_i
        R_unitLabCost_i[is.na(R_unitLabCost_i)] <- 0 
        R_unitLabCost_i
    })
}

unitInputCost <- function() {
    eq({#UIC i[ind]= ZIDZ(((z demand nom i[ind]+(depreciation K i[ind]*price capital delay)*euro 1* Year 1/ Euro constant 1)),y real i[ind])*euro 1/ Euro constant 1
        circCapitalCost_i <- totalZnom_i #nominal
        fixedCapitalCost_i <- F_KRealDepr_i * R_pK_lag #nominal
        totalInputCost_i <- circCapitalCost_i + fixedCapitalCost_i #nominal
        totalProd_i <-  F_totalOutputReal_i # real : "physical" quantities of ouptut
        R_unitInputCost_i <- totalInputCost_i / F_totalOutputReal_i
        R_unitInputCost_i[is.na(R_unitInputCost_i)] <- 0
        R_unitInputCost_i 
    })
}

unitFactorCostFossilSubsidiesReduction <- function(){
    eq({#U SRF i[ind]= Subs RES fossil SRF i[ind] / y nom i[ind] unit costs in case of reduction of fossil subsidies
    })
}

unitFactorCost <- function() {
    eq({#UFC 
        R_unitFactorCost_i <- R_unitInputCost_i + R_unitLabCost_i # + U SRF i[ind]
        R_unitFactorCost_i
    })
}


# R_unitFactorCost_i = f(R_unitLabCost_i)
setPrices <- function() {
    eq({# p i = max(((1+markup i[ind])*(1+vat rate[ind])*UFC delay i[ind])/p init i[ind],p i delay[ind]) et  p init i[ind]= INITIAL((1+markup i[ind])*(1+vat rate[ind])*UFC delay i[ind]
        # Deflation may occurs.
        if(t==gp("startYear")){
            R_p_i <- gd("R_p_i",1)
        }else{
            R_p_i[] <- ((1 + R_markup_i) * (1 + R_VAT) * R_unitFactorCost_i) / gd("R_p_i",1)
        } 
        R_p_i
    })
}
# -> This means we get rid of ULC delay 

## Regular functions -----------------------------------------------------------------------------------------

currentInflationByIndustry_i <- function(){
    eq({
        R_inflation_i <- (R_p_i - R_p_i_lag) / R_p_i_lag
        R_inflation_i
    })
}

currentInflationWeights_i <- function() {
    eq({# inflation weights i[ind]= c nom i[ind]/sum(c nom i[ind!])
    	SH_nomConsNACE_i <- F_Cnom_i / sum(F_Cnom_i)
        SH_nomConsNACE_i
    })
}

currentInflation <- function(){
    eq({# inflation= sum(inflation i[ind!]*inflation weights i[ind!])
        R_inflation <- sum(R_inflation_i * SH_nomConsNACE_i)
        R_inflation
    })
}


#CPI=
#	sum(p i[ind!]*price weights i[ind!])
#	~	Euro/Euro constant
#	~	consumer price index
#	|
#

#
#inflation=
#	sum(inflation i[ind!]*inflation weights i[ind!])
#	~	percentage
#	~		|
#


## period connectors -----------------------------------------------------------------------------------------

## Regular functions -----------------------------------------------------------------------------------------

## Vensim initial§) -----------------------------------------------------------------------------------------

# END Fonctions ------------------------------------------------------------------------------------------------

source(here("notebooks", "r-nb", "B-modules", "_0verbose.r"))
# Store the modules functions in the objects to be retained when cleaning workspace
toKeep <- c(toKeep, functions_in_env)

                                            
                                            