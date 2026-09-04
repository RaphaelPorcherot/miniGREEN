# NOTES
## There is demographic growth if print(apply(gd("ST_population_csg", 1),"Gender",sum) - apply(gi("ST_population_csg"),"Gender",sum)>0)  is TRUE

# BEGIN Fonctions ------------------------------------------------------------------------------------------------

POL_trendEntrySkill <- function() {
  eq({ # trend entry skill
    start <- gp("startPolicy")
    end <- gp("endPolicy")
    coeff <- gp("coeff_trendEntrySkill")

    if (t >= start && gp("Act_entrySkill") == 1) {
      factor <- 1 + coeff * min(end - start, t - start) / (end - start)
    } else {
      factor <- 1
    }

    R_trendEntrySkill_sg <- gi("R_trendEntrySkill_sg") * factor
    R_trendEntrySkill_sg
  })
}


# ------------------------------------------------------------------------------------------------

## Regular functions -----------------------------------------------------------------------------------------


#ALL OF THIS : LEVEL in Vensim
# initial value is first value, this function allows to compute value for t+1
birth <- function() {
  eq({
      F_birth_csg <- template_population_csg
      fertility_factor <- (gp("R_fertility") / gp("reproLife"))
      # Compute total birth
      totalBirth <- fertility_factor * sum(Pop_lvl[c("15-24", "25-44"), , "female"])
      # Assign half of it to each gender 
      F_birth_csg["0-14", "child", ] <- totalBirth / length(gender) 
      F_birth_csg
  })
}

death <- function() {
  eq({# There is infant mortality, low but still
      F_death_csg <- Pop_lvl * gp("R_mortality_csg")
      F_death_csg
  })
}

maturationOut <- function() {
  eq({## No one mature out of old age, they just die
      F_maturationOut_csg <- Pop_lvl * (1 - gp("R_mortality_csg")) / yearsCohort_c
      F_maturationOut_csg[is.na(F_maturationOut_csg)] <- 0 
      F_maturationOut_csg
  })
}       

maturationIn <- function() {
  eq({# Create an empty row to align the array dimensions
      empty_row <- array(0, dim = c(1, length(skill), length(gender)))
      # Bind the new cohort (those who are maturing into the next cohort) with existing data
      incomingPop <- abind(empty_row, F_maturationOut_csg[-dim(F_maturationOut_csg)[1], ,], along = 1) 
      # Index 1 is cohort, so we bind along the cohort dimension
      dimnames(incomingPop) <- dimnames(F_maturationOut_csg)
      ## The point now is to compute a 3D array equivalent in structure to totalPop,
      ## though not for the whole population but only for the incoming cohort.
      # Assign the coming-to-age to each skill group, including capitalists
      incomingPop[2, , "male"] <- incomingPop[2, 1, "male"]
      incomingPop[2, , "female"] <- incomingPop[2, 1, "female"]
      # Sum over skills in the other cohorts by cohort and gender
      incomingPop[3:5, -1, "male"] <- rowSums(incomingPop[3:5,,"male"])
      incomingPop[3:5, -1, "female"] <- rowSums(incomingPop[3:5,,"female"])
      incomingPop
  })
}
 
skillShiftIncomingPop <- function() {
  eq({     
      totalPop_lvl <- Pop_lvl
      totalPop_lvl[,,"male"] <- rowSums(Pop_lvl[,, "male"])
      totalPop_lvl[,,"female"] <- rowSums(Pop_lvl[,, "female"])
      # This gives SH_population_csg, the 3D array of shares by cohort and gender of each skill group.
      sharesPop_lvl <- Pop_lvl
      sharesPop_lvl <- Pop_lvl/totalPop_lvl
      
      # ~~~~~~~~~~~~~~~~ LOGIC CHECK: sum of population shares = 2 ~~~~~~~~~~~~~~~~
      sums <- rowSums(sharesPop_lvl)
      invalid_idx <- which(abs(sums - length(gender)) > tolerance)
      if (length(invalid_idx) > 0) {
          details <- sprintf(
              "Row %d: sum = %.3f (%s 2)", invalid_idx, #d
              sums[invalid_idx], #.3f
              ifelse(sums[invalid_idx] > 2, ">", "<")
          )
          stop(paste("Population shares do not sum to 2 (1 per gender) on the following rows:", paste(details, collapse = "\n")
          ))
      }
      # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      
    ## We store neither sharesPop nor totalPop, becasue they are start-of-period of values. 

      smooth_vector <- template_population_s
      smooth_vector[] <- smooth_vensim(R_diffSkill_u_s * R_sensSkillShift_s,timeSkillTransition)
      smooth_vector_sg <- bind_cols("male"=smooth_vector, "female"=smooth_vector )

      ## First adult cohort with trend entry
      skillshift_sg <- 1 + smooth_vector_sg + R_trendEntrySkill_sg 
      c <- "15-24"
      F_maturationIn_csg <- template_population_csg  
      for(g in gender){
          F_maturationIn_csg[c,,g] <- incomingPop[c,,g] * sharesPop_lvl[c,,g] * skillshift_sg[,g]
      }
      F_maturationIn_csg[c,"medium",] <- incomingPop[c,2,] - colSums(F_maturationIn_csg[c, c("low", "high", "cap"),])
      
      ## The rest of the adult cohorts (sans trend entry)
      skillshift_sg <- 1 + smooth_vector_sg
      for(c in 3:5){
          for(g in gender){
              F_maturationIn_csg[c,,g] <- incomingPop[c,,g] * sharesPop_lvl[c,,g] * skillshift_sg[,g]
          }
          F_maturationIn_csg[c,"medium",] <- incomingPop[c,2,] - colSums(F_maturationIn_csg[c, c("low", "high", "cap"),]) 
      }
      F_maturationIn_csg
  })
}       

skillShiftAllPop <- function() {
  eq({
      totalPop <- Pop_lvl
      totalPop[,,"male"] <- rowSums(Pop_lvl[,, "male"])
      totalPop[,,"female"] <- rowSums(Pop_lvl[,, "female"])
      
      smooth_vector <- template_population_s
      smooth_vector[] <- smooth_vensim(R_diffSkill_u_s * R_sensSkillShift_s, timeSkillTransition)
      smooth_vector_sg <- bind_cols("male"=smooth_vector, "female"=smooth_vector )
      
      skillshift_sg <- 1 + smooth_vector_sg 
      
      ## of existing stock (sans trend entry)
      for(c in 2:5){
          for(g in gender){
              Pop_lvl[c,,g] <- Pop_lvl[c,,g] * skillshift_sg[,g]
          }
          Pop_lvl[c,"medium",] <- totalPop[c,2,] - colSums(Pop_lvl[c, c("low", "high", "cap"),])
      }
      PopSkillShift <- Pop_lvl
      PopSkillShift
  })
}

endCurrentPeriodPop <- function() {
  eq({
      ST_population_csg <- PopSkillShift + (F_birth_csg - F_death_csg) + (F_maturationIn_csg - F_maturationOut_csg)
      ST_population_csg
  })
}

# END Fonctions ------------------------------------------------------------------------------------------------


source(here("notebooks", "r-nb", "B-modules", "_0verbose.r"))
# Store the modules functions in the objects to be retained when cleaning workspace
toKeep <- c(toKeep, functions_in_env)

                                            