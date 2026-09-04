# BEGIN Fonctions ------------------------------------------------------------------------------------------------
# Here put the functions that are affected by policy (POL_) and/or shock (SHOCK_)

POL_scalingLabourProductivity <- function() {
  eq({
    # scalling lambda . Prev : 0.5
    start <- gp("startPolicy")
    end <- gp("endPolicy")
    coeff <- gp("coeff_scalingLabProd") # scalling lambda
    if (t >= start && gp("Act_scalingLabProd") == 1) {
      factor <- 1 + coeff * min(end - start, t - start) / (end - start)
    } else {
      factor <- 1
    }

    R_scalingLabProd <- 0.8 * factor
    R_scalingLabProd
  })
}

# ------------------------------------------------------------------------------------------------
# Here for all other functions

## period connectors -----------------------------------------------------------------------------------------

## Regular functions -----------------------------------------------------------------------------------------

computeAlternativeChangeLabourProductivity <- function() {
  eq({
    # Per industry, all of them. This used to read max(0, mean) — R's max() is a
    # reduction, so it replaced all nineteen industry means by the largest one.
    # Vensim's max() is elementwise here; pmax() is its R equivalent, and the
    # vector goes first or the names are lost.
    #
    # TODO(2026): the 2025 model floors the mean at zero, the 2026 model does
    # not, and that removal is undocumented. Do not simply follow 2026 here —
    # ask. The technology module is known to be giving the 2026 translator
    # trouble, so the floor may have been dropped deliberately, or in passing.
    # This line follows 2025, like the rest of the module.
    #
    # The economics, for whoever picks this up: an alternative technology that
    # lowers productivity is a legitimate draw — it simply will not be the one
    # selected. Flooring it at zero does not stop a bad alternative being
    # modelled, it stops it being recognised as bad. See inconsistencies_new.md.
    mean <- pmax(gp("R_gLabProdMean_i"), 0)
    sd <- gp("R_gLabProdSd_i")
    min <- gp("R_gLabProdMin_i")
    max <- gp("R_gLabProdMax_i")

    R_gLabProdAlt_iv <- template_industry_iv
    # T1 is the incumbent technology: no change beyond diffusion, hence
    # lambda diffusion * (1 + 0)
    R_gLabProdAlt_iv[, "T1"] <- 0
    # delta lambda T2 i : change in labour productivity for T2
    R_gLabProdAlt_iv[, "T2"] <- R_scalingLabProd *
      rtruncnorm(
        n = 1,
        a = min + sd,
        b = max + sd,
        mean = mean + sd,
        sd = sd
      )
    # delta lambda T3 i : change in labour productivity for T3
    R_gLabProdAlt_iv[, "T3"] <- R_scalingLabProd *
      rtruncnorm(1, min - sd, max - sd, mean - sd, sd)
    # delta lambda T4 i : change in labour productivity for T4
    R_gLabProdAlt_iv[, "T4"] <- R_scalingLabProd *
      rtruncnorm(1, min + sd, max + sd, mean + sd, sd)
    R_gLabProdAlt_iv
  })
}

computeAlternativeLabourProductivity <- function() {
  eq({
    # lambda T iv
    baseLabProd <- template_industry_iv
    # only the incumbent technology carries the diffusion term; the alternatives
    # start from last period's productivity
    baseLabProd[, "T1"] <- R_labProdDiffusion_i
    baseLabProd[, setdiff(technology, "T1")] <- R_labProd_i_lag
    R_labProdAlt_iv <- baseLabProd * (1 + R_gLabProdAlt_iv)
    R_labProdAlt_iv
  })
}

computeAlternativeDesiredLabour <- function() {
  eq({
    # L T iv - unlike L i, it is not used elsewhere : there is no need to make a separate function for it.
    ST_desLabAlt_iv <- F_totalOutputReal_i_lag / (R_labProdAlt_iv * F_labHr_i)
    ST_desLabAlt_iv[is.nan(ST_desLabAlt_iv)] <- 0 # New addition to match the ZIDZ() of L i [ind]
    # L T isv[ind,skill,techn] and L T gisv[gender,ind,skill,techn]=
    ST_desLabAlt_isv <- template_industry_isv
    ST_desLabAlt_isvg <- template_industry_isvg
    for (v in technology) {
      ST_desLabAlt_isv[,, v] <- ST_desLabAlt_iv[, v] * SH_skill_is_lvl
      for (g in gender) {
        ST_desLabAlt_isvg[,, v, "male"] <- ST_desLabAlt_isv[,, v] *
          SH_male_is_lvl
        SH_female_is_lag <- 1 - SH_male_is_lvl
        ST_desLabAlt_isvg[,, v, "female"] <- ST_desLabAlt_isv[,, v] *
          SH_female_is_lag
      }
    }
    ST_desLabAlt_isvg
  })
}

