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

`WD` and `WS` are declared as modules but barely present in either Vensim
model. See §13 for what each untranslated module actually contains.

### What changed between the 2025 and the 2026 Vensim model

The 2026 model has 777 variables against 1078. Of those, 705 are common, 373
were removed and 72 added.

**Removed** — the whole policy panel (`Act_*`, basic income, job guarantee, work
time reduction, minimum and maximum wage, wealth tax, phase-out schedules,
carbon tax redistribution), most of the inequality apparatus (Gini/Theil/Palma
collapsed into a single `GINI yd`), the time-use module — ~110 lines in 2025,
nothing but an orphaned input array in 2026 — and the eight `caseN_i` technology
variables (now a single `cases T i` indexed on a `cases Tech` subscript).

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
├── MAPPING.md         which R function translates which Vensim equation
├── vensim_model_2026.txt  the source of truth for the translation
├── src/
│   ├── paths.r            every path in the project resolves through here
│   ├── run_model.r        the orchestrator: loads, then runs the time loop
│   ├── snapshot.r         take / check a reference snapshot (§9.1)
│   ├── A-prep-steps/
│   │   ├── 0-log-config.r      logging: levels, blocks, object listings
│   │   ├── 1-custom-functions.r  engine: eq(), the table layer, keep, loaders
│   │   ├── 2-structure.r      dimensions, templates, modules, the states registry
│   │   └── 3-invariants.r     what must hold at the end of every period (§9.2)
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
├── app/graph/             Shiny dependency-graph viewer
└── docs/EUROGREEN/        Vensim sources and calibration data — see §11.3
```

**All paths go through `src/paths.r`.** Never write a literal path in a module.
The previous layout (`notebooks/r-nb/...`) is gone.

**`TODO(2026)` marks a line where the 2025 and the 2026 model differ and the
code still follows 2025.** The modules are 2025 translations throughout;
migrating one line at a time would make them internally inconsistent, so the
differences are marked rather than applied.

The marker records a decision *to take*, not one already taken. Following 2026
is usually right, but not always: some of its changes are undocumented, and an
undocumented simplification is a question for its author, not an authority.
`grep -rn "TODO(2026)" src/` lists them.

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

Three further columns and one further table:

* `Kind` — `state`, `flow` or `aux`. Stamped from the states registry (§6.2).
* `Region` — one value (`"IT"`) for now. See §10.
* a separate `deps` table recording, for each variable, what it depends on, with
  a `Role` of `input` or `parameter`, plus the module and the function it came
  from.

  Dependencies used to ride as an attribute on the value itself. They no longer
  do. An attribute on a value that gets rewritten every period is metadata
  pretending to be data: it makes two otherwise identical runs compare unequal,
  and it means reconstructing the dependency graph requires reading `d` and
  hoping the right period is still there. The table is the single source.

`Scenario` will become a column of `d` when scenarios arrive.

### 4.2 Running the model

`src/run_model.r` does two things. Read top to bottom it sets the model up —
inputs, tables, policy panel, modules — which is slow and does not depend on the
parameters. Then it defines `run_model()`, which is the part that can be run
again:

```r
run_model()                                           # as it stands
run_model(params = c(R_fertility = 1.6))              # with a parameter changed
run_model(params = p, quiet = TRUE)                   # inside an optimiser
```

Setup happens once, a run takes about 1.7 s. So a calibration loop is:

```r
loss <- function(x) {
  out <- run_model(params = c(R_fertility = x), quiet = TRUE)
  sum((out$population - observed)^2)
}
optim(par = 1.4, fn = loss)
```

`run_model()` returns a named list of the series a calibration or a scenario
comparison actually looks at, plus `d` in full for everything else.

**Every name in `params` must already exist in `dp`.** A typo is an error, not a
silent no-op — which matters most when an optimiser is driving this and nobody
is reading the output. `dt_update()` is what does the replacing: `dt_set()` only
ever appends, so until now there was no way to change a parameter at all.

`reset_state()` puts the model back at its starting point between runs: an empty
`d`, no equation marked as computed, and the lag and level variables restored
from `init`. Two runs with the same parameters give the same answer.

`quiet = TRUE` silences the per-period messages, the memory checkpoints and the
invariant summary — a calibration may call this thousands of times. The
invariants still run, and still stop the model if one is violated.

### 4.3 The keep registry

`clean_ws()` frees memory by emptying the global environment. Everything the
model needs must be registered first:

```r
keep_add("someName")   # protect specific names
keep_snapshot()        # protect everything defined so far
keep_list()            # what is protected
clean_ws()             # remove the rest
```

`run_model.r` calls `keep_snapshot()` once, right after the modules load — at
that point the global environment holds the structure, the four tables and the
equations, and nothing else. Anything created afterwards (the intermediate
values of a period) is fair game for `clean_ws()`.

### 4.4 Reading and writing

| Function | Does |
|---|---|
| `gp(name)` | read a parameter from `dp` |
| `gi(name)` | read an initial value from `init` |
| `gl(name)` | read lookup data from `lookup` |
| `gd(name, t)` | read one variable at one period from `d` |
| `gda(name, from, to)` | read a variable over a window of periods |

All five take an optional `info` of `"all"`, `"desc"`, `"mod"`, `"kind"` or
`"region"` to get the row or one of its metadata columns instead of the value.

`gda()` returns a vector when every period holds a scalar, a matrix
(periods × elements) when they are same-length vectors, and the raw list
otherwise. Pass `from` and `to`: the model never needs the whole history, only
a few recent periods.

**Writes go through `dt_set()`, and nothing else.**

```r
dt_set("d", module = "DEM", name = "ST_population_csg", value = x, period = t)
```

It fills the next free row of the right block and registers it. Calling `set()`
directly on one of the four tables leaves the registry stale and breaks every
subsequent read — in a module you never do either, because `eq()` writes for
you.

**Performance.** `d` is pre-allocated at ~110 000 rows. Finding the next free
row by scanning it, as the old `To()` family did, cost 4.9 s per 1000 writes —
roughly nine minutes of pure scanning over a full 61-period run. A cursor per
`(Module, Period)` block replaces the scan, and a registry maps
`(Name, Period)` to a row index for reads. Neither ever touches the table.
Measured on this model:

| | before | after |
|---|---|---|
| allocate a row (1000×) | 4.95 s | 0.023 s — **215×** |
| read a variable (500×) | 1.06 s | 0.021 s — **50×** |

### 4.5 `eq()` — the contract

Every equation of the model is an R function whose body is a single `eq({...})`
block. `eq()` does five things so that you do not have to:

1. **Collects dependencies** by walking the expression, and separates them from
   parameters and auxiliaries.
2. **Blocks execution** if any dependency is not yet available, and logs why.
3. **Assigns** the result to the global environment under the target name.
4. **Writes** it to `d` for the current period, in run mode.
5. **Attaches metadata** (dependencies, parameters, originating function) to the
   result.

Dependencies are collected by walking the block, and four kinds of name are
excluded because they are not dependencies: variables the block assigns itself,
`for` loop variables, the formal arguments of functions defined inside the
block, and parameters read from `dp`.

That third one is recent. Without it, writing a helper function inside an
`eq()` block made `eq()` block on the helper's own argument names — they look
like undefined variables to a walker that does not track scope.

#### What not to write inside an `eq()` block

The collection is a **syntactic walk**. It cannot see anything that only exists
at run time. Three things therefore break it, and all three fail **silently** —
the block runs when it should have waited, on whatever stale value was lying
around. The same list is in `src/B-modules/_module-template.r`, where you will
be looking when you write a new equation.

| Do not write | Why | Instead |
|---|---|---|
| `f <- function(x = R_labProd_i)` | `all.names()` does not descend into a formal's default value, so `R_labProd_i` is never seen at all | read the variable in the body: `f <- function(x) ...; f(R_labProd_i)` |
| `assign(paste0("ST_", k), v)`, `get(nm)`, `eval(parse(text = ...))` | there is no name in the expression for the walk to find | write the name out |
| `gp(param_name)` — a symbol, not a string | the walk takes the symbol's *name*, so it records `"param_name"` and never the parameter actually read | `gp("R_fertility")` |

If automatic collection ever proves wrong in a way the exclusions cannot cover,
the fallback is to give `eq()` an explicit `dep = c(...)` argument again and use
it in place of the collected list. That is about five lines, and nothing else in
the design depends on inference. `eq()` carried exactly such a parameter until
now — left over from the original design, never read, silently ignoring any
caller that used it. It has been removed rather than left as a trap.

#### The contract

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

### 4.6 The main loop

Because `eq()` refuses to run an equation whose inputs are missing, **you do not
have to order the equations correctly**. The loop runs several passes; each pass
resolves whatever became computable. Equations are grouped by module in
`run_model.r`, in commented blocks, so that the reading order reproduces the
*views* of the Vensim model. That grouping is intentional and should be kept.

```r
eq_new_period()                 # forget what the previous period computed
eq_run_passes(function() {
    # POLICY block
    # GOV block
    # L block
    # ... one block per module, in a readable order ...
})
```

`eq_run_passes()` calls that function repeatedly and stops when a pass resolves
nothing new. Two properties make it safe:

* **An equation that succeeded is not run again in the same period.** Its value
  is already in the global environment for the equations downstream, and nothing
  it reads has moved. On this model that is 71 equations computed once instead
  of 213 calls over three passes — **67% of the work avoided**. `dev` mode
  bypasses it, so console re-runs still work.

* **A pass that resolves nothing while equations are still waiting is an
  error**, naming them, not a silent exit. The old `iter <- 3` was exactly
  enough for this model, with no margin: one equation added in the wrong order
  and it would never have been computed, with nothing but a line in a log to say
  so.

`max_passes` (in `2-structure.r`, default 50) is only a safety cap on runaway
loops. It is not the number of passes taken — the model settles in three.

This is **not** a topological sort. The mechanism and the freedom to order
equations however you like are unchanged.

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
non_skill <- setdiff(pop_group, skill)                     # child and cap
```

