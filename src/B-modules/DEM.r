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
  eq({
    # Whoever matures out of a cohort matures into the next one, so the array is
    # shifted down by one cohort. Nobody matures out of the last cohort (they
    # die), and nobody matures into the first (they are born), hence the row of
    # zeros on top and the dropped last row at the bottom.
    empty_row   <- array(0, dim = c(1, length(pop_group), length(gender)))
    incomingPop <- abind(empty_row,
                         F_maturationOut_csg[head(cohort, -1), , ],
                         along = 1)
    dimnames(incomingPop) <- dimnames(F_maturationOut_csg)

    # Load every population group of a cohort with that cohort's total, which
    # skillShiftIncomingPop() then splits between groups.
    #   - into 15-24 they arrive as children, so the total sits in `child`
    #   - into the cohorts above they arrive already spread, so the total is
    #     the sum over groups
    olderCohorts <- setdiff(cohort, c("0-14", "15-24"))
    for (g in gender) {
      incomingPop["15-24", , g] <- incomingPop["15-24", "child", g]
      incomingPop[olderCohorts, setdiff(pop_group, "child"), g] <-
        rowSums(incomingPop[olderCohorts, , g])
    }
    incomingPop
  })
}

# Vensim: smooth(sens skill cs[skill] * (u s[mid] - u s[skill]),
#                duration skill transition)
#
# A SMOOTH is a hidden stock, so it is declared here as a variable of its own
# rather than recomputed inside the two equations that read it — which is also
# why it appears only once, though Vensim writes it out at every use.
smoothSkillShift <- function() {
  eq({
    input <- R_diffSkill_u_s * gp("R_sensSkillShift_s")

    # SMOOTH initialises to its input; afterwards it relaxes towards it.
    #
    # Written as a state and its flow, like every other state: the flow of a
    # SMOOTH is (input - state) / delay, which is what makes it a smooth. It
    # reads the state, which is allowed — see the note on state updates in
    # _module-template.r.
    if (t == startYear) {
      R_smoothSkillShift_s <- input
    } else {
      prev <- gd("R_smoothSkillShift_s", t - dt)
      F_smoothSkillShift_s <- (input - prev) / gp("timeSkillTransition")
      R_smoothSkillShift_s <- prev + F_smoothSkillShift_s * dt
    }
    R_smoothSkillShift_s
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

    smooth_vector_sg <- bind_cols("male"  = R_smoothSkillShift_s,
                                  "female" = R_smoothSkillShift_s)

    F_maturationIn_csg <- template_population_csg

    # `medium` is not shifted: it is backed out as the residual, so that the
    # groups still add up to the cohort total once `low`, `high` and `cap` have
    # moved. maturationIn() loaded every non-child group with the cohort total,
    # so any one of them can be read for it — "low" here.
    shifted <- setdiff(pop_group, c("child", "medium"))

    for (coh in setdiff(cohort, "0-14")) {
      # only the first adult cohort also carries the entry trend
      skillshift_sg <- if (coh == "15-24") 1 + smooth_vector_sg + R_trendEntrySkill_sg
                       else                1 + smooth_vector_sg

      for (g in gender) {
        F_maturationIn_csg[coh, , g] <- incomingPop[coh, , g] *
                                        sharesPop_lvl[coh, , g] * skillshift_sg[, g]
      }
      F_maturationIn_csg[coh, "medium", ] <-
        incomingPop[coh, "low", ] - colSums(F_maturationIn_csg[coh, shifted, ])
    }
    F_maturationIn_csg
  })
}       

skillShiftAllPop <- function() {
  eq({
    totalPop <- Pop_lvl
    totalPop[,,"male"] <- rowSums(Pop_lvl[,, "male"])
    totalPop[,,"female"] <- rowSums(Pop_lvl[,, "female"])

    smooth_vector_sg <- bind_cols("male"  = R_smoothSkillShift_s,
                                  "female" = R_smoothSkillShift_s)

    skillshift_sg <- 1 + smooth_vector_sg 

    ## of existing stock (sans trend entry)
    shifted <- setdiff(pop_group, c("child", "medium"))
    for (coh in setdiff(cohort, "0-14")) {
      for (g in gender) {
        Pop_lvl[coh, , g] <- Pop_lvl[coh, , g] * skillshift_sg[, g]
      }
      Pop_lvl[coh, "medium", ] <- totalPop[coh, "low", ] -
                                  colSums(Pop_lvl[coh, shifted, ])
    }
    PopSkillShift <- Pop_lvl
    PopSkillShift
  })
}

endCurrentPeriodPop <- function() {
  eq({
    # Vensim: Skills XXXX gs = INTEG(Skills * smooth(...) + in - out - deaths)
    #
    # The `Skills * smooth(...)` term reads the state, and skillShiftAllPop()
    # applies it as PopSkillShift = Pop_lvl * (1 + smooth), which is the same
    # thing: Pop_lvl + Pop_lvl * smooth. The remaining flows are plain.
    F_population_csg  <- (F_birth_csg - F_death_csg) +
                         (F_maturationIn_csg - F_maturationOut_csg)
    ST_population_csg <- PopSkillShift + F_population_csg * dt
    ST_population_csg
  })
}

# END Fonctions ------------------------------------------------------------------------------------------------
