# Inconsistencies — second pass

Problems found while refactoring the engine and retranslating against
`vensim_model_2026.txt`.

`src/inconsistencies.qmd` holds the first pass, against the 2025 model. This
file continues it. Keep them separate: the first pass has to be replayed against
the 2026 model in its own right, since some of what it found may have been
fixed upstream, some not, and some of the 2026 simplifications may rest on the
buggy behaviour.

## Template

```
## <variable or function> — <one line>

**Status:** open | fixed | moot
**Where:** file:line
**Found:** how it turned up

### Problem
### Solution        (or: Leads, when it is yours to decide)
```

`moot` means the code involved does not survive the 2026 model, so the bug is
recorded rather than fixed.

---

## `intensityChangeMean` — a single bad cell wipes the whole array

**Status:** fixed. The branch is dead today — `Act_minHourW` is not even in the
policy panel, so `&&` short-circuits before `gp()` is called — and the policy is
gone from the 2026 model. Fixed anyway: it is one word, and the fix is not in
doubt.
**Where:** `src/B-modules/L.r`, in `POL_shift_hourlyWage()`, both the `Act_minHourW`
and the `Act_maxHourW` branch.
**Found:** surveying positional array indexing before rewriting the modules with
named indices.

### Problem

Inside a triple loop over gender, population group and industry:

```r
for (i in industry) {
  gap_value <- gap_minToMeanWage_isg[i, s, g]
  if (is.na(gap_value) || is.infinite(gap_value)) {
    intensityChangeMean[industry, pop_group, gender] <- 0   # <- the whole array
    next
  }
  ...
  intensityChangeMean[i, s, g] <- change_value                # <- one cell
}
```

The guard assigns to `[industry, pop_group, gender]` — the full index vectors,
so **every cell of the array**, not the cell `[i, s, g]` the loop is on. One
industry with a missing or infinite wage gap therefore erases every value
computed before it.

The intent is clear from the line two branches up, which does it correctly for a
whole slice (`intensityChangeMean[, s, g] <- 0`), and from the assignment at the
bottom of the loop.

A wage gap is `diff / (coeffWageDispersion_isg * R_hrWage_isg_lvl)`, so it is
`NaN` or `Inf` wherever the wage or the dispersion coefficient is zero — which
is exactly the `child` and `cap` slices, and any industry with no wage data.
Those are not rare cases.

### Solution

```r
intensityChangeMean[i, s, g] <- 0
```

### Why Vensim has no equivalent

**Vensim's `skill` dimension holds only `low, mid, hig`.** There is no `child`
and no `cap`. `average wage changes gis` is therefore computed over 2 x 19 x 3
cells, every one of which has a real wage and a real dispersion coefficient:

```
average wage changes gis[gender,ind,skill] =
    difference wage min wage gis[gender,ind,skill]
  / (Coefficient wage dispersion[gender,ind,skill] * wage delay gis[gender,ind,skill])
```

The `NaN` case cannot arise there. It exists in R only because `PopGroup` was
widened to five modalities, two of which have a zero wage — so the guard is an
artefact of the R representation, not a translation of anything. That is also
why zeroing one cell is the right behaviour: the Vensim semantics simply have
nothing to say about those cells.

---

## `R_gLabProdAlt_iv` — `max()` where `pmax()` was meant, collapsing 19 industries into 1

**Status:** fixed, on the reading of the Vensim source. See the decision below.
**Where:** `src/B-modules/TECH.r`, `computeAlternativeChangeLabourProductivity()`.
**Found:** reading the function while replacing its positional Technology indices.

### Problem

```r
mean <- gp("R_gLabProdMean_i")        # a vector, one value per industry
sd   <- gp("R_gLabProdSd_i")          # idem

R_gLabProdAlt_iv[, "T2"] <- R_scalingLabProd *
  rtruncnorm(n = 1, a = min + sd, b = max + sd,
             mean = max(0, mean) + sd,       # <- max(), not pmax()
             sd = sd)
```

