# ==============================================================================
# INVARIANTS
# ==============================================================================
#
# Things that must be true at the end of every period, whatever the scenario.
# They are the standing substitute for a reference run: there is no output from
# Vensim to compare against, and the snapshot only covers the periods that have
# been run, so what keeps the model honest is a set of statements that cannot be
# false in a correct model.
#
# Most of them are not ours. The authors of the Vensim model left `check ...`
# and `test ...` variables in it — ratios that should be 1, differences that
# should be 0. They test the economics rather than the code, which is exactly
# what is wanted here.
#
# Registering one:
#
#   invariant("a short name",
#             function() sum(a) / sum(b),      # what is measured
#             expect = 1,                      # what it must equal
#             source = "check L tot",          # the Vensim variable, if any
#             note   = "why this must hold")
#
# A check whose inputs do not exist yet is **skipped, not failed**: most of the
# model is still commented out of the main loop, and an invariant on a variable
# that is not computed yet says nothing. Skipped checks are counted and named,
# so that they cannot quietly stay skipped forever. Any other error is a
# failure — a check that breaks for its own reasons is a broken check.
# ------------------------------------------------------------------------------

.invariants <- new.env(parent = emptyenv())
.invariants$reg <- list()

invariant <- function(name, check, expect = 0, tol = NULL, source = "", note = "") {
  .invariants$reg[[name]] <- list(check = check, expect = expect, tol = tol,
                                  source = source, note = note)
  invisible(name)
}

## Evaluate every invariant. Reports all failures at once rather than stopping
## at the first: when something is wrong you want the whole picture.
check_invariants <- function(period = NULL, strict = TRUE, verbose = FALSE) {

  if (is.null(period)) period <- get0("t", envir = .GlobalEnv)
  tol_default <- get0("tolerance", envir = .GlobalEnv, ifnotfound = 1e-6)

  passed <- failed <- skipped <- character()
  detail <- list()

  for (nm in names(.invariants$reg)) {
    inv <- .invariants$reg[[nm]]
    got <- tryCatch(inv$check(),
                    error = function(e) structure(NA, missing_input = e$message))

    # an input that does not exist yet: the check has nothing to say
    if (!is.null(attr(got, "missing_input"))) {
      if (grepl("not found|introuvable|objet", attr(got, "missing_input"))) {
        skipped <- c(skipped, nm); next
      }
      failed <- c(failed, nm)
      detail[[nm]] <- paste("the check itself failed:", attr(got, "missing_input"))
      next
    }

    ok <- if (is.logical(inv$expect)) {
      isTRUE(got) == isTRUE(inv$expect)
    } else {
      all(abs(got - inv$expect) < (inv$tol %||% tol_default))
    }

    if (isTRUE(ok)) {
      passed <- c(passed, nm)
      if (verbose) detail[[nm]] <- paste("=", format(got, digits = 10))
    } else {
      failed <- c(failed, nm)
      detail[[nm]] <- paste0("expected ", format(inv$expect),
                             ", got ", format(got, digits = 10),
                             if (nzchar(inv$source)) paste0("  [Vensim: ", inv$source, "]"),
                             if (nzchar(inv$note)) paste0("\n      ", inv$note))
    }
  }

  log_info("Invariants at ", period, ": ", length(passed), " held, ",
           length(failed), " failed, ", length(skipped), " skipped")
  if (length(skipped)) log_info("  skipped (inputs not computed yet): ",
                                paste(skipped, collapse = ", "))
  for (nm in failed) log_error("  ", nm, ": ", detail[[nm]])

  if (length(failed)) {
    msg <- paste0("Invariants violated at period ", period, ":\n",
                  paste0("  - ", failed, ": ", unlist(detail[failed]), collapse = "\n"))
    if (strict) stop(msg) else warning(msg)
  } else {
    message("Invariants at ", period, ": ", length(passed), " held, ",
            length(skipped), " skipped.")
  }

  invisible(list(passed = passed, failed = failed, skipped = skipped, detail = detail))
}