The dimension is labelled `PopGroup` in every template's `dimnames`, so the
label on the data says what the data is.

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

Templates are generated, not hand-written:

```r
template_population_csg <- make_template(c("Cohort", "PopGroup", "Gender"))
template_industry_ii    <- make_template(c("Industry", "Industry"))
```

`make_template()` takes dimension *names* and looks their modalities up in
`dimension_modalities`, the single list that maps a capitalised dimension name
to its levels. A name may repeat — that is how the input-output matrix is built.

This replaces the eighteen hand-written `array(0, dim = ..., dimnames = ...)`
blocks. It is also what makes the multi-regional version affordable (§10): one
function to change rather than eighteen declarations plus every loader.

To add a dimension, add one entry to `dimension_modalities`. Nothing else needs
to know about it.

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

### 6.5 A state, its flow, and the one question to ask

Every state in the model advances the same way, and only this way:

```
state(t) = state(t - dt) + net_flow * dt
```

That arithmetic lives in `advance_state(prev, flow)`, not in the equations, so
that `dt` cannot be written in one place and forgotten in another. An equation
computes the **flow**; a second one advances the **state**:

```r
flowSkillLabourShare <- function() {          # the flow, on its own
  eq({
    F_skillShare_is <- convergence * gp("R_trendSkill_is")
    F_skillShare_is
  })
}

shift_SkillLabourShare <- function() {        # the state
  eq({
    SH_skill_is <- advance_state(SH_skill_is_lvl, F_skillShare_is)
    SH_skill_is
  })
}
```