`a`, `b` and `sd` stay per-industry. `mean` does not: `max(0, mean)` returns a
**single number**, the largest mean across all industries — 0.0833. So every
industry's draw is centred on the best industry's mean instead of its own.

This is the `min`/`max` versus `pmin`/`pmax` trap that the project's own
documentation warns about: *"Use min() if applied to a scalar. Use pmin() if
applied to an array (no matter which dimensions), else it will just return the
minimal element of your array."*

It is not a small bias. The truncation bounds are `mean_i ± 3·sd_i`, so an
industry whose upper bound sits below 0.0833 has its **entire** distribution
above its own ceiling, and every draw is clamped there:

| | |
|---|---|
| industries whose upper bound is below the shared centre | **12 of 19** |
| per-industry means, actual range | -0.0173 to 0.0833 |
| centre used for all of them | 0.0833 |

The worst cases are the service sectors, which are exactly the ones the model
gives low or negative productivity growth: `ict` (-0.0173), `profserv`
(-0.0093), `otherserv`, `public`, `health`, `education`, `construction`,
`hospitality`. Their labour productivity growth is drawn as if they were the
economy's most dynamic sector.

The same line appears three times, for `T2`, `T3` and `T4`.

### What Vensim does — and the two models disagree

**2026** — every argument `[ind]`-subscripted, and no floor:

```
delta lambda T2 i[ind] = scalling lambda *
  RANDOM NORMAL(
    min delta lambda i[ind] + sd delta lambda i[ind],
    max delta lambda i[ind] + sd delta lambda i[ind],
    mean delta lambda i[ind] + sd delta lambda i[ind],
    sd delta lambda i[ind], seed )
```

**2025** — the same, except the mean *is* floored:

```
    max(0, mean delta lambda i[ind]) + sd delta lambda i[ind],
```

So the floor was **faithfully translated from the 2025 model**, not invented by
the R version. It is the colleague who removed it in 2026. The R translation was
right about the floor and wrong about how to express it.

The collapse, on the other hand, is a genuine translation bug, and a subtle one:
**Vensim's `max()` inside a `[ind]`-subscripted equation is elementwise**, while
R's `max()` is a reduction. The same three characters mean different things in
the two languages. `pmax` is R's elementwise `max`.

### Decision

The collapse is fixed. The floor is kept and marked, because the module is a
translation of 2025 and this is where 2025 and 2026 differ:

```r
# TODO(2026): the 2025 model floors the mean at zero, the 2026 model does not.
mean <- pmax(gp("R_gLabProdMean_i"), 0)     # per industry, all of them
rtruncnorm(n = 1, a = min + sd, b = max + sd, mean = mean + sd, sd = sd)
```

The `TODO(2026)` marker is the convention for a line where the 2025 and 2026
models differ and the module still follows 2025. It marks a decision to take,
not one already taken: sometimes 2026 is the improvement and sometimes it is an
undocumented change worth querying. `grep -rn "TODO(2026)" src/` finds them all.

* **The collapse was a translation bug.** Vensim's `max()` is elementwise here;
  R's is a reduction. `pmax` is the R equivalent. Both the R suffix `_i` and the
  Vensim `[ind]` say per-industry, and no reading makes one industry's mean
  drive the other eighteen.
* **The floor stays, and 2026 does not settle it.** It is in the 2025 source
  and was translated correctly in intent, so it is not a mistake. The 2026 model
  dropped it — but that removal is **undocumented**, and the technology module is
  known to be giving the 2026 translator trouble, so it may be a considered
  choice or it may be collateral. It is kept as
  `pmax(gp("R_gLabProdMean_i"), 0)` and marked `TODO(2026)`: a question to put to
  the 2026 translator, not a change to apply.

  The economics point the same way: an alternative technology that *lowers*
  productivity is a legitimate draw — it simply will not be the one selected.
  Flooring it at zero does not prevent a bad alternative from being modelled,
  it prevents it from being recognised as bad.

