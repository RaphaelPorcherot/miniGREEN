# Vensim ↔ R map

Which R function translates which Vensim equation, and where to find it.

The point is to be able to check the translation **one function at a time**:
open an R module, find its row here, jump to the line it names in
`vensim_model_2026.txt`, and compare. And the other way round — a Vensim
variable that appears nowhere in this file has not been translated yet.

> **This file is maintained by hand.** The first draft was generated from the
> Vensim equations quoted in the comments of each `eq()` block; from here on it
> is edited, not regenerated. Update a row when you check it, and update the
> counters at the bottom when you do.

## How to read a row

| Column | |
|---|---|
| **R function** | the function in `src/B-modules/<MODULE>.r` |
| **Output** | the variable it writes to `d` |
| **Vensim** | the variable(s) in `vensim_model_2026.txt` it covers |
| **Line** | where to find the first of them in that file |
| **Conf.** | how far the correspondence has been established, see below |

**One R function may cover several Vensim variables.** That is expected: the
Vensim model often splits one calculation across two or three variables that
exist only to be read once. Where that happens, list them all in the `Vensim`
column — the map has to stay usable in both directions.

**Some R functions have no Vensim original at all.** They were added while
correcting the model, and are marked `added` with a line saying why and a
pointer to `src/inconsistencies.qmd`. They are not gaps in the map; they are
deliberate departures from Vensim, and they matter more than the rest, because
nobody comparing the two models would otherwise know they are there.

## Confidence

| Conf. | What it means | What to do |
|---|---|---|
| `checked` | a human has read both equations side by side **once**. Not final: it means the correspondence was plausible to one reader on one day, not that the translation is right | re-check when the module is reworked, and whenever the equation changes |
| `added` | no Vensim original — added deliberately, see the note under the table | keep the note current |
| `high` | the comment names a variable that exists in the 2026 model, **and** its subscripts match the R suffix — e.g. Vensim `wage gis[gender,ind,skill]` against R `R_hrWage_isg`, both `{g,i,s}` | spot-check |
| `medium` | the comment names a variable that exists in 2026, but the subscripts do not corroborate | read both; the name may be right and the shape wrong |
| `low` | the name was found somewhere in the comment rather than leading it, or it only exists in the **2025** model and looks renamed | treat as a lead, not a match |
| `none` | nothing found — the comment quotes no Vensim variable | fill in by hand, or mark `added` |

Two independent signals feed `high`: the **name** (from the comment) and the
**shape** (subscripts against the R suffix). They are derived from different
places, so agreeing is real evidence.

Disagreeing is not proof of an error. Three innocent reasons for a `medium`:

* the R function covers several Vensim variables, so it legitimately has a
  different shape from any one of them;
* the R name ends in a qualifier rather than an index — `..._lag`, `..._lag2` —
  so there is no suffix to compare;
* the indices are the same but written in a different order, which the
  comparison ignores (it sorts them) but which is still worth a look.

---

## POLICY — Policy, shocks, triggers, shifts

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `POL_maxWage` | `R_maxHrWage` |  |  | none |
| `POL_minWage` | `R_minHrWage` |  |  | none |
| `POL_wageCompWTR` | `R_gWageCompWTR_i` |  |  | none |
| `POL_wageIndex` | `R_sensHrWagePrice` |  |  | none |

## DEM — Demography

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `POL_trendEntrySkill` | `R_trendEntrySkill_sg` |  |  | none |
| `birth` | `F_birth_csg` |  |  | none |
| `death` | `F_death_csg` |  |  | none |
| `endCurrentPeriodPop` | `ST_population_csg` |  |  | none |
| `maturationIn` | `incomingPop` |  |  | none |
| `maturationOut` | `F_maturationOut_csg` |  |  | none |
| `skillShiftAllPop` | `PopSkillShift` |  |  | none |
| `skillShiftIncomingPop` | `F_maturationIn_csg` |  |  | none |

## IO — Input-output

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `interIndustryCoeff` | `R_a_ii` | `a ii` | 4458 | high |
| `leontieffMatrix_ii` | `leontieff_ii` |  |  | none |
| `nominalFinalDemandForDomesticGoods_i` | `F_finalDemNom_i` | `c dom nom i`, `gov c dom nom i`, `total exp nom i` | 4799 | high |
| `nominalInterIndustryTradeMatrix_ii` | `Znom_ii` |  |  | none |
| `nominalIntermediateDemand_interindustryAndImport` | `totalZnom_i` | `z demand nom i`, `Z nom ii`, `Z imp nom i` | 9568 | high |
| `nominalTotalOuput_i` | `F_totalOutputNom_i` | `y nom i` | 9345 | high |
| `realFinalDemandForDomesticGoods_i` | `F_finalDemReal_i` | `final demand real i` | 5676 | high |
| `realInterIndustryTradeMatrix_ii` | `Zreal_ii` |  |  | none |
| `realTotalOuput_i` | `F_totalOutputReal_i` | `y real i` | 9356 | high |

## P — Prices

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `SHOCK_setMarkup` | `R_markup_i` | `markup i` | 7308 | high |
| `currentInflation` | `R_inflation` | `inflation`, `inflation i`, `inflation weights i` | 6482 | high |
| `currentInflationByIndustry_i` | `R_inflation_i` |  |  | none |
| `currentInflationWeights_i` | `SH_nomConsNACE_i` | `inflation weights i`, `c nom i` | 4170 | high |
| `setPrices` | `R_p_i` | `p i`, `markup i`, `vat rate`, `UFC delay i`, `p init i`, `p i delay` | 3278 | high |
| `setPricesCapital` | `` | `price capital`, `p i`, `price capital weights i` | 7704 | medium |
| `unitFactorCost` | `R_unitFactorCost_i` |  |  | none |
| `unitFactorCostFossilSubsidiesReduction` | `` | `y nom i` |  | low |
| `unitInputCost` | `R_unitInputCost_i` | `UIC i`, `z demand nom i`, `depreciation K i`, `y real i` | 9093 | high |
| `unitLabCost` | `R_unitLabCost_i` | `ULC i`, `GWB i`, `y real delay i` | 496 | high |