Two functions rather than one, because a flow that exists only as a local
variable inside its state's equation cannot be inspected, plotted, or read by
anything else. Split, it lands in `d` with `Kind == "flow"` like any other
variable.

#### The question to ask

When you translate a Vensim `INTEG`, the question is **not** "is the update
additive or multiplicative". It is:

> **What is the net flow, and does that flow read the state it feeds?**

A flow that reads its own state is entirely legitimate — it is what makes a
smooth a smooth. What is not legitimate is *inventing* that self-reference when
the Vensim flow does not have it.

| State | Vensim flow | Reads its own state? |
|---|---|---|
| `skill trend is` | `convergence * trend` | no |
| `male share is` | `sens*(u_m - u_f) + convergence * trend` | no — the state is only in the guard |
| `Skills XXXX gs` | `Skills * smooth(...) + in - out - deaths` | **yes**, the first term |
| a `SMOOTH` | `(input - state) / delay` | **yes** — that *is* the smooth |
| `Share source Ed Z nrg i` | `-g(t) * Share / (1 - Share[renew])` | **yes** |

Writing `state * factor` is shorthand for `state + state * (factor - 1)`, so it
is correct **only when the Vensim flow really does have a term proportional to
the stock**. For the population it does, and `PopSkillShift = Pop_lvl * (1 +
smooth)` is exactly Vensim's `Skills + Skills * smooth(...)`. For the two share
variables it does not, and writing it that way scaled every flow by the share it
fed — which broke the invariant that the shares sum to 1, since the trends are
built to sum to zero precisely so that an *additive* flow conserves it. That
cost up to 7% drift over the horizon. See `inconsistencies_new.md`.