### Measured effect

| | `max()`, as found | `pmax()`, kept | `pmax()` dropped (2026) |
|---|---|---|---|
| correlation between the drawn growth and each industry's own mean | 0.199 | **0.749** | 0.791 |
| economy-wide mean of the draw | 0.0493 | 0.0227 | 0.0215 |

Almost all of the gain comes from fixing the collapse, not from the floor: only
four industries have a negative mean, so flooring changes little. Which is why
keeping the floor until the 2026 retranslation costs nothing.

The correlation is the telling one: before the fix, the draw barely tracked the
parameter that is supposed to drive it.

Only one variable in `d` moves — `R_gLabProdAlt_iv` — because everything
downstream of it is still commented out of the main loop. The blast radius will
grow when those functions are switched on, which is a reason to have fixed it
now rather than later.

---

## `lag2` on a state — a lag of something that is already its own lag

**Status:** the period bug is fixed in both functions. Whether
`realCapitalStock_lag2()` should exist at all is yours to decide.
**Where:** `src/B-modules/I.r`, `realCapitalStock_lag2()`;
`src/B-modules/TECH.r`, `labourProductivity_lag2()`.
**Found:** you raised it — the suspicion that the original modellers took a lag
*of a state variable*, getting a two-period lag where they wanted one.

### The distinction that settles it

A **state** carries its own past: `gd(X, t - dt)` *is* its lag, and a separate
`X delay` variable is redundant. An **auxiliary** does not: it is recomputed
from scratch each period, so a lag of it has to be stored explicitly.

| | state? | `delay2` used in Vensim? |
|---|---|---|
| `K i` | **yes**, `INTEG` | **no** |
| `lambda i` | no, an auxiliary | **yes** |

`src/inconsistencies.qmd` already records the same pattern for wages — *"wage
delay gis is inconsistent: wage_gis is already a level, hence a lagged
variable"* — and removed `wage delay gis` on those grounds. Line 546 of that
file flags it as *"likely the case also for the computation of lambda
diffusion"*. It is not: lambda is the case where the delay is legitimate.

### Capital: the delay chain is dead

In Vensim 2025:

```
K delay i[ind]  = DELAY FIXED( K i[ind],       Year 1, K initial i[ind] )
K delay2 i[ind] = DELAY FIXED( K delay i[ind], Year 1, initial K delay i[ind] )
```

`K delay2 i` appears in its own definition and in the sketch metadata, and **in
no equation**. In Vensim 2026 it does not exist. In the R, `ST_Kreal_i_lag2` is
never read and the call is commented out of the main loop. Dead on all three
sides.

What lambda diffusion actually reads, in both models, is `K i` and `K delay i`:

```
techn frontier lambda i[ind] * (K i[ind] - (1/Year 1 - depreciation rates i[ind]) * K delay i[ind])
+ lambda delay i[ind] * (1/Year 1 - depreciation rates i[ind]) * K delay i[ind] * Year 1
```

Since `K i` is a state, `K delay i` is its beginning-of-period value — which in
the R is `ST_Kreal_i_lvl`. So the correspondence is
`K i` → `ST_Kreal_i`, `K delay i` → `ST_Kreal_i_lvl`, and nothing maps to
`K delay2 i`. That is what `todo.md` records under *"Lvl and lag"*: the R took
`_lvl` and `_lag2`, shifting the whole thing one year into the past.

**Recommendation: delete `realCapitalStock_lag2()`.** Not applied — the call is
commented out, which is the frontier of the current translation.

### Lambda: the delay chain is real, the code was not

```
lambda delay2 i[ind] = DELAY FIXED(lambda delay i[ind], Year 1, initial lambda delay i[ind])
techn frontier lambda i[ind] = lambda delay i[ind] + (lambda delay i[ind] - lambda delay2 i[ind])
```

A linear extrapolation from the last two values, which genuinely needs both.
`labourProductivity_lag2()` is legitimate. Its period arguments were not:

```r
} else if (t == gp("startYear") + 1) {
  R_labProd_i_lag2 <- gd("R_labProd_i", 1)      # period 1 — but periods are years
} else {
  R_labProd_i_lag2 <- gd("R_labProd_i", t - 2)  # this one was right
}
```

Periods in `d` are years, 2010 to 2070. `gd(x, 1)` asks for a period that does
not exist and would have raised an error the first time the loop reached 2011 —
the fourth bug of the kind that only shows once the time loop runs, after
`gd()` ignoring its argument, `smooth_vensim()` past the first period, and
`max()` collapsing the input-output matrix.

`realCapitalStock_lag2()` had the same fault and worse: its last branch read
`gd("ST_Kreal_i", 2)`, a constant, never `t - 2`.

Both now read `t - dt` and `t - 2 * dt`.

---

## `SH_skill_is` and `SH_male_is` — a flow multiplied by its own stock

**Status:** open. It changes results materially, and it is a modelling question
as much as a translation one.
**Where:** `src/B-modules/L.r`, `shift_SkillLabourShare()` and
`shift_MaleLabourShare()`.
**Found:** step 6 — separating flows from state updates forces the question of
what the flow actually is.

### Problem

Vensim declares both as `INTEG(flow, initial)` with an **additive** flow:

```
skill trend is[ind,skill] = INTEG( in skill trend is[ind,skill], initial )
in skill trend is[ind,skill] = convergence * skill distribution trend is[ind,skill]

male share is[ind,skill]  = INTEG( in male share is[ind,skill], initial )
in male share is[ind,skill] = IF THEN ELSE(flow + male share is > 1, 0, flow)
   where flow = sens*(u_m - u_f) + convergence * male share trend is
```

The R writes both as `level * (1 + flow)`, which is `level + level * flow` —
the flow scaled by the stock it feeds:

```r
factor_is   <- 1 + shift_is
SH_skill_is <- SH_skill_is_lvl * factor_is
```

The parameters are not compensating for it: `R_trendSkill_is` holds exactly the
values of the Vensim `skill distribution trend is` TABBED ARRAY.

### Why it matters: the shares stop summing to one

The Vensim trends sum to zero across skills within each industry — deviation
4e-08, so this is deliberate, not luck. That is what makes an **additive**
update conserve the sum:

| | one step, max deviation from 1 |
|---|---|
| additive (Vensim) | 3.5e-08 |
| multiplicative (R) | **0.0043** |

Over twenty periods the skill shares drift to between **0.928 and 1.025**
instead of staying at 1. The additive form stays at exactly 1.

The effect on the dynamics is the other half: the flow is scaled by a share
between 0 and 0.68, so every skill category drifts more slowly than intended,
and the smaller a category is in an industry, the more slowly it moves — the
opposite of a share that is supposed to be catching up.

### And the check that should have caught it cannot fire

`shift_SkillLabourShare()` opens with:

```r
if (!all(rowSums(SH_skill_is_lvl) - 1) < tolerance) {
  stop("Error: Row sums on SH_skill_is_lvl are not equal to 1 ...")
}
```

The parentheses are misplaced. `all()` receives a numeric vector, coerces it to
logical — every non-zero value becomes TRUE — and returns a single logical,
which is then negated and compared to 1e-6. Feed it a row summing to 3 and it
still returns FALSE. **The check has never fired and cannot.**

```r
if (!all(abs(rowSums(SH_skill_is_lvl) - 1) < tolerance)) stop(...)   # what was meant
```

The two are coupled: fixing the check while keeping the multiplicative update
would make the model stop, because the invariant really is violated.

### What the first pass already says

`src/inconsistencies.qmd` and `src/assumptions.qmd` were searched. Neither
documents the multiplicative form as a choice. What they do say points the other
way:

* **`inconsistencies.qmd`, section `SH_skill_is`** — *"initial values add to
  slightly more than one, a correction has been made but rationale must be
  provided. […] Additionally **a rescaling check has been introduced into
  `shift_SkillLabourShare` to make sure that it actually adds up to one by
  industry**."*

  So the invariant is not an inference from the Vensim: it is the stated intent,
  and a check was written to enforce it. That check is the one that cannot fire.

* **`inconsistencies.qmd`, section `SH_male_is`** — two problems are raised and
  fixed, the out-of-bounds guard and the sign of the unemployment effect. But
  the code quoted there as the *starting point* already reads
  `SH_male_is <- SH_male_is_lvl * factor`. The multiplicative form predates both
  fixes and was never the subject of either.

* **`assumptions.qmd`** — the entries on `R_trendSkill_is` and `R_trendMale_is`
  are template stubs about the trend being exogenous. Nothing on how it is
  applied.

The multiplicative form therefore looks like an unexamined inheritance rather
than a decision, and it is incompatible with an invariant the first pass
explicitly set out to enforce.

### Decision needed

1. **Adopt the additive form**, matching Vensim and restoring the invariant.
   `SH_skill_is <- SH_skill_is_lvl + shift_is`, and for `SH_male_is` the guard
   becomes Vensim's `flow + stock > 1` rather than `stock * (1 + flow) < 1`.
   Changes results for every period after the first. **This is the reading the
   evidence supports.**

2. **Keep the multiplicative form**, if it turns out to have been deliberate —
   in which case it needs an entry in `src/assumptions.qmd` saying so, and the
   sum-to-one check has to go, since the invariant would no longer hold.

Nothing applied either way. The `abs()` fix to the check is held with it, since
it would fail under option 2.

---

## `smooth_vensim()` — right in the first period, wrong in every one after

**Status:** fixed.
**Where:** `src/A-prep-steps/1-custom-functions.r`, and its two call sites in
`src/B-modules/DEM.r`.
**Found:** reviewing the engine before the time loop is added.

### Problem

The function resolved its own variables. Handed the *expression*
`R_diffSkill_u_s * R_sensSkillShift_s`, it walked it, looked each name up in
`d`, `init`, `dp` and the global environment in turn, and evaluated the result.

Past the first period that meant:

* `R_diffSkill_u_s` was found in `d`, so `gda()` returned its **whole history**:
  a matrix of periods x PopGroup.
* `R_sensSkillShift_s` was found in `dp`, so `gp()` returned a **vector of 5**,
  one sensitivity per population group.
* The product of the two recycles the vector **down the columns**, not across
  them.

Each sensitivity therefore lands on a different population group depending on
how many periods have elapsed. With six periods simulated:

| | `child` | `low` | `medium` | `high` | `cap` |
|---|---|---|---|---|---|
| computed, t3 | 0 | -0.0393 | 0 | 0 | **0.0169** |
| correct, t3 | 0 | -0.0917 | 0 | -0.0083 | 0 |

14 of 30 cells wrong, and `child`, `medium` and `cap` — structurally zero,
since nobody in those groups changes skill — pick up non-zero values. The
scrambling then feeds the smoothing itself, so the returned value is wrong even
where the last row happens to line up.

None of this showed, because the first period takes a different branch and
returns the input unsmoothed, and the time loop has never run.

This is the second of three bugs of that shape, with `gd()` ignoring its period
argument and `max()` collapsing the input-output matrix.

### Solution

`smooth_vensim()` now takes **values** and does the arithmetic, nothing else:

```r
smooth_vensim <- function(input, prev, delay, dt = 1) {
  alpha <- dt / delay
  if (any(alpha <= 0) || any(alpha > 1)) stop(...)
  prev + alpha * (input - prev)
}
```

Resolving where `input` and `prev` come from is the caller's job, as it is for
every other variable. A `SMOOTH` is a hidden stock, so the smoothed quantity is
now a variable of the model in its own right — `R_smoothSkillShift_s`, with
`Kind == "state"`, registered in `model_states` and visible in `d`:

```r
smoothSkillShift <- function() {
  eq({
    input <- R_diffSkill_u_s * gp("R_sensSkillShift_s")
    R_smoothSkillShift_s <- if (t == startYear) input
      else smooth_vensim(input, prev = gd("R_smoothSkillShift_s", t - dt),
                         delay = gp("timeSkillTransition"), dt = dt)
    R_smoothSkillShift_s
  })
}
```

Vensim writes the same `smooth(...)` out at each use; there is one state here
because both call sites smooth the same expression.

### Verified

The arithmetic, against the analytic form: converges on a constant input
(0.9977 after 15 steps, alpha = 1/3), half-life 1.71 theoretical against 2
observed, step response lags without overshooting.

Over ten real periods with a drifting input: the smooth initialises to its
input, trails a rising input without ever going backwards, stays within its
range, closes the gap, keeps the structurally-zero groups at zero, and writes a
value to `d` each period.

No existing variable changed — `d` gains one row and the other 72 are
untouched.

---

## `max()` / `min()` used where `pmax()` / `pmin()` was meant — a whole family

**Status:** fixed, four sites.
**Found:** checking whether the zero floor in `TECH` was deliberate. It was — and
the check turned up three more instances of the same mistranslation.

### The mistranslation

In Vensim, `max(a, b)` inside a subscripted equation is **elementwise**: it
returns one value per subscript combination. In R, `max()` is a **reduction**:
it returns a single number, whatever the shape of its arguments. `pmax()` is R's
elementwise version.

A Vensim `max()` transcribed as an R `max()` therefore silently collapses an
array to a scalar. Nothing errors — R recycles the scalar wherever the array
was expected, so the model runs and produces numbers.

### The four sites

| Where | Was | Collapses | Runs today? |
|---|---|---|---|
| `TECH.r`, `computeAlternativeChangeLabourProductivity` (×3) | `max(0, mean)` | 19 industry means → 1 | **yes** |
| `IO.r`, `interIndustryCoeff` | `max(0, R_a_ii)` | the 19×19 input-output matrix → 1 | only from period 2 |
| `L.r`, `POL_shift_hourlyWage` (×2) | `max(R_minHrWage_indexed, R_HrWage_isg)` `min(R_maxHrWage_indexed, R_HrWage_isg)` | the 19×5×2 wage array → 1 | no, dead branch |

`IO.r` is the one to look at twice. The `t == startYear` branch returns the
matrix properly, so the `else` branch has **never executed**. From the second
period of the first real run, the entire input-output structure of the model
would become the number 0.30358 — and stay there, since `max(0, scalar)` is that
same scalar for ever after. Everything downstream — the Leontief inverse, real
and nominal output, intermediate demand — would be built on it.

This is the third bug of that family, after `gd()` ignoring its period argument
and `smooth_vensim()` on its `t > startYear` branch: code that only runs once
the time loop exists, and that has therefore never been exercised.

### Argument order matters too

`pmax(0, x)` **drops the `dim` attribute** and returns a bare vector. The array
must come first:

```r
pmax(R_a_ii, 0)          # 19x19, dimnames intact
pmax(0, R_a_ii)          # a length-361 vector, no dim, no dimnames
```

`TR.r` already had the right form (`pmax(F_Xnom_i, 0)`), which is the house
convention.

### How to catch the rest

```bash
grep -rnE "<- *(max|min)\(" src/B-modules/*.r src/run_model.r
```

Returns nothing today. Worth re-running whenever a Vensim `max`/`min` is
translated: read the Vensim equation, and if it is subscripted, the R is
`pmax`/`pmin` with the array first.

---

## `lengthPhaseOut_i` — the vector is built, then thrown away

**Status:** fixed.
**Where:** `src/run_model.r`, the phase-out policy panel.
**Found:** chasing an `_i` suffix on an object that turned out to be indexed by
energy source.

### Problem