computeAlternativeGrossWageBill <- function() {
  eq({
    #GWB iv
    F_GWBAlt_isvg <- template_industry_isvg
    for (v in technology) {
      F_GWBAlt_isvg[,, v, ] <- R_hrWage_isg_lvl *
        F_labHr_i *
        ST_desLabAlt_isvg[,, v, ]
    }
    ind_idx <- which(names(dimnames(F_GWBAlt_isvg)) == "Industry")
    tech_idx <- which(names(dimnames(F_GWBAlt_isvg)) == "Technology")
    F_GWBAlt_iv <- apply(F_GWBAlt_isvg, c(ind_idx, tech_idx), sum)
    F_GWBAlt_iv
    # Remember : F_GWB_isg <-  R_hrWage_isg_lvl * F_labHr_i * ST_labEmp_isg
    # In first period :
    #F_GWBAlt_iv[,1] - apply(R_hrWage_isg_lvl * F_labHr_i * ST_desLab_isg, 1, sum) == 0
    # This is because labProdDiffusion = labProd
    # F_GWBAlt_iv[,1] - apply(F_GWB_isg, 1, sum) : will be different than zero each time EmpLab is not == DesLab
  })
}


unitLabCostAlt <- function() {
  eq({
    #ULC T iv[ind,techn]=
    #(GWB T iv[ind,techn]*(1+ss rate employer)/y nom delay i[ind])*Euro good 1
    R_unitLabCostAlt_iv
  })
}

unitInputCostAlt <- function() {
  eq({
    # UIC T iv[ind,techn]=
    #(Z T demand iv[ind,techn]+depreciation K delay i[ind]* euro 1/Euro constant 1* Year 1\
    #	+associated GHG cost[ind,techn])/y nom delay i[ind]*euro 1/Euro constant 1
    R_unitInputCostAlt_iv
  })
}

unitFactorCostAlt <- function() {
  eq({
    #UFC T iv[ind,techn]=
    #ULC T iv[ind,techn]+UIC T iv[ind,techn]
    R_unitFactorCostAlt_iv
  })
}

# note that delta damage multiplier i was originally introduced in lambda_i, but in fact
# it is applied to a ii
#shiftLabourProductivity_i <- function() {
#    eq({#lambda i
#        if (t == 1) {# In 1st period, R_labProd_i = R_labProd_i_lag
#            R_labProd_i <- gi("R_labProd_i")
#        } else {
#            T1_i <- T1_i
#            candidate <- if (T1_i == UFC_T_iv[ind, "T1"]) {
#                R_lambdaDiffusion_i
#            } else if (T1_i == UFC_T_iv[ind, "T2"]) {
#                R_labProd_i_lag * (1 + delta_lambda_T2_i[ind])
#            } else if (T1_i == UFC_T_iv[ind, "T3"]) {
#                R_labProd_i_lag * (1 + delta_lambda_T3_i[ind])
#            } else {
#                R_labProd_i_lag * (1 + delta_lambda_T4_i[ind])
#            }
#            R_labProd_i <- max(candidate, 0)
#        }
#    })
#}

techFrontierLabourProd <- function() {
  eq({
    # techn frontier lambda i
    R_techFrontLadProd_i <- R_labProd_i_lag +
      (R_labProd_i_lag - R_labProd_i_lag2)
    R_techFrontLadProd_i
  })
}

currTechDiffusionLabourProd <- function() {
  eq({
    # lambda diffusion i
    # continuous effect of implentation/diffusion in the absense of a new technological frontire/ a new technology being adopted
    # Check consistency of lvl and lag with the spirit rather than just the letter of vensim (even though the letter made it work !)
    recentInvestemnt <- (ST_KReal_i_lvl - (ST_KReal_i_lag2 - F_KRealDepr_i_lag))
    eff_newK <- R_techFrontLadProd_i * recentInvestemnt
    eff_oldK <- R_labProd_i_lag * (ST_KReal_i_lag2 - F_KRealDepr_i_lag)

    R_labProdDiffusion_i <- (eff_newK + eff_oldK) / ST_KReal_i_lvl
    R_labProdDiffusion_i
  })
}

# Vensim INITIAL --------------------------------------------------------------------------------------------

labourProductivity_lag2 <- function() {
  eq({
    # lambda delay2 i
    if (t == gp("startYear")) {
      R_labProd_i_lag2 <- R_labProd_i_lag
    } else if (t == gp("startYear") + 1) {
      R_labProd_i_lag2 <- gd("R_labProd_i", 1) # t-1
    } else {
      R_labProd_i_lag2 <- gd("R_labProd_i", t - 2)
    }
    R_labProd_i_lag2
  })
}


# END Fonctions ------------------------------------------------------------------------------------------------
