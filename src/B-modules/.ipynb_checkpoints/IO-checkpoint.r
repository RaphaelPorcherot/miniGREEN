module_name <- "IO"

# BEGIN Fonctions ------------------------------------------------------------------------------------------------
# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_)
# ----------------------------------------------------------------------------------------------------------------
# Here for all other functions



## period connectors ---------------------------------------------------------------------------------------------

## Regular functions ---------------------------------------------------------------------------------------------

leontieffMatrix_ii <- function(){
    eq({# Leontieff ii : GET_DIRECT_CONSTANTS('economy.xlsx','technology','B143') -> probably a previous version of the model in which the leontieff was precomputed in first period ? 
        leontieff_ii <- solve(gp("I") - R_a_ii)
        leontieff_ii
    })
}

nominalFinalDemandForDomesticGoods_i <- function(){
    eq({# c dom nom i[ind] + I supply dom nom i[ind] + gov c dom nom i[ind] + total exp nom i[\ 	~	Final demand for domestically produced goods, nominal
        F_finalDemNom_i <- domCnom_i + domInom_i + domGnom_i + Xnom_i
        F_finalDemNom_i 
    })
}

realFinalDemandForDomesticGoods_i <- function(){
    eq({#final demand real i[toind!] # 	~	Final demand for domestically produced goods, real
        F_finalDemReal_i <- F_finalDemNom_i / R_p_i 
        F_finalDemReal_i
    })
}


realTotalOuput_i <- function(){
    eq({#y real i[ind]=Real output by industry: \
        if(gp("fullCapacityConstraint")==0){
            #F_totalOutputReal_i <- rowSums(leontieff_ii # * final demand real i[toind!]
        }else{
            #F_totalOutputReal_i <- min(
                                        #rowSums(leontieff_ii # final demand real i[toind!],
                                        #y FC i[ind])
            #)
        }
        F_totalOutputReal_i
    })
}

interIndustryCoeff <- function(){
    eq({# a ii[ind,toind] 
        if(t==gp("startYear")){
            R_a_ii <- gi("R_a_ii") 
        } else {
            #if(T_i[ind] == UFC_Tiv[ind, T1]){
            # R_a_ii <- a_diffusion_ii[ind, toind]        
            #}else if( T_i[ind] = UFC_Tiv[ind, T2]){ 
            # R_a_ii <- a_delay_ii[ind, toind] * (1 + delta_a_T2_ii[ind, toind])
            #}else if T_i[ind] = UFC_Tiv[ind, T3]){
            #R_a_ii <- a_delay_ii[ind, toind] * (1 + delta_a_T3_ii[ind, toind])        
            #}else if(T_i[ind] = UFC_Tiv[ind, T3]){
            #R_a_ii <- a_delay_ii[ind, toind] * (1 + delta_a_T4_ii[ind, toind])
            #
            R_a_ii <- max(0, R_a_ii)
        }
           #R_a_ii <- R_a_ii * (1+ delta damage multiplier i[ind]
           R_a_ii
    })
            
}

realInterIndustryTradeMatrix_ii <- function() {
    eq({#Interindustry trade matrix, real
        Zreal_ii <- R_a_ii * as.vector(F_totalOutputReal_i) # we multiply each column of the A matrix by the output vector to get flux from sector i to sector j. 
        
        #if(gp("financialIncomeSwitch"==1){
         #   ZReal_ii[,"finance"] <- # sum(Financial industry revenue i[ind!]/CPI)
        #}
        
        Zreal_ii 
    })
}

nominalInterIndustryTradeMatrix_ii <- function() {
    eq({#Interindustry trade matrix, nominal
        Znom_ii <- Zreal_ii * as.vector(R_p_i) # we could have used sweep() too
        Znom_ii
    })
}

nominalIntermediateDemand_interindustryAndImport <-function() {
    eq({# z demand nom i[toind]=sum(Z nom ii[ind!,toind])+Z imp nom i[toind] | intermediate demand by industry including imports, nominal
        totalZnom_i <- colSums(Znom_ii) + impZnom_i
        totalZnom_i
    })
}


nominalTotalOuput_i <- function(){
    eq({#y nom i[ind] Nominal output by industry
        F_totalOutputNom_i <- F_totalOutputReal_i * R_p_i
        F_totalOutputNom_i
    })
}


	

## Vensim initial§) ----------------------------------------------------------------------------------------------


# END Fonctions --------------------------------------------------------------------------------------------------

source(here("notebooks", "r-nb", "B-modules", "_0verbose.r"))
# Store the modules functions in the objects to be retained when cleaning workspace
toKeep <- c(toKeep, functions_in_env)

                                            
                                            