#### The rule, for a new state

1. Find the Vensim `INTEG` and read its flow argument. That argument is your
   `F_` variable, verbatim — not scaled, not smoothed, not turned into a factor.
2. Give the flow its own equation, returning `F_<something>`.
3. Advance the state with `advance_state(prev, flow)`. Never write the
   arithmetic out.
4. Register both in `model_states` in `2-structure.r`: the state, its flow, and
   an `integ_rationale` if the economic reading and the numerical one diverge.
5. If the state has an invariant — shares summing to one, a population
   identity — write the check and make sure it can actually fire. The one
   guarding `SH_skill_is` read `!all(rowSums(x) - 1) < tolerance`, which
   collapses the vector to a single logical before comparing and returns `FALSE`
   for a row summing to three. It had never fired.

`Kind` follows from the registry, not from the name: a variable is a `flow`
because it feeds a state. Plenty of `F_` variables are flows in the economic
sense — births, deaths, investment — without being the net flow of any state;
they are the terms a net flow is built from.

#### Where the flow does not exist

`R_smoothSkillShift_s` has no flow in the first period. A `SMOOTH` initialises
to its input, so there is no previous state to flow from, and emitting a zero
would claim the state did not move when in fact it appeared. The registry pairs
it with `F_smoothSkillShift_s`, which is written to `d` from the second period
on. That is a property of initialisation, not a gap.

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
Flattening and rebuilding named 3D and 4D arrays on every step would be painful
for no benefit.

`advance_state(prev, flow)` is where the Euler step lives, and every state goes
through it (§6.5). That is the groundwork, not the whole job — and it is worth
being precise about what still stands between here and RK4, rather than
implying a one-line swap.

**What RK4 needs that we do not have yet.** Euler evaluates the flow once, at
the state it already has. RK4 evaluates it **four times per step, at states that
do not exist yet** — `y + k1·dt/2`, and so on. So it needs the flow as a
*function* `f(t, y)` that can be called on an arbitrary state.

Today a flow is a **value**, computed by an equation that reads the global
environment. `flowSkillLabourShare()` cannot be asked "what would you be at this
other state?" — it does not take the state as an argument.

Bridging that means one of:

* giving each flow equation an explicit state argument, so it can be evaluated
  away from the current one; or
* running the whole equation pass against a substituted state, which the pass
  loop could do — set the states, run the pass, read the flows — at the cost of
  four passes per step.

Neither is hard, and §6.5 is what makes either possible: the flows are named,
registered, and separated from the updates. But it is a real piece of work, not
a substitution.

**And a large part of the model is not integrable anyway.** Annual income tax
brackets, cohort maturation on a one-year step, `IF THEN ELSE(Time = 10, ...)`
Covid shocks, `DELAY FIXED`. RK4 would apply to the states; the rest stays
discrete annual whatever happens.

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

The implementation follows that literally. The function takes **values, not
expressions** — no introspection, no scope hunting. The smoothed quantity is a
variable in its own right, registered with `Kind = "state"`, and therefore
visible in `d`, in the outputs and in the dependency graph like anything else.

```r
smooth_vensim <- function(input, prev, delay, dt = 1) {
  alpha <- dt / delay
  stopifnot(alpha > 0, alpha <= 1)
  prev + alpha * (input - prev)
}
```

Resolving where `input` and `prev` come from is the job of `eq()`, exactly as for
every other variable.