## C — Consumption

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `accumulatedInflationCOICOP_p` | `R_accInfl_p` | `infl cumulative p`, `bridge ip`, `infl cumulative i` | 6476 | high |
| `accumulatedInflationNACE_i` | `R_accInfl_i` | `infl cumulative i`, `p i` | 6470 | high |
| `currentPopIncomeGroups_dsg` | `ST_population_dsg` | `pop d` | 1264 | medium |
| `disposableIncomePerCapita_dsg` | `F_dispIncPerCap_dsg` | ~~`yd d`~~ → `yd d nom`, `yd d test`, `yd delay d` | 969 | low |
| `expectationDisposableIncomePerCapita_dsg` | `F_expDispIncPerCap_dsg` | ~~`exp yd d`~~ → `initial exp yd d` | 931 | low |
| `expectationDisposableIncomePerCapita_dsg_lag` | `F_expDispIncPerCap_dsg` | `yd delay d` | 9373 | medium |
| `expectationDisposableIncomePerCapita_dsg_lag2` | `F_expDispIncPerCap_dsg` | `yd delay2 d` | 9378 | medium |
| `nominalIndividualConsExpenditure_dp` | `F_nomIndC_dp` | `c dp`, `c tot d` | 924 | high |
| `nominalTotalConsumptionDemandCOICOP_p` | `F_Cnom_p` | `c p`, `c dp`, `pop d` | 4827 | high |
| `nominalTotalConsumptionDemandNACE_i` | `F_Cnom_i` | `c nom i`, `c real i`, `p i` | 4821 | low |
| `realTotalConsumptionDemandCOICOP_p` | `F_Creal_p` | `c real p`, `c p` | 4851 | high |
| `realTotalConsumptionDemandNACE_i` | `F_Creal_i` | `c real i`, `bridge ip`, `c real p` | 4833 | high |
| `sharesNominalConsExpenditurePerCapitaInCOICOP_dp` | `SH_nomIndC_dp` | ~~`beta dp`~~ → `basic beta dp` | 911 | low |

## I — Investment

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `POL_shiftRateRealCapitalDepreciation` | `R_KrealDepr_i` |  |  | none |
| `realCapitalDepreciation` | `F_KrealDepr_i` | `depreciation K i` | 5295 | high |
| `realCapitalDepreciation_lag` | `F_KrealDepr_i_lag` | `depreciation K delay i` | 5290 | medium |
| `realCapitalStock` | `ST_Kreal_i` | `K i` | 6996 | high |
| `realCapitalStock_lag2` | `ST_Kreal_i_lag2` | `K delay i` | 6991 | medium |
| `realInvestmentDemand` | `F_GFCFreal_i` | `GFCF real i` | 3220 | high |

## TR — International trade

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `POL_importShareInIntermediateTrade` | `SH_impZ_ii` | `share imp Z ii` | 8680 | high |
| `SHIFT_nominalExport` | `F_Xnom_i` | `g exp i` | 5731 | high |
| `SHIFT_nominalImportIntermediateDemand` | `impZnom_i` | `Z imp nom i`, `p i`, `Z imp real ii` | 9574 | high |
| `realExport` | `F_Xreal_i` | `total exp nom i`, `p i` |  | low |
| `realImportInterMediateDemand` | `impZreal_ii` | `Z imp real ii`, `share imp Z ii`, `Z real ii` | 9582 | high |
| `totalRealImportIntermediateDemand` | `totalImpZ` | `Z imp real ii` |  | low |

## L — Labour

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `POL_annualWorkingHours` | `F_labHr_i` |  |  | none |
| `POL_shift_hourlyWage` | `R_HrWage_isg` |  |  | none |
| `activePop` | `ST_activePop_csg` |  |  | none |
| `availableLabour` | `ST_labS_csg` |  |  | none |
| `desiredLabour_i` | `ST_desLab_i` | ~~`L i`~~ → `check L is`, `L i desired` | 745 | low |
| `desiredLabour_isg` | `ST_desLab_isg` | — *no Vensim original* |  | added |
| `diffRateUnemploymentByGender` | `R_diffGender_u_s` |  |  | none |
| `diffRateUnemploymentBySkill` | `R_diffSkill_u_s` |  |  | none |
| `employedLabour` | `ST_labEmp_isg` |  |  | none |
| `employedLabour_lag` | `ST_labEmp_isg_lag` |  |  | none |
| `employmentRate_g` | `R_e_g` |  |  | none |
| `employmentRate_s` | `R_e_s` |  |  | none |
| `employmentRate_sg` | `R_e_sg` |  |  | none |
| `grossWageBill` | `F_GWB_isg` |  |  | none |
| `inactivePop` | `ST_inactivePop_sg` | `N olf gs` | 7521 | high |
| `incomeExpectation` | `F_expIncome_sg` | `exp inc e gs` | 3406 | high |
| `incomeExpectation_lag` | `F_expIncome_sg_lag` |  |  | none |
| `shift_LabourForceParticipationRate` | `R_LFRP_csg` |  |  | none |
| `shift_MaleLabourShare` | `SH_male_is` |  |  | none |
| `shift_SkillLabourShare` | `SH_skill_is` |  |  | none |
| `unemployedLabour` | `ST_labUnemp_sg` | `L u gs`, `labour supply gs`, `L gs` | 7043 | high |
| `unemploymentRate_s` | `R_u_s` |  |  | none |
| `unemploymentRate_sg` | `R_u_sg` |  |  | none |
| `workingAgePop` | `ST_workAgePop_csg` | `Working age population cgs` | 3390 | medium |

* **`desiredLabour_isg`** — Added while correcting the 2025 model: without it firms could hire as many workers as they wanted even when none were left. See `src/inconsistencies.qmd`, *ST_EmpLab_i — unemployment may be negative*.