# ------------------------------------------------------------------------------
# The register
# ------------------------------------------------------------------------------
# Accounting identities. These are the model's own definitions: if one of them
# fails, people have been created or lost somewhere.

invariant("active population = employed + unemployed",
  function() sum(ST_activePop_csg) - (sum(ST_labEmp_isg) + sum(ST_labUnemp_sg)),
  expect = 0, tol = 1e-4,
  note = "Nobody of working age is both, and nobody is neither.")

invariant("working age = active + inactive",
  function() sum(ST_workAgePop_csg) - (sum(ST_activePop_csg) + sum(ST_inactivePop_sg)),
  expect = 0, tol = 1e-4)

# Vensim's `test adult` compares three variables computed by three different
# equations. Slicing one array the same two ways instead would be a tautology:
# total - children - everything-but-children is zero whatever the array holds.
# The comparison has to be between quantities that were arrived at separately.
# Here that is `ST_workAgePop_csg`, which workingAgePop() derives by masking,
# against a decomposition of the population it was derived from.
invariant("population = working age + children + capitalists + retired",
  function() {
    sum(Pop_lvl) - (sum(ST_workAgePop_csg) +
                    sum(Pop_lvl[, "child", ]) +
                    sum(Pop_lvl[, "cap", ]) +
                    sum(Pop_lvl["65+", , ]) -
                    sum(Pop_lvl["65+", "cap", ]))     # retired capitalists, counted twice
  },
  expect = 0, tol = 1e-4, source = "test adult",
  note = paste("Working-age population is computed by masking, not by slicing,",
               "so a wrong mask shows up here."))

invariant("desired labour adds up over gender and group",
  function() sum(ST_desLab_isg) / sum(ST_desLab_i),
  expect = 1, source = "check L tot",
  note = "Splitting desired labour by gender and population group must not change the total.")

# Shares are shares.

invariant("skill shares sum to 1 by industry",
  function() max(abs(rowSums(SH_skill_is) - 1)),
  expect = 0,
  note = paste("The exogenous trends sum to zero by industry so that an additive",
               "flow conserves this. Writing the flow as a factor on the stock",
               "broke it - see inconsistencies_new.md."))

invariant("male shares lie in [0, 1]",
  function() all(SH_male_is >= 0 & SH_male_is <= 1), expect = TRUE)

invariant("energy source shares sum to 1 by industry",
  function() max(abs(rowSums(SH_enSrc_enDemZ_in) - 1)), expect = 0)

# Structural zeros. `child` and `cap` are population groups, not qualifications:
# they must never carry employment or working-age population. This is the class
# of error that hand-written exclusions used to produce - see README 5.3.

invariant("no employment in child or cap",
  function() sum(ST_labEmp_isg[, non_skill, ]), expect = 0, tol = 1e-9)

invariant("no working-age population in child or cap",
  function() sum(ST_workAgePop_csg[, non_skill, ]), expect = 0, tol = 1e-9)

invariant("no working-age population under 15 or over 64",
  function() sum(ST_workAgePop_csg[c("0-14", "65+"), , ]), expect = 0, tol = 1e-9)

# Signs. Nothing here can be negative without something having gone wrong.

invariant("population is non-negative",
  function() all(ST_population_csg >= 0), expect = TRUE)

invariant("unemployment is non-negative",
  function() all(ST_labUnemp_sg >= 0), expect = TRUE,
  note = paste("Employers can otherwise hire more workers than exist -",
               "see inconsistencies.qmd, ST_EmpLab_i."))

invariant("employment is non-negative",
  function() all(ST_labEmp_isg >= 0), expect = TRUE)

# States. Whatever else changes, a state must stay finite.

invariant("every state is finite",
  function() {
    st <- stats::na.omit(model_states$r)
    st <- st[vapply(st, exists, logical(1), envir = .GlobalEnv)]
    all(vapply(st, function(v) all(is.finite(get(v, envir = .GlobalEnv))), logical(1)))
  }, expect = TRUE)

log_block("Invariants registered")
log_objects(names(.invariants$reg), "Checks")
message("Invariants registered (", length(.invariants$reg), ")")