Resolving where `input` and `prev` come from is the caller's job:

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

> The previous implementation resolved variables itself, by walking the
> expression and searching `dp`, `init`, `d` and the global environment in turn.
> It produced the right answer in the first period and a wrong one afterwards —
> a whole history from `gda()` multiplied by a per-element vector from `gp()`,
> which recycles down the columns instead of across them. It went unnoticed
> because the time loop had never run past the first period. It was replaced,
> not tidied. See `inconsistencies_new.md`.

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
changes no results. Snapshots live in `output/_ref_*.rds` (git-ignored).

```bash
Rscript src/snapshot.r take  phase0   # run the model, save d as the reference
Rscript src/snapshot.r check phase0   # run it again, compare against that
```

`check` exits 0 when nothing moved. When something did, it names what: variables
that stopped being computed, variables that appeared, and variables whose value
changed.

### 9.2 The model's own invariants

Things that must be true at the end of every period, whatever the scenario.
They live in `src/A-prep-steps/3-invariants.r` and run at the end of each
period. `check_invariants()` reports **all** failures at once, not the first —
when something is wrong you want the whole picture.

Most of them are not ours. The authors of the Vensim model left `check ...` and
`test ...` variables in it — ratios that should be 1, differences that should be
0. They test the economics rather than the code, which is what is wanted here.

Registering one:

```r
invariant("skill shares sum to 1 by industry",
          function() max(abs(rowSums(SH_skill_is) - 1)),
          expect = 0,
          source = "",                     # the Vensim variable, if there is one
          note   = "why this must hold")
```

Currently 14 registered, in four families:

| | |
|---|---|
| **accounting identities** | active = employed + unemployed; working age = active + inactive; population = working age + children + capitalists + retired; desired labour adds up over gender and group |
| **shares are shares** | skill shares sum to 1 by industry; male shares in [0,1]; energy source shares sum to 1 |
| **structural zeros** | no employment, and no working-age population, in `child` or `cap`; nobody of working age under 15 or over 64 |
| **signs and finiteness** | population, employment and unemployment non-negative; every state finite |

**A check whose inputs do not exist yet is skipped, not failed.** Most of the
model is still commented out of the main loop, and an invariant on a variable
that is not computed says nothing. Skipped checks are counted and named, so they
cannot quietly stay skipped for ever.

#### Write checks that can fail

This is the part that matters, and it is easy to get wrong twice over.

The guard on `SH_skill_is` read `!all(rowSums(x) - 1) < tolerance`, which
collapses a numeric vector to one logical before comparing and returns `FALSE`
for a row summing to three. It had never fired — while the bug it was written to
catch was live.

The second way is subtler. A first version of the population invariant here read

```r
sum(pop) - sum(pop["0-14", , ]) - sum(pop[setdiff(cohort, "0-14"), , ])
```

which is **zero whatever the array holds**: total minus children minus
everything-but-children. Slicing one array two ways cannot produce a
disagreement. Vensim's `test adult` is meaningful because it compares three
variables computed by three *different* equations. The R version now compares
`ST_workAgePop_csg`, which `workingAgePop()` derives by masking, against a
decomposition of the population it was derived from — so a wrong mask shows up.

Both were caught by testing the tests: break each invariant deliberately, one at
a time, and confirm it fires. All 14 do. An untested check is a comment.

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

1. A `Region` column on `d`, `init` and `dp`, with a single value `"IT"`, and a
   matching `region` column on every input CSV (§11.3). It costs nothing today;
   retrofitting it later would mean touching every read, every write and every
   input file.
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

### 11.1 The extraction manifest

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

### 11.2 The Shiny dependency viewer

`app/graph/` renders the model as a directed graph, one node per variable,
coloured by module. Deployed at <https://rewind.shinyapps.io/graph/>.

```r
library(shiny); library(rsconnect)
runApp()
deployApp()
```

It reads its edges from the `deps` table:

```r
edges_df <- deps[Role == "input", .(from = Dependency, to = Variable)]
```

Only `input` edges are drawn; a `parameter` role is a constant from `dp`, which
would clutter the graph without informing it. The app itself has not been
touched since the refactoring began and is expected to need work — that comes
last, once the model is complete.