```r
lengthPhaseOut_i <- template_energy_n
lengthPhaseOut_i[] <- c(gp("lengthPhaseOut_carbon"), gp("lengthPhaseOut_gas"),
                        gp("lengthPhaseOut_oil"),    gp("lengthPhaseOut_bio"), 0)
loadFillPol("lengthPhaseOut_i", 50, "energy sources and their number of phasing out years")
```

The third line stores **the scalar 50**, not the vector built on the two lines
above. `gp("lengthPhaseOut_i")` therefore returned `50`, and every energy source
phased out over fifty years:

| source | intended | actually used |
|---|---|---|
| solid (carbon) | 20 | 50 |
| liquid (oil) | 30 | 50 |
| gas | 50 | 50 |
| biomass | 50 | 50 |
| renew | 0 | 50 |

The line immediately above it, for `productPhaseOut_i`, passes the vector
correctly — so this is a slip, not a convention.

Downstream, `endYear_i <- length_i + start` became a scalar instead of a
per-source vector, and `sweep(SH_enSrc_atPolStart_in, 2, length_i, "/")`
recycled the single value across all five sources. It divided by something, so
nothing errored.

Masked today because `Act_phaseOut` is 0 and the branch never runs. It would
have surfaced as "carbon takes fifty years to phase out" the first time anyone
switched the policy on — which is exactly the kind of thing nobody would think
to question.

### Solution

Pass the vector, and rename. These parameters are indexed by **EnergySource**,
not Industry: they are built from `template_energy_n` and swept over the
`EnergySource` dimension. The `_i` suffix was wrong, and it is what made the
scalar invisible — a length-1 object where an industry vector was expected looks
no more wrong than a length-1 object where an energy vector was expected, but
the reader was never given the chance to notice.

```r
lengthPhaseOut_n  <- template_energy_n
lengthPhaseOut_n[] <- c(...)
loadFillPol("lengthPhaseOut_n", lengthPhaseOut_n, "...")
```

`productPhaseOut_i` is renamed to `_n` for the same reason, along with the local
`length_i`, `product_i`, `startYear_i`, `endYear_i` and `phaseOut_InProgress_i`
in `EN.r`.

---

## `sweep()` with a numeric margin — fixed, and no helper needed

**Status:** fixed.
**Where:** `src/B-modules/L.r`, `src/B-modules/EN.r`.

`sweep(x, 1, ...)` and `sweep(x, 2, ...)` follow the order of a template's
dimensions silently. A helper looked necessary, but **base `sweep()` already
accepts a dimension name** when `names(dimnames(x))` is set — which every
template has:

```r
sweep(ST_labEmp_isg * R_hrWage_isg_lvl, "Industry", F_labHr_i, `*`)
```

`GOV.r` and `C.r` already had this form written out in comments as the "more
explicit alternative". It works; it is now the code.

---

## `R_diffSkill_u_s` — a positional vector carrying wrong names

**Status:** fixed.
**Where:** `src/B-modules/L.r`, `diffRateUnemploymentBySkill()`.

```r
R_diffSkill_u_s <- c(0, R_u_s["medium"] - R_u_s["low"], 0,
                     R_u_s["medium"] - R_u_s["high"], 1)
```

Five values that had to line up with `pop_group` in order, with nothing
enforcing it. Worse, the names it did carry were wrong: `c()` inherited them
from the subtractions, so the result was

```
        medium              medium
 0.0000 -0.1924  0.0000  0.0277  1.0000
```

— the `low` slot labelled `medium`, the `high` slot labelled `medium`, and
three slots with no name at all. Anything reading it by name would have got the
wrong cell or nothing.

```r
R_diffSkill_u_s <- template_population_s
R_diffSkill_u_s["low"]  <- R_u_s["medium"] - R_u_s["low"]
R_diffSkill_u_s["high"] <- R_u_s["medium"] - R_u_s["high"]
R_diffSkill_u_s["cap"]  <- 1
```

`child` and `medium` stay at zero by construction. Values unchanged.