## GOV — Government

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `POL_govWageCompWTR` | `F_govWageCompWTR_isg` |  |  | none |
| `POL_incomeTaxRate` | `R_incomeTax` |  |  | none |
| `POL_otherBenefits` | `F_othBenefPerCap` | `init other benefits per cap` | 6548 | high |
| `POL_pensionBenefitsShare_in_wageBill` | `SH_pension_toWage` | `pension wage ratio` | 7631 | high |
| `POL_unempBenefitsShareInWageBill` | `SH_unempBenef_toWage` | `ub wage ratio` | 9042 | high |
| `POL_valueAddedTaxRate` | `R_VAT` | `ub wage ratio` | 9042 | high |
| `grossAnnualIncomePerCapita_employed` | `F_GWBperCap_isg` | `gross annual income e gis` | 755 | high |
| `grossAnnualIncomePerCapita_pension` | `F_GPBperCap_sg` | `gross annual income p gs`, `GPB gs`, `Skills 65+ gs` | 5940 | high |
| `grossAnnualIncomePerCapita_unemployed` | `F_GUBperCap_sg` | `GUB gs`, `L u gs` | 5963 | low |
| `grossPensionBenefits` | `F_GPB_sg` | `GPB gs`, `GWB gs`, `L gs`, `Skills 65+ gs` | 5932 | high |
| `grossUnempBenefits` | `F_GUB_sg` |  |  | none |
| `incomeTaxLevyPerCapita_employed` | `F_incTaxEmpPerCap_isg` |  |  | none |
| `incomeTaxLevyPerCapita_pension` | `F_incTaxPensPerCap_sg` | `inc tax p gs` | 419 | high |
| `incomeTaxLevyPerCapita_unemployed` | `F_incTaxUnempPerCap_sg` | `inc tax u gs` | 353 | high |
| `socialSecurityAnnualContPerCapita_eByEmployer` | `F_socSecPerCap_eEmployer_isg` | `soc sec contr employer gis` | 8784 | high |
| `socialSecurityAnnualContPerCapita_employed` | `F_socSecPerCap_e_isg` | `soc sec contr e gis` | 8778 | high |
| `socialSecurityAnnualContPerCapita_pension` | `F_socSecPerCap_p_sg` | `gross annual income u gs` |  | low |
| `socialSecurityAnnualContPerCapita_unemployed` | `F_socSecPerCap_u_sg` | `gross annual income u gs` |  | low |
| `socialSecurityContRateByEmployee` | `R_socSecEmployee` |  |  | none |
| `socialSecurityContRateByEmployer` | `R_socSecEmployer` |  |  | none |
| `socialSecurityContRateTotal` | `R_socSec` |  |  | none |
| `taxableAnnualIncomePerCapita_employed` | `F_taxIncPerCap_e_isg` | `taxable inc e gis`, `gross annual income e gis` | 8818 | high |
| `taxableAnnualIncomePerCapita_pension` | `F_taxIncPerCap_p_sg` | `taxable inc p gs`, `gross annual income p gs` | 8824 | high |
| `taxableAnnualIncomePerCapita_unemployed` | `F_taxIncPerCap_u_sg` | `taxable inc u gs`, `gross annual income u gs` | 8829 | high |
| `totalIncomeTaxLevy` | `F_incTaxLevy` | `inc tax rev` | 6437 | high |

## TECH — Technology

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `POL_scalingLabourProductivity` | `R_scalingLabProd` |  |  | none |
| `computeAlternativeChangeLabourProductivity` | `R_gLabProdAlt_iv` |  |  | none |
| `computeAlternativeDesiredLabour` | `ST_desLabAlt_isvg` |  |  | none |
| `computeAlternativeGrossWageBill` | `F_GWBAlt_iv` |  |  | none |
| `computeAlternativeLabourProductivity` | `R_labProdAlt_iv` | `lambda T iv` | 586 | medium |
| `currTechDiffusionLabourProd` | `R_labProdDiffusion_i` | `lambda diffusion i` | 7075 | high |
| `labourProductivity_lag2` | `R_labProd_i_lag2` | `lambda delay2 i` | 7070 | medium |
| `techFrontierLabourProd` | `R_techFrontLadProd_i` | `techn frontier lambda i` | 8850 | high |
| `unitFactorCostAlt` | `R_unitFactorCostAlt_iv` | `UFC T iv` | 9072 | high |
| `unitInputCostAlt` | `R_unitInputCostAlt_iv` | `UIC T iv` | 9128 | high |
| `unitLabCostAlt` | `R_unitLabCostAlt_iv` | `ULC T iv` | 9175 | high |

## EN — Energy

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `POL_PhaseOutReductionEnShare` | `R_gEnShare_fromPolicy_in` |  |  | none |
| `POL_Shift_EnSourceShare_in_InterProdEnDemand` | `SH_enSrc_enDemZ_in` | `Share source Ed Z nrg i` | 8696 | high |
| `POL_fossilSubsidiesReduction` | `fossilSubRed_i` |  |  | none |
| `shift_EnSourceShare_FromRenewGrowth_i` | `R_gEnShare_fromRenew_in` |  |  | none |

## CADA — Carbon tax and damage function

| R function | Output | Vensim | Line | Conf. |
|---|---|---|---|---|
| `CarbonCostETS` | `F_carbonCostETS_i` | `CO2 cost ETS i` | 5014 | high |
| `CarbonCostTotal` | `F_carbonCostTotal_i` | `carbon cost tot i` | 4941 | high |
| `CarbonTaxCoverage` | `F_taxableCarbon_i` | `CO2 for CT i`, `CO2 i`, `selection ETS i` | 5029 | high |
| `CarbonTaxLevy` | `F_carbonTaxLevy_i` | `carbon tax i` | 4958 | high |
| `POL_carbonTaxRate` | `R_carbonTax` | `carbon tax rate` | 4968 | high |
| `POL_priceETS` | `priceETS_i` | `p ETS` | 7618 | medium |

---

## Not translated yet