### 11.3 Where the numbers come from

`docs/EUROGREEN/` holds the Vensim sources and the calibration data.

| File | What it is |
|---|---|
| `vensimModel_noDelete.txt` | the 2025 model as text — for comparing against the 2026 one |
| `REWIND_2025_v0_EUROGREEN_v2.5_revise.mdl` | the 2025 model, native format |
| `MODEL_2023_households_v3_w_energy-Pisa-03.26.mdl` | the Pisa branch of the model |
| `economy.xlsx`, `demography.xlsx`, `environment.xlsx` | the data behind every `GET DIRECT CONSTANTS(...)` in the Vensim source |
| `calibration_2024.xlsx` | calibration |
| `indicators.lst` | Vensim indicator list |
| `_oldM4W/` | the earlier M4W model |

> **The spreadsheets are the authority only for what is not yet imported.**
> A large part of the inputs has already been extracted, reshaped against a
> template and stored as individual CSV files under `input/`. Those are done.
> Do not re-derive a value from `economy.xlsx` when a CSV for it already exists
> under `input/initial/`, `input/parameter/` or `input/lookup/` — the CSV is the
> one the model reads, and going back to the spreadsheet risks silently
> reintroducing a shape or a modality that the template already fixed.
>
> The rule when translating a new variable: look in `input/` first. Only if
> nothing is there do you go to the spreadsheet, and then the extraction goes
> through `tool/` and the manifest (§11.1) so that it is recorded.

**An input that is missing gets added — it is never read inline.** When a
variable being translated has no CSV under `input/`, the value does not go into
the equation as a literal, and it does not get read from the spreadsheet at run
time. It is extracted, shaped against the template that matches its indices
(§5.5), written as a CSV in the right module folder, and loaded by `loadFill()`
like everything else. An input that lives anywhere other than `input/` is
invisible to the calibration entry point (§8 of the backlog) and to anyone
reading the model.

Every input CSV carries a **`region` column**, holding `IT` for now — the
existing ones and the new ones alike. It costs nothing today and means the input
format does not change when regions arrive: only the number of rows does. See
§10.

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
  Every `gd(x, t-1)` in `I.r` and in `run_model.r` would have silently returned
  2010 values the day the loop was added.
* **`gd(..., info=)` queried `lookup` instead of `d`.**
* **`smooth_vensim()` returned a wrong result for `t > startYear`** (§8).
* `loadFill()` used `next` inside a `tryCatch` handler, which is not a loop, and
  `message()` where `stop()` was meant — a file could fail to load silently.
* `read_and_validate_csv()` reported missing columns with `message()`, not
  `stop()`.
* `load_3d()` referenced `desc` before it existed in that scope.
* **Double sourcing.** The `BEGIN`/`END` + tempfile pattern read a file back,
  cut out the section between two comment markers, wrote it to a temp file and
  sourced *that* into a throwaway environment — purely to find out what the file
  had defined, for the log. Every prep step and all thirteen modules were
  therefore evaluated twice. `ls()` on the environment that was just populated
  answers the same question. Gone, along with `toKeep0/1/2`.

  It cost nothing in time — measured at ~10 s for a full run either way, since
  what was being re-evaluated is function definitions. What it cost was
  robustness: the markers had to match exactly, a stray `# END` anywhere in the
  file silently truncated the section, and nothing checked the result.
* `_0verbose.r`, sourced at the foot of each module to produce that listing, is
  deleted. `sourceSet()` already computes the same list as a by-product of
  sourcing the file, so the thirteen modules lose their trailing boilerplate
  (`module_name <- "X"`, the `source()`, the `toKeep` append) entirely.
* `toKeep`, a mutable global appended to with `<<-` from a dozen places in an
  order that had to be right, replaced by a **keep registry**: an environment
  with `keep_add()`, `keep_snapshot()` and `keep_list()`. Registration is
  idempotent and order-independent, and no reassignment can silently drop an
  entry. `keep_snapshot()` is called once, after the modules load, and protects
  everything defined up to that point.
* Logging has levels (`log_info` / `log_warn` / `log_error`, threshold set in
  `log_init()`), a timestamp and a level on every line, and no emoji in the
  file — a log is read with `grep`, not admired. `log_message()` survives as an
  alias for `log_info()`.
