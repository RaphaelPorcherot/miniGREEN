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

The `TODO(2026)` marker is the convention for a line that is a faithful 2025
translation and will change when the module is retranslated. `grep -rn
"TODO(2026)" src/` finds them all.

* **The collapse was a translation bug.** Vensim's `max()` is elementwise here;
  R's is a reduction. `pmax` is the R equivalent. Both the R suffix `_i` and the
  Vensim `[ind]` say per-industry, and no reading makes one industry's mean
  drive the other eighteen.
* **The floor stays, for now.** It is in the 2025 source and was translated
  correctly in intent, so it is not a mistake — the 2026 model simply dropped
  it. The module is still a translation of 2025 throughout, and half-migrating
  one line to 2026 would make it internally inconsistent. It is therefore kept
  as `pmax(gp("R_gLabProdMean_i"), 0)` and marked `TODO(2026)` in the code, to
  be dropped when TECH is retranslated.

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