706 of the 792 variables in `vensim_model_2026.txt` are not claimed by any row above. Some are genuinely still to do; some are already covered by a function whose row is `none`. Working through those rows is what shrinks this list.

<details><summary>Show the list</summary>

| Vensim | Line |
|---|---|
| `ACT TECH` | 1428 |
| `Act CT redistrib` | 4601 |
| `Act PNRR` | 4152 |
| `Act adapt` | 4587 |
| `Act carbon tax` | 4594 |
| `Act econ damage` | 1507 |
| `Act elast beta` | 4608 |
| `Act gradual adapt CT hh` | 4615 |
| `Act w eff` | 1550 |
| `C19 cons 2020` | 4868 |
| `CB spend` | 4981 |
| `CO2` | 5007 |
| `CO2 ETS i` | 5019 |
| `CO2 Nace tot` | 5044 |
| `CO2 fd hh nrg` | 5024 |
| `CO2 hh tot` | 5034 |
| `CO2 nrg` | 5049 |
| `CO2 nrg i` | 5054 |
| `CP SW i` | 3448 |
| `CPI` | 5202 |
| `Carbon tax hh d` | 4947 |
| `Carbon tax hh tot` | 4952 |
| `Carbon tax nace` | 4963 |
| `Carbon tax tot` | 4976 |
| `Co GW` | 3297 |
| `Co SW` | 3310 |
| `Cp GW i` | 3423 |
| `Cs GW i` | 3485 |
| `Cs SW i` | 3491 |
| `Div i` | 5343 |
| `Div rate` | 5357 |
| `Dmnl Euro 1` | 4359 |
| `Dmnl Year` | 4414 |
| `Dmnl year 1` | 4419 |
| `E C Z i` | 5426 |
| `E C Ztot` | 5431 |
| `E C hh nrg` | 5408 |
| `E C nrg i` | 5413 |
| `E Zdom ii` | 5447 |
| `E Zimp i` | 5455 |
| `E fd hh imp i` | 5436 |
| `Ecoef Exp i` | 5460 |
| `Ecoef Zimp i` | 5478 |
| `Ecoef fd imp` | 5467 |
| `Ecoeff fd hh i` | 5486 |
| `Ed Z Res i` | 5546 |
| `Ed Z Res tot` | 5551 |
| `Ed Z i` | 5522 |
| `Ed Z nrg` | 5528 |
| `Ed Z nrg i` | 5533 |
| `Ed Z tot i` | 528 |
| `Ed Z tot public i` | 535 |
| `Ed fd hh dom` | 5493 |
| `Ed fd hh dom i` | 5498 |
| `Ed fd hh imp tot` | 5504 |
| `Ed fd hh nrg` | 451 |
| `Ed fd hh tot` | 5509 |
| `Ed to Residual i` | 5514 |
| `Equity i` | 5603 |
| `Equity initial i` | 5608 |
| `Euro 0` | 4399 |
| `Euro constant 1` | 4424 |
| `Euro good 1` | 4344 |
| `FINAL TIME` | 9697 |
| `Full capacity contraint` | 5724 |
| `GDP initial` | 5759 |
| `GDP nom` | 5765 |
| `GDP nom delay` | 5771 |
| `GDP real` | 5776 |
| `GDP real delay` | 5782 |
| `GFCF real i delay` | 5793 |
| `GHG` | 5798 |
| `GHG Nace tot` | 5814 |
| `GHG fd hh` | 5804 |
| `GHG i` | 5809 |
| `GIEC` | 5819 |
| `GIEC ktoe` | 5825 |
| `GINI yd` | 5837 |
| `GPB spend` | 5927 |
| `GUB spend` | 5958 |
| `GW recharge I` | 3688 |
| `GWB` | 4323 |
| `GWB T iv` | 5995 |
| `GWB gis` | 761 |
| `GWB i[ind] :EXCEPT:` | 867 |
| `Goods 0` | 4364 |
| `Hours 1` | 4349 |
| `I desired i` | 6028 |
| `I gov` | 6038 |
| `I imp i` | 6043 |
| `I max i` | 479 |
| `I nom i` | 6048 |
| `I nom tot` | 158 |
| `INITIAL TIME` | 9702 |
| `Id dom nom i` | 6054 |
| `Id matrix ii` | 6060 |
| `Id minus A ii` | 6084 |
| `Id nom i` | 190 |
| `Inactive\_tot` | 740 |
| `Initial coeff BLUE i` | 3642 |
| `Initial mixed income` | 6738 |
| `Inv PNRR gov i` | 185 |
| `Inv conversion vector i` | 6965 |
| `K initial i` | 7004 |
| `K tot` | 7012 |
| `Kton 1` | 4389 |
| `L T gisv` | 7022 |
| `L T isv` | 7027 |
| `L T iv` | 7032 |
| `L gis Delay` | 3862 |
| `L gis initial` | 3867 |
| `L i desired` | 113 |
| `LFPR` | 7104 |
| `LFPR delay gs` | 4202 |
| `LFPR g` | 7110 |
| `LFPR gs` | 855 |
| `LFPR initial gs` | 7116 |
| `LFPR s` | 7124 |
| `Ld constr i` | 99 |
| `Ld gis` | 86 |
| `Ld gis delay` | 81 |
| `Ld i s` | 127 |
| `Ld tot` | 76 |
| `Leontief ii` | 7090 |
| `Loans initial i` | 7137 |
| `Ls shares i` | 133 |
| `Ls tot` | 94 |
| `ME ii` | 7361 |
| `Mixed to labour income ratio` | 7495 |
| `NIC` | 7549 |
| `Naming convention: set Vensim with tools>options>setting>show_underbar and Model>settings>Sketch_use_hard_underbar. Use brief informative names and whenever necessary describe the variable in the comments. use the variable suffix to indicate its subscripts in alphabetical order: a` | 9733 |
| `P` | 1541 |
| `P rand RCP26` | 2442 |
| `P rand RCP60` | 2448 |
| `P rand RCP85` | 2466 |
| `P1` | 3095 |
| `PET` | 1594 |
| `PNNR missions i` | 198 |
| `PNRR spend` | 180 |
| `PT rand RCP45` | 1642 |
| `People 1` | 4374 |
| `People Euro 0` | 4379 |
| `Pop 014 g` | 7647 |
| `Pop 1524 g` | 7653 |
| `Pop 2544 g` | 7659 |
| `Pop 4564 g` | 7665 |
| `Pop 65+ g` | 7671 |
| `Precipitation` | 2627 |
| `Profits` | 7765 |
| `RES shares g rates 1021 i` | 7815 |
| `S Time Policy start` | 7987 |
| `S Time end` | 7981 |
| `S carbon tax max` | 7838 |
| `S corp tax rate` | 7847 |
| `S depreciation rates` | 7852 |
| `S equitiesliabilities` | 7857 |
| `S fintax` | 7862 |
| `S g RES hh` | 7875 |
| `S g RES i` | 7880 |
| `S g exp` | 7870 |
| `S inctax 2` | 7885 |
| `S inctax 3` | 7890 |
| `S inctax 4` | 7895 |
| `S inctax 5` | 7900 |
| `S inctax 6` | 7905 |
| `S mpc` | 7910 |
| `S other benefits` | 7915 |
| `S pension ratio` | 7920 |
| `S scalling A` | 7925 |
| `S scalling lambda` | 7930 |
| `S share imp C` | 7936 |
| `S share imp G` | 7941 |
| `S share imp I` | 7946 |
| `S share imp Z` | 7951 |
| `S sickness benefit` | 7956 |
| `S skill demand trend` | 7961 |
| `S skill supply trend` | 7966 |
| `S ss rate employee` | 7971 |
| `S ss rate employer` | 7976 |
| `S trend Gcons` | 7993 |
| `S ub ratio` | 7998 |
| `S vat rate` | 8003 |
| `S working hours` | 8008 |
| `S1 RES shares g rates 2130 i` | 8102 |
| `S1 depreciation rates i` | 8016 |
| `S1 equity to liabilities ratio` | 8040 |
| `S1 g exp i` | 8047 |
| `S1 hours i` | 8088 |
| `S1 pension wage ratio` | 8095 |
| `S1 share imp GFCF i` | 8125 |
| `S1 share imp Z ii` | 8251 |
| `S1 share imp gov i` | 8167 |
| `S1 share imp hh i` | 8209 |
| `S1 trend entry skill gs` | 8302 |
| `SAVEPER` | 9707 |
| `SD spend` | 8450 |
| `SW runoff R` | 3595 |
| `Skills 1524 gs` | 1361 |
| `Skills 2544 gs` | 1390 |
| `Skills 4564 gs` | 1328 |
| `Switch Off Technology` | 4180 |
| `T i` | 609 |
| `T rand RCP26` | 2526 |
| `T rand RCP45` | 2532 |
| `T rand RCP60` | 2550 |
| `T rand RCP85` | 2568 |
| `TIME STEP` | 9713 |
| `TJ to ktoe` | 8877 |
| `Temperature` | 1660 |
| `Temperature mean:` | 1470 |
| `Temperature p10:` | 1475 |
| `Temperature p90:` | 1480 |
| `Time Act PNRR` | 174 |
| `Time shock` | 4187 |
| `Total exp i nom delay` | 8937 |
| `U tot` | 874 |
| `UCC i` | 812 |
| `UFC i` | 817 |
| `UFC initial i` | 3872 |
| `UIC delay i` | 9077 |
| `UIC delay initial i` | 9082 |
| `UIC delay2 i` | 9088 |
| `UIC initial i` | 9102 |
| `ULC delay i` | 9133 |
| `ULC delay initial i` | 9138 |
| `ULC delay2 i` | 9144 |
| `ULC initial i` | 9149 |
| `VA` | 9185 |
| `VA i` | 1485 |
| `W cap f` | 9210 |
| `W gs f` | 9220 |
| `W tot` | 502 |
| `W tot cap` | 507 |
| `W tot workers` | 512 |
| `WRestitution GW Mm3` | 3124 |
| `WRestitution GW Mm3 i` | 3114 |
| `WRestitution SW Mm3` | 3149 |
| `WRestitution SW Mm3 i` | 3154 |
| `WStress GW perc` | 3208 |
| `WStress SW perc` | 3214 |
| `WStress Tot perc` | 3196 |
| `Wd Extended GW tot Mm3` | 3119 |
| `Wd Extended SW tot Mm3` | 3109 |
| `Wd Extended Tot Mm3` | 3202 |
| `Wdem BLUE GW Mm3 i` | 3791 |
| `Wdem BLUE GW tot` | 3322 |
| `Wdem BLUE Mm3 i` | 3385 |
| `Wdem BLUE Mm3 tot` | 3342 |
| `Wdem BLUE SW Mm3 i` | 3669 |
| `Wdem BLUE SW tot` | 3337 |
| `Wdem GREY GW i` | 3292 |
| `Wdem GREY GW i[ind] :EXCEPT:` | 3290 |
| `Wdem GREY GW tot` | 3353 |
| `Wdem GREY SW i` | 3363 |
| `Wdem GREY SW tot` | 3368 |
| `Wdem GREY i` | 3358 |
| `Wdem GREY tot Mm3` | 3373 |
| `Year 1` | 4528 |
| `Z T demand iv` | 9661 |
| `Z nom initial ii` | 9593 |
| `Z real tot` | 9656 |
| `Zd real i` | 9676 |
| `Zs real i` | 9681 |
| `a T iiv` | 551 |
| `a delay ii` | 4567 |
| `a delay2 ii` | 4429 |
| `a diffusion ii` | 4572 |
| `a i delay` | 7 |
| `a i row` | 32 |
| `a i0` | 56 |
| `a param beta distribution i` | 3837 |
| `a param beta distribution i[ind] :EXCEPT:` | 3835 |
| `adaptation` | 4548 |
| `adaptation sensitivity` | 4623 |
| `adaptation spend` | 4533 |
| `adult population gs` | 4632 |
| `adult population s` | 4638 |
| `alpha AGR` | 3528 |
| `av daily work hours gs` | 1252 |
| `av infl cum d delay` | 4160 |
| `av infl cumulative d` | 879 |
| `average propensity to consume` | 4650 |
| `b cap` | 4662 |
| `b gs` | 4674 |
| `b param beta distribution i` | 3800 |
| `b param beta distribution i[ind] :EXCEPT:` | 3797 |
| `b0 cap` | 342 |
| `b0 s` | 332 |
| `base VAT rate` | 1491 |
| `basic beta dp` | 911 |
| `bbb` | 4681 |
| `benefit per child` | 4686 |
| `beta initial dp` | 4749 |
| `births g` | 4754 |
| `c dom nom` | 4794 |
| `c dom real i` | 4805 |
| `c imp nom i` | 4810 |
| `c imp real i` | 4816 |
| `c inc d` | 936 |
| `c real i delay` | 4846 |
| `c total nom` | 4857 |
| `c total real` | 4862 |
| `c19 LFPR 2020` | 4217 |
| `c19 LFPR 2021` | 4228 |
| `c19 LFPR 2022` | 4235 |
| `c19 cons 2021` | 4874 |
| `c19 exp 2020` | 4880 |
| `c19 exp 2021` | 4886 |
| `c19 imp 2020` | 4892 |
| `c19 imp 2021` | 4898 |
| `c19 inv 2020` | 4904 |
| `c19 inv 2021` | 4910 |
| `c19 shock cons` | 4916 |
| `c19 shock exp` | 4409 |
| `c19 shock imp` | 4922 |
| `c19 shock inv` | 4927 |
| `cap prod i` | 4933 |
| `cases T i` | 665 |
| `change coeff BLUE GW agr` | 3572 |
| `change coeff BLUE SW agr` | 3584 |
| `check IO1` | 2 |
| `check L is` | 745 |
| `check L tot` | 750 |
| `check PET` | 3618 |
| `check inactive` | 348 |
| `check\_share\_sources i` | 5002 |
| `child benef gs` | 4986 |
| `climate damage A` | 1462 |
| `coef CO2 to GHG fd hh` | 5068 |
| `coef CO2 to GHG i` | 5074 |
| `coef Ed to C fd hh nrg` | 5081 |
| `coef Ed to C nrg i` | 5088 |
| `coef NIC to GIEC` | 5102 |
| `coeff BLUE i` | 1536 |
| `coeff Co` | 3378 |
| `coeff E C to CO2 hh nrg` | 5109 |
| `coeff E C to CO2 nrg i` | 5119 |
| `coeff GREEN agr` | 3764 |
| `coeff P` | 3722 |
| `coeff T` | 3104 |
| `coeff adj BLUE GW i` | 1589 |
| `coeff adj BLUE GW i[ind] :EXCEPT:` | 1587 |
| `coeff adj BLUE SW i` | 1562 |
| `coeff adj BLUE SW i[ind] :EXCEPT:` | 1560 |
| `coeff adj GREEN agr` | 3675 |
| `coeff conv mm to Mm3` | 3728 |
| `coeff intens BLUE GW i` | 3786 |
| `coeff intens BLUE GW i[ind] :EXCEPT:` | 3784 |
| `coeff intens BLUE SW i` | 3779 |
| `coeff intens BLUE SW i[ind] :EXCEPT:` | 3777 |
| `coeff irrigation eff` | 3716 |
| `coefficient of Dilution GW i` | 3497 |
| `coefficient of Dilution SW i` | 3129 |
| `cohort years c` | 5144 |
| `const Co GW` | 3347 |
| `const PET` | 3682 |
| `convergence` | 5179 |
| `conversion` | 4501 |
| `corp tax i` | 5185 |
| `corp tax rate` | 5191 |
| `corp tax rev` | 5197 |
| `d Aii T` | 540 |
| `d cap` | 5208 |
| `d gs` | 5215 |
| `d lambda T i` | 562 |
| `d0 cap` | 5222 |
| `d0 s` | 5228 |
| `damage` | 4559 |
| `damage beta distribution i` | 3820 |
| `damage beta distribution i[ind] :EXCEPT:` | 3817 |
| `damage multiplier delay i` | 5238 |
| `damage multiplier i` | 3829 |
| `damage multiplier i[ind] :EXCEPT:` | 3827 |
| `deaths 1524 gs` | 1385 |
| `deaths 2544 gs` | 1351 |
| `deaths 4564 gs` | 1356 |
| `deaths 65+ gs` | 1418 |
| `deaths014 g` | 5243 |
| `deaths1524 g` | 5248 |
| `deaths2544 g` | 5253 |
| `deaths4564 g` | 5258 |
| `deaths65+ g` | 5263 |
| `debt gdp` | 5268 |
| `debt i` | 5273 |
| `debt repayment i` | 5279 |
| `def gdp` | 5284 |
| `delta a T2 ii` | 711 |
| `delta a T3 ii` | 684 |
| `delta a T4 ii` | 597 |
| `delta damage multiplier i` | 1512 |
| `delta e inc gs` | 729 |
| `delta lambda T2 i` | 642 |
| `delta lambda T3 i` | 654 |
| `delta lambda T4 i` | 631 |
| `depreciation rates i` | 5300 |
| `dg A i` | 12 |
| `draw T2 i` | 5383 |
| `draw T3 i` | 5389 |
| `draw T4 i` | 5395 |
| `duration adapt` | 5401 |
| `duration skill transition` | 4496 |
| `e` | 792 |
| `e g` | 798 |
| `e gs` | 778 |
| `e s` | 5441 |
| `eco flow R` | 3607 |
| `elast p exp` | 5556 |
| `en eff size` | 5562 |
| `eq cap` | 5568 |
| `eq gs` | 5575 |
| `eq0 cap` | 5582 |
| `eq0 s` | 5588 |
| `equity delay i` | 5598 |
| `equity to liabilities ratio` | 5614 |
| `error I` | 3771 |
| `error PET` | 3623 |
| `error R` | 3630 |
| `euro 1` | 4384 |
| `euro goods 1` | 4394 |
| `exog g gov c` | 1440 |
| `exp damage i` | 3852 |
| `exp damage i[ind] :EXCEPT:` | 3849 |
| `exp damage normalized i` | 3809 |
| `exp damage normalized i[ind] :EXCEPT:` | 3807 |
| `exp inc e delay gs` | 5626 |
| `exp inc e gs[gender,skill] :EXCEPT:` | 3403 |
| `exp inc e initial gs` | 5631 |
| `exp initial i` | 5636 |
| `expectetion y real` | 138 |
| `feasible GW Mm3` | 3159 |
| `feasible SW Mm3` | 3175 |
| `feasible Water Supply Mm3` | 3191 |
| `fertility rate` | 5644 |
| `fin tax cap` | 5650 |
| `fin tax gs` | 5656 |
| `fin tax rev` | 5662 |
| `final demand nom i` | 5670 |
| `financial income tax rate` | 5682 |
| `g A i` | 61 |
| `g GDP nom` | 5743 |
| `g GDP real` | 5748 |
| `g GDP real delay` | 108 |
| `g L gis` | 3843 |
| `g exp` | 50 |
| `g exp inc e gs` | 734 |
| `g lamba i` | 5754 |
| `g relative UC i` | 962 |
| `g y nom i` | 168 |
| `goods 1` | 4369 |
| `goods euro constant 1e6` | 4404 |
| `gov I frac` | 5906 |
| `gov c imp nom i` | 5895 |
| `gov c nom delay i` | 4261 |
| `gov c nom i` | 4245 |
| `gov def` | 5900 |
| `gov interest` | 5914 |
| `gov wages frac` | 5920 |
| `gross fin inc cap` | 5952 |
| `gross fin inc gs` | 517 |
| `h eff` | 6001 |
| `hours i` | 6007 |
| `hours mean` | 152 |
| `i i` | 472 |
| `in Equity i` | 6119 |
| `in I desired i` | 6124 |
| `in K i` | 6129 |
| `in LFPR gs` | 4296 |
| `in Loans i` | 6134 |
| `in adapation` | 4506 |
| `in bonds cap` | 6090 |
| `in bonds gs` | 6096 |
| `in deposits cap` | 6107 |
| `in deposits gs` | 4197 |
| `in equity cap` | 6112 |
| `in equity gs` | 4207 |
| `in male share is` | 6143 |
| `in share RES i` | 24 |
| `in share RES i[nrg,ind] :EXCEPT:` | 17 |
| `in share sources` | 6155 |
| `in skill trend is` | 6378 |
| `in skills 1425 gs` | 4434 |
| `in skills 2544 gs` | 4511 |
| `in skills 4564 gs` | 6384 |
| `in skills 65+ gs` | 6396 |
| `in wage gis` | 830 |
| `inc tax e gis` | 395 |
| `income tax rates t` | 385 |
| `inflation delay` | 6487 |
| `inflation rate inccat` | 4165 |
| `inflation target` | 6497 |
| `init distr skill cgs` | 6508 |
| `init gov c nom i` | 6527 |
| `init gov debt` | 6503 |
| `init i` | 6535 |
| `init inflation` | 6542 |
| `init lab prod` | 122 |
| `init pop cg` | 6562 |
| `init sd per cap` | 6570 |
| `init time use dt` | 6582 |
| `initial CT` | 6680 |
| `initial GFCF i` | 6696 |
| `initial GFCF real i` | 6706 |
| `initial GWB` | 6711 |
| `initial T i` | 6878 |
| `initial UFC T iv` | 6922 |
| `initial a delay ii` | 6613 |
| `initial a ii` | 6618 |
| `initial adaptation` | 4523 |
| `initial damage multiplier i` | 6686 |
| `initial depreciation K i` | 6691 |
| `initial exp yd d` | 931 |
| `initial interest rate` | 6716 |
| `initial lambda delay i` | 6722 |
| `initial lambda i` | 6727 |
| `initial post tax profits i` | 6744 |
| `initial prob T2 i` | 6830 |
| `initial prob T3 i` | 6837 |
| `initial share source Ed Z nrg i` | 6850 |
| `initial share source Ed fd hh nrg` | 6843 |
| `initial techn frontier a ii` | 6883 |
| `initial techn frontier lambda i` | 6888 |
| `initial uc` | 6893 |
| `initial unit int dem i` | 6927 |
| `initial wealth distribution per skill s` | 6950 |
| `initial wealth per adult` | 6955 |
| `initial welath distribution capitalists` | 6960 |
| `interest` | 6018 |
| `invert check` | 6975 |
| `investment rate i` | 6980 |
| `k1 GW i` | 3534 |
| `k1 SW i` | 3540 |
| `k2 GW i` | 3473 |
| `k2 SW i` | 3479 |
| `kton tj 1` | 4354 |
| `lab prod` | 147 |
| `labour share` | 7049 |
| `lambda delay i` | 7065 |
| `lambda i` | 573 |
| `lev delay i` | 462 |
| `lev i` | 7098 |
| `lev initial i` | 467 |
| `lifetime K i` | 7130 |
| `male share delay is` | 7195 |
| `male share initial is` | 7200 |
| `male share is` | 7224 |
| `male share trend is` | 7231 |
| `markup calibration parm i` | 7257 |
| `markup delay i` | 7302 |
| `markup initial i` | 7321 |
| `maturation014 g` | 7331 |
| `maturation1524 g` | 7336 |
| `maturation2544 g` | 7341 |
| `maturation4564 g` | 7346 |
| `max R` | 3635 |
| `max delta a ii` | 7351 |
| `max delta lambda i` | 7356 |
| `mean I` | 3693 |
| `mean P` | 3699 |
| `mean PET` | 3705 |
| `mean R` | 3710 |
| `mean delta a ii` | 7407 |
| `mean delta lambda i` | 7466 |
| `min delta a ii` | 7474 |
| `min delta lambda i` | 7479 |
| `mixed income per capita d` | 7484 |
| `mixed income total` | 7489 |
| `mortality rate cg` | 7504 |
| `mpc inc d` | 916 |
| `net fin inc cap` | 7530 |
| `net fin inc gs` | 7536 |
| `net labour income pc gis` | 7542 |
| `no action` | 4543 |
| `omega employment` | 7572 |
| `omega lambda` | 7579 |
| `omega price` | 862 |
| `other benefits per cap` | 7598 |
| `other benefits spend` | 7590 |
| `out Loans i` | 7607 |
| `output to GDP ratio` | 7613 |
| `pop cap` | 1258 |
| `pop share d` | 7677 |
| `pop share ordered gini` | 7682 |
| `population g` | 7687 |
| `population total` | 1423 |
| `post tax profits delay i` | 7693 |
| `post tax profits i` | 7698 |
| `price capital delay` | 7710 |
| `price weights i` | 7724 |
| `prob T2 i` | 7729 |
| `prob T3 i` | 7744 |
| `prob T4 i` | 7759 |
| `profits i` | 823 |
| `profits post debt delay i` | 456 |
| `profits residual` | 7770 |
| `pseudo rGW` | 3504 |
| `pseudo rSW` | 3546 |
| `rGW i` | 3138 |
| `rGW i[ind] :EXCEPT:` | 3136 |
| `rSW i` | 3144 |
| `range I` | 3601 |
| `ratio GW i` | 3613 |
| `ratio I` | 3268 |
| `ratio R` | 3273 |
| `ratio SW i` | 3738 |
| `ratio from Ed to E C i` | 7785 |
| `reproductive life` | 7809 |
| `savings cap` | 8310 |
| `savings gs` | 8316 |
| `scalling lambda` | 8350 |
| `scalling tech` | 8371 |
| `sd delta a ii` | 8381 |
| `sd delta lambda i` | 8442 |
| `seed` | 8465 |
| `sens JG` | 4291 |
| `sens LFPR income` | 8576 |
| `sens exp init` | 163 |
| `sens i` | 8495 |
| `sens i i` | 8503 |
| `sens inv i` | 8531 |
| `sens male share unemp s` | 8585 |
| `sens mkup` | 1446 |
| `sens mkup delay` | 1451 |
| `sens prob` | 8594 |
| `sens scalling lambda` | 1456 |
| `sens skill cs` | 8600 |
| `sens uw g` | 8610 |
| `share c d` | 8617 |
| `share emissions relevant energy i` | 8622 |
| `share emissions relevant energy nrg` | 8627 |
| `share imp GFCF i` | 8632 |
| `share imp gov i` | 8648 |
| `share imp hh i` | 8664 |
| `sick disab per cap` | 8456 |
| `skill distribution initial is` | 8715 |
| `skill distribution trend is` | 8739 |
| `skill trend delay is` | 8764 |
| `skill trend is` | 8770 |
| `soc sec rev` | 8790 |
| `ss rate employee` | 8801 |
| `ss rate employer` | 8807 |
| `stock of bonds` | 4655 |
| `stock of bonds delay` | 4669 |
| `tax floors f` | 414 |
| `techn frontier a ii` | 8839 |
| `temp RCP scenario` | 1497 |
| `test adult` | 1317 |
| `test work pop` | 1413 |
| `time adaptation` | 8861 |
| `tot Div` | 4192 |
| `tot final demand nom` | 8922 |
| `tot gov rev` | 951 |
| `tot gov spend` | 321 |
| `tot y real` | 8927 |
| `total beta issue` | 8932 |
| `total exp nom` | 8942 |
| `total gov c nom` | 8947 |
| `total imp nom` | 8953 |
| `total imp nom i` | 8958 |
| `total trade balance nom` | 8967 |
| `track tech choice` | 8977 |
| `trade balance nom i` | 8988 |
| `transfers spend` | 942 |
| `trend entry skill gs` | 9005 |
| `trend gov c i` | 8993 |
| `u` | 785 |
| `u g` | 804 |
| `u gs` | 845 |
| `u initial gs` | 9021 |
| `u s` | 9029 |
| `ub coverage ratio` | 9035 |
| `uc delay i` | 4554 |
| `uc i` | 9053 |
| `uc normal` | 9059 |
| `unit intermedite demand i` | 9180 |
| `vat i` | 9190 |
| `vat rev` | 9204 |
| `w eff` | 1577 |
| `w0` | 9230 |
| `w0 s` | 9236 |
| `w0\_cap` | 9242 |
| `wage delay gis` | 773 |
| `wage gis` | 4337 |
| `wage gs` | 9248 |
| `wages gov` | 4328 |
| `wages initial gis` | 9255 |
| `weekly hours` | 9300 |
| `working age pop g` | 9306 |
| `working age pop total` | 1323 |
| `working age pop total tot` | 9311 |
| `working age population gs` | 9316 |
| `working weeks per year` | 9321 |
| `y initial i` | 9327 |
| `y nom delay i` | 9339 |
| `y real FC i` | 37 |
| `y real unconstrained i` | 9367 |
| `yd d nom` | 969 |
| `yd d test` | 1111 |
| `yd initial d` | 9383 |
| `yd order` | 9388 |
| `yd share` | 9393 |
| `yd share cumulative gini` | 9398 |
| `yd share ordered gini` | 9551 |
| `yd tot` | 9556 |
| `yearly exp adapt` | 9561 |
| `z T nom iiv` | 9666 |
| `z T real iiv` | 9671 |

</details>

---

## Counters

Keep these in step with the tables above when you edit a row.

| | |
|---|---|
| R functions | 126 |
| `checked` | 0 |
| `added` | 1 |
| `high` | 54 |
| `medium` | 10 |
| `low` | 11 |
| `none` | 50 |
| Vensim variables not claimed | 706 / 792 |