* `_0verbose.R` was capitalised while all thirteen modules sourced it as `.r`.
  That only worked because macOS has a case-insensitive filesystem; it would
  have failed on Linux.
* `pryr` no longer builds on R 4.6. Its single use, `mem_used()`, moved to
  `lobstr`.
* A block that runs out of pre-allocated rows now says which block, how big it
  was, and which of `npar` / `nvar` / `nlookup` to raise.

### Open

* **Modules with no R file yet.** "Still there" means the 2026 model has its
  equations, so it has to be translated; "gone" means the 2026 model dropped it,
  so there is nothing left to translate.

  | Module | 2025 | 2026 | |
  |---|---|---|---|
  | `FI` finance | yes | **yes**, plus `stock of bonds` and `interest` | to translate — 8 of the 35 states, and the accounting identities that go with them |
  | `PVA` profits, VA | yes | **yes** | to translate |
  | `ENV` environment | yes | **yes** | to translate |
  | `WS` water supply | yes | **yes** | to translate |
  | `WD` water demand | marginal | marginal | barely present in either; check before starting |
  | `TU` time use | yes, ~110 lines | **gone** | nothing to translate |

  `FI` is not new: `b`/`d`/`eq` by household group and for capitalists, and
  `debt i`, have identical equations in both models. Only `stock of bonds` and
  `interest` were added in 2026.

  `TU` is the reverse: a working module in 2025, removed in 2026. What survives
  is `init time use dt[inc cat,timeuse]`, an initial-values array that appears
  in its own definition and in the sketch metadata and nowhere else — an
  orphaned input for a module that no longer exists. The `timeuse` subscript is
  likewise still declared and indexes nothing.
* Calibration. `run_model()` is the entry point (§4.6); no calibration
  procedure is written on top of it yet. Block calibration — module by module,
  holding the rest fixed — is the realistic approach for a model with this many
  parameters and a non-convex loss.
* `R_mortality_csg` is stored as a full 3D array although it only varies by
  cohort. Same for several other DEM parameters.
* Scenarios: a `Scenario` column on `d`.
* Unit checking. Vensim does dimensional analysis; R does not. Worth adding.
* **A 2025 ↔ 2026 diff.** The variable-level comparison in §2 was done once, by
  hand, and is not reproducible. Phase 2 needs it as a tool: for each equation
  being retranslated, what changed between the two models, so that the
  difference is read rather than guessed. `TODO(2026)` markers are the
  short-term stand-in.
* **Every inconsistency met along the way goes into `inconsistencies_new.md`,
  fixed or not.** Including the ones the 2026 model already fixed — recorded for
  memory, so that a later reader knows the question was asked. The rule when
  retranslating an equation: check `src/inconsistencies.qmd` first, so that a
  bug already found is not reintroduced.
* `inconsistencies.qmd` needs to be replayed against
  `vensim_model_2026.txt`: some of the bugs found may have been fixed upstream,
  some may not, and some of the 2026 simplifications may rest on the buggy
  behaviour. Findings go into `inconsistencies_new.md`.
* `testthat` for the invariants of §9.2.

---

## Where this is going

| | |
|---|---|
| **Phase 1** — the engine | in progress, steps 6 to 10 remain |
| **Phase 2** — finish the translation against the 2026 model, and rebuild the Shiny viewer | |
| **Phase 3** — continuous time (§7) | |
| **Phase 4** — multi-regional (§10) | |

Phases 3 and 4 are what phase 1 is preparing for: `dt` written out and states
separated from flows for the first, a `Region` column and generated templates
for the second. Neither is started.

---

## Sources and references

In this repository — see §11.3 for how to use them:

* `docs/EUROGREEN/` — the Vensim sources and the calibration spreadsheets

Kept outside this repository:

* `r-nb-rewind-docu` — the previous documentation notebook. Superseded by this
  file for everything except the generated dependency graphs and the "current
  status" figures; worth revisiting when the Shiny viewer is picked up again
  (§11.2).
* DEFINE — a comparable ecological SFC model written in R
* `sysde` — system dynamics tutorials in R
* Duggan, *System Dynamics Modeling with R* (2016)
