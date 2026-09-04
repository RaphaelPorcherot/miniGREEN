# REWIND — Vensim to R

REWIND is an IO-SFC-SD ecological macroeconomic model calibrated for Italy. This
repository holds its translation from Vensim to R.

The reference source is `vensim_model_2026.txt` — the simplified version of the
model (v2.5, Firenze), exported as text from Vensim. This repository is *not* a
port of the Vensim engine: it is a hand-written system dynamics simulation
framework, which is the normal approach for large SD models with dense
subscripts.

> **Status.** This document describes the target architecture agreed for the
> current refactoring. Sections marked **[planned]** are not implemented yet.
> Everything else is either in place or being put in place in the current pass.

---

## Table of contents

1. [Installation](#1-installation)
2. [The model in brief](#2-the-model-in-brief)
3. [Repository layout](#3-repository-layout)
4. [How the engine works](#4-how-the-engine-works)
5. [Naming conventions](#5-naming-conventions)
6. [States, flows and auxiliaries](#6-states-flows-and-auxiliaries)
7. [Time step and the route to continuous time](#7-time-step-and-the-route-to-continuous-time)
8. [Vensim to R](#8-vensim-to-r)
9. [Verification](#9-verification)
10. [Preparing for the multi-regional version](#10-preparing-for-the-multi-regional-version)
11. [Tools](#11-tools)
12. [Git workflow](#12-git-workflow)
13. [Known issues and backlog](#13-known-issues-and-backlog)

---

## 1. Installation

The only environment manager used is **renv**. Python, Poetry and JupyterLab are
no longer part of the toolchain: the model runs as plain R scripts.

### 1.1 Install R

* **macOS** — from <https://cran.r-project.org/bin/macosx/>
* **Ubuntu/Debian** — `sudo apt update && sudo apt install r-base`
* **Windows** — from <https://cran.r-project.org/bin/windows/base/>

### 1.2 Install renv globally

```bash
R -e "install.packages('renv', repos='https://cloud.r-project.org/')"
```

On Linux this may need `sudo`.

### 1.3 Restore the project environment

```bash
cd /path/to/rewind
R
```

```r
# renv usually activates itself when it sees renv.lock.
# If you do not see "Project ... loaded. [renv x.y.z]", run:
renv::activate()

# then install everything the project needs
renv::restore()
```

If `renv::restore()` complains about a missing `make`, you lack compiler tools.
Some packages ship as source only.

* **Windows** — install RTools from <https://cran.r-project.org/bin/windows/Rtools/>
* **macOS** — `xcode-select --install`
* **Ubuntu** — `sudo apt install build-essential`

Then run `renv::restore()` again.

### 1.4 Run the model

```bash
Rscript src/run_model.r
```

### 1.5 Managing packages

```r
renv::install("somepackage")   # add
renv::snapshot()               # write it to renv.lock  <- do not forget

renv::status()                 # check drift
renv::update()                 # update (once a year is enough)

renv::remove("somepackage")    # remove
renv::snapshot()
renv::restore()                # prune what is no longer needed
```

After someone else adds a package, `git pull` then `renv::restore()`.

---

## 2. The model in brief

| | |
|---|---|
| Industries | 19 |
| Genders | 2 |
| Population groups | 5 — `child`, `low`, `medium`, `high`, `cap` (see §5.3) |
| Age cohorts | 5 — `0-14`, `15-24`, `25-44`, `45-64`, `65+` |
| Occupational status | 4 — `emp`, `unemp`, `olf`, `pension` |
| Energy sources | 5 — `solid`, `liquid`, `gas`, `biomass`, `renew` |
| COICOP products | 16 |
| Technologies | 4 |
| Time step | 1 year |
| Horizon | 2010 → 2070 (61 periods), Covid years 2020-2022 |

Modules:

| Code | Module | Code | Module |
|---|---|---|---|
| `POLICY` | Policy, shocks, triggers, shifts | `TR` | International trade |
| `DEM` | Demography | `FI` | Finance |
| `TU` | Time use | `L` | Labour |
| `IO` | Input-output | `GOV` | Government |
| `P` | Prices | `TECH` | Technology |
| `PVA` | Profits and value added | `EN` | Energy |
| `C` | Consumption | `ENV` | Environment |
| `I` | Investment | `CADA` | Carbon tax and damage function |

`WD` (water demand) and `WS` (water supply) are declared but out of scope for now.

### What changed between the 2025 and the 2026 Vensim model

The 2026 model has 777 variables against 1078. Of those, 705 are common, 373
were removed and 72 added.

**Removed** — the whole policy panel (`Act_*`, basic income, job guarantee, work
time reduction, minimum and maximum wage, wealth tax, phase-out schedules,
carbon tax redistribution), most of the inequality apparatus (Gini/Theil/Palma
collapsed into a single `GINI yd`), the time-use module, and the eight `caseN_i`
technology variables (now a single `cases T i` indexed on a `cases Tech`
subscript).

**Added** — PNRR (Italian recovery plan) spending, climate damage and
temperature, a genuine financial block (`stock of bonds`, `interest`, `debt i`),
and `Ld gis` labour demand.

Two consequences worth knowing:

* `WITH LOOKUP` went from 228 occurrences to **0**. The lookup machinery was
  almost entirely consumed by the minimum/maximum wage policy, which is gone.
  Only `mpc fct`, `beta fct p`, `Free ETS i` and the damage functions remain.
* `smooth()` appears **14 times in only 2 distinct forms**, 12 of them being the
  same skill-transition expression.

The R code written for the 2025 model is largely reusable: DEM, L, I, IO, P,
GOV, TR, TECH and EN all survive nearly intact. `POLICY.r` is parked, not
deleted — the policies may come back.

---

## 3. Repository layout

```
├── README.md          this file
├── vensim_model_2026.txt  the source of truth for the translation
├── src/
│   ├── paths.R            every path in the project resolves through here
│   ├── run_model.r        the orchestrator: loads, then runs the time loop
│   ├── A-prep-steps/
│   │   ├── 0-log-config.r      logging
│   │   ├── 1-custom-functions.r  engine: eq(), the d layer, loaders
│   │   └── 2-structure.r      dimensions, templates, module list
│   ├── B-modules/         one file per module, one function per equation
│   ├── assumptions.qmd
│   ├── inconsistencies.qmd    Vensim bugs found and how they were fixed
│   └── long-comments.qmd      comments preserved from the .mdl
├── input/
│   ├── scalars.csv       all scalar parameters and initial values
│   ├── initial/<MODULE>/  initial values of states
│   ├── parameter/<MODULE>/ parameters
│   └── lookup/<MODULE>/   graphical function data (x, y pairs)
├── output/                saved runs and snapshots (git-ignored)
├── log/                   run logs (git-ignored)
├── tool/                  Vensim → R extraction helpers
└── app/graph/             Shiny dependency-graph viewer
```

**All paths go through `src/paths.R`.** Never write a literal path in a module.
The previous layout (`notebooks/r-nb/...`) is gone.

**Files and directories are `kebab-case`** (`A-prep-steps/`, `0-log-config.r`,
`long-comments.qmd`). The `camelCase` rule of §5 applies to R objects — variables
and functions — not to file names.

---

## 4. How the engine works

### 4.1 Four tables

Everything the model knows lives in one of four `data.table`s. Nothing is left
loose in the global environment between periods.

| Table | Holds | Varies over time? |
|---|---|---|
| `dp` | parameters | no |
| `init` | initial values | no |
| `lookup` | graphical function data (`x`, `y` pairs) | no |
| `d` | every computed variable, every period | yes |

The distinction between `dp` and `init` is deliberate and worth stating: `dp` is
for what is **fully exogenous**, `init` for what is **exogenous only until
something moves it**. A parameter that a policy can shift belongs in `init`,
because it will have a different value in later periods. Putting it in `dp`
would be a lie about the model.

Common columns: `Name`, `Module`, `Value` (a list column — scalars up to 4D
arrays), `Description`. `d` adds `Period`.

**[planned]** Three additions:

* `Kind` — `state`, `flow` or `aux`. See §6.
* `Region` — one value (`"IT"`) for now. See §10.
* a separate `deps` table recording, for each variable, what it depends on.
  Dependencies are currently attached as an attribute on the value; the
  attribute stays (the Shiny app reads it), but the table is what queries should
  use, because an attribute lives on a value that is rewritten every period.

`Scenario` will become a column of `d` when scenarios arrive.

### 4.2 Reading and writing

| Function | Does |
|---|---|
| `gp(name)` | read a parameter from `dp` |
| `gi(name)` | read an initial value from `init` |
| `gl(name)` | read lookup data from `lookup` |
| `gd(name, t)` | read one variable at one period from `d` |
| `gda(name, from, to)` | read a variable over a window of periods |

Writes go through `eq()` (see below), not by hand.

**[planned] Performance.** `d` is pre-allocated at ~110 000 rows. The current
`To()` / `pTo()` / `iTo()` / `lTo()` family finds the next free row by scanning
the whole table on every single write — measured at 4.2 s per 1000 calls, which
is roughly nine minutes of pure scanning for a full 61-period run. They are
replaced by an **O(1) cursor** per `(Module, Period)` block: ~300× faster.
Reads use a `(Name, Period)` key and are windowed — the model never needs the
whole history, only a few recent periods.

### 4.3 `eq()` — the contract

Every equation of the model is an R function whose body is a single `eq({...})`
block. `eq()` does five things so that you do not have to:

1. **Collects dependencies** by walking the expression, and separates them from
   parameters and auxiliaries.
2. **Blocks execution** if any dependency is not yet available, and logs why.
3. **Assigns** the result to the global environment under the target name.
4. **Writes** it to `d` for the current period, in run mode.
5. **Attaches metadata** (dependencies, parameters, originating function) to the
   result.

The contract you must respect when writing one:

```r
myEquation <- function() {
  eq({
    intermediate <- something * gp("someParameter")
    ST_myVariable <- intermediate + F_someFlow
    ST_myVariable          # <- the last line MUST be the bare variable name
  })
}
```

The last line has to be the bare name of the target variable. That is how `eq()`
knows what it just computed.

### 4.4 The main loop

Because `eq()` refuses to run an equation whose inputs are missing, **you do not
have to order the equations correctly**. The loop runs several passes; each pass
resolves whatever became computable. Equations are grouped by module in
`run_model.r`, in commented blocks, so that the reading order reproduces the
*views* of the Vensim model. That grouping is intentional and should be kept.

```
for each period t:
    reset the per-period registry
    repeat:
        POLICY block
        GOV block
        L block
        ... one block per module, in a readable order ...
    until no pass resolves anything new
    update the states:  state <- state + net_flow * dt
    check the invariants
```

**[planned]** Two changes to this loop:

* **Memoisation.** An equation that succeeded in one pass is not recomputed in
  the next. The value is already in the global environment for downstream
  equations to use. A `dev` mode escape keeps console re-runs working.
* **Adaptive passes.** `iter <- 3` is replaced by "keep going while a pass
  resolves something new". This is *not* a topological sort — the mechanism and
  your freedom to order equations as you like are unchanged. It only means that
  if four passes are needed you get four, and that an equation which can never
  be resolved becomes a named error instead of a line in a log file.

---

## 5. Naming conventions

### 5.1 Variables

```
[TYPE]_[variableName]_[subscripts]
```

**`[TYPE]` describes the economics.** Always uppercase:

| Prefix | Meaning |
|---|---|
| `ST_` | stock, in absolute terms |
| `F_` | flow, in absolute terms |
| `R_` | rate, in % |
| `SH_` | share, in %, bounded 0–1 |
| *(none)* | anything else — years, degrees Celsius, price indices |

Derived forms:

| Pattern | Meaning |
|---|---|
| `R_g...` | growth rate |
| `F_g...` | absolute change |
| `R_d...` | time difference |
| `eff_...` | an effect or impact term |
| `...Mean` | a mean (not `avg`) |

`[variableName]` is lowerCamelCase: `finalDemand`, not `final_demand` or
`final-demand`.

For `SH_`, the first item is what is being shared and the second is what it is a
share *of*, made explicit with `_in_` or `_to_`:
`SH_enSrc_enDemZ_in` = share of energy source in the energy demand arising from
intermediate production.

### 5.2 Subscripts

Order indices by **decreasing number of modalities**. `ST_population_csg` is
cohort (5), then population group (5), then gender (2). This makes the console
output readable and makes it much easier to remember which index is which once
you go past two dimensions.

| Letter | Dimension | | Letter | Dimension |
|---|---|---|---|---|
| `a` | assets | | `n` | energy source |
| `c` | cohorts | | `p` | COICOP products |
| `d` | occupational status | | `s` | population group (see below) |
| `e` | household energy use | | `t` | time use |
| `g` | gender | | `v` | technologies |
| `i` | industries | | | |

Vensim's `k` (ind+fd+exp), `l` (ind+imp) and `z` (skill+capitalists) are not
used.

Every combination of indices must have a template (§5.5).

### 5.3 `PopGroup` versus `skill` — read this carefully

The dimension carried by the letter `s` has five modalities:

```r
pop_group <- c("child", "low", "medium", "high", "cap")
```

It folds three different things into one dimension:

| Modality | What it actually is |
|---|---|
| `child` | a generational status — does not work yet |
| `low` `medium` `high` | an actual qualification level |
| `cap` | a class status — capitalist |

This is a deliberate choice to avoid a mostly-empty Cartesian product (a
capitalist has no qualification level). The cost is that **"summing over `s`"
has no single meaning**: some aggregations want all five modalities, some want
only the three genuine skills.

The dimension is therefore named **`PopGroup`**, not `Skill`, and the genuine
skills are available as a named subset:

```r
pop_group <- c("child", "low", "medium", "high", "cap")   # the partition
skill     <- c("low", "medium", "high")                    # actual qualifications
```

**Always index by the named subset, never by position or by hand-written
exclusion.**

```r
x[, skill, ]                                              # yes
x[, -1, ]                                                 # no
x[, -which(dimnames(x)[[2]] %in% c("child","cap")), ]     # no
```

This is not cosmetic. The bug recorded in `inconsistencies.qmd` as
*"capitalists actually eating out of the labour force"* is exactly a case of a
hand-written exclusion getting it wrong.

Note that Vensim writes `mid` and `hig` where we write `medium` and `high`. The
recoding is handled once, in the import manifest (§11), and nowhere else.

### 5.4 Equation functions

Function names are **lowerCamelCase**, like variable names — the project uses one
case convention throughout, never `snake_case`. They may be verbose: a function
name should say what the equation does, in full.

The underscore is therefore free to carry meaning rather than word boundaries. It
separates the *components* of a name, exactly as it does for variables:

| | |
|---|---|
| `SH_A_in_B` | share of A in B |
| `R_C_of_D` | rate of C, of D |
| `employmentRate_sg` | the same quantity, by population group and gender |
| `realCapitalDepreciation_lag` | the lagged version of `realCapitalDepreciation` |

So `_` marks a qualifier — a subscript set, a variant, a lag — and never a word
break inside a concept. `realCapitalStock`, not `real_capital_stock`.

Functions affected by a policy or a shock are prefixed `POL_` or `SHOCK_`, and
are listed first in their module file.

Write one function per **unit operation**. A calculation that is only used by one
other equation does not deserve its own function — fold it in. A calculation used
by two or more does.

### 5.5 Templates

Every array in the model is built from a named template, so that dimension names
travel with the data and mismatches fail loudly instead of recycling silently.

**[planned]** Templates are generated rather than hand-written:

```r
template_population_csg <- make_template(c("Cohort", "PopGroup", "Gender"))
```

This replaces ~20 hand-written `array(0, dim = ..., dimnames = ...)` blocks. It
is also what makes the multi-regional version affordable later (§10): one
function to change instead of twenty declarations plus every loader.

---

## 6. States, flows and auxiliaries

### 6.1 There is no `_lvl` any more — and this matters

> **Vensim "levels" and Vensim "delays" are the same thing in this code.**
>
> The distinction between `_lvl` and `_lag` has been removed. It never
> corresponded to two different objects, and maintaining two names for one
> concept was a documented source of error in the original Vensim model.

The one true statement is:

**A state's value at `t` is, by construction, its value at the end of `t-1`.
Every state is an implicit lag of itself.**

So there is exactly one way to look backwards:

```r
gd("ST_Kreal_i", t - 1)      # the value one period ago
gda("ST_Kreal_i", t - 3, t)  # a window
```

and nothing else. No `_lvl` suffix, no `_lag` global set before the loop, no
parallel copy of a state living in the global environment. If you find yourself
writing `X_lvl <- ...`, you are re-introducing the bug.

A genuine `DELAY FIXED` on a **non-state** variable (Vensim has 42 of them) is a
different matter: that one is a real lagged auxiliary and keeps a `_lag` suffix,
because there is no state to read back from.

### 6.2 The `Kind` column

The economic prefix (`ST_`, `F_`, `R_`, `SH_`) says what a variable **is**. It
does not say how it is **computed**. Those are two different questions and one
prefix cannot carry both.

`Kind` carries the second one:

| `Kind` | Meaning | Integrated? |
|---|---|---|
| `state` | carries its own past; has an initial value | yes |
| `flow` | a rate of change feeding a state | no |
| `aux` | computed algebraically within the period | no |

The stock-update step and, later, the RK4 stepper iterate over `Kind ==
"state"` — **never over a name prefix**. A naming convention cannot be checked
by a machine; a column can. Any Vensim `INTEG` that is not registered as a
`state` is a test failure.

### 6.3 When a share is a state

`SH_enSrc_enDemZ_in` is a share, economically. It is also a Vensim `INTEG`. There
is no contradiction: a share is dimensionless, and nothing stops a dimensionless
quantity from carrying its own past. Saying "the energy mix has inertia — you
cannot rebuild the grid in a year" is exactly what an `INTEG` on a share means.

Such cases carry an **`integ_rationale`** field in the registry: one line saying
*why* this variable is a state. Three of them exist today.

**The decision rule.** Look at the inflow. Does it reference the stock itself,
directly or through anything computed in the same period?

| | |
|---|---|
| **Yes** | It must stay a state. Converting it creates an algebraic loop. |
| **No, and the inflow is purely exogenous or time-dependent** | It could become an auxiliary, but the gain is negligible and you lose uniform treatment. |
| **No, but the stock appears in an accounting identity** (population, capital, debt) | It must stay a state, or the identity breaks. |

The first row is the important one, and it is architectural, not aesthetic.
**The model is sequentially solvable — it has no simultaneity — precisely because
these states break the loops.** Converting one to an auxiliary would create a
simultaneity, which would break the dependency-blocking design of `eq()`.

Worked examples, from the 2026 model:

* **`Share source Ed Z nrg i`** — the inflow is
  `-g(t) * ZIDZ(Share[nrg], 1 - Share[renew])`. Self-referential. **Must stay a
  state.**
* **`male share is`** — the inflow contains a saturation guard
  `IF THEN ELSE(... + male share is > 1, 0, ...)`. Self-referential and
  genuinely path-dependent. **Must stay a state.**
* **`skill trend is`** — the inflow is `convergence * trend`, purely exogenous.
  A closed-form cumulative sum would work. **Could be an auxiliary, but is not
  worth it.**

### 6.4 The states

The 2026 Vensim model has exactly **35 `INTEG`** variables. This list is closed
and is the authority for what gets registered as `Kind == "state"`.

| Vensim | R | Module |
|---|---|---|
| `Pop 014 g` … `Pop 65+ g` | `ST_population_csg` | DEM |
| `Skills 1524 gs` … `Skills 65+ gs` | *(same array)* | DEM |
| `LFPR gs` | `R_LFRP_csg` | L |
| `wage gis` | `R_hrWage_isg` | L |
| `male share is` | `SH_male_is` | L |
| `skill trend is` | `SH_skill_is` | L |
| `K i` | `ST_Kreal_i` | I |
| `I desired i` | — | I |
| `gov c nom i` | — | GOV |
| `Share source Ed Z nrg i` | `SH_enSrc_enDemZ_in` | EN |
| `prob T2 i`, `prob T3 i` | — | TECH |
| `adaptation` | — | CADA |
| `stock of bonds`, `interest`, `debt i` | — | FI |
| `b cap`, `b gs`, `d cap`, `d gs`, `eq cap`, `eq gs` | — | FI |

Entries with `—` are not translated yet. The financial block is new in 2026 and
the `FI` module has not been started.

### 6.5 Flows are computed separately from states

**[planned]** A module computes a **net flow** and stops there. It does not
update the state.

```r
# in the module: a pure flow, no side effect on the state
netCapitalFormation <- function() {
  eq({
    F_KrealNet_i <- F_GFCFreal_i - F_KrealDepr_i
    F_KrealNet_i
  })
}
```

The update happens once, at the end of the period, for all states at once:

```r
state <- state + net_flow * dt
```

This is what makes RK4 possible later (§7). Today `I.r` does both in one
expression:

```r
ST_Kreal_i <- ST_Kreal_i_lvl + (F_GFCFreal_i - F_KrealDepr_i)   # to be split
```

---

## 7. Time step and the route to continuous time

`dt` is defined once in `2-structure.r` and appears explicitly in every state
update:

```r
dt <- 1   # annual, discrete
```

With `dt = 1` and explicit Euler this is exactly what the code does today and
what Vensim does by default. Writing `dt` now costs nothing and makes the later
transition mechanical.

**You do not need `deSolve`.** Its requirement that state be a flat numeric
vector is an interface constraint of that package, not a mathematical necessity.
Flattening and rebuilding named 3D and 4D arrays on every step would be
painful for no benefit. The stepper is written directly against the named
arrays:

```r
step_euler(t, dt)   # now
step_rk4(t, dt)     # later, same interface
```

Because the stepper iterates over `Kind == "state"`, adding RK4 touches one
function and no equations at all.

**One honest limit.** A large part of this model is not integrable in continuous
time by construction: annual income tax brackets, cohort maturation on a
one-year step, `IF THEN ELSE(Time = 10, ...)` Covid shocks, `DELAY FIXED`. RK4
applies to the 35 states; the rest stays discrete annual. That is a feature, not
a shortcoming — but it means the work of separating flows from state updates is
bounded to 35 places, not to the whole model.

---

## 8. Vensim to R

| Vensim | R |
|---|---|
| `INTEG(flow, init)` | a variable with `Kind = "state"`, initial value in `init`, updated by the stepper |
| `DELAY FIXED(x, 1, init)` | `gd("x", t-1)`; for a state, that *is* the state (§6.1) |
| `INITIAL(x)` | an `if (t == startYear) {...} else {...}` inside the equation |
| `ZIDZ(a, b)` | divide, then `x[is.nan(x)] <- 0` |
| `IF THEN ELSE` | `if/else` for scalars, `ifelse()` for arrays — the distinction is not optional in R |
| `MIN`, `MAX` | `min`/`max` for scalars, `pmin`/`pmax` for arrays |
| `WITH LOOKUP`, `lookup extrapolate` | `approxfun(x, y, rule = 2)` built on the fly from `gl()` data |
| `RANDOM UNIFORM(a, b)` | `runif(n, a, b)` |
| `RANDOM NORMAL(m, x, h, r, s)` | `rtruncnorm(n, a, b, mean, sd)` |
| `SMOOTH(x, delay)` | `smooth_vensim()` — see below |
| `TABBED ARRAY` | a CSV in `input/`, imported by `loadFill()` |
| `GET DIRECT CONSTANTS` | a CSV in `input/` |

### `smooth_vensim()`

Vensim's `SMOOTH` is a hidden stock:

```
Smooth       = SMOOTH(input, delay)
dSmooth/dt   = (input - Smooth) / delay
Smooth(t+dt) = Smooth(t) + (input(t) - Smooth(t)) * dt / delay
```

**[planned]** The implementation follows that literally. The function takes
**values, not expressions** — no introspection, no scope hunting. The smoothed
quantity is a variable in its own right, registered with `Kind = "state"`, and
therefore visible in `d`, in the outputs and in the dependency graph like
anything else.

```r
smooth_vensim <- function(input, prev, delay, dt = 1) {
  alpha <- dt / delay
  stopifnot(alpha > 0, alpha <= 1)
  prev + alpha * (input - prev)
}
```

Resolving where `input` and `prev` come from is the job of `eq()`, exactly as for
every other variable.

> The previous implementation resolved variables itself, by walking the
> expression and searching `dp`, `init`, `d` and the global environment in turn.
> It produced the right answer in the first period and a wrong one afterwards,
> which went unnoticed because the time loop had never run past the first
> period. It is being replaced, not tidied.

Lookups, worked example:

```r
freeETS_i <- template_industry_i
for (i in industry) {
  sub <- gl("freeETS_i")[industry == i]
  if (nrow(sub) < 2) { freeETS_i[i] <- 0; next }
  freeETS_i[i] <- approxfun(sub$x, sub$y, rule = 2)(t)
}
```

The interpolator is rebuilt on the spot rather than stored, because keeping
every lookup function in memory is expensive and building one is cheap.

---

## 9. Verification

There is **no reference run from Vensim**, and none is wanted: the original model
contains enough bugs and modelling errors that reproducing it is not the goal.
Two substitutes are used instead.

### 9.1 Before/after snapshots

Every refactoring step must leave `d` bit-identical to the snapshot taken before
it. This does not validate the model — it guarantees that infrastructure work
changes no results. Snapshots live in `output/_ref_*.rds`.

### 9.2 The model's own invariants

The original authors left consistency checks inside the Vensim model. They are
ratios that should equal 1 or differences that should equal 0, and they test the
economics rather than the code. They are ported as assertions run at the end of
each period:

| Check | Should be |
|---|---|
| `check IO1` = `sum(final demand nom i) / sum(VA i)` | 1 |
| `check L is` = `sum(L i desired) / sum(Ld i s)` | 1 |
| `check L tot` = `sum(Ld gis) / sum(L i desired)` | 1 |
| `check inactive` = `Inactive_tot / sum(N olf gs)` | 1 |
| `check PET` | 1 |
| `test adult` = `pop - pop014 - adult pop` | 0 |
| `test work pop` = `working age pop total tot / working age pop total` | 1 |

To which the R model adds `check_population_consistency()`:
active = employed + unemployed, working age = active + inactive, and total
population equal to the sum of its demographic components.

---

## 10. Preparing for the multi-regional version

The target is an inter-regional IO structure — a matrix of regional IO matrices.
No decision has been taken on the modelling approach, but two things are true
already and shape what is done now.

**Regions are not separable.** With an inter-regional IO matrix, region *r*'s
intermediate demand feeds region *s*'s output **in the same period**. Running the
whole model as a loop over regions would therefore impose a one-period lag on
inter-regional flows, which changes the economics. That approach is ruled out
unless that lag is wanted deliberately.

**Two classes of variable need different treatment:**

* **Region-separable** — demography, labour, most of government. Add `r` as a
  leading index; the equations do not change and vectorise naturally.
* **Region-coupled** — the IO block, trade, energy flows. The arrays gain *two*
  region indices (origin and destination) and the equations genuinely change.
  `R_a_ii` (19×19) becomes a block matrix (19R × 19R), and the Leontief inverse
  is taken once on the whole block matrix. That is not iteration.

**What is being done now, and only this:**

1. A `Region` column on `d`, `init` and `dp`, with a single value `"IT"`. It
   costs nothing today; retrofitting it later would mean touching every read and
   write.
2. `make_template()` (§5.5), so that adding a region index later is one change
   in one function rather than twenty declarations plus every loader.

No region machinery beyond that until the inter-regional data actually exists —
which is usually the binding constraint, not the code.

---

## 11. Tools

`tool/` holds the helpers that convert Vensim text exports into the CSV files
under `input/`.

* `tool/data-to-convert/` — raw `.txt` blocks copied out of Vensim (matrices,
  `TABBED ARRAY`, constant lists)
* `tool/data-lookup/` — raw `.txt` blocks for graphical functions
* `tool/directed_graphs.qmd` — builds the dependency graph consumed by the Shiny
  app

**[planned]** The two extraction notebooks are replaced by a single parser driven
by a **manifest CSV** rather than by interactive `readline()` prompts. One row
per variable:

```csv
vensim_name,r_name,kind,dimensions,module,recode
"Free ETS i",freeETS_i,lookup,"Industry",CADA,
"a ii",R_a_ii,parameter,"Industry,Industry",IO,
"skill distribution initial is",SH_skill_is,initial,"Industry,PopGroup",L,"mid=medium;hig=high"
```

This makes imports reproducible and re-runnable, records the Vensim ↔ R mapping
as a by-product, and puts the `mid`/`medium` recoding in one place. The lookup
scope is now small (four variables), so this is a modest piece of work rather
than a framework.

### The Shiny dependency viewer

`app/graph/` renders the model as a directed graph, one node per variable,
coloured by module. Deployed at <https://rewind.shinyapps.io/graph/>.

```r
library(shiny); library(rsconnect)
runApp()
deployApp()
```

It currently reads dependencies from the attribute attached to each value in
`d`. Once the `deps` table exists it should read that instead — the attribute is
tied to a value that gets rewritten every period, so the graph is a by-product
of the data rather than a queryable object.

---

## 12. Git workflow

### Branch types

| Prefix | Purpose |
|---|---|
| `test/` | throwaway experiments |
| `dev/` | active development — `dev/<feature>` or `dev/<module>` |
| `feat/` | a new feature or module — `feat/<name>` |
| `bugfix/` | fixing a reported or discovered bug |
| `hotfix/` | urgent fix — merge into both `main` and `dev/` |

### Everyday commands

```bash
git fetch                        # before you start
git checkout -b dev/my-thing
# ... work ...
git add -A
git commit -m "clear message"
git push -u origin dev/my-thing
```

### Practices

* Commit small and often; the history is what lets you find when something broke.
* Push early — it is also your backup.
* `git fetch` or `git pull` before starting, to avoid conflicts.
* One branch per task.
* Resolve conflicts by reading them, never by accepting blindly.
* Delete merged branches: `git branch -d <name>` and
  `git push origin --delete <name>`.

---

## 13. Known issues and backlog

### Fixed in the current pass

* **`gd(var, time)` ignored its `time` argument.** The filter read
  `Period == Period`, which is always true, and the function returned the first
  period's value. It appeared to work only because the time loop had never run.
* **`gd(..., info=)` queried `lookup` instead of `d`.**
* **`smooth_vensim()` returned a wrong result for `t > startYear`** (§8).
* `loadFill()` used `next` inside a `tryCatch` handler, which is not a loop, and
  `message()` where `stop()` was meant — a file could fail to load silently.
* `read_and_validate_csv()` reported missing columns with `message()`, not
  `stop()`.
* `load_3d()` referenced `desc` before it existed in that scope.
* **Double sourcing.** The `BEGIN`/`END` + tempfile pattern re-sourced every
  module file a second time into a temporary environment, purely to list its
  objects for the log. Replaced by `local({})` plus a `log_objects()` helper,
  which also removes the need for `toKeep0/1/2`.
* `toKeep`, a mutable global appended to with `<<-` from a dozen places,
  replaced by a registry environment populated by the loaders themselves.

### Open

* **`FI` (finance) is new in the 2026 model and is in scope.** It brings 8 of the
  35 states — `stock of bonds`, `interest`, `debt i`, and `b`/`d`/`eq` by
  household group and for capitalists — plus the accounting identities that go
  with them. It has no counterpart in the current R code and has to be written
  from scratch.
* `TU`, `PVA`, `ENV`, `WD`, `WS` modules not started, and not in scope for now.
* Calibration. `run_model(params = NULL, scenario = NULL)` exists as the entry
  point but no calibration procedure is written. Block calibration — module by
  module, holding the rest fixed — is the realistic approach for a model with
  this many parameters and a non-convex loss.
* `R_mortality_csg` is stored as a full 3D array although it only varies by
  cohort. Same for several other DEM parameters.
* Scenarios: a `Scenario` column on `d`.
* Unit checking. Vensim does dimensional analysis; R does not. Worth adding.
* `r-REWIND-inconsistencies.qmd` needs to be replayed against
  `vensim_model_2026.txt`: some of the bugs found may have been fixed upstream,
  some may not, and some of the 2026 simplifications may rest on the buggy
  behaviour. Findings go into `inconsistencies_new.md`.
* `testthat` for the invariants of §9.2.

---

## Sources and references

Kept outside this repository:

* `vensimModel_noDelete.txt` — the 2025 model, for comparison with the 2026 one
* `economy.xlsx`, `demography.xlsx`, `environment.xlsx`, `calibration_2024.xlsx` —
  the calibration spreadsheets. Every `GET DIRECT CONSTANTS('economy.xlsx', ...)`
  in the Vensim source points at these, so they are the authority for any number
  imported into `input/`.
* DEFINE — a comparable ecological SFC model written in R
* `sysde` — system dynamics tutorials in R
* Duggan, *System Dynamics Modeling with R* (2016)